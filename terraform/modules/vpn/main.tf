terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

data "aws_ami" "amazon_linux_2" {
  most_recent = true

  owners = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-kernel-5.10-hvm-*-x86_64-gp2"]
  }
}

data "aws_subnet" "selected" {
  id = var.subnet_id
}

data "aws_region" "current" {}

resource "aws_instance" "this" {
  ami           = data.aws_ami.amazon_linux_2.id
  instance_type = var.instance_type
  subnet_id     = var.subnet_id

  root_block_device {
    delete_on_termination = true
    encrypted             = true

    volume_type = "gp2"
    volume_size = 25

    tags = {
      Billing              = "AR Architecture Dept"
      Project              = "VPN"
      Environment          = "Production"
      Terraform-Managed    = true
      Terraform-Repository = "https://github.com/ArnyDnD/Atikarooms-admin-services/tree/main/"
    }
  }

  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  iam_instance_profile   = aws_iam_instance_profile.vpn_profile.name
  vpc_security_group_ids = [aws_security_group.this.id]

  user_data = <<EOUD
#!/bin/bash

sudo tee /etc/yum.repos.d/mongodb-org-6.0.repo << EOF
[mongodb-org-6.0]
name=MongoDB Repository
baseurl=https://repo.mongodb.org/yum/amazon/2/mongodb-org/6.0/x86_64/
gpgcheck=1
enabled=1
gpgkey=https://www.mongodb.org/static/pgp/server-6.0.asc
EOF

sudo tee /etc/yum.repos.d/pritunl.repo << EOF
[pritunl]
name=Pritunl Repository
baseurl=https://repo.pritunl.com/stable/yum/amazonlinux/2/
gpgcheck=1
enabled=1
EOF

sudo rpm -Uvh https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
gpg --keyserver hkp://keyserver.ubuntu.com --recv-keys 7568D9BB55FF9E5287D586017AE645C0CF8E292A
gpg --armor --export 7568D9BB55FF9E5287D586017AE645C0CF8E292A > key.tmp; sudo rpm --import key.tmp; rm -f key.tmp

sudo yum -y update

sudo yum -y install pritunl mongodb-org
sudo systemctl enable mongod pritunl
sudo systemctl start mongod pritunl
EOUD

  lifecycle {
    ignore_changes = [ami]
  }

  tags = {
    "Name" = "${var.app}-instance"
  }
}

resource "aws_network_interface" "public_ip" {
  subnet_id                 = var.subnet_id
  ipv6_address_list_enabled = false
  private_ip_list_enabled   = false

  attachment {
    instance     = aws_instance.this.id
    device_index = 0
  }
}

#tfsec:ignore:aws-ec2-no-public-ingress-sgr
#tfsec:ignore:aws-ec2-no-public-egress-sgr
resource "aws_security_group" "this" {
  name        = "${var.app}-security-group"
  description = "Security group of the VPN Node"
  vpc_id      = var.vpc_id

  ingress {
    description = "Public HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Public HTTPS"
    from_port   = var.vpn_web_port
    to_port     = var.vpn_web_port

    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "VPN UDP"
    from_port   = var.vpn_port
    to_port     = var.vpn_port
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description      = "Outbound all traffic"
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    "Name" = "${var.app}-sg"
  }

}
