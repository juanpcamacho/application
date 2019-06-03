##################################################################################
# VARIABLES
##################################################################################

variable "aws_access_key" {}

variable "aws_region" {}

variable "aws_secret_key" {}
variable "private_key_path" {}

variable "github_url" {}

variable "key_name" {
  default = "etax"
}

variable "company" {
  default = "gorilla"
}

variable "app" {
  default = "timeoffmanagement"
}

variable "network_address_space" {
  default = "10.0.0.0/16"
}

variable "amis" {
  description = "Base AMI to launch the instances"
  default = {
  us-east-1 = "ami-0c6b1d09930fac512"
  }
}

variable "billing_code_tag" {}
variable "environment_tag" {}

variable "instance_count" {
  default = 2
}

variable "subnet_count" {
  default = 2
}

variable "git" {
  default = "https://github.com/juanpcamacho/application.git"
}

##################################################################################
# PROVIDERS
##################################################################################

provider "aws" {
  access_key = "${var.aws_access_key}"
  secret_key = "${var.aws_secret_key}"
  region     = "${var.aws_region}"
}

provider "github" {
  base_url = "https://github.com/"
  token = "5abc4baee52b76b3c3121794c409263afb1c0c20"
  organization = ""
}

##################################################################################
# DATA
##################################################################################

data "aws_availability_zones" "available" {}
data "aws_ami" "custom" {
  owners = ["self"]
  filter {
    name   = "tag:Component"
    values = ["web"]
  }
  most_recent = true
}



##################################################################################
# RESOURCES
##################################################################################

# NETWORKING #
resource "aws_vpc" "vpc" {
  cidr_block = "${var.network_address_space}"

  tags = {
    Name        = "${var.environment_tag}-vpc"
    BillingCode = "${var.billing_code_tag}"
    Environment = "${var.environment_tag}"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = "${aws_vpc.vpc.id}"

  tags = {
    Name        = "${var.environment_tag}-igw"
    BillingCode = "${var.billing_code_tag}"
    Environment = "${var.environment_tag}"
  }
}

resource "aws_subnet" "PublicSubnet" {
  count                   = "${var.subnet_count}"
  cidr_block              = "${cidrsubnet(var.network_address_space, 8, count.index + 1)}"
  vpc_id                  = "${aws_vpc.vpc.id}"
  map_public_ip_on_launch = "true"
  availability_zone       = "${data.aws_availability_zones.available.names[count.index]}"

  tags = {
    Name        = "Public-subnet-${count.index + 1}"
    BillingCode = "${var.billing_code_tag}"
    Environment = "${var.environment_tag}"
  }
}

resource "aws_subnet" "PrivateSubnet" {
  count                   = "${var.subnet_count}"
  cidr_block              = "${cidrsubnet(var.network_address_space, 8, count.index + 3)}"
  vpc_id                  = "${aws_vpc.vpc.id}"
  map_public_ip_on_launch = "false"
  availability_zone       = "${data.aws_availability_zones.available.names[count.index]}"

  tags = {
    Name        = "Private-subnet-${count.index + 1}"
    BillingCode = "${var.billing_code_tag}"
    Environment = "${var.environment_tag}"
  }
}

# Elastic IP for the NAT #
resource "aws_eip" "nat" {
  tags = {
    Name        = "EIP"
    BillingCode = "${var.billing_code_tag}"
    Environment = "${var.environment_tag}"
  }
}

# NAT Gateway #
resource "aws_nat_gateway" "NATgw" {
  allocation_id = "${aws_eip.nat.id}"
  subnet_id     = "${element(aws_subnet.PublicSubnet.*.id,0)}"

  tags = {
    Name        = "NAT-GW"
    BillingCode = "${var.billing_code_tag}"
    Environment = "${var.environment_tag}"
  }
}

# ROUTING #
resource "aws_route_table" "Pubrtb" {
  vpc_id = "${aws_vpc.vpc.id}"

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = "${aws_internet_gateway.igw.id}"
  }

  tags = {
    Name        = "${var.environment_tag}-Pubrtb"
    BillingCode = "${var.billing_code_tag}"
    Environment = "${var.environment_tag}"
  }
}

resource "aws_route_table" "Prvrtb" {
  vpc_id = "${aws_vpc.vpc.id}"

  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = "${aws_nat_gateway.NATgw.id}"
  }

  tags = {
    Name        = "${var.environment_tag}-Prvrtb"
    BillingCode = "${var.billing_code_tag}"
    Environment = "${var.environment_tag}"
  }
}

resource "aws_route_table_association" "Pubrta-subnet" {
  count          = "${var.subnet_count}"
  subnet_id      = "${element(aws_subnet.PublicSubnet.*.id,count.index)}"
  route_table_id = "${aws_route_table.Pubrtb.id}"
}

