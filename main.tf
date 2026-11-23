data "aws_region" "current" {}

# --- Internal NLB in front of the service ------------------------------------

resource "aws_lb" "this" {
  name               = "${var.name}-nlb"
  internal           = true
  load_balancer_type = "network"
  subnets            = var.subnet_ids
  tags               = var.tags
}

resource "aws_lb_target_group" "this" {
  name        = "${var.name}-tg"
  port        = var.service_port
  protocol    = "TCP"
  target_type = "ip"
  vpc_id      = var.vpc_id
  tags        = var.tags
}

resource "aws_lb_target_group_attachment" "this" {
  for_each = toset(var.target_ips)

  target_group_arn = aws_lb_target_group.this.arn
  target_id        = each.value
  port             = var.service_port
}

resource "aws_lb_listener" "this" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }
}

# REST API VPC links (v1) point at NLB ARNs.
resource "aws_api_gateway_vpc_link" "this" {
  name        = "${var.name}-link"
  target_arns = [aws_lb.this.arn]
  tags        = var.tags
}

# --- Interface endpoint clients use to reach the private API -------------------

resource "aws_security_group" "endpoint" {
  name        = "${var.name}-execute-api"
  description = "HTTPS to the execute-api endpoint from allowed CIDRs"
  vpc_id      = var.vpc_id
  tags        = var.tags
}

resource "aws_vpc_security_group_ingress_rule" "endpoint_https" {
  for_each = toset(var.allowed_cidrs)

  security_group_id = aws_security_group.endpoint.id
  description       = "HTTPS from ${each.value}"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = each.value
}

resource "aws_vpc_endpoint" "execute_api" {
  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${data.aws_region.current.region}.execute-api"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.subnet_ids
  security_group_ids  = [aws_security_group.endpoint.id]
  private_dns_enabled = true
  tags                = merge(var.tags, { Name = "${var.name}-execute-api" })
}

# --- Private REST API ---------------------------------------------------------------

resource "aws_api_gateway_rest_api" "this" {
  name = var.name

  endpoint_configuration {
    types            = ["PRIVATE"]
    vpc_endpoint_ids = [aws_vpc_endpoint.execute_api.id]
  }

  tags = var.tags
}

# Only calls that arrive through our endpoint are allowed.
module "policy_guard" {
  source = "./modules/policy-guard"

  vpc_endpoint_id = aws_vpc_endpoint.execute_api.id
  policy_json = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = "*"
        Action    = "execute-api:Invoke"
        Resource  = "${aws_api_gateway_rest_api.this.execution_arn}/*"
      },
      {
        Effect    = "Deny"
        Principal = "*"
        Action    = "execute-api:Invoke"
        Resource  = "${aws_api_gateway_rest_api.this.execution_arn}/*"
        Condition = {
          StringNotEquals = { "aws:SourceVpce" = aws_vpc_endpoint.execute_api.id }
        }
      },
    ]
  })
}

resource "aws_api_gateway_rest_api_policy" "this" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  policy      = module.policy_guard.policy_json
}

# The endpoint can only be used to call this API, not any API in any account.
# Separate resource, because the API already depends on the endpoint.
resource "aws_vpc_endpoint_policy" "execute_api" {
  vpc_endpoint_id = aws_vpc_endpoint.execute_api.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = "*"
        Action    = "execute-api:Invoke"
        Resource  = "${aws_api_gateway_rest_api.this.execution_arn}/*"
      },
    ]
  })
}

resource "aws_api_gateway_resource" "proxy" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_rest_api.this.root_resource_id
  path_part   = "{proxy+}"
}

resource "aws_api_gateway_method" "proxy" {
  rest_api_id   = aws_api_gateway_rest_api.this.id
  resource_id   = aws_api_gateway_resource.proxy.id
  http_method   = "ANY"
  authorization = "NONE" # access is limited by the resource policy above

  request_parameters = {
    "method.request.path.proxy" = true
  }
}

resource "aws_api_gateway_integration" "proxy" {
  rest_api_id             = aws_api_gateway_rest_api.this.id
  resource_id             = aws_api_gateway_resource.proxy.id
  http_method             = aws_api_gateway_method.proxy.http_method
  type                    = "HTTP_PROXY"
  integration_http_method = "ANY"
  uri                     = "http://${aws_lb.this.dns_name}/{proxy}"
  connection_type         = "VPC_LINK"
  connection_id           = aws_api_gateway_vpc_link.this.id

  request_parameters = {
    "integration.request.path.proxy" = "method.request.path.proxy"
  }
}

resource "aws_api_gateway_deployment" "this" {
  rest_api_id = aws_api_gateway_rest_api.this.id

  # Redeploy when the API shape or the policy changes.
  triggers = {
    redeploy = sha1(jsonencode([
      aws_api_gateway_resource.proxy.id,
      aws_api_gateway_method.proxy.id,
      aws_api_gateway_integration.proxy.id,
      aws_api_gateway_rest_api_policy.this.policy,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }

  # A private API can't be deployed before it has a resource policy.
  depends_on = [aws_api_gateway_rest_api_policy.this, aws_api_gateway_integration.proxy]
}

resource "aws_api_gateway_stage" "this" {
  rest_api_id   = aws_api_gateway_rest_api.this.id
  deployment_id = aws_api_gateway_deployment.this.id
  stage_name    = var.stage_name
  tags          = var.tags
}
