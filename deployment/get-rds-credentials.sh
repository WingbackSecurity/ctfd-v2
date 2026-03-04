#!/bin/bash
# get-rds-credentials.sh - Retrieve RDS credentials from Secrets Manager
# Usage: ./get-rds-credentials.sh

set -e

# Configuration
DEPLOYMENT_DIR="/Users/pcuser/midfield/ctfd-v2/deployment"
AWS_PROFILE="ctfd"
AWS_REGION="us-east-1"

cd "$DEPLOYMENT_DIR"

# Get secret names from Terraform output
USERNAME_SECRET=$(terraform output -raw rds_username_secret_name 2>/dev/null || echo "ctfd-v2-rds-username")
PASSWORD_SECRET=$(terraform output -raw rds_password_secret_name 2>/dev/null || echo "ctfd-v2-rds-password")

echo "Retrieving RDS credentials from Secrets Manager..."
echo ""

# Retrieve username
echo "Username Secret: $USERNAME_SECRET"
RDS_USER=$(aws --profile $AWS_PROFILE secretsmanager get-secret-value \
  --region $AWS_REGION \
  --secret-id $USERNAME_SECRET \
  --query SecretString \
  --output text 2>/dev/null)

if [ -z "$RDS_USER" ]; then
  echo "Error: Could not retrieve username from secret: $USERNAME_SECRET"
  exit 1
fi

# Retrieve password
echo "Password Secret: $PASSWORD_SECRET"
RDS_PASSWORD=$(aws --profile $AWS_PROFILE secretsmanager get-secret-value \
  --region $AWS_REGION \
  --secret-id $PASSWORD_SECRET \
  --query SecretString \
  --output text 2>/dev/null)

if [ -z "$RDS_PASSWORD" ]; then
  echo "Error: Could not retrieve password from secret: $PASSWORD_SECRET"
  exit 1
fi

# Get other connection details from Terraform
RDS_ENDPOINT=$(terraform output -raw rds_endpoint 2>/dev/null || echo "")
RDS_PORT=$(terraform output -raw rds_port 2>/dev/null || echo "3306")
RDS_DATABASE=$(terraform output -raw rds_database_name 2>/dev/null || echo "ctfd")

echo ""
echo "📋 RDS Connection Details:"
echo "=========================="
echo "Host:     $RDS_ENDPOINT"
echo "Port:     $RDS_PORT"
echo "Database: $RDS_DATABASE"
echo "Username: $RDS_USER"
echo "Password: $RDS_PASSWORD"
echo ""
echo "Connection Command:"
echo "mysql -h $RDS_ENDPOINT -P $RDS_PORT -u $RDS_USER -p $RDS_DATABASE"
echo ""
echo "Connection String (for SQL clients):"
echo "mysql://$RDS_USER:$RDS_PASSWORD@$RDS_ENDPOINT:$RDS_PORT/$RDS_DATABASE"
echo ""
echo "Or use AWS CLI to retrieve:"
echo "  Username: aws --profile $AWS_PROFILE secretsmanager get-secret-value --secret-id $USERNAME_SECRET --query SecretString --output text"
echo "  Password: aws --profile $AWS_PROFILE secretsmanager get-secret-value --secret-id $PASSWORD_SECRET --query SecretString --output text"