resource "aws_route_table_association" "Privrta-subnet" {
  count          = "${var.subnet_count}"
  subnet_id      = "${element(aws_subnet.PrivateSubnet.*.id,count.index)}"
  route_table_id = "${aws_route_table.Prvrtb.id}"
}

# SECURITY GROUPS #
resource "aws_security_group" "elb-sg" {
  name   = "nginx_elb_sg"
  vpc_id = "${aws_vpc.vpc.id}"

  #Allow HTTP from anywhere
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  #allow all outbound
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.environment_tag}-elb-sg"
    BillingCode = "${var.billing_code_tag}"
    Environment = "${var.environment_tag}"
  }
}

# Nginx security group 
resource "aws_security_group" "nginx-sg" {
  name   = "nginx_sg"
  vpc_id = "${aws_vpc.vpc.id}"

  # SSH access from anywhere
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTP access from the VPC
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["${var.network_address_space}"]
  }
# HTTP access from the VPC
  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["${var.network_address_space}"]
  }
  # outbound internet access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.environment_tag}-nginx-sg"
    BillingCode = "${var.billing_code_tag}"
    Environment = "${var.environment_tag}"
  }
}

### Creating EC2 instance (Bastion)
resource "aws_instance" "bastion" {
  ami               = "${lookup(var.amis,var.aws_region)}"
  key_name               = "${var.key_name}"
  vpc_security_group_ids = ["${aws_security_group.nginx-sg.id}"]
  source_dest_check = false
  instance_type = "t2.micro"
  subnet_id = "${element(aws_subnet.PublicSubnet.*.id,0)}"
  iam_instance_profile = "EC2"

  tags = {
    Name        = "${var.environment_tag}-Bastion"
    BillingCode = "${var.billing_code_tag}"
    Environment = "${var.environment_tag}"
  }
}

# Create a new load balancer
resource "aws_elb" "gorillaELB" {
  name               = "gorilla-elb"
  #availability_zones = "${data.aws_availability_zones.available.names}"
  subnets            = "${aws_subnet.PublicSubnet.*.id}"
  security_groups    = ["${aws_security_group.elb-sg.id}"]
  listener {
    instance_port     = 3000
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }


  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    target              = "tcp:3000"
    interval            = 30
  }

  cross_zone_load_balancing   = true
  idle_timeout                = 400
  connection_draining         = true
  connection_draining_timeout = 400

  tags = {
    Name        = "${var.environment_tag}-elb"
    BillingCode = "${var.billing_code_tag}"
    Environment = "${var.environment_tag}"
  }
}


## Creating Launch Configuration
resource "aws_launch_configuration" "gorilla_lc" {
  image_id               = "${data.aws_ami.custom.id}"
  instance_type          = "t2.micro"
  security_groups        = ["${aws_security_group.nginx-sg.id}"]
  key_name               = "${var.key_name}"
  iam_instance_profile   = "EC2"
  user_data = <<-EOF
              #!/bin/bash
              sudo yum update -y
              sudo yum install ruby -y
              sudo yum install wget -y
              cd /home/ec2-user
              wget "https://aws-codedeploy-us-east-1.s3.us-east-1.amazonaws.com/latest/install"
              chmod +x ./install
              sudo ./install auto
              sudo pm2 start npm --name "WebApp" --cwd /timeoff-management -- start
              EOF
  lifecycle {
    create_before_destroy = true
  }
}

## Creating AutoScaling Group
resource "aws_autoscaling_group" "gorilla-ASC" {
  launch_configuration = "${aws_launch_configuration.gorilla_lc.id}"
  vpc_zone_identifier  = "${aws_subnet.PrivateSubnet.*.id}"
  name                 = "${var.company}-ASG"
  min_size = 2
  max_size = 6
  load_balancers = ["${aws_elb.gorillaELB.name}"]
  health_check_type = "ELB"
  tag {
    key                 = "Name"
    value               = "${var.app}-${var.environment_tag}"
    propagate_at_launch = true
  }
}

##################################################################################
# CI/CD Implementation
##################################################################################
##Creation of the S3 Bucket for Artifact store
resource "aws_s3_bucket" "b" {
  bucket = "${var.company}-art-s3"
  acl    = "private"

  tags = {
    Name        = "${var.environment_tag}-S3"
    BillingCode = "${var.billing_code_tag}"
    Environment = "${var.environment_tag}"
  }
}

resource "aws_iam_role" "CodeBuildRole" {
  name = "CodeBuildRole"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "codebuild.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "CodeBuildRole" {
  role = "${aws_iam_role.CodeBuildRole.name}"

  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Resource": [
        "*"
      ],
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "ec2:CreateNetworkInterface",
        "ec2:DescribeDhcpOptions",
        "ec2:DescribeNetworkInterfaces",
        "ec2:DeleteNetworkInterface",
        "ec2:DescribeSubnets",
        "ec2:DescribeSecurityGroups",
        "ec2:DescribeVpcs"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:*"
      ],
      "Resource": [
        "${aws_s3_bucket.b.arn}",
        "${aws_s3_bucket.b.arn}/*"
      ]
    }
  ]
}
POLICY
}

