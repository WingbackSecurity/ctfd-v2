output "lb_dns_name" {
  value       = var.create_in_aws ? module.ecs[0].lb_dns_name : null
  description = "DNS name for the Load Balancer"
}

output "lb_port" {
  value       = var.create_in_aws ? 80 : null
  description = "Port that CTFd is reachable on"
}

output "vpc_id" {
  value       = var.create_in_aws ? module.vpc[0].vpc_id : null
  description = "Id for the VPC created for CTFd"
}

output "challenge_bucket_id" {
  value       = var.create_in_aws ? module.s3[0].challenge_bucket.id : null
  description = "Challenge bucket name"
}

# RDS Outputs
output "rds_endpoint" {
  value       = var.create_in_aws ? module.rds[0].rds_endpoint_address : null
  description = "RDS cluster endpoint address"
}

output "rds_port" {
  value       = var.create_in_aws ? module.rds[0].rds_port : null
  description = "RDS cluster port"
}

output "rds_database_name" {
  value       = var.create_in_aws ? module.rds[0].rds_db_name : null
  description = "RDS database name"
}

output "rds_security_group_id" {
  value       = var.create_in_aws ? module.rds[0].rds_security_group_id : null
  description = "RDS security group ID"
}

# RDS Credentials Secrets Manager
output "rds_username_secret_arn" {
  value       = var.create_in_aws ? aws_secretsmanager_secret.rds_username[0].arn : null
  description = "ARN of Secrets Manager secret containing RDS username"
}

output "rds_username_secret_name" {
  value       = var.create_in_aws ? aws_secretsmanager_secret.rds_username[0].name : null
  description = "Name of Secrets Manager secret containing RDS username"
}

output "rds_password_secret_arn" {
  value       = var.create_in_aws ? aws_secretsmanager_secret.rds_password[0].arn : null
  description = "ARN of Secrets Manager secret containing RDS password"
}

output "rds_password_secret_name" {
  value       = var.create_in_aws ? aws_secretsmanager_secret.rds_password[0].name : null
  description = "Name of Secrets Manager secret containing RDS password"
}

# ElastiCache Outputs (if enabled)
output "elasticache_endpoint" {
  value       = var.create_in_aws && var.enable_elasticache ? module.elasticache[0].cache_connection_string : null
  description = "ElastiCache endpoint (if enabled)"
}
