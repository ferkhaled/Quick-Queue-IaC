terraform {
 required_providers {
   aws = {
     source = "hashicorp/aws"
     version = ">= 5.25.0"
   }
}

}

provider "aws" {
  region = "us-east-1"
}

# Create a VPC
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "qq_vpc"
  }
}

# Create an internet gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "my-igw"
  }
}

# Create a public subnet
resource "aws_subnet" "public" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "my-public-subnet"
  }
}

# Create a route table for the public subnet
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "my-public-route-table"
  }
}

# Associate the route table with the public subnet
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# Create a security group to allow SSH access
resource "aws_security_group" "allow_ssh" {
  name        = "allow_ssh"
  description = "Allow SSH inbound traffic"
  vpc_id      = aws_vpc.main.id

ingress = [
    for port in [22, 8080, 9000, 9090, 80] : {
      description      = "TLS from VPC"
      from_port        = port
      to_port          = port
      protocol         = "tcp"
      ipv6_cidr_blocks = ["::/0"]
      self             = false
      prefix_list_ids  = []
      security_groups  = []
      cidr_blocks      = ["0.0.0.0/0"]
    }
  ]

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"          # Allow all outbound traffic
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "allow_ssh"
  }
}

# Create an EC2 instance with 2 vCPUs (using t3.medium as example)
resource "aws_instance" "qq_k8s_master" {
  ami           = "ami-064519b8c76274859" # Amazon Linux 2 AMI ID (choose the region-appropriate one)
  instance_type = "t3.medium"             # Instance type with 2 vCPUs

  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.allow_ssh.id]
  associate_public_ip_address = true  # Enable public IP
  key_name = "my-key"  # Reference your key pair for SSH access

  tags = {
    Name = "qq_k8s_master"
  }
}


# Create two private VPS with 1 CPU each
resource "aws_instance" "qq_k8s_node_1" {
  ami           = "ami-064519b8c76274859"  # Same AMI for Ubuntu
  instance_type = "t3.micro"               # Instance type with 1 vCPU (t3.micro)
  subnet_id     = aws_subnet.public.id    # Launch in private subnet
  key_name      = "my-key"                 # Specify SSH key (optional)
  vpc_security_group_ids      = [aws_security_group.allow_ssh.id]
  tags = {
    Name = "qq_k8s_node_1"
  }

  associate_public_ip_address = true      # This is a private instance, no public IP
}

resource "aws_instance" "qq_k8s_node_2" {
  ami           = "ami-064519b8c76274859"  # Same AMI for Ubuntu
  instance_type = "t3.micro"               # Instance type with 1 vCPU (t3.micro)
  subnet_id     = aws_subnet.public.id    # Launch in private subnet
  key_name      = "my-key"                 # Specify SSH key (optional)
  vpc_security_group_ids      = [aws_security_group.allow_ssh.id]

tags = {
    Name = "qq_k8s_node_2"
  }
 associate_public_ip_address = true      # This is a private instance, no public IP
}




resource "local_file" "inventory" {
  filename = "../ansible/inventory"
  content = templatefile("ansible_inventory.tftpl", {
    master_ip = aws_instance.qq_k8s_master.public_ip
    node_ips = [
      aws_instance.qq_k8s_node_1.public_ip,
      aws_instance.qq_k8s_node_2.public_ip
    ]
  })
}



resource "aws_key_pair" "my_key" {
  key_name   = "my-key"
  public_key = file("~/.ssh/qq_rsa.pub")  # Path to your public SSH key
}