resource "aws_codebuild_project" "CodeBuild" {
  name          = "${var.company}-${var.app}"
  description   = "${var.company}-${var.app}"
  build_timeout = "5"
  service_role  = "${aws_iam_role.CodeBuildRole.arn}"

  artifacts {
    type = "S3"
    location = "${aws_s3_bucket.b.id}"
    name = "${var.company}-${var.app}"
    packaging = "ZIP"
  }


  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/standard:2.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"

    environment_variable {
      name  = "Name"
      value = "${var.company}-${var.app}-CB"
    }

    environment_variable {
      name  = "BillingCode"
      value = "${var.billing_code_tag}"
    }
  }

  source {
    type            = "GITHUB"
    location        = "${var.git}"
    git_clone_depth = 1
  }

  tags = {
    Name        = "${var.environment_tag}-CBP"
    BillingCode = "${var.billing_code_tag}"
    Environment = "${var.environment_tag}"
  }
}

resource "aws_iam_role" "CodeDeployRole" {
  name = "CodeDeploy"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "",
      "Effect": "Allow",
      "Principal": {
        "Service": "codedeploy.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "AWSCodeDeployRole" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSCodeDeployRole"
  role       = "${aws_iam_role.CodeDeployRole.name}"
}

resource "aws_codedeploy_app" "CodeDeploy" {
  compute_platform = "Server"
  name             = "${var.company}-${var.app}"
}

resource "aws_codedeploy_deployment_config" "CodeDeploy-Conf" {
  deployment_config_name = "Healthy"

  minimum_healthy_hosts {
    type  = "HOST_COUNT"
    value = 1
  }
}

resource "aws_codedeploy_deployment_group" "CodeDeploy-GP" {
  app_name              = "${aws_codedeploy_app.CodeDeploy.name}"
  deployment_group_name = "${var.company}-${var.app}-dgn"
  service_role_arn      = "${aws_iam_role.CodeDeployRole.arn}"

  ec2_tag_set {
    ec2_tag_filter {
      key   = "Name"
      type  = "KEY_AND_VALUE"
      value = "${var.app}-${var.environment_tag}"
    }

  }


  auto_rollback_configuration {
    enabled = true
    events  = ["DEPLOYMENT_FAILURE"]
  }
}

resource "aws_iam_role" "CodePipeline" {
  name = "CodePipeline"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "codepipeline.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "codepipeline_policy" {
  name = "codepipeline_policy"
  role = "${aws_iam_role.CodePipeline.id}"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect":"Allow",
      "Action":"s3:*",
      "Resource": [
        "${aws_s3_bucket.b.arn}",
        "${aws_s3_bucket.b.arn}/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "codebuild:BatchGetBuilds",
        "codebuild:StartBuild"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": "codedeploy:*",
      "Resource": "*"
    }
  ]
}
EOF
}


resource "aws_codepipeline" "codepipeline" {
  name     = "${var.company}-${var.app}-pl"
  role_arn = "${aws_iam_role.CodePipeline.arn}"

  artifact_store {
    location = "${aws_s3_bucket.b.bucket}"
    type     = "S3"

#    encryption_key {
#      id   = "${data.aws_kms_alias.s3kmskey.arn}"
#      type = "KMS"
#    }
  }

  stage {
    name = "Source"

    action {
      name             = "GitHub"
      category         = "Source"
      owner            = "ThirdParty"
      provider         = "GitHub"
      version          = "1"
      output_artifacts = ["source_output"]

      configuration = {
        Owner  = "juanpcamacho"
        Repo   = "application"
        Branch = "master"
        OAuthToken = "97797ff22aa0c6f722bc4c060528c63317c7aacc"
      }
    }
  }

  stage {
    name = "Build"

    action {
      name             = "Build"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      input_artifacts  = ["source_output"]
      output_artifacts = ["build_output"]
      version          = "1"

      configuration = {
        ProjectName = "${aws_codebuild_project.CodeBuild.name}"
      }
    }
  }

  stage {
    name = "Deploy"

    action {
      name            = "Deploy"
      category        = "Deploy"
      owner           = "AWS"
      provider        = "CodeDeploy"
      input_artifacts = ["build_output"]
      version         = "1"

      configuration = {
        ApplicationName = "${aws_codedeploy_app.CodeDeploy.name}"
        DeploymentGroupName = "${aws_codedeploy_deployment_group.CodeDeploy-GP.deployment_group_name}"
      }
    }
  }
}

##################################################################################
# OUTPUT
##################################################################################

output "elb_dns_name" {
  value = "${aws_elb.gorillaELB.dns_name}"
}