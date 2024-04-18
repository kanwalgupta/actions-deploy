provider "aws" {
  region = "us-east-1"
}

terraform {
  backend "s3" {
    bucket = "mytfbucket-jigsaw"
    key    = "state.tfstate"
    region = "us-east-1"
    # Ensure all required configurations like encrypt, acl, etc., are specified if needed
  }
}

resource "aws_instance" "ec2_instance" {
  ami           = "ami-0d7a109bf30624c99" # you may need to update this
  instance_type = "t2.micro"
  iam_instance_profile = aws_iam_instance_profile.ec2_profile.name
  key_name = "sample-machine-pair" # update this
  user_data = <<-EOF
  #!/bin/bash
  export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
  export REGION=us-east-1
  export BACKEND_CONTAINER=flask_api
  export REPOSITORY_NAME=flask_app
  sudo yum update -y
  sudo yum install docker -y
  sudo systemctl start docker

  aws ecr get-login-password --region $REGION | sudo docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com
  sudo docker pull $AWS_ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$REPOSITORY_NAME:latest

  while ! sudo docker container ls | grep -wq $BACKEND_CONTAINER; do
    sudo docker run -d -p 80:80 --name $BACKEND_CONTAINER --platform=linux/amd64/v2 $AWS_ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$REPOSITORY_NAME
    sleep 5
  done
  EOF

  vpc_security_group_ids = [aws_security_group.http_backend_security.id, aws_security_group.ssh_backend_security.id]


  tags = {
      Name = "backend iam server"
  }
}

resource "aws_iam_role" "ec2_ecr_role" {

    assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
      Service = "ec2.amazonaws.com"
      }
      Sid = ""
      },
    ]
  })
}

# create instance profile, as a container for the iam role
resource "aws_iam_instance_profile" "ec2_profile" {
 role = aws_iam_role.ec2_ecr_role.name
}

# attach role to policy
resource "aws_iam_role_policy_attachment" "ecr_read_only" {
 role = aws_iam_role.ec2_ecr_role.name
 policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}