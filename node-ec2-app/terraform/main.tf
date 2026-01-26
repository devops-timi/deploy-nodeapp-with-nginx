resource "aws_instance" "app_server" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t2.micro"
  key_name      = var.instance_key
  vpc_security_group_ids = [aws_security_group.node_app_sg.id]
  iam_instance_profile = aws_iam_instance_profile.ec2_profile.name  

  root_block_device {
    volume_size           = 8
    volume_type           = "gp3"
    delete_on_termination = true
    encrypted             = true
  }

  user_data = <<-EOF
              #!/bin/bash
              set -e
              
              # Log everything
              exec > >(tee /var/log/user-data.log)
              exec 2>&1
              echo "Starting EC2 setup at $(date)"
              
              # Update system
              apt-get update -y
              
              # Install Docker
              apt-get install -y docker.io
              
              # Start Docker
              systemctl start docker
              systemctl enable docker

              # Add ubuntu user to docker group
              usermod -aG docker ubuntu
              
              # Install Nginx
              apt-get install -y nginx
              
              # Configure Nginx reverse proxy
              cat > /etc/nginx/sites-available/nodeapp <<'NGINX_CONFIG'
              server {
                listen 80;
                server_name _;

                location / {
                  proxy_pass http://127.0.0.1:3000;
                  proxy_http_version 1.1;

                  proxy_set_header Host $host;
                  proxy_set_header X-Real-IP $remote_addr;
                  proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                  proxy_set_header X-Forwarded-Proto $scheme;
                }
              }
              NGINX_CONFIG
              
              # Enable Nginx site
              ln -sf /etc/nginx/sites-available/nodeapp /etc/nginx/sites-enabled/nodeapp
              rm -f /etc/nginx/sites-enabled/default

              # Test and restart Nginx
              nginx -t
              systemctl restart nginx
              systemctl enable nginx
              
              # Create app directory
              mkdir -p /opt/app
              chown ubuntu:ubuntu /opt/app
              
              echo "EC2 setup completed successfully at $(date)"
              EOF

  tags = {
    Name = "node-nginx-instance"
  }
}

resource "aws_iam_role" "ec2_ecr_role" {
  name = "ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "ec2-ecr-role"
  }
}

resource "aws_iam_role_policy" "ecr_pull_policy" {
  name = "ecr-pull-policy"
  role = aws_iam_role.ec2_ecr_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]
        Resource = "*"
      }
    ]
  })
}

# Instance Profile
resource "aws_iam_instance_profile" "ec2_profile" {
  name = "ec2-ecr-instance-profile"
  role = aws_iam_role.ec2_ecr_role.name

  tags = {
    Name = "ec2-ecr-profile"
  }
}

resource "aws_security_group" "node_app_sg" {
  name        = "node-sg"
  description = "Allow 22, 80"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
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
}

