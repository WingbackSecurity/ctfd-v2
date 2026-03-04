#!/bin/bash
# update-rds-ip.sh - Update RDS security group with current IP
# Usage: ./update-rds-ip.sh

set -e

# Configuration
DEPLOYMENT_DIR="/Users/pcuser/midfield/ctfd-v2/deployment"
AWS_PROFILE="ctfd"
AWS_REGION="us-east-1"

cd "$DEPLOYMENT_DIR"

# Get current public IP
echo "Getting current public IP..."
MY_IP=$(curl -s https://checkip.amazonaws.com)
CIDR_IP="${MY_IP}/32"

echo "Current IP: $MY_IP"

# Get security group ID from Terraform output
SG_ID=$(terraform output -raw rds_security_group_id 2>/dev/null || \
  terraform state show module.rds[0].aws_security_group.rds 2>/dev/null | grep "id " | awk '{print $3}')

if [ -z "$SG_ID" ] || [ "$SG_ID" == "null" ]; then
  echo "Error: Could not get security group ID from Terraform"
  echo "Please run 'terraform output' to see available outputs"
  exit 1
fi

echo "Security Group ID: $SG_ID"

# Check if rule already exists
EXISTING_RULE=$(aws --profile $AWS_PROFILE ec2 describe-security-groups \
  --region $AWS_REGION \
  --group-ids $SG_ID \
  --query "SecurityGroups[0].IpPermissions[?FromPort==\`3306\` && ToPort==\`3306\` && IpProtocol==\`tcp\`].IpRanges[?CidrIp==\`$CIDR_IP\`].CidrIp" \
  --output text 2>/dev/null || echo "")

if [ "$EXISTING_RULE" == "$CIDR_IP" ]; then
  echo "✅ IP $CIDR_IP is already allowed. No changes needed."
  exit 0
fi

# Find and remove old rules (if exists)
echo "Checking for existing rules..."
OLD_RULES=$(aws --profile $AWS_PROFILE ec2 describe-security-groups \
  --region $AWS_REGION \
  --group-ids $SG_ID \
  --query "SecurityGroups[0].IpPermissions[?FromPort==\`3306\` && ToPort==\`3306\` && IpProtocol==\`tcp\`].IpRanges[].CidrIp" \
  --output text 2>/dev/null || echo "")

if [ -n "$OLD_RULES" ]; then
  echo "Removing old IP rules: $OLD_RULES"
  for OLD_IP in $OLD_RULES; do
    echo "  Removing: $OLD_IP"
    aws --profile $AWS_PROFILE ec2 revoke-security-group-ingress \
      --region $AWS_REGION \
      --group-id $SG_ID \
      --protocol tcp \
      --port 3306 \
      --cidr $OLD_IP 2>/dev/null || echo "    Rule not found or already removed"
  done
fi

# Add new rule
echo "Adding new rule for IP: $CIDR_IP"
aws --profile $AWS_PROFILE ec2 authorize-security-group-ingress \
  --region $AWS_REGION \
  --group-id $SG_ID \
  --protocol tcp \
  --port 3306 \
  --cidr $CIDR_IP \
  --description "RDS access - updated $(date +%Y-%m-%d\ %H:%M:%S)"

echo ""
echo "✅ Successfully updated security group!"
echo "   New IP: $CIDR_IP"
echo "   Security Group: $SG_ID"
echo ""
echo "📋 RDS Connection Details:"
echo "=========================="

# Get RDS credentials from Secrets Manager
USERNAME_SECRET=$(terraform output -raw rds_username_secret_name 2>/dev/null || echo "${APP_NAME:-ctfd-v2}-rds-username")
PASSWORD_SECRET=$(terraform output -raw rds_password_secret_name 2>/dev/null || echo "${APP_NAME:-ctfd-v2}-rds-password")

if [ -n "$USERNAME_SECRET" ] && [ -n "$PASSWORD_SECRET" ]; then
  RDS_USER=$(aws --profile $AWS_PROFILE secretsmanager get-secret-value \
    --region $AWS_REGION \
    --secret-id $USERNAME_SECRET \
    --query SecretString \
    --output text 2>/dev/null || echo "")

  RDS_PASSWORD=$(aws --profile $AWS_PROFILE secretsmanager get-secret-value \
    --region $AWS_REGION \
    --secret-id $PASSWORD_SECRET \
    --query SecretString \
    --output text 2>/dev/null || echo "")

  RDS_ENDPOINT=$(terraform output -raw rds_endpoint 2>/dev/null || echo "")
  RDS_PORT=$(terraform output -raw rds_port 2>/dev/null || echo "3306")
  RDS_DATABASE=$(terraform output -raw rds_database_name 2>/dev/null || echo "ctfd")

  if [ -n "$RDS_USER" ] && [ -n "$RDS_PASSWORD" ] && [ -n "$RDS_ENDPOINT" ]; then
    echo "Host:     $RDS_ENDPOINT"
    echo "Port:     $RDS_PORT"
    echo "Database: $RDS_DATABASE"
    echo "Username: $RDS_USER"
    echo "Password: $RDS_PASSWORD"
    echo ""
    echo "Connection Command:"
    echo "mysql -h $RDS_ENDPOINT -P $RDS_PORT -u $RDS_USER -p $RDS_DATABASE"
  else
    echo "⚠️  Could not retrieve all RDS credentials"
    echo "   Run './get-rds-credentials.sh' to get connection details"
  fi
else
  echo "⚠️  Could not find RDS credential secrets"
  echo "   Run './get-rds-credentials.sh' to get connection details"
fi
