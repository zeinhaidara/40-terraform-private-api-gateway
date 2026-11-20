output "invoke_url" {
  description = "Stage URL. Resolves only inside the VPC (private DNS on the endpoint)."
  value       = aws_api_gateway_stage.this.invoke_url
}

output "rest_api_id" {
  description = "ID of the private REST API."
  value       = aws_api_gateway_rest_api.this.id
}

output "vpc_endpoint_id" {
  description = "execute-api interface endpoint ID."
  value       = aws_vpc_endpoint.execute_api.id
}

output "nlb_arn" {
  description = "Internal NLB ARN."
  value       = aws_lb.this.arn
}

output "nlb_target_group_arn" {
  description = "Target group to register service targets in."
  value       = aws_lb_target_group.this.arn
}
