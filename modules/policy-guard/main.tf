# Refuses an API resource policy that doesn't deny calls from other VPC endpoints.
# The root module passes its policy through here, and tests feed it bad policies.
terraform {
  required_version = ">= 1.9.0, < 2.0.0"
}

variable "vpc_endpoint_id" {
  description = "The only execute-api endpoint allowed to invoke the API."
  type        = string
}

variable "policy_json" {
  description = "REST API resource policy as JSON."
  type        = string

  validation {
    condition = anytrue([
      for s in try(jsondecode(var.policy_json).Statement, []) :
      try(s.Effect, "") == "Deny"
      && contains(flatten([try(s.Action, [])]), "execute-api:Invoke")
      && try(s.Condition.StringNotEquals["aws:SourceVpce"], "") == var.vpc_endpoint_id
    ])
    error_message = "The API policy must deny execute-api:Invoke when aws:SourceVpce is not the module's VPC endpoint."
  }
}

output "policy_json" {
  description = "The checked policy, unchanged."
  value       = var.policy_json
}
