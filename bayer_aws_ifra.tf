provider "aws" {
  region = "us-east-1"
}

# VPC for EKS
resource "aws_vpc" "eks_vpc" {
  cidr_block = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
}

# Internet Gateway for VPC
resource "aws_internet_gateway" "eks_igw" {
  vpc_id = aws_vpc.eks_vpc.id
}

# Route Table for Public Subnet
resource "aws_route_table" "eks_public_route_table" {
  vpc_id = aws_vpc.eks_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.eks_igw.id
  }
}

# Public Subnet for EKS
resource "aws_subnet" "eks_public_subnet" {
  vpc_id            = aws_vpc.eks_vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-1a"
  map_public_ip_on_launch = true
}

# Private Subnet for EKS
resource "aws_subnet" "eks_private_subnet" {
  vpc_id            = aws_vpc.eks_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1a"
}

# Associate Route Table with Public Subnet
resource "aws_route_table_association" "eks_public_route_table_assoc" {
  subnet_id      = aws_subnet.eks_public_subnet.id
  route_table_id = aws_route_table.eks_public_route_table.id
}

# Security Group for EKS
resource "aws_security_group" "eks_sg" {
  name        = "bayer-eks-sg"
  vpc_id      = aws_vpc.eks_vpc.id
  description = "EKS Security Group"

  # Allow inbound SSH
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow inbound HTTPS
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# IAM Role for EKS Cluster
resource "aws_iam_role" "eks_role" {
  name = "eks-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = {
        Service = "eks.amazonaws.com"
      }
    }]
  })
}

# IAM Policy Attachment for EKS
resource "aws_iam_role_policy_attachment" "eks_policy_attach" {
  role       = aws_iam_role.eks_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# EKS Cluster
resource "aws_eks_cluster" "eks_cluster" {
  name     = "bayer-eks-cluster"
  role_arn = aws_iam_role.eks_role.arn

  vpc_config {
    subnet_ids = [aws_subnet.eks_public_subnet.id, aws_subnet.eks_private_subnet.id]
  }

  depends_on = [aws_internet_gateway.eks_igw]
}

# Node Group for EKS (Worker Nodes)
resource "aws_eks_node_group" "eks_node_group" {
  cluster_name    = aws_eks_cluster.eks_cluster.name
  node_group_name = "bayer-eks-node-group"
  node_role_arn   = aws_iam_role.eks_role.arn
  subnet_ids      = [aws_subnet.eks_public_subnet.id, aws_subnet.eks_private_subnet.id]

  scaling_config {
    desired_size = 2
    max_size     = 3
    min_size     = 1
  }
}

# Amazon ECR for Appointment Service
resource "aws_ecr_repository" "appointment_service" {
  name = "appointment-service"
}

# Amazon ECR for Patient Service
resource "aws_ecr_repository" "patient_service" {
  name = "patient-service"
}

# Output the EKS Cluster Name
output "eks_cluster_name" {
  value = aws_eks_cluster.eks_cluster.name
}

# Output the ECR URIs
output "appointment_service_ecr_uri" {
  value = aws_ecr_repository.appointment_service.repository_url
}

output "patient_service_ecr_uri" {
  value = aws_ecr_repository.patient_service.repository_url
}

# IAM Role for EC2 Worker Nodes
resource "aws_iam_role" "eks_node_role" {
  name = "eks-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}

# IAM Policy Attachment for EC2 Worker Nodes
resource "aws_iam_role_policy_attachment" "eks_worker_node_policy_attach" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

# Amazon CloudWatch for Monitoring EKS
resource "aws_cloudwatch_log_group" "eks_log_group" {
  name              = "/aws/eks/bayer-eks-cluster"
  retention_in_days = 30
}
