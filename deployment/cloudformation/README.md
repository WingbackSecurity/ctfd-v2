# CTFd v2 CloudFormation Deployment

CloudFormation templates for deploying CTFd with cost-optimized infrastructure. This is a complete conversion from the Terraform deployment, providing the same functionality using AWS CloudFormation.

## 📋 Table of Contents

- [Structure](#structure)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Deployment Methods](#deployment-methods)
- [Configuration](#configuration)
- [Accessing Resources](#accessing-resources)
- [Cost Estimates](#cost-estimates)
- [Troubleshooting](#troubleshooting)
- [Maintenance](#maintenance)

## 📁 Structure

- **main.yaml** - Main stack that orchestrates all nested stacks
- **vpc.yaml** - VPC, subnets, NAT Gateway, Internet Gateway
- **rds.yaml** - RDS Aurora MySQL cluster (serverless v2)
- **s3.yaml** - S3 bucket for challenge files
- **ecs.yaml** - ECS cluster, service, ALB, auto-scaling, CloudWatch alarms
- **elasticache.yaml** - ElastiCache Redis cluster (optional)
- **cdn.yaml** - CloudFront CDN (optional)
- **parameters.json** - Parameter file (similar to terraform.tfvars)
- **deploy.sh** - Automated deployment script

## ✅ Prerequisites

1. **AWS CLI** installed and configured
2. **AWS Profile** named `ctfd` configured with appropriate credentials
3. **Your public IP address** (for RDS access)
4. **S3 bucket** for storing CloudFormation templates (required for nested stacks)

## 🚀 Quick Start

### Method 1: Using the Deployment Script (Recommended)

The easiest way to deploy is using the provided `deploy.sh` script:

```bash
cd /Users/pcuser/midfield/ctfd-v2/deployment/cloudformation

# Make script executable (if not already)
chmod +x deploy.sh

# Run the deployment script
./deploy.sh
```

The script will:
- ✅ Automatically detect your current IP address
- ✅ Update `parameters.json` with your IP
- ✅ Optionally create and upload templates to S3
- ✅ Deploy the CloudFormation stack
- ✅ Optionally wait for completion and show outputs

### Method 2: Manual Deployment

#### Step 1: Get Your IP Address

```bash
curl https://checkip.amazonaws.com
```

#### Step 2: Update Parameters

Edit `parameters.json` and set:
- `RDSAllowedIP` - Your IP in CIDR format (e.g., "24.23.219.102/32")

#### Step 3: Upload Templates to S3

**Important**: Nested CloudFormation stacks require templates to be in S3 (not local files).

```bash
# Get your AWS account ID
ACCOUNT_ID=$(aws --profile ctfd sts get-caller-identity --query Account --output text)

# Create S3 bucket for templates (if it doesn't exist)
aws --profile ctfd s3 mb s3://ctfd-cf-templates-${ACCOUNT_ID} --region us-east-1

# Upload all templates
cd /Users/pcuser/midfield/ctfd-v2/deployment/cloudformation
aws --profile ctfd s3 cp . s3://ctfd-cf-templates-${ACCOUNT_ID}/ \
  --recursive \
  --exclude "*.md" \
  --exclude "*.json" \
  --exclude "*.sh" \
  --region us-east-1
```

**Note**: The bucket name `ctfd-cf-templates-127214172072` is already configured in `main.yaml`. If you use a different account, update the TemplateURL values in `main.yaml`.

#### Step 4: Deploy the Stack

```bash
ACCOUNT_ID=$(aws --profile ctfd sts get-caller-identity --query Account --output text)

aws --profile ctfd cloudformation create-stack \
  --stack-name ctfd-v2 \
  --template-url https://s3.amazonaws.com/ctfd-cf-templates-${ACCOUNT_ID}/main.yaml \
  --parameters file://parameters.json \
  --capabilities CAPABILITY_IAM \
  --region us-east-1
```

#### Step 5: Monitor Deployment

```bash
# Watch stack events
aws --profile ctfd cloudformation describe-stack-events \
  --stack-name ctfd-v2 \
  --region us-east-1 \
  --max-items 10 \
  --query 'StackEvents[*].[Timestamp,ResourceType,LogicalResourceId,ResourceStatus]' \
  --output table

# Check stack status
aws --profile ctfd cloudformation describe-stacks \
  --stack-name ctfd-v2 \
  --region us-east-1 \
  --query 'Stacks[0].StackStatus' \
  --output text
```

**Expected Duration**: 15-30 minutes for initial deployment

## ⚙️ Configuration

### ECS Cluster Name

Set `ECSClusterName` parameter to use an existing cluster (default: `ctfd-ecs`).

### RDS Configuration

- **Serverless v2**: Enabled by default
  - Min Capacity: 0.5 ACU (scales down when idle)
  - Max Capacity: 2 ACU (handles 30-40 users)
- **Public Access**: Enabled (restricted by security group)
- **IP Access**: Set `RDSAllowedIP` to allow access from your IP
- **Encryption**: Optional KMS key via `RDSEncryptionKeyARN`

### ECS Configuration

- **Idle**: 1 task with 0.5 vCPU, 1GB memory
- **Peak**: Auto-scales to 4 tasks
- **Auto-Scaling Triggers**:
  - Scale Up: CPU > 70% OR Request count > 100
  - Scale Down: CPU < 30% for 15 minutes
- **Cooldown**: 1 min (scale up), 5 min (scale down)

### ElastiCache (Optional)

Set `EnableElastiCache` to `"true"` to enable Redis caching. Useful for:
- High-traffic training sessions
- Session management
- Caching frequently accessed data

**Cost**: ~$7.50/month for `cache.t2.micro`

### CDN (Optional)

Set `CreateCDN` to `"true"` and provide:
- `CTFDomain` - Your custom domain (e.g., "ctf.example.com")
- `CTFDomainZoneId` - Route53 Hosted Zone ID
- `HTTPSCertificateARN` - ACM Certificate ARN for HTTPS

## 🔐 Accessing Resources

### Get Load Balancer URL

```bash
aws --profile ctfd cloudformation describe-stacks \
  --stack-name ctfd-v2 \
  --region us-east-1 \
  --query 'Stacks[0].Outputs[?OutputKey==`LoadBalancerDNS`].OutputValue' \
  --output text
```

This is your CTFd application URL.

### Get RDS Connection Details

```bash
# Get RDS endpoint
aws --profile ctfd cloudformation describe-stacks \
  --stack-name ctfd-v2 \
  --region us-east-1 \
  --query 'Stacks[0].Outputs[?OutputKey==`RDSEndpoint`].OutputValue' \
  --output text

# Get username
aws --profile ctfd secretsmanager get-secret-value \
  --secret-id ctfd-v2-rds-username \
  --region us-east-1 \
  --query SecretString --output text

# Get password
aws --profile ctfd secretsmanager get-secret-value \
  --secret-id ctfd-v2-rds-password \
  --region us-east-1 \
  --query SecretString --output text
```

### Update RDS IP When It Changes

If your IP address changes, update the security group:

```bash
# Get your current IP
MY_IP=$(curl -s https://checkip.amazonaws.com)
echo "Your IP: $MY_IP"

# Get security group ID
SG_ID=$(aws --profile ctfd cloudformation describe-stacks \
  --stack-name ctfd-v2 \
  --region us-east-1 \
  --query 'Stacks[0].Outputs[?OutputKey==`RDSSecurityGroupId`].OutputValue' \
  --output text)

# Remove old rules (optional - list first to see what to remove)
aws --profile ctfd ec2 describe-security-group-rules \
  --filters "Name=group-id,Values=$SG_ID" \
  --region us-east-1

# Add new IP rule
aws --profile ctfd ec2 authorize-security-group-ingress \
  --group-id $SG_ID \
  --protocol tcp \
  --port 3306 \
  --cidr ${MY_IP}/32 \
  --region us-east-1 \
  --description "Allow RDS access from my IP"
```

### View All Stack Outputs

```bash
aws --profile ctfd cloudformation describe-stacks \
  --stack-name ctfd-v2 \
  --region us-east-1 \
  --query 'Stacks[0].Outputs' \
  --output table
```

Key outputs:
- `LoadBalancerDNS` - CTFd application URL
- `RDSEndpoint` - RDS endpoint address
- `RDSPort` - RDS port (3306)
- `RDSDatabaseName` - Database name
- `RDSSecurityGroupId` - Security group ID for IP updates
- `RDSUsernameSecretName` - Secrets Manager secret name for username
- `RDSPasswordSecretName` - Secrets Manager secret name for password
- `ChallengeBucketId` - S3 bucket name for challenges
- `VPCId` - VPC ID

## 💰 Cost Estimates

### Idle (0-1 users)
- RDS Serverless: 0.5 ACU (~$25/month)
- ECS Fargate: 1 task, 0.5 vCPU, 1GB (~$15/month)
- Application Load Balancer: ~$16/month
- NAT Gateway: ~$32/month
- Data Transfer: ~$2/month
- **Total: ~$90/month**

### Peak (30-40 users)
- RDS Serverless: 1-2 ACU (~$50-100/month)
- ECS Fargate: Up to 4 tasks (~$60/month)
- ElastiCache (optional): ~$7.50/month
- Same other costs
- **Total: ~$150-180/month**

### Cost Optimization Tips

1. **Disable ElastiCache** when not needed (saves ~$7.50/month)
2. **Use Fargate Spot** for non-critical workloads (50% savings)
3. **Monitor RDS scaling** - adjust min/max capacity based on usage
4. **Delete stack** when not in use to avoid idle costs

## 🔧 Troubleshooting

### Stack Creation Fails

**Check stack events for errors:**

```bash
aws --profile ctfd cloudformation describe-stack-events \
  --stack-name ctfd-v2 \
  --region us-east-1 \
  --max-items 50 \
  --query 'StackEvents[?ResourceStatus==`CREATE_FAILED` || ResourceStatus==`ROLLBACK_IN_PROGRESS`]' \
  --output table
```

**Common Issues:**

1. **"TemplateURL must be a supported URL"**
   - **Solution**: Ensure all templates are uploaded to S3 and `main.yaml` uses S3 URLs

2. **"Resource creation cancelled"**
   - **Solution**: Check IAM permissions, resource limits, or service quotas

3. **"InvalidParameterValue"**
   - **Solution**: Verify parameter values in `parameters.json`

### RDS Connection Issues

1. **Verify your IP is allowed:**
   ```bash
   SG_ID=$(aws --profile ctfd cloudformation describe-stacks \
     --stack-name ctfd-v2 \
     --region us-east-1 \
     --query 'Stacks[0].Outputs[?OutputKey==`RDSSecurityGroupId`].OutputValue' \
     --output text)
   
   aws --profile ctfd ec2 describe-security-group-rules \
     --filters "Name=group-id,Values=$SG_ID" \
     --region us-east-1
   ```

2. **Check RDS cluster status:**
   ```bash
   aws --profile ctfd rds describe-db-clusters \
     --db-cluster-identifier ctfd-v2-db-cluster \
     --region us-east-1 \
     --query 'DBClusters[0].Status'
   ```

3. **Verify security group rules allow traffic from VPC**

### ECS Tasks Not Starting

1. **Check CloudWatch Logs:**
   ```bash
   aws --profile ctfd logs tail /aws/ecs/ctfd-v2 --follow --region us-east-1
   ```

2. **Verify task definition:**
   ```bash
   aws --profile ctfd ecs describe-task-definition \
     --task-definition ctfd-v2 \
     --region us-east-1
   ```

3. **Check IAM roles:**
   - Execution role needs Secrets Manager and ECR permissions
   - Task role needs S3 permissions

4. **Verify container image exists:**
   ```bash
   aws --profile ctfd ecr describe-images \
     --repository-name ctfd \
     --region us-east-1
   ```

5. **Check service events:**
   ```bash
   aws --profile ctfd ecs describe-services \
     --cluster ctfd-ecs \
     --services ctfd-v2 \
     --region us-east-1 \
     --query 'services[0].events[:5]'
   ```

### Load Balancer Not Responding

1. **Check target group health:**
   ```bash
   aws --profile ctfd elbv2 describe-target-health \
     --target-group-arn $(aws --profile ctfd elbv2 describe-target-groups \
       --names ctfd-v2-tg \
       --region us-east-1 \
       --query 'TargetGroups[0].TargetGroupArn' \
       --output text) \
     --region us-east-1
   ```

2. **Verify security groups allow traffic**
3. **Check ECS service is running tasks**

## 🔄 Maintenance

### Updating Templates

When you modify any CloudFormation template:

1. **Upload updated template to S3:**
   ```bash
   aws --profile ctfd s3 cp <template-name>.yaml \
     s3://ctfd-cf-templates-127214172072/ \
     --region us-east-1
   ```

2. **Update the stack:**
   ```bash
   aws --profile ctfd cloudformation update-stack \
     --stack-name ctfd-v2 \
     --template-url https://s3.amazonaws.com/ctfd-cf-templates-127214172072/main.yaml \
     --parameters file://parameters.json \
     --capabilities CAPABILITY_IAM \
     --region us-east-1
   ```

### Enabling ElastiCache for Training

Before a training session:

1. Update `parameters.json`:
   ```json
   {
     "ParameterKey": "EnableElastiCache",
     "ParameterValue": "true"
   }
   ```

2. Update the stack:
   ```bash
   aws --profile ctfd cloudformation update-stack \
     --stack-name ctfd-v2 \
     --template-url https://s3.amazonaws.com/ctfd-cf-templates-127214172072/main.yaml \
     --parameters file://parameters.json \
     --capabilities CAPABILITY_IAM \
     --region us-east-1
   ```

3. Wait for update to complete (~10-15 minutes)

After training, set `EnableElastiCache` back to `"false"` and update again.

### Scaling ECS Tasks Manually

```bash
# Update desired count
aws --profile ctfd ecs update-service \
  --cluster ctfd-ecs \
  --service ctfd-v2 \
  --desired-count 2 \
  --region us-east-1
```

Or update the `FrontendDesiredCount` parameter in the stack.

## 🗑️ Cleanup

To delete all resources:

```bash
aws --profile ctfd cloudformation delete-stack \
  --stack-name ctfd-v2 \
  --region us-east-1
```

**Warning**: This will delete:
- ✅ All data in RDS database (unless `DBSkipFinalSnapshot` is `false`)
- ✅ All files in S3 challenge bucket (unless `ForceDestroyChallengeBucket` is `false`)
- ✅ All CloudWatch logs
- ✅ All Secrets Manager secrets

**To preserve data:**
1. Take a manual RDS snapshot before deletion
2. Export S3 bucket contents
3. Export Secrets Manager secrets

## 📊 Monitoring

### CloudWatch Metrics

Key metrics to monitor:
- **ECS**: `CPUUtilization`, `MemoryUtilization`
- **RDS**: `CPUUtilization`, `DatabaseConnections`, `FreeableMemory`
- **ALB**: `RequestCount`, `TargetResponseTime`, `HTTPCode_Target_2XX_Count`
- **ElastiCache**: `CPUUtilization`, `NetworkBytesIn`, `NetworkBytesOut`

### CloudWatch Alarms

The stack automatically creates alarms for:
- High CPU utilization (scale up)
- Low CPU utilization (scale down)
- High request count (scale up)

View alarms:
```bash
aws --profile ctfd cloudwatch describe-alarms \
  --alarm-name-prefix ctfd-v2 \
  --region us-east-1
```

## 🔄 Differences from Terraform Version

- ✅ Uses nested CloudFormation stacks instead of modules
- ✅ Secrets Manager secrets are created in the main stack
- ✅ Database password is generated by RDS stack and referenced
- ✅ All templates must be in S3 (for nested stacks)
- ✅ Uses CloudFormation intrinsic functions instead of Terraform functions
- ✅ Same cost optimizations and auto-scaling behavior

## 📝 Notes

- **S3 Bucket**: Templates are stored in `ctfd-cf-templates-127214172072`. Update `main.yaml` if using a different account.
- **Region**: Default is `us-east-1`. Update region in all commands if deploying elsewhere.
- **Profile**: Uses `ctfd` AWS profile. Set `AWS_PROFILE` environment variable or use `--profile` flag.
- **Stack Name**: Default is `ctfd-v2`. Can be changed but update all references.

## 🆘 Getting Help

If you encounter issues:

1. Check the [Troubleshooting](#troubleshooting) section
2. Review CloudFormation stack events for detailed error messages
3. Check CloudWatch logs for application-level errors
4. Verify all prerequisites are met
5. Ensure IAM permissions are correct

## 📚 Additional Resources

- [AWS CloudFormation Documentation](https://docs.aws.amazon.com/cloudformation/)
- [ECS Best Practices](https://docs.aws.amazon.com/AmazonECS/latest/bestpracticesguide/)
- [RDS Aurora Serverless v2](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/aurora-serverless-v2.html)
