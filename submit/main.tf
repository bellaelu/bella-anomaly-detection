terraform {
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

variable "my_ip" {
  default = "50.73.238.18/32"
}

variable "key_name" {
  default = "ds5220awssshkey"
}

variable "repo_url" {
  default = "https://github.com/bellaelu/bella-anomaly-detection.git"
}


resource "aws_sns_topic" "dp1" {
  name = "ds5220-dp1"
}

resource "aws_sns_topic_policy" "sns_policy" {
  arn = aws_sns_topic.dp1.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
        Action   = "sns:Publish"
        Resource = aws_sns_topic.dp1.arn
      }
    ]
  })
}


resource "aws_s3_bucket" "data_bucket" {
}

resource "aws_s3_bucket_notification" "bucket_notification" {

  bucket = aws_s3_bucket.data_bucket.id

  topic {
    topic_arn = aws_sns_topic.dp1.arn
    events    = ["s3:ObjectCreated:Put"]

    filter_prefix = "raw/"
    filter_suffix = ".csv"
  }

  depends_on = [aws_sns_topic_policy.sns_policy]
}


resource "aws_iam_role" "ec2_role" {
  name = "anomaly-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "s3_access" {

  role = aws_iam_role.ec2_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "s3:*"
        Resource = [
          aws_s3_bucket.data_bucket.arn,
          "${aws_s3_bucket.data_bucket.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_instance_profile" "instance_profile" {
  role = aws_iam_role.ec2_role.name
}



resource "aws_security_group" "instance_sg" {

  name        = "anomaly-sg"
  description = "Allow SSH and FastAPI"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
  }

  ingress {
    from_port   = 8000
    to_port     = 8000
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



resource "aws_instance" "anomaly_instance" {

  ami           = "ami-0e2c8caa4b6378d8c"
  instance_type = "t3.micro"

  key_name = var.key_name

  iam_instance_profile = aws_iam_instance_profile.instance_profile.name

  vpc_security_group_ids = [
    aws_security_group.instance_sg.id
  ]

  root_block_device {
    volume_size = 16
    volume_type = "gp3"
  }

  user_data = <<-EOF
              #!/bin/bash
              set -e
              exec > /var/log/userdata.log 2>&1

              apt-get update -y
              apt-get install -y git python3 python3-pip python3-venv

              cd /opt
              git clone ${var.repo_url} anomaly-detection
              cd anomaly-detection

              python3 -m venv /opt/anomaly-detection/venv
              /opt/anomaly-detection/venv/bin/pip install -r requirements.txt

              export BUCKET_NAME=${aws_s3_bucket.data_bucket.id}
              echo "BUCKET_NAME=${aws_s3_bucket.data_bucket.id}" >> /etc/environment

              cat > /etc/systemd/system/anomaly.service <<EOT
              [Unit]
              Description=Anomaly Detection FastAPI
              After=network.target

              [Service]
              User=ubuntu
              WorkingDirectory=/opt/anomaly-detection
              EnvironmentFile=/etc/environment
              ExecStart=/opt/anomaly-detection/venv/bin/fastapi run app.py --host 0.0.0.0 --port 8000
              Restart=always

              [Install]
              WantedBy=multi-user.target
              EOT

              systemctl daemon-reload
              systemctl enable anomaly
              systemctl start anomaly
              EOF

}



resource "aws_eip" "elastic_ip" {
  domain = "vpc"
}

resource "aws_eip_association" "eip_assoc" {
  instance_id   = aws_instance.anomaly_instance.id
  allocation_id = aws_eip.elastic_ip.id
}



resource "aws_sns_topic_subscription" "http_sub" {

  topic_arn = aws_sns_topic.dp1.arn
  protocol  = "http"
  endpoint  = "http://${aws_eip.elastic_ip.public_ip}:8000/notify"

}