terraform {
    backend "s3" {
      bucket         = "terraform-state-nodeapp-01"
      key            = "deploy-nodeapp-with-nginx/node-ec2-app/terraform.tfstate"
      region         = "us-east-1"
      dynamodb_table = "terraform-state-lock"
      encrypt        = true
    }
}
