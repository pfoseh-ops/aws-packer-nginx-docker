# Terraform example to launch EC2 instances from the Docker+Nginx AMI

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  type        = string
  default     = "us-east-1"
  description = "AWS region"
}

variable "ami_id" {
  type        = string
  description = "AMI ID from Packer build (e.g., ami-xxxxxxxxx)"
}

variable "instance_type" {
  type        = string
  default     = "t3.micro"
  description = "EC2 instance type"
}

variable "instance_count" {
  type        = number
  default     = 1
  description = "Number of instances to launch"
}

variable "key_name" {
  type        = string
  description = "AWS key pair name for SSH access"
}

# Security group allowing HTTP/HTTPS
resource "aws_security_group" "nginx" {
  name        = "nginx-docker-sg"
  description = "Security group for Nginx Docker instances"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "nginx-docker-sg"
  }
}

# Launch EC2 instances
resource "aws_instance" "nginx" {
  count                = var.instance_count
  ami                  = var.ami_id
  instance_type        = var.instance_type
  key_name             = var.key_name
  vpc_security_group_ids = [aws_security_group.nginx.id]
  
  associate_public_ip_address = true

  tags = {
    Name = "nginx-docker-${count.index + 1}"
  }

  lifecycle {
    ignore_changes = [ami]
  }
}

# Outputs
output "instance_ips" {
  value = {
    for instance in aws_instance.nginx : instance.id => instance.public_ip
  }
  description = "Public IPs of launched instances"
}

output "instance_public_dns" {
  value = {
    for instance in aws_instance.nginx : instance.id => instance.public_dns
  }
  description = "Public DNS names of launched instances"
}

output "nginx_urls" {
  value = [
    for instance in aws_instance.nginx :
    "http://${instance.public_ip}"
  ]
  description = "URLs to access Nginx on each instance"
}
