terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

# How to write output.tf and variable.tf and other .tf files?

provider "aws" {
  region = var.region
}