terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

#################################
# DATA SOURCES
#################################

data "aws_availability_zones" "available" {}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical Ubuntu

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

#################################
# VPC
#################################

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "miracle-vpc"
  }
}

#################################
# SUBNETS
#################################

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "miracle-public-subnet"
  }
}


resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "miracle-private-subnet"
  }
}

#################################
# INTERNET GATEWAY
#################################

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "miracle-igw"
  }
}

#################################
# NAT GATEWAY
#################################

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "miracle-nat-eip"
  }
}


resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id

  depends_on = [
    aws_internet_gateway.igw
  ]

  tags = {
    Name = "miracle-nat-gateway"
  }
}

#################################
# ROUTE TABLES
#################################

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "miracle-public-route-table"
  }
}


resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }

  tags = {
    Name = "miracle-private-route-table"
  }
}


resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}


resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

#################################
# SECURITY GROUPS
#################################

resource "aws_security_group" "public" {

  name   = "miracle-public-sg"
  vpc_id = aws_vpc.main.id


  ingress {
    description = "SSH access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }


  ingress {
    description = "HTTP access"
    from_port   = 80
    to_port     = 81
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
    Name = "miracle-public-sg"
  }
}



resource "aws_security_group" "private" {

  name   = "miracle-private-sg"
  vpc_id = aws_vpc.main.id


  ingress {
    description     = "SSH from public instance"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [
      aws_security_group.public.id
    ]
  }

# Redis port, only from vote/result SG
  ingress {
    description     = "Redis from Vote/Result"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.public.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }


  tags = {
    Name = "miracle-private-sg"
  }
}

resource "aws_security_group" "database" {

  name   = "miracle-database-sg"
  vpc_id = aws_vpc.main.id

 ingress {
    description     = "SSH from public instance"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [
      aws_security_group.public.id
    ]
  }

  ingress {
    description     = "postgres from private instances"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [
      aws_security_group.private.id, aws_security_group.public.id
    ]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "miracle-database-sg"
  }
}
#################################
# EC2 INSTANCES
#################################

resource "aws_instance" "public_instance" {

  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [
    aws_security_group.public.id
  ]

  key_name = "supercool-miracle-key"

  tags = {
    Name = "miracle-public-instance"
  }
}



resource "aws_instance" "backend_instance_1" {

  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.private.id
  vpc_security_group_ids = [
    aws_security_group.private.id
  ]

  key_name = "supercool-miracle-key"

  tags = {
    Name = "miracle-backend-instance-1"
  }
}



resource "aws_instance" "database_instance_2" {

  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.private.id
  vpc_security_group_ids = [
    aws_security_group.database.id
  ]

  key_name = "supercool-miracle-key"

  tags = {
    Name = "miracle-database-instance-2"
  }
}


#################################
# OUTPUTS
#################################

output "public_ip" {
  value = aws_instance.public_instance.public_ip
}

output "backend_instance_1_ip" {
  value = aws_instance.backend_instance_1.private_ip
}
output "database_instance_2_ip" {
  value = aws_instance.database_instance_2.private_ip
}
