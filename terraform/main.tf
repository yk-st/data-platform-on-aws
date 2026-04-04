# Data Platform on AWS using Terraform
# Created with Terraform MCP and Copilot Agent

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.3"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
  # 心配な人はStateをS3などにしてください
  backend "local" {
    path = "./.state/terraform.tfstate"
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = var.common_tags
  }
}

# No longer using random_id - bucket suffix is provided as a variable
