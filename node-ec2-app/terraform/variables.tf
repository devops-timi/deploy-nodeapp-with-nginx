variable "instance_type" {
  type    = string
  default = "t2.micro"
}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "instance_key" { 
  type        = string
  description = "Name of keypair"
  default     = "us-connect"
}

variable "allowed_ssh_cidr" {
  description = "CIDR block allowed to SSH into EC2 instance"
  type        = string
  default     = "197.211.59.82"
}

