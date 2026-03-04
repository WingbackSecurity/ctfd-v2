# CTFd CloudFormation Deployment Guide

This guide covers deploying the CTFd infrastructure using AWS CloudFormation.

## Architecture Overview

The CloudFormation deployment creates the following resources:

- **VPC**: Public and private subnets across 3 availability zones
- **RDS Aurora MySQL**: Serverless v2 database cluster
- **ECS Service**: Fargate tasks running CTFd (uses existing cluster)
- **Application Load Balancer**: HTTP traffic routing
- **S3 Bucket**: Challenge file storage
- **Secrets Manager**: Database credentials and CTFd secret key
- **ElastiCache** (optional): Redis cluster for caching
- **CloudFront CDN** (optional): Content delivery network

## Prerequisites

1. **AWS CLI** configured with appropriate credentials
2. **AWS Profile** with permissions for CloudFormation, ECS, RDS, S3, Secrets Manager, EC2, ELB
3. **Existing ECS Cluster** (e.g., `ctfd-ecs`)
4. **CTFd Docker Image** pushed to ECR
5. **ACM Certificate** (for HTTPS - see Post-Deployment section)
6. **S3 Bucket** for storing CloudFormation templates

## Directory Structure

```
cloudformation/
├── main.yaml              # Main stack (orchestrates nested stacks)
├── vpc.yaml               # VPC, subnets, NAT gateway, routing
├── rds.yaml               # Aurora MySQL cluster
├── s3.yaml                # Challenge bucket
├── ecs.yaml               # ECS service, ALB, auto-scaling
├── elasticache.yaml       # Redis cluster (optional)
├── cdn.yaml               # CloudFront distribution (optional)
├── parameters.json        # Stack parameters
└── deploy.sh              # Deployment helper script
```

## Configuration

### 1. Upload Templates to S3

CloudFormation nested stacks require templates to be stored in S3:

```bash
# Create S3 bucket for templates (replace ACCOUNT_ID)
aws --profile ctfd s3 mb s3://ctfd-cf-templates-ACCOUNT_ID --region us-east-1

# Upload all templates
cd deployment/cloudformation
aws --profile ctfd s3 cp main.yaml s3://ctfd-cf-templates-ACCOUNT_ID/
aws --profile ctfd s3 cp vpc.yaml s3://ctfd-cf-templates-ACCOUNT_ID/
aws --profile ctfd s3 cp rds.yaml s3://ctfd-cf-templates-ACCOUNT_ID/
aws --profile ctfd s3 cp s3.yaml s3://ctfd-cf-templates-ACCOUNT_ID/
aws --profile ctfd s3 cp ecs.yaml s3://ctfd-cf-templates-ACCOUNT_ID/
aws --profile ctfd s3 cp elasticache.yaml s3://ctfd-cf-templates-ACCOUNT_ID/
aws --profile ctfd s3 cp cdn.yaml s3://ctfd-cf-templates-ACCOUNT_ID/
```

### 2. Update Template URLs

Edit `main.yaml` and update the `S3TemplateBucketName` default value to match your bucket name.

### 3. Configure Parameters

Edit `parameters.json` with your values:

| Parameter | Description | Example |
|-----------|-------------|---------|
| `AppName` | Application name prefix | `ctfd-v2` |
| `RDSAllowedIP` | IP allowed to access RDS directly | `1.2.3.4/32` |
| `CTFDImage` | ECR image URI | `123456789.dkr.ecr.us-east-1.amazonaws.com/ctfd:latest` |
| `ECSClusterName` | Existing ECS cluster name | `ctfd-ecs` |
| `DBServerless` | Use Aurora Serverless v2 | `true` |
| `DBServerlessMinCapacity` | Min ACU for serverless | `0.5` |
| `DBServerlessMaxCapacity` | Max ACU for serverless | `2` |
| `EnableElastiCache` | Enable Redis caching | `false` |
| `CreateCDN` | Create CloudFront distribution | `false` |

## Deployment

### Deploy Stack

```bash
cd deployment/cloudformation

aws --profile ctfd cloudformation create-stack \
  --stack-name ctfd-v2 \
  --template-url https://s3.amazonaws.com/ctfd-cf-templates-ACCOUNT_ID/main.yaml \
  --parameters file://parameters.json \
  --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
  --region us-east-1
```

