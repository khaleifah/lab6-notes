# Adapted from the supplied Blackboard template. The application is configured
# separately at Task 3 step 4, keeping the infrastructure/application distinction.
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = "eu-west-1" # Verify your selected Region and key pair first.
}

locals {
  first_name       = "khaleifah"
  repository_url   = "https://github.com/khaleifah/lab6-notes.git"
  website_packages = "docker.io docker-compose-v2 nginx curl openssl"
  website_port     = 80
  public_http      = true  # Set false for Task 4 and capture the SSH-only firewall.
  public_https     = false # Set true only for the direct HTTPS extra credit.
}

resource "aws_lightsail_instance" "website" {
  name              = "${local.first_name}-website-ccen448f26"
  availability_zone = "eu-west-1a"
  blueprint_id      = "ubuntu_24_04"
  bundle_id         = "micro_3_0" # Example 1 GB IPv4 bundle; verify eligibility in your account.
  ip_address_type   = "ipv4"
  key_pair_name     = "khaleifah-lab6-key"
  user_data = join("\n", [
    "#!/bin/bash",
    "set -eu",
    "export DEBIAN_FRONTEND=noninteractive",
    "apt-get update",
    "apt-get install -y git ${local.website_packages}",
    "git clone '${local.repository_url}' /opt/website",
    "chown -R ubuntu:ubuntu /opt/website"
  ])
}

resource "aws_lightsail_static_ip" "website" {
  name = "${local.first_name}-website-ip-ccen448f26"
}

resource "aws_lightsail_static_ip_attachment" "website" {
  static_ip_name = aws_lightsail_static_ip.website.name
  instance_name  = aws_lightsail_instance.website.name
}

resource "aws_lightsail_instance_public_ports" "website" {
  instance_name = aws_lightsail_instance.website.name
  port_info {
    protocol  = "tcp"
    from_port = 22
    to_port   = 22
  }
  dynamic "port_info" {
    for_each = local.public_http ? [local.website_port] : []
    content {
      protocol  = "tcp"
      from_port = port_info.value
      to_port   = port_info.value
    }
  }
  dynamic "port_info" {
    for_each = local.public_https ? [443] : []
    content {
      protocol  = "tcp"
      from_port = port_info.value
      to_port   = port_info.value
    }
  }
}

output "static_ipv4" {
  value      = aws_lightsail_static_ip.website.ip_address
  depends_on = [aws_lightsail_static_ip_attachment.website]
}
