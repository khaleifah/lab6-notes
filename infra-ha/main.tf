# Separate state from infra-single. Creates FOUR instances: web1, web2, db, lb.
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}
provider "aws" {
  region = var.region
}
variable "region" {
  type    = string
  default = "eu-west-1"
}
variable "availability_zone" {
  type    = string
  default = "eu-west-1a"
}
variable "key_pair_name" {
  type = string
}
variable "bundle_id" {
  type    = string
  default = "micro_3_0"
}
variable "first_name" {
  type    = string
  default = "khaleifah"
}
locals {
  roles = toset(["web1", "web2", "db", "lb"])
}
resource "aws_lightsail_instance" "node" {
  for_each          = local.roles
  name              = "${var.first_name}-${each.key}-ha-ccen448f26"
  availability_zone = var.availability_zone
  blueprint_id      = "ubuntu_24_04"
  bundle_id         = var.bundle_id
  ip_address_type   = "ipv4"
  key_pair_name     = var.key_pair_name
  user_data         = "#!/bin/bash\nset -eu\napt-get update\napt-get install -y python3\n"
}
resource "aws_lightsail_static_ip" "node" {
  for_each = local.roles
  name     = "${var.first_name}-${each.key}-ha-ip-ccen448f26"
}
resource "aws_lightsail_static_ip_attachment" "node" {
  for_each       = local.roles
  static_ip_name = aws_lightsail_static_ip.node[each.key].name
  instance_name  = aws_lightsail_instance.node[each.key].name
}
resource "aws_lightsail_instance_public_ports" "node" {
  for_each      = local.roles
  instance_name = aws_lightsail_instance.node[each.key].name
  # All browser traffic uses the SSH + Cloudflare path through the LB.
  port_info {
    protocol  = "tcp"
    from_port = 22
    to_port   = 22
  }
}
output "nodes" {
  value = {
    for role in local.roles : role => {
      name       = aws_lightsail_instance.node[role].name
      public_ip  = aws_lightsail_static_ip.node[role].ip_address
      private_ip = aws_lightsail_instance.node[role].private_ip_address
    }
  }
  depends_on = [aws_lightsail_static_ip_attachment.node]
}
