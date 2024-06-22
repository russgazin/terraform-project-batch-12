# build vpc && igw:
module "vpc" {
  source = "./modules/vpc_module"

  cidr_block        = "10.0.0.0/24"
  vpc_tag           = "vpc"
  create_attach_igw = true
}

# build subnets:
module "subnets" {
  source = "./modules/subnet_module"

  for_each = {
    public_1a  = ["10.0.0.0/26", "us-east-1a", true]
    public_1b  = ["10.0.0.64/26", "us-east-1b", true]
    private_1a = ["10.0.0.128/26", "us-east-1a", false]
    private_1b = ["10.0.0.192/26", "us-east-1b", false]
  }

  vpc_id                  = module.vpc.id
  cidr_block              = each.value[0]
  availability_zone       = each.value[1]
  map_public_ip_on_launch = each.value[2]
  subnet_tag              = each.key
}

# build natgw:
module "natgw" {
  source = "./modules/natgw_module"

  subnet_id = module.subnets["public_1a"].id
  natgw_tag = "natgw"
}

# build public rtb:
module "public_rtb" {
  source = "./modules/rtb_module"

  vpc_id         = module.vpc.id
  gateway_id     = module.vpc.igw_id
  nat_gateway_id = null
  subnets = [
    module.subnets["public_1a"].id,
    module.subnets["public_1b"].id
  ]
}

# build private rtb:
module "private_rtb" {
  source = "./modules/rtb_module"

  vpc_id         = module.vpc.id
  gateway_id     = null
  nat_gateway_id = module.natgw.id
  subnets = [
    module.subnets["private_1a"].id,
    module.subnets["private_1b"].id
  ]
}

# build ec2 sg:
module "ec2_sgrp" {
  source = "./modules/sg_module"

  name        = "ec2-sgrp"
  description = "ec2_sgrp"
  vpc_id      = module.vpc.id
  sg_tag      = "ec2_sgrp"

  sg_rules = {
    ssh_rule      = ["ingress", 22, 22, "tcp", "0.0.0.0/0"]
    http_rule     = ["ingress", 80, 80, "tcp", module.alb_sgrp.id]
    outbound_rule = ["egress", 0, 0, "-1", "0.0.0.0/0"]
  }
}

# build ec2 instances:
module "instances" {
  source = "./modules/instance_module"

  for_each = {
    public_1a_instance = module.subnets["public_1a"].id
    public_1b_instance = module.subnets["public_1b"].id
  }

  ami                    = data.aws_ami.ami.id
  key_name               = data.aws_key_pair.ssh_key.key_name
  instance_type          = "t2.micro"
  subnet_id              = each.value
  vpc_security_group_ids = [module.ec2_sgrp.id]
  user_data              = file("user_data.sh")
  instance_tag           = each.key
}

# build tg:
module "tg" {
  source = "./modules/tg_module"

  name     = "alb-tgrp"
  port     = 80
  protocol = "HTTP"
  vpc_id   = module.vpc.id
  tg_tag   = "alb_tgrp"

  instance_ids = [
    module.instances["public_1a_instance"].id,
    module.instances["public_1b_instance"].id
  ]
}

# build acm cert:
module "certificate" {
  source = "./modules/acm_module"

  domain_name               = "rustemtntk.com"
  subject_alternative_names = ["*.rustemtntk.com"]
  validation_method         = "DNS"
  cert_tag                  = "project_certificate"
  zone_id                   = data.aws_route53_zone.zone.zone_id
}

# build alb sg:
module "alb_sgrp" {
  source = "./modules/sg_module"

  name        = "alb-sgrp"
  description = "alb_sgrp"
  vpc_id      = module.vpc.id
  sg_tag      = "alb_sgrp"

  sg_rules = {
    "http_rule"     = ["ingress", 80, 80, "tcp", "0.0.0.0/0"]
    "https_rule"    = ["ingress", 443, 443, "tcp", "0.0.0.0/0"]
    "outbound_rule" = ["egress", 0, 0, "-1", "0.0.0.0/0"]
  }
}

# build alb:
module "alb" {
  source = "./modules/alb_module"

  name               = "alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [module.alb_sgrp.id]
  subnets = [
    module.subnets["public_1a"].id,
    module.subnets["public_1b"].id
  ]

  alb_tag          = "alb"
  certificate_arn  = module.certificate.arn
  target_group_arn = module.tg.arn
}

# build route53 cname record:
module "application_entrypoint" {
  source = "./modules/route53_module"

  zone_id = data.aws_route53_zone.zone.zone_id
  name    = "projectb12.rustemtntk.com"
  type    = "CNAME"
  ttl     = 60
  records = [module.alb.dns_name]
}

# build rds sg:
module "rds_sgrp" {
  source = "./modules/sg_module"

  name        = "rds-sgrp"
  description = "rds_sgrp"
  vpc_id      = module.vpc.id
  sg_tag      = "rds_sgrp"

  sg_rules = {
    "mysql/aurora"  = ["ingress", 3306, 3306, "tcp", module.ec2_sgrp.id]
    "outbound_rule" = ["egress", 0, 0, "-1", "0.0.0.0/0"]
  }
}

# build rds subnet group:
module "db_subnet_group" {
  source = "./modules/rds_subnet_group"

  name                = "db-subnet-group"
  db_subnet_group_tag = "db_subnet_group"
  subnet_ids = [
    module.subnets["private_1a"].id,
    module.subnets["private_1b"].id
  ]
}

locals {
  rds_creds = jsondecode(data.aws_secretsmanager_secret_version.credentials.secret_string)
}

# build rds instance:
module "rds" {
  source = "./modules/rds_instance"

  allocated_storage    = 20
  engine               = "mysql"
  engine_version       = "5.7.44"
  instance_class       = "db.t3.micro"
  db_name              = "myDbInstance"
  username             = local.rds_creds.USERNAME
  password             = local.rds_creds.PASSWORD
  security_group_ids   = [module.rds_sgrp.id]
  db_subnet_group_name = module.db_subnet_group.name
}
