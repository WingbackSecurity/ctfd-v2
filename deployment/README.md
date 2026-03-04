# CTFd v2 Deployment

Cost-optimized Terraform deployment for CTFd with auto-scaling capabilities.

## Features

- **Cost Optimized**: Minimal idle costs (~$90/month) with auto-scaling for peak loads
- **Optional Redis**: Enable ElastiCache only when needed for training sessions
- **Auto-Scaling**: Automatically scales ECS tasks from 1-4 based on CPU and request load
- **RDS Access**: Publicly accessible RDS with IP-restricted security group
- **Secrets Management**: RDS credentials stored in AWS Secrets Manager

## Prerequisites

1. AWS CLI configured with `ctfd` profile
2. Terraform >= 1.7.3
3. Your current public IP address

## Quick Start

### 1. Get Your IP Address

```bash
curl https://checkip.amazonaws.com
```

### 2. Configure Variables

```bash
cd /Users/pcuser/midfield/ctfd-v2/deployment
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` and set:
- `rds_allowed_ip` - Your IP in CIDR format (e.g., "24.23.219.102/32")

### 3. Initialize Terraform

```bash
terraform init
```

### 4. Review Plan

```bash
terraform plan
```

### 5. Deploy

```bash
terraform apply
```

## Configuration

### ECR Image

The ECR image is hardcoded by default:
- `127214172072.dkr.ecr.us-east-1.amazonaws.com/ctfd:latest`

Override in `terraform.tfvars` if needed.

### RDS Configuration

- **Serverless**: Enabled by default
- **Min Capacity**: 0.5 ACU (scales down when idle)
- **Max Capacity**: 2 ACU (handles 30-40 users)
- **Public Access**: Enabled (restricted by security group)

### ECS Configuration

- **Idle**: 1 task with 0.5 vCPU, 1GB memory
- **Peak**: Auto-scales to 4 tasks
- **Auto-Scaling**: Based on CPU (>70% scale up, <30% scale down) and request count

### ElastiCache (Optional)

- **Default**: Disabled (saves ~$7.50/month)
- **Enable**: Set `enable_elasticache = true` in `terraform.tfvars` before training sessions

## Accessing RDS

### Get Connection Details

```bash
./get-rds-credentials.sh
```

### Update IP When It Changes

```bash
./update-rds-ip.sh
```

This script will:
1. Get your current public IP
2. Update the RDS security group
3. Display connection details

## Outputs

After deployment, view outputs:

```bash
terraform output
```

Key outputs:
- `lb_dns_name` - CTFd application URL
- `rds_endpoint` - RDS endpoint address
- `rds_security_group_id` - Security group ID for IP updates
- `rds_username_secret_name` - Secrets Manager secret name for username
- `rds_password_secret_name` - Secrets Manager secret name for password

## Cost Estimates

### Idle (0-1 users)
- RDS: 0.5 ACU (~$25/month)
- ECS: 1 task, 0.5 vCPU, 1GB (~$15/month)
- ALB: ~$16/month
- NAT Gateway: ~$32/month
- **Total: ~$90/month**

### Peak (30-40 users)
- RDS: 1-2 ACU (~$50-100/month)
- ECS: Up to 4 tasks (~$60/month)
- ElastiCache (optional): ~$7.50/month
- Same other costs
- **Total: ~$150-180/month**

## Enabling ElastiCache for Training

Before a training session:

1. Edit `terraform.tfvars`:
   ```hcl
   enable_elasticache = true
   ```

2. Apply:
   ```bash
   terraform apply
   ```

After training, disable it:
```hcl
enable_elasticache = false
terraform apply
```

## Auto-Scaling

Auto-scaling is configured automatically:
- **Scale Up**: When CPU > 70% or request count is high
- **Scale Down**: When CPU < 30% for 15 minutes
- **Cooldown**: 1 min (scale up), 5 min (scale down)

## Troubleshooting

### RDS Connection Issues

1. Check your IP is allowed:
   ```bash
   ./update-rds-ip.sh
   ```

2. Verify security group:
   ```bash
   aws --profile ctfd ec2 describe-security-groups \
     --group-ids $(terraform output -raw rds_security_group_id) \
     --query 'SecurityGroups[0].IpPermissions'
   ```

### Get RDS Credentials

```bash
./get-rds-credentials.sh
```

Or manually:
```bash
# Username
aws --profile ctfd secretsmanager get-secret-value \
  --secret-id $(terraform output -raw rds_username_secret_name) \
  --query SecretString --output text

# Password
aws --profile ctfd secretsmanager get-secret-value \
  --secret-id $(terraform output -raw rds_password_secret_name) \
  --query SecretString --output text
```

## Cleanup

To destroy all resources:

```bash
terraform destroy
```

**Warning**: This will delete all data including RDS database and S3 bucket contents.
