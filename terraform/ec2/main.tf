resource "aws_vpc" "research" {
  cidr_block           = "10.10.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name    = "research-ec2-vs-serverless-vpc"
    Project = "EC2VsServerlessResearch"
  }
}

resource "aws_internet_gateway" "research" {
  vpc_id = aws_vpc.research.id

  tags = {
    Name = "research-igw"
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.research.id
  cidr_block              = "10.10.1.0/24"
  map_public_ip_on_launch = true

  tags = {
    Name = "research-public-subnet"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.research.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.research.id
  }

  tags = {
    Name = "research-public-route-table"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "app" {
  name        = "research-ec2-app-sg"
  description = "HTTP access for research application"
  vpc_id      = aws_vpc.research.id

  ingress {
    description = "Research HTTP endpoint"
    from_port   = 80
    to_port     = 80
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
    Project = "EC2VsServerlessResearch"
  }
}

resource "aws_iam_role" "ec2" {
  name = "research-ec2-ssm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2" {
  name = "research-ec2-instance-profile"
  role = aws_iam_role.ec2.name
}

resource "aws_instance" "app" {
  ami                         = var.ami_id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.app.id]
  associate_public_ip_address = true
  monitoring                  = true
  iam_instance_profile        = aws_iam_instance_profile.ec2.name

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  user_data = templatefile(
    "${path.module}/user_data.sh",
    {
      app_py_b64     = base64encode(file("${path.module}/../../application/ec2/app.py"))
      compute_py_b64 = base64encode(file("${path.module}/../../application/ec2/compute_logic.py"))
    }
  )

  root_block_device {
    volume_type = "gp3"
    volume_size = 8
    encrypted   = true
  }

  tags = {
    Name    = "research-fixed-ec2"
    Project = "EC2VsServerlessResearch"
  }
}
