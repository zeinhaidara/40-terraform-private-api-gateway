# Example root with placeholder IDs. This has never been applied.
terraform {
  required_version = ">= 1.9.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.73.0"
    }
  }
}

provider "aws" {
  region = "eu-west-2"
}

module "orders_api" {
  source = "../.."

  name          = "orders"
  vpc_id        = "vpc-0aaaaaaaaaaaaaaa1"
  subnet_ids    = ["subnet-0aaaaaaaaaaaaaa01", "subnet-0aaaaaaaaaaaaaa02"]
  allowed_cidrs = ["10.0.0.0/8"]
  service_port  = 8080
  target_ips    = ["10.1.2.10", "10.1.3.10"]

  tags = { project = "orders", owner = "platform@example.com" }
}

output "invoke_url" {
  value = module.orders_api.invoke_url
}
