# Runs against a mocked AWS provider. Nothing is created in AWS.
mock_provider "aws" {
  mock_data "aws_region" {
    defaults = {
      region = "eu-west-2"
    }
  }

  # The provider validates ARN formats, so random mock strings won't do.
  mock_resource "aws_lb" {
    defaults = {
      arn      = "arn:aws:elasticloadbalancing:eu-west-2:123456789012:loadbalancer/net/svc-nlb/0123456789abcdef"
      dns_name = "svc-nlb-0123456789abcdef.elb.eu-west-2.amazonaws.com"
    }
  }

  mock_resource "aws_lb_target_group" {
    defaults = {
      arn = "arn:aws:elasticloadbalancing:eu-west-2:123456789012:targetgroup/svc-tg/0123456789abcdef"
    }
  }

  mock_resource "aws_vpc_endpoint" {
    defaults = {
      id = "vpce-0123456789abcdef0"
    }
  }

  mock_resource "aws_api_gateway_rest_api" {
    defaults = {
      id            = "abc123defg"
      execution_arn = "arn:aws:execute-api:eu-west-2:123456789012:abc123defg"
    }
  }
}

variables {
  name          = "svc"
  vpc_id        = "vpc-0aaaaaaaaaaaaaaa1"
  subnet_ids    = ["subnet-0aaaaaaaaaaaaaa01", "subnet-0aaaaaaaaaaaaaa02"]
  allowed_cidrs = ["10.0.0.0/8"]
  target_ips    = ["10.1.2.10", "10.1.3.10"]
}

run "private_api_wired_through_vpc_link_to_nlb" {
  command = apply

  assert {
    condition     = aws_api_gateway_rest_api.this.endpoint_configuration[0].types == tolist(["PRIVATE"])
    error_message = "API must be PRIVATE"
  }

  assert {
    condition     = tolist(aws_api_gateway_rest_api.this.endpoint_configuration[0].vpc_endpoint_ids) == tolist(["vpce-0123456789abcdef0"])
    error_message = "API must be bound to the module's execute-api endpoint"
  }

  assert {
    condition     = aws_lb.this.internal && aws_lb.this.load_balancer_type == "network"
    error_message = "NLB must be internal"
  }

  assert {
    condition     = tolist(aws_api_gateway_vpc_link.this.target_arns) == tolist([aws_lb.this.arn])
    error_message = "VPC link must target the NLB"
  }

  assert {
    condition     = aws_api_gateway_integration.proxy.connection_type == "VPC_LINK" && aws_api_gateway_integration.proxy.connection_id == aws_api_gateway_vpc_link.this.id
    error_message = "integration must go through the VPC link"
  }

  assert {
    condition     = aws_api_gateway_integration.proxy.uri == "http://svc-nlb-0123456789abcdef.elb.eu-west-2.amazonaws.com/{proxy}"
    error_message = "integration URI must point at the NLB"
  }

  assert {
    condition     = aws_vpc_endpoint.execute_api.service_name == "com.amazonaws.eu-west-2.execute-api" && aws_vpc_endpoint.execute_api.private_dns_enabled
    error_message = "execute-api endpoint with private DNS expected"
  }

  assert {
    condition     = length(aws_lb_target_group_attachment.this) == 2
    error_message = "both target IPs should be registered"
  }

  assert {
    condition = alltrue([
      for r in aws_vpc_security_group_ingress_rule.endpoint_https :
      r.from_port == 443 && r.to_port == 443 && r.cidr_ipv4 == "10.0.0.0/8"
    ])
    error_message = "endpoint SG must allow only 443 from allowed_cidrs"
  }
}

run "resource_policy_denies_other_endpoints" {
  command = apply

  assert {
    condition     = jsondecode(aws_api_gateway_rest_api_policy.this.policy).Statement[1].Effect == "Deny"
    error_message = "second statement must be a Deny"
  }

  assert {
    condition     = jsondecode(aws_api_gateway_rest_api_policy.this.policy).Statement[1].Condition.StringNotEquals["aws:SourceVpce"] == "vpce-0123456789abcdef0"
    error_message = "Deny must apply to every endpoint except ours"
  }

  assert {
    condition     = jsondecode(aws_api_gateway_rest_api_policy.this.policy).Statement[0].Resource == "arn:aws:execute-api:eu-west-2:123456789012:abc123defg/*"
    error_message = "policy must be scoped to this API"
  }
}

run "open_world_cidr_rejected" {
  command = plan

  variables {
    allowed_cidrs = ["10.0.0.0/8", "0.0.0.0/0"]
  }

  expect_failures = [var.allowed_cidrs]
}

run "empty_subnets_rejected" {
  command = plan

  variables {
    subnet_ids = []
  }

  expect_failures = [var.subnet_ids]
}

run "bad_target_ip_rejected" {
  command = plan

  variables {
    target_ips = ["10.1.2.300"]
  }

  expect_failures = [var.target_ips]
}

run "bad_port_rejected" {
  command = plan

  variables {
    service_port = 70000
  }

  expect_failures = [var.service_port]
}

run "bad_stage_name_rejected" {
  command = plan

  variables {
    stage_name = "v1-beta"
  }

  expect_failures = [var.stage_name]
}