### Monitor Deployment

```bash
# Check stack status
aws --profile ctfd cloudformation describe-stacks \
  --stack-name ctfd-v2 \
  --region us-east-1 \
  --query 'Stacks[0].StackStatus' \
  --output text

# Watch events
aws --profile ctfd cloudformation describe-stack-events \
  --stack-name ctfd-v2 \
  --region us-east-1 \
  --max-items 15 \
  --query 'StackEvents[*].[LogicalResourceId,ResourceStatus]' \
  --output table

# Check for failures
aws --profile ctfd cloudformation describe-stack-events \
  --stack-name ctfd-v2 \
  --region us-east-1 \
  --query 'StackEvents[?ResourceStatus==`CREATE_FAILED`].[LogicalResourceId,ResourceStatusReason]' \
  --output table
```

**Expected Timeline:**
- VPC: ~2 minutes
- RDS: ~10-15 minutes
- ECS: ~5 minutes
- **Total: ~20-25 minutes**

### Get Outputs

```bash
aws --profile ctfd cloudformation describe-stacks \
  --stack-name ctfd-v2 \
  --region us-east-1 \
  --query 'Stacks[0].Outputs' \
  --output table
```

Key outputs:
- `LoadBalancerDNS`: ALB DNS name for testing
- `RDSEndpoint`: Database endpoint
- `ChallengeBucketId`: S3 bucket name

## Post-Deployment: Configure HTTPS

The CloudFormation template creates an HTTP-only ALB. To enable HTTPS, follow these manual steps:

### 1. Get ALB and Certificate ARNs

```bash
# Get ALB ARN
ALB_ARN=$(aws --profile ctfd elbv2 describe-load-balancers \
  --names ctfd-v2-alb \
  --region us-east-1 \
  --query 'LoadBalancers[0].LoadBalancerArn' \
  --output text)

# Get ALB Security Group
ALB_SG=$(aws --profile ctfd elbv2 describe-load-balancers \
  --names ctfd-v2-alb \
  --region us-east-1 \
  --query 'LoadBalancers[0].SecurityGroups[0]' \
  --output text)

# Get Target Group ARN
TG_ARN=$(aws --profile ctfd elbv2 describe-target-groups \
  --names ctfd-v2-tg \
  --region us-east-1 \
  --query 'TargetGroups[0].TargetGroupArn' \
  --output text)

# Get HTTP Listener ARN
HTTP_LISTENER_ARN=$(aws --profile ctfd elbv2 describe-listeners \
  --load-balancer-arn $ALB_ARN \
  --region us-east-1 \
  --query 'Listeners[?Port==`80`].ListenerArn' \
  --output text)

# List available certificates
aws --profile ctfd acm list-certificates --region us-east-1
```

### 2. Create HTTPS Listener (Port 443)

```bash
# Replace CERTIFICATE_ARN with your ACM certificate ARN
CERT_ARN="arn:aws:acm:us-east-1:ACCOUNT_ID:certificate/YOUR-CERT-ID"

aws --profile ctfd elbv2 create-listener \
  --load-balancer-arn $ALB_ARN \
  --protocol HTTPS \
  --port 443 \
  --certificates CertificateArn=$CERT_ARN \
  --default-actions Type=forward,TargetGroupArn=$TG_ARN \
  --region us-east-1
```

### 3. Modify HTTP Listener to Redirect to HTTPS

```bash
aws --profile ctfd elbv2 modify-listener \
  --listener-arn $HTTP_LISTENER_ARN \
  --default-actions '[{"Type":"redirect","RedirectConfig":{"Protocol":"HTTPS","Port":"443","Host":"#{host}","Path":"/#{path}","Query":"#{query}","StatusCode":"HTTP_301"}}]' \
  --region us-east-1
```

### 4. Allow HTTPS in Security Group

```bash
aws --profile ctfd ec2 authorize-security-group-ingress \
  --group-id $ALB_SG \
  --protocol tcp \
  --port 443 \
  --cidr 0.0.0.0/0 \
  --region us-east-1
```

### 5. Update DNS

Update your DNS provider (Cloudflare, Route53, etc.) to point your domain to the ALB:

