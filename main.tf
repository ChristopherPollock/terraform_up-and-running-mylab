resource "aws_instance" "example" {
    ami ="ami-08c40ec9ead489470"
    instance_type = "t2.micro"

    tags = {
        Name = "Terraform"
    }
}