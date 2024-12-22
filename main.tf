provider "aws" {
  region                   = "us-east-1"
  shared_credentials_files = ["C:/Users/PC/.aws/credentials"]
  profile                  = "default"
}

# Create default VPC data source
data "aws_vpc" "default" {
  default = true
}

# Create subnet in availability zone us-east-1a
resource "aws_subnet" "subnet_1a" {
  vpc_id                  = data.aws_vpc.default.id
  cidr_block              = "172.31.1.0/24" # CIDR block within the default VPC range
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true
  tags = {
    Name = "subnet-1a"
  }
}

# Create subnet in availability zone us-east-1b
resource "aws_subnet" "subnet_1b" {
  vpc_id                  = data.aws_vpc.default.id
  cidr_block              = "172.31.2.0/24" # Another CIDR block within the default VPC range
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true
  tags = {
    Name = "subnet-1b"
  }
}

# Create security group to allow all inbound and outbound traffic
resource "aws_security_group" "allow_all" {
  name        = "allow_all"
  description = "Allow all inbound and outbound traffic"

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Create EC2 Key Pair resource
resource "aws_key_pair" "keypair" {
  key_name   = "my-keypair"                            # Choose a name for the keypair
  public_key = file("C:/Users/PC/.ssh/my-keypair.pub") # Path to your public key
}

output "key_pair_name" {
  value = aws_key_pair.keypair.key_name
}

output "key_pair_id" {
  value = aws_key_pair.keypair.id
}

# Create EC2 instance for Jenkins and Apache server in subnet_1a (us-east-1a)
resource "aws_instance" "jenkins_apache_server" {
  ami                         = "ami-0e2c8caa4b6378d8c" # Replace with the latest Ubuntu AMI for us-east-1
  instance_type               = "t2.micro"
  subnet_id                   = aws_subnet.subnet_1a.id # Launch in subnet_1a (us-east-1a)
  vpc_security_group_ids      = [aws_security_group.allow_all.id]
  associate_public_ip_address = true # Enable public IP address for the EC2 instance

  tags = {
    Name = "Jenkins and Apache Server"
  }

  user_data = <<-EOF
  #!/bin/bash

# Update system packages
sudo apt update -y

# Install nginx if not already installed
sudo apt install -y nginx

# Create a simple HTML file to show the message
echo "Creating HTML file with 'SERVER1' message..."

# Use 'cat' to prevent issues with special characters
sudo bash -c 'cat > /var/www/html/index.html << EOF
<!DOCTYPE html>
<html>
  <head>
    <title>Simple Server Page</title>
  </head>
  <body>
    <h1>SERVER1</h1>
  </body>
</html>
EOF'

# Ensure nginx is running
sudo systemctl enable nginx
sudo systemctl start nginx

# Show completion message
echo "Nginx is up and running. You can view the page at http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)"

EOF
}


# Create EC2 instance for Docker server in subnet_1b (us-east-1b)
resource "aws_instance" "docker_server" {
  ami                         = "ami-0e2c8caa4b6378d8c" # Replace with the latest Ubuntu AMI for us-east-1
  instance_type               = "t2.micro"
  subnet_id                   = aws_subnet.subnet_1b.id # Launch in subnet_1b (us-east-1b)
  vpc_security_group_ids      = [aws_security_group.allow_all.id]
  associate_public_ip_address = true # Enable public IP address for the EC2 instance

  tags = {
    Name = "Nginx Server"
  }

  user_data = <<-EOF
  #!/bin/bash

# Update system packages
sudo apt update -y

# Install nginx if not already installed
sudo apt install -y nginx

# Create a simple HTML file to show the message
echo "Creating HTML file with 'SERVER2' message..."

# Use 'cat' to prevent issues with special characters
sudo bash -c 'cat > /var/www/html/index.html << EOF
<!DOCTYPE html>
<html>
  <head>
    <title>Simple Server Page</title>
  </head>
  <body>
    <h1>SERVER2</h1>
  </body>
</html>
EOF'

# Ensure nginx is running
sudo systemctl enable nginx
sudo systemctl start nginx

# Show completion message
echo "Nginx is up and running. You can view the page at http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)"

EOF
}

# Output the public IP of Docker EC2 instance
output "ec2_public_ip_docker" {
  value       = aws_instance.docker_server.public_ip
  description = "The public IP address of the Docker EC2 instance"
}

# Register Docker EC2 instance to the unified target group
resource "aws_lb_target_group_attachment" "docker_attachment" {
  target_group_arn = aws_lb_target_group.unified_target_group.arn
  target_id        = aws_instance.docker_server.id
  port             = 80
}






# Create Application Load Balancer (ALB)
resource "aws_lb" "my_alb" {
  name               = "my-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.allow_all.id]
  subnets            = [aws_subnet.subnet_1a.id, aws_subnet.subnet_1b.id]  # Include both subnets

  enable_deletion_protection = false

  tags = {
    Name = "my-alb"
  }
}

# Create a single Target Group for both instances
resource "aws_lb_target_group" "unified_target_group" {
  name     = "unified-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.default.id

  health_check {
    path                = "/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 3
    unhealthy_threshold = 3
  }
}

# Register Jenkins Apache EC2 instance to the unified target group
resource "aws_lb_target_group_attachment" "jenkins_apache_attachment" {
  target_group_arn = aws_lb_target_group.unified_target_group.arn
  target_id        = aws_instance.jenkins_apache_server.id
  port             = 80
}



# Create an ALB Listener to forward traffic to the unified target group
resource "aws_lb_listener" "http_listener" {
  load_balancer_arn = aws_lb.my_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.unified_target_group.arn
  }
}

# Output the DNS name of the Application Load Balancer
output "alb_dns_name" {
  value = aws_lb.my_alb.dns_name
}

# Output the public IP of Jenkins Apache EC2 instance
output "ec2_public_ip_jenkins" {
  value       = aws_instance.jenkins_apache_server.public_ip
  description = "The public IP address of the Jenkins Apache EC2 instance"
}

