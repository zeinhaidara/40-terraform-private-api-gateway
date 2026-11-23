variable "name" {
  description = "Prefix for resource names."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,24}$", var.name))
    error_message = "name must be 2-25 lowercase letters, digits or hyphens (NLB names are short)."
  }
}

variable "vpc_id" {
  description = "VPC that holds the NLB and the execute-api endpoint."
  type        = string

  validation {
    condition     = can(regex("^vpc-[0-9a-f]{8,17}$", var.vpc_id))
    error_message = "vpc_id must look like vpc-0123456789abcdef0."
  }
}

variable "subnet_ids" {
  description = "Private subnets for the NLB and the VPC endpoint, ideally one per AZ."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) > 0 && alltrue([for s in var.subnet_ids : can(regex("^subnet-[0-9a-f]{8,17}$", s))])
    error_message = "subnet_ids must list at least one subnet-... ID."
  }
}

variable "allowed_cidrs" {
  description = "Client CIDRs allowed to reach the execute-api endpoint on 443."
  type        = list(string)

  validation {
    condition     = length(var.allowed_cidrs) > 0 && alltrue([for c in var.allowed_cidrs : can(cidrhost(c, 0))])
    error_message = "allowed_cidrs must list at least one valid CIDR."
  }

  # A private API reachable from public ranges defeats the point.
  validation {
    condition = alltrue([
      for c in var.allowed_cidrs : anytrue([
        for base in ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "100.64.0.0/10"] :
        try(
          tonumber(split("/", c)[1]) >= tonumber(split("/", base)[1])
          && cidrhost("${split("/", c)[0]}/${split("/", base)[1]}", 0) == cidrhost(base, 0),
          false
        )
      ])
    ])
    error_message = "allowed_cidrs must sit inside 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16 or 100.64.0.0/10."
  }
}

variable "service_port" {
  description = "Port the internal service listens on behind the NLB."
  type        = number
  default     = 8080

  validation {
    condition     = var.service_port >= 1 && var.service_port <= 65535
    error_message = "service_port must be 1-65535."
  }
}

variable "target_ips" {
  description = "Optional private IPs to register in the NLB target group."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for ip in var.target_ips : can(cidrhost("${ip}/32", 0))])
    error_message = "target_ips must be IPv4 addresses."
  }
}

variable "stage_name" {
  description = "API Gateway stage name."
  type        = string
  default     = "v1"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_]{1,64}$", var.stage_name))
    error_message = "stage_name must be letters, digits or underscores."
  }
}

variable "tags" {
  description = "Tags for every taggable resource."
  type        = map(string)
  default     = {}
}
