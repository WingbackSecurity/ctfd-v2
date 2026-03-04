variable "app_name" {
  type        = string
  default     = "ctfd-v2"
  description = "Name of application"
}

variable "aws_region" {
  type        = string
  description = "Region to deploy CTFd into"
  default     = "us-east-1"
}

variable "aws_profile" {
  type        = string
  description = "AWS profile to use"
  default     = "ctfd"
}

# ECR Image - Hardcoded default
variable "ctfd_image" {
  type        = string
  default     = "127214172072.dkr.ecr.us-east-1.amazonaws.com/ctfd:latest"
  description = "Docker image for CTFd from ECR"
}

# RDS IP Access
variable "rds_allowed_ip" {
  type        = string
  description = "Your IP address in CIDR format (e.g., 24.23.219.102/32)"
}

# Registry credentials - not needed for ECR (uses IAM)
variable "registry_username" {
  type        = string
  default     = null
  description = "Not needed for ECR (uses IAM)"
}

variable "registry_password" {
  type        = string
  default     = null
  sensitive   = true
  description = "Not needed for ECR (uses IAM)"
}

# ElastiCache - Optional
variable "enable_elasticache" {
  type        = bool
  default     = false
  description = "Enable ElastiCache Redis for high load scenarios"
}

variable "elasticache_cluster_instances" {
  type        = number
  description = "Number of instances in ElastiCache cluster"
  default     = 1
}

variable "elasticache_cluster_instance_type" {
  type        = string
  description = "Instance type for instance in ElastiCache cluster"
  default     = "cache.t2.micro"
}

variable "elasticache_cluster_port" {
  type        = number
  description = "Port to connect to the ElastiCache cluster on"
  default     = 6379
}

variable "elasticache_encryption_key_arn" {
  type        = string
  description = "Encryption key for use with ElastiCache at-rest encryption"
  default     = ""
}

# RDS Configuration - Optimized for cost
variable "db_serverless" {
  type        = bool
  description = "Configure serverless RDS cluster"
  default     = true
}

variable "db_serverless_min_capacity" {
  type        = number
  description = "Minimum capacity for serverless RDS"
  default     = 0.5
}

variable "db_serverless_max_capacity" {
  type        = number
  description = "Maximum capacity for serverless RDS"
  default     = 2
}

variable "db_cluster_instance_type" {
  type        = string
  description = "Type of instances to create in the RDS cluster (if not serverless)"
  default     = "db.r5.large"
}

variable "db_engine" {
  type        = string
  description = "Engine for the RDS cluster"
  default     = "aurora-mysql"
}

variable "db_engine_version" {
  type        = string
  description = "Engine version for the RDS cluster"
  default     = "8.0.mysql_aurora.3.08.2"
}

variable "db_port" {
  type        = number
  description = "Port to connect to the RDS cluster on"
  default     = 3306
}

variable "db_user" {
  type        = string
  description = "Username for the RDS database"
  default     = "ctfd"
}

variable "db_name" {
  type        = string
  description = "Name for the database in RDS"
  default     = "ctfd"
}

variable "db_deletion_protection" {
  type        = bool
  description = "If true database will not be able to be deleted without manual intervention"
  default     = false
}

variable "db_skip_final_snapshot" {
  type        = bool
  description = "If true database will not be snapshotted before deletion"
  default     = false
}

variable "db_character_set" {
  default     = "utf8mb4"
  type        = string
  description = "The database character set"
}

variable "db_collation" {
  default     = "utf8mb4_bin"
  type        = string
  description = "The database collation"
}

variable "rds_encryption_key_arn" {
  type        = string
  description = "Encryption key for use with RDS at-rest encryption"
  default     = ""
}

# ECS Configuration - Optimized for cost
variable "ecs_cluster_name" {
  type        = string
  description = "Name of the ECS cluster"
  default     = "ctfd-ecs"
}

variable "frontend_desired_count" {
  type        = number
  description = "Desired number of task instances for the frontend service"
  default     = 1
}

variable "frontend_minimum_healthy_percent" {
  type        = number
  description = "Minimum health percent for the frontend service"
  default     = 100
}

variable "frontend_maximum_percent" {
  type        = number
  description = "Maximum health percent for the frontend service"
  default     = 200
}

variable "frontend_minimum_count" {
  type        = number
  description = "Minimum number of task instances for the frontend service"
  default     = 1
}

variable "frontend_maximum_count" {
  type        = number
  description = "Maximum number of task instances for the frontend service"
  default     = 4
}

# S3 Configuration
variable "force_destroy_challenge_bucket" {
  type        = bool
  default     = false
  description = "Whether the S3 bucket containing the CTFD challenge data should be force destroyed"
}

variable "s3_encryption_key_arn" {
  type        = string
  description = "Encryption key for use with S3 bucket at-rest encryption"
  default     = ""
}

# CDN Configuration
variable "create_cdn" {
  type        = bool
  default     = false
  description = "Whether to create a cloudfront CDN deployment"
}

variable "ctf_domain" {
  type        = string
  description = "Domain to use for the CTFd deployment"
  default     = ""
}

variable "ctf_domain_zone_id" {
  type        = string
  description = "Zone id for the route53 zone for the ctf_domain"
  default     = ""
}

variable "https_certificate_arn" {
  type        = string
  description = "SSL Certificate ARN to be used for the HTTPS server"
  default     = ""
}

variable "force_destroy_log_bucket" {
  type        = bool
  default     = false
  description = "Whether the S3 bucket containing the logging data should be force destroyed"
}

variable "create_in_aws" {
  type        = bool
  default     = true
  description = "Create AWS resources"
}
