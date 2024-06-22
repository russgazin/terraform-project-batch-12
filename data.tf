data "aws_key_pair" "ssh_key" {
  key_name = "virginia"
}

data "aws_ami" "ami" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-kernel-5.10-hvm-2.0.*.0-x86_64-gp2"]
  }
}

data "aws_route53_zone" "zone" {
  name         = "rustemtntk.com"
  private_zone = false
}

data "aws_secretsmanager_secret_version" "credentials" {
  secret_id = "rds-credentials"
}