provider "aws" {
	region = "ap-south-1"
	profile = "mohit-ka-eks"
}



# Create VPC for Kubernetes Cluster
resource "aws_vpc" "app-vpc" {

  cidr_block       = "172.168.0.0/16"
  instance_tenancy = "default"
  enable_dns_hostnames = true
  tags = {
    service = "wp-eks"
  }
}


# Creating three subnets 
# Subnet-1
resource "aws_subnet" "sub1" {

  availability_zone = "ap-south-1a"
  cidr_block        = "172.168.0.0/24"
  vpc_id            = "${aws_vpc.app-vpc.id}"
  map_public_ip_on_launch = true
  tags = {
    "kubernetes.io/cluster/KubeCluster" = "shared"
  }
}

# Subnet-2
resource "aws_subnet" "sub2" {

  availability_zone = "ap-south-1b"
  cidr_block        = "172.168.1.0/24"
  vpc_id            = "${aws_vpc.app-vpc.id}"
  map_public_ip_on_launch = true
  tags = {
    "kubernetes.io/cluster/KubeCluster" = "shared"
  }
}

# Subnet-3
resource "aws_subnet" "sub3" {

  availability_zone = "ap-south-1c"
  cidr_block        = "172.168.3.0/24"
  vpc_id            = "${aws_vpc.app-vpc.id}"
  map_public_ip_on_launch = true
  tags = {
    "kubernetes.io/cluster/KubeCluster" = "shared"
  }
}


# Internet gateway
resource "aws_internet_gateway" "igw" {
depends_on=[
	aws_subnet.sub3
]
  vpc_id = "${aws_vpc.app-vpc.id}"

  tags = {
    Name = "main"
  }
}


# Route table for subnet
resource "aws_route_table" "wp-route" {
depends_on=[
	aws_internet_gateway.igw
]
  vpc_id = "${aws_vpc.app-vpc.id}"

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = "${aws_internet_gateway.igw.id}"
  }

  tags = {
    Name = "wp-route"
  }
}


# Route table association with subnet-1
resource "aws_route_table_association" "pub-association1" {
depends_on=[
	aws_route_table.wp-route
]
  subnet_id      = "${aws_subnet.sub1.id}"
  route_table_id = "${aws_route_table.wp-route.id}"
}

# Route table association with subnet-2
resource "aws_route_table_association" "pub-association2" {
depends_on=[
	aws_route_table.wp-route
]
  subnet_id      = "${aws_subnet.sub2.id}"
  route_table_id = "${aws_route_table.wp-route.id}"
}

# Route table association with subnet-3
resource "aws_route_table_association" "pub-association3" {
depends_on=[
	aws_route_table.wp-route
]
  subnet_id      = "${aws_subnet.sub3.id}"
  route_table_id = "${aws_route_table.wp-route.id}"
}


# IAM role for eks
resource "aws_iam_role" "eks-cluster-policy" {
  name = "eks-cluster-example"

  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "eks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
POLICY
}


# IAM policy attachment
resource "aws_iam_role_policy_attachment" "eks-cluster-AmazonEKSClusterPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks-cluster-policy.name
}


# Create EKS cluster
resource "aws_eks_cluster" "eks-cluster" {
  name     = "KubeCluster"
  role_arn = aws_iam_role.eks-cluster-policy.arn

  vpc_config {
    subnet_ids = [aws_subnet.sub1.id, aws_subnet.sub2.id, aws_subnet.sub2.id]
  }

  # Ensure that IAM Role permissions are created before and deleted after EKS Cluster handling.
  # Otherwise, EKS will not be able to properly delete EKS managed EC2 infrastructure such as Security Groups.
  depends_on = [
    aws_iam_role_policy_attachment.eks-cluster-AmazonEKSClusterPolicy,
  ]
}


# IAM role for NodeGroup
resource "aws_iam_role" "nodegroup_role" {
  name = "eks-node-group"

  assume_role_policy = jsonencode({
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
    Version = "2012-10-17"
  })
}

resource "aws_iam_role_policy_attachment" "worker-AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.nodegroup_role.name
}

resource "aws_iam_role_policy_attachment" "worker-AmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.nodegroup_role.name
}

resource "aws_iam_role_policy_attachment" "worker-AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.nodegroup_role.name
}


# Node Group for Cluster
resource "aws_eks_node_group" "eks-nodegrp" {
  cluster_name    = aws_eks_cluster.eks-cluster.name
  node_group_name = "NodeGroup1"
  node_role_arn   = aws_iam_role.nodegroup_role.arn
  subnet_ids      = [aws_subnet.sub1.id, aws_subnet.sub2.id, aws_subnet.sub2.id]
  scaling_config {
    desired_size = 3
    max_size     = 5
    min_size     = 3
  }

  # Ensure that IAM Role permissions are created before and deleted after EKS Node Group handling.
  # Otherwise, EKS will not be able to properly delete EC2 Instances and Elastic Network Interfaces.
  depends_on = [
    aws_iam_role_policy_attachment.worker-AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.worker-AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.worker-AmazonEC2ContainerRegistryReadOnly,
  ]
}


# Updating Local config file.
resource "null_resource" "command" {
depends_on = [ aws_eks_node_group.eks-nodegrp, ]

  provisioner "local-exec" {
    
    command = "aws eks update-kubeconfig --name KubeCluster --profile mohit-ka-eks"
  }
}


