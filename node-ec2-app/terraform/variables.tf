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



