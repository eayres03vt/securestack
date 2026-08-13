# This block tells Terraform which "provider" (cloud) plugin to download and use.
# Providers are how Terraform talks to AWS, Azure, GCP, etc. via their APIs.
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

# This configures the AWS provider itself - which region to build resources in.
# Credentials are NOT set here. Terraform automatically picks them up from the
# same place the AWS CLI stores them (~/.aws/credentials), which is why we ran
# `aws configure` earlier instead of pasting keys into any file.
provider "aws" {
  region = var.aws_region
}
