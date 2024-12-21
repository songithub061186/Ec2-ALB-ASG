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
    Name = "Jenkins Server"
  }

  user_data = <<-EOF
  #!/bin/bash
echo "start"

# Update package lists
sudo apt update -y

# Set hostname for Jenkins
sudo hostnamectl set-hostname jenkins

# Install OpenJDK and required packages
sudo apt install -y openjdk-21-jdk openjdk-21-jre

# Add Jenkins repository key and configure Jenkins repository
sudo wget -q -O /usr/share/keyrings/jenkins-keyring.asc https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key
echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/" | sudo tee /etc/apt/sources.list.d/jenkins.list > /dev/null

# Install Jenkins
sudo apt update -y
sudo apt install -y jenkins

# Change the Jenkins port to 9090
sudo sed -i 's/HTTP_PORT=8080/HTTP_PORT=9090/' /etc/default/jenkins

# Start Jenkins and enable it to start on boot
sudo systemctl start jenkins
sudo systemctl enable jenkins

echo "Jenkins is now running on port 9090"

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
set -e  # Exit on any error
exec > >(tee /var/log/ip-display.log) 2>&1

echo "Starting IP address display setup..."

# Update package list
sudo apt update -y

# Install nginx
echo "Installing nginx..."
sudo apt install -y nginx

# Enable and start nginx
sudo systemctl enable nginx
sudo systemctl start nginx

# Fetch public IP address using multiple fallbacks
echo "Fetching public IP address..."
public_ip=$(curl -s http://icanhazip.com || 
           curl -s http://ifconfig.me || 
           curl -s http://ip.appspot.com ||
           echo "Could not fetch IP address")

# Create a more styled HTML file
echo "<!DOCTYPE html>
<html>
  <head>
    <title>Server Public IP Address</title>
    <style>
      body {
        font-family: Arial, sans-serif;
        display: flex;
        justify-content: center;
        align-items: center;
        height: 100vh;
        margin: 0;
        background-color: #f0f2f5;
      }
      .container {
        text-align: center;
        padding: 20px;
        background-color: white;
        border-radius: 8px;
        box-shadow: 0 2px 4px rgba(0, 0, 0, 0.1);
      }
      h1 {
        color: #1a73e8;
      }
      .ip {
        font-size: 24px;
        color: #202124;
        margin: 20px 0;
      }
    </style>
  </head>
  <body>
    <div class='container'>
      <h1>Server Public IP Address</h1>
      <div class='ip'>$public_ip</div>
      <p>Last updated: $(date)</p>
    </div>
  </body>
</html>" | sudo tee /var/www/html/index.html > /dev/null

# Ensure nginx is running
sudo systemctl restart nginx

# Verify nginx status
echo "Checking nginx status..."
sudo systemctl status nginx

echo "Setup completed!"
echo "You can now access your public IP at: http://$public_ip"

EOF
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

# Register Docker EC2 instance to the unified target group
resource "aws_lb_target_group_attachment" "docker_attachment" {
  target_group_arn = aws_lb_target_group.unified_target_group.arn
  target_id        = aws_instance.docker_server.id
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

# Output the public IP of Docker EC2 instance
output "ec2_public_ip_docker" {
  value       = aws_instance.docker_server.public_ip
  description = "The public IP address of the Docker EC2 instance"
}
