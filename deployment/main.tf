# Get current AWS account and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate CTFd secret key
resource "random_password" "ctfd_secret_key" {
  length  = 24
  special = true
}

# VPC Module
module "vpc" {
  count    = var.create_in_aws ? 1 : 0
  source   = "./modules/vpc"
  app_name = var.app_name
}

# RDS Module - Optimized for cost
module "rds" {
  count                      = var.create_in_aws ? 1 : 0
  source                     = "./modules/rds"
  app_name                   = var.app_name
  vpc_id                     = module.vpc[0].vpc_id
  private_subnet_ids         = module.vpc[0].private_subnet_ids
  db_cluster_instance_type   = var.db_cluster_instance_type
  db_engine                  = var.db_engine
  db_serverless              = var.db_serverless
  db_engine_version          = var.db_engine_version
  db_port                    = var.db_port
  db_user                    = var.db_user
  db_name                    = var.db_name
  db_deletion_protection     = var.db_deletion_protection
  db_skip_final_snapshot     = var.db_skip_final_snapshot
  db_serverless_min_capacity = var.db_serverless_min_capacity
  db_serverless_max_capacity = var.db_serverless_max_capacity
  rds_encryption_key_arn     = var.rds_encryption_key_arn
  character_set              = var.db_character_set
  collation                  = var.db_collation
  publicly_accessible        = true
}

# RDS Security Group Rule - Allow access from your IP
resource "aws_security_group_rule" "rds_allow_my_ip" {
  count             = var.create_in_aws ? 1 : 0
  type              = "ingress"
  from_port         = var.db_port
  to_port           = var.db_port
  protocol          = "tcp"
  cidr_blocks       = [var.rds_allowed_ip]
  security_group_id = module.rds[0].rds_security_group_id
  description       = "Allow RDS access from my IP"
}

# RDS Credentials in Secrets Manager - Option A (separate secrets)
resource "aws_secretsmanager_secret" "rds_username" {
  count                          = var.create_in_aws ? 1 : 0
  name                           = "${var.app_name}-rds-username"
  force_overwrite_replica_secret = true
  recovery_window_in_days        = 0

  tags = {
    Name        = "${var.app_name}-rds-username"
    Environment = "production"
  }
}

resource "aws_secretsmanager_secret_version" "rds_username" {
  count     = var.create_in_aws ? 1 : 0
  secret_id = aws_secretsmanager_secret.rds_username[0].id
  secret_string = module.rds[0].rds_user
}

resource "aws_secretsmanager_secret" "rds_password" {
  count                          = var.create_in_aws ? 1 : 0
  name                           = "${var.app_name}-rds-password"
  force_overwrite_replica_secret = true
  recovery_window_in_days        = 0

  tags = {
    Name        = "${var.app_name}-rds-password"
    Environment = "production"
  }
}

resource "aws_secretsmanager_secret_version" "rds_password" {
  count     = var.create_in_aws ? 1 : 0
  secret_id = aws_secretsmanager_secret.rds_password[0].id
  secret_string = module.rds[0].rds_password
}

# S3 Module
module "s3" {
  count                          = var.create_in_aws ? 1 : 0
  source                         = "./modules/s3"
  force_destroy_challenge_bucket = var.force_destroy_challenge_bucket
  s3_encryption_key_arn          = var.s3_encryption_key_arn
}

# ElastiCache Module - Optional
module "elasticache" {
  count                             = var.create_in_aws && var.enable_elasticache ? 1 : 0
  source                            = "./modules/elasticache"
  app_name                          = var.app_name
  vpc_id                            = module.vpc[0].vpc_id
  private_subnet_ids                = module.vpc[0].private_subnet_ids
  elasticache_cluster_instances     = var.elasticache_cluster_instances
  elasticache_cluster_instance_type = var.elasticache_cluster_instance_type
  elasticache_cluster_port          = var.elasticache_cluster_port
  elasticache_encryption_key_arn    = var.elasticache_encryption_key_arn
}

# ECS Module
module "ecs" {
  count                            = var.create_in_aws ? 1 : 0
  source                           = "./modules/ecs"
  ecs_cluster_name                 = var.ecs_cluster_name
  vpc_id                           = module.vpc[0].vpc_id
  private_subnet_ids               = module.vpc[0].private_subnet_ids
  public_subnet_ids                = module.vpc[0].public_subnet_ids
  ctfd_image                       = var.ctfd_image
  db_connection_string             = module.rds[0].db_connection_string
  cache_connection_string          = var.enable_elasticache ? module.elasticache[0].cache_connection_string : null
  ctfd_secret_key                  = random_password.ctfd_secret_key.result
  registry_username                = var.registry_username
  registry_password                = var.registry_password
  challenge_bucket                 = module.s3[0].challenge_bucket.id
  challenge_bucket_arn             = module.s3[0].challenge_bucket.arn
  frontend_desired_count           = var.frontend_desired_count
  frontend_minimum_healthy_percent = var.frontend_minimum_healthy_percent
  frontend_maximum_percent         = var.frontend_maximum_percent
  frontend_minimum_count           = var.frontend_minimum_count
  frontend_maximum_count           = var.frontend_maximum_count
}

# CDN Module - Optional
module "cdn" {
  count                    = var.create_in_aws && var.create_cdn ? 1 : 0
  source                   = "./modules/cdn"
  ctf_domain               = var.ctf_domain
  app_name                 = var.app_name
  ctf_domain_zone_id       = var.ctf_domain_zone_id
  https_certificate_arn    = var.https_certificate_arn
  force_destroy_log_bucket = var.force_destroy_log_bucket
  origin_domain_name       = var.create_in_aws ? module.ecs[0].lb_dns_name : ""
}