- **Record Type**: CNAME (or ALIAS for Route53)
- **Name**: `ctf` (for ctf.yourdomain.com)
- **Value**: ALB DNS (e.g., `ctfd-v2-alb-1234567890.us-east-1.elb.amazonaws.com`)

## Testing

### Check ECS Service Health

```bash
# Check target health
aws --profile ctfd elbv2 describe-target-health \
  --target-group-arn $TG_ARN \
  --region us-east-1

# Check ECS service
aws --profile ctfd ecs describe-services \
  --cluster ctfd-ecs \
  --services ctfd-v2 \
  --region us-east-1 \
  --query 'services[0].[status,runningCount,desiredCount]'
```

### Test HTTP Endpoint

```bash
# Test ALB directly (skip certificate verification for ALB DNS)
curl -sk https://ctfd-v2-alb-XXXX.us-east-1.elb.amazonaws.com

# Test via domain (after DNS propagation)
curl -s https://ctf.yourdomain.com
```

### View ECS Logs

```bash
aws --profile ctfd logs tail /ecs/ctfd-v2 --follow --region us-east-1
```

## Update Stack

To update the stack after modifying templates:

```bash
# Re-upload modified templates
aws --profile ctfd s3 cp ecs.yaml s3://ctfd-cf-templates-ACCOUNT_ID/

# Update stack
aws --profile ctfd cloudformation update-stack \
  --stack-name ctfd-v2 \
  --template-url https://s3.amazonaws.com/ctfd-cf-templates-ACCOUNT_ID/main.yaml \
  --parameters file://parameters.json \
  --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
  --region us-east-1
```

## Tear Down

### Delete Stack

```bash
aws --profile ctfd cloudformation delete-stack \
  --stack-name ctfd-v2 \
  --region us-east-1

# Wait for deletion
aws --profile ctfd cloudformation wait stack-delete-complete \
  --stack-name ctfd-v2 \
  --region us-east-1
```

### Clean Up (if deletion fails)

If S3 buckets have objects:
```bash
# Empty bucket first
aws --profile ctfd s3 rm s3://BUCKET_NAME --recursive

# Then retry stack deletion
```

If Secrets Manager secrets exist:
```bash
# Force delete secrets
aws --profile ctfd secretsmanager delete-secret \
  --secret-id SECRET_NAME \
  --force-delete-without-recovery \
  --region us-east-1
```

## Troubleshooting

### Common Issues

| Issue | Solution |
|-------|----------|
| `TemplateURL must be a supported URL` | Upload templates to S3 |
| `CAPABILITY_NAMED_IAM required` | Add `--capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM` |
| `Resource already exists` | Delete orphaned resources (S3 buckets, secrets) |
| `Fn::Equals cannot be partially collapsed` | Use `Fn::If` with conditions instead |
| `ECSCluster creation failed` | Use existing cluster (set `ECSClusterName` parameter) |

### Debug Failed Stack

```bash
# Get failure reason
aws --profile ctfd cloudformation describe-stack-events \
  --stack-name ctfd-v2 \
  --region us-east-1 \
  --query 'StackEvents[?ResourceStatus==`CREATE_FAILED`].[LogicalResourceId,ResourceStatusReason]' \
  --output table
```

### Check Nested Stack

```bash
# List nested stacks
aws --profile ctfd cloudformation list-stack-resources \
  --stack-name ctfd-v2 \
  --region us-east-1 \
  --query 'StackResourceSummaries[?ResourceType==`AWS::CloudFormation::Stack`].[LogicalResourceId,PhysicalResourceId]' \
  --output table
```

## Cost Optimization

- **Aurora Serverless v2**: Scales to 0.5 ACU (~$43/month minimum)
- **Fargate Spot**: Configure in ECS for 70% cost savings
- **ElastiCache**: Disable if not needed (`EnableElastiCache: false`)
- **CloudFront**: Disable if not needed (`CreateCDN: false`)
- **NAT Gateway**: ~$32/month per AZ (consider NAT instances for dev)

## Security Recommendations

1. Enable `DBDeletionProtection: true` for production
2. Set `DBSkipFinalSnapshot: false` for production
3. Use dedicated KMS keys for encryption (`RDSEncryptionKeyARN`, `S3EncryptionKeyARN`)
4. Restrict `RDSAllowedIP` to specific IPs
5. Enable VPC Flow Logs
6. Use AWS WAF with CloudFront
