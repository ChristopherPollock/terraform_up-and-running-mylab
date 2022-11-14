variable "server_port" {
  description = "The port the server will use for HTTP requests"
  type        = number
  default     = 8080
}

variable "inbound_port" {
  description = "The port HTTP requests will come into from the outside world"
  type        = number
  default     = 80
}

output "public_ip" {
  value       = aws_instance.example.public_ip
  description = "THe Public IP address of the web server"
}

output "alb_dns_name" {
  value       = aws_lb.example.dns_name
  description = "The domain name of the load balancer"
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}
resource "aws_security_group" "instance" {
  name = "terraform-example-instance"
  ingress {
    from_port   = var.server_port
    to_port     = var.server_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
#Single Se4rver instance example
resource "aws_instance" "example" {
  ami                    = "ami-08c40ec9ead489470"
  instance_type          = "t2.micro"
  vpc_security_group_ids = [aws_security_group.instance.id]


  user_data = <<-EOF
            #!/bin/bash
            echo "Hello, World!" > index.html
            nohup busybox httpd -f -p ${var.server_port} &
            EOF

  user_data_replace_on_change = true

  tags = {
    Name = "Terraform"
  }
}
# Multiple servers started from a launch configuration, tied to an autoscaling group, and fronted by an application load balancer
resource "aws_launch_configuration" "example" {
  image_id        = "ami-08c40ec9ead489470"
  instance_type   = "t2.micro"
  security_groups = [aws_security_group.instance.id]

  user_data = <<-EOF
            #!/bin/bash
            echo "Hello, World!" > index.html
            nohup busybox httpd -f -p ${var.server_port} &
            EOF
}

resource "aws_autoscaling_group" "example" {
  launch_configuration = aws_launch_configuration.example.name
  vpc_zone_identifier  = data.aws_subnets.default.ids
  target_group_arns    = [aws_lb_target_group.asg.arn]
  health_check_type    = "ELB"

  min_size = 2
  max_size = 10

  tag {
    key                 = "Name"
    value               = "teraform-asg-example"
    propagate_at_launch = true
  }
}

resource "aws_lb" "example" {
  name               = "terraform-asg-example"
  load_balancer_type = "application"
  subnets            = data.aws_subnets.default.ids
  security_groups    = [aws_security_group.alb.id]
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.example.arn
  port              = var.inbound_port
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "404: Page not found, dumbass!"
      status_code  = 404
    }
  }
}

resource "aws_security_group" "alb" {
  name = "terraform-example-alb"

  #Allow inbound HTTP Requests
  ingress {
    from_port   = var.inbound_port
    to_port     = var.inbound_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  #All all out outbound requests
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
resource "aws_lb_target_group" "asg" {
  name     = "terraform-asg-example"
  port     = var.server_port
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.default.id
  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 15
    timeout             = 3
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

resource "aws_lb_listener_rule" "asg" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 100

  condition {
    path_pattern {
      values = ["*"]
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.asg.arn
  }

}
