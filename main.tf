terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.0"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = var.region
}

################################

# Create VPC and Networking resourecs
resource "aws_vpc" "vault" {
  cidr_block           = var.address_space
  enable_dns_hostnames = true

  tags = {
    Name          = "vault-cloudhsm-vpc"
  }
}

resource "aws_subnet" "vault" {
  vpc_id     = aws_vpc.vault.id
  cidr_block = var.subnet_prefix_1
  availability_zone = var.availability_zone

  tags = {
    Name          = "vault-subnet"
  }
}

resource "aws_security_group" "vault" {
  name = "vault-security-group"

  vpc_id = aws_vpc.vault.id

  ingress {
    from_port   = 22 # SSH
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80 # HTTP
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443 # HTTPS
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 8200 # Vault API
    to_port     = 8201 # Vault Replication & Request Forwarding
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 8 # Ping Testing
    to_port     = 0
    protocol    = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port       = 0 # Outbound Internet Access
    to_port         = 0
    protocol        = "-1"
    cidr_blocks     = ["0.0.0.0/0"]
    prefix_list_ids = []
  }

  tags = {
    Name          = "vault-security-group"
  }
}

resource "aws_internet_gateway" "vault" {
  vpc_id = aws_vpc.vault.id

  tags = {
    Name          = "vault-internet-gateway"
  }
}

resource "aws_route_table" "vault" {
  vpc_id = aws_vpc.vault.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.vault.id
  }
}

resource "aws_route_table_association" "vault" {
  subnet_id      = aws_subnet.vault.id
  route_table_id = aws_route_table.vault.id
}

################################

# Find latest Ubuntu 18.04 image
data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name = "name"
    #values = ["ubuntu/images/hvm-ssd/ubuntu-disco-19.04-amd64-server-*"]
    values = ["ubuntu/images/hvm-ssd/ubuntu-bionic-18.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical
}

# Creates and associates Elastic IP
resource "aws_eip" "vault" {
  instance = aws_instance.vault.id
  vpc      = true
}

resource "aws_eip_association" "vault" {
  instance_id   = aws_instance.vault.id
  allocation_id = aws_eip.vault.id
}

# Provisions EC2 instance that will run Vault
resource "aws_instance" "vault" {
  availability_zone           = var.availability_zone
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  key_name                    = aws_key_pair.vault.key_name
  associate_public_ip_address = true
  subnet_id                   = aws_subnet.vault.id
  vpc_security_group_ids      = [aws_security_group.vault.id, aws_cloudhsm_v2_cluster.cloudhsm_v2_cluster.security_group_id]
  root_block_device {
    volume_size = 20
  }

  tags = {
    Name          = "vault-instance"
  }
}

# Generate an ephemeral private key to create SSH key pair
resource "tls_private_key" "vault" {
  algorithm = "RSA"
}

locals {
  private_key_filename = "instruqt-ssh-key.pem"
}

resource "aws_key_pair" "vault" {
  key_name   = local.private_key_filename
  public_key = tls_private_key.vault.public_key_openssh

  provisioner "local-exec" {
    command = <<-EOT
      echo '${tls_private_key.vault.private_key_pem}' > ./id_rsa.pem
      chmod 400 ./id_rsa.pem
    EOT
  }
}

# Provision CloudHSM
resource "aws_cloudhsm_v2_cluster" "cloudhsm_v2_cluster" {
  hsm_type   = "hsm1.medium"
  subnet_ids = [aws_subnet.vault.id]

  tags = {
    Name = "vault-aws_cloudhsm_v2_cluster"
  }
}

resource "aws_cloudhsm_v2_hsm" "cloudhsm_v2_hsm" {
  cluster_id        = aws_cloudhsm_v2_cluster.cloudhsm_v2_cluster.cluster_id
  availability_zone = var.availability_zone
  subnet_id = aws_subnet.vault.id
}