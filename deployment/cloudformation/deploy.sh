#!/bin/bash

# CTFd CloudFormation Deployment Script
# This script helps deploy the CTFd infrastructure using CloudFormation

set -e

PROFILE="${AWS_PROFILE:-ctfd}"
REGION="${AWS_REGION:-us-east-1}"
STACK_NAME="${STACK_NAME:-ctfd-v2}"
TEMPLATE_BUCKET=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    print_error "AWS CLI is not installed. Please install it first."
    exit 1
fi

# Check if profile exists
if ! aws --profile "$PROFILE" sts get-caller-identity &> /dev/null; then
    print_error "AWS profile '$PROFILE' not found or not configured."
    exit 1
fi

# Get account ID
ACCOUNT_ID=$(aws --profile "$PROFILE" sts get-caller-identity --query Account --output text)
print_info "Using AWS Account: $ACCOUNT_ID"

# Get current IP
print_info "Getting your current public IP..."
MY_IP=$(curl -s https://checkip.amazonaws.com)
print_info "Your IP: $MY_IP"

# Update parameters.json with current IP
if [ -f "parameters.json" ]; then
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        sed -i '' "s|YOUR_IP_HERE|$MY_IP|g" parameters.json
    else
        # Linux
        sed -i "s|YOUR_IP_HERE|$MY_IP|g" parameters.json
    fi
    print_info "Updated parameters.json with your IP"
else
    print_error "parameters.json not found!"
    exit 1
fi

# Ask if user wants to upload templates to S3
read -p "Do you want to upload templates to S3? (recommended for nested stacks) [y/N]: " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    TEMPLATE_BUCKET="ctfd-cf-templates-${ACCOUNT_ID}"
    
    # Create bucket if it doesn't exist
    if ! aws --profile "$PROFILE" s3 ls "s3://${TEMPLATE_BUCKET}" 2>&1 | grep -q 'NoSuchBucket'; then
        print_info "Creating S3 bucket: $TEMPLATE_BUCKET"
        aws --profile "$PROFILE" s3 mb "s3://${TEMPLATE_BUCKET}" --region "$REGION" 2>/dev/null || true
    else
        print_info "S3 bucket already exists: $TEMPLATE_BUCKET"
    fi
    
    # Upload templates
    print_info "Uploading CloudFormation templates to S3..."
    aws --profile "$PROFILE" s3 cp . "s3://${TEMPLATE_BUCKET}/" \
        --recursive \
        --exclude "*.md" \
        --exclude "*.json" \
        --exclude "*.sh" \
        --region "$REGION"
    
    TEMPLATE_URL="https://s3.amazonaws.com/${TEMPLATE_BUCKET}/main.yaml"
    print_info "Templates uploaded. Using S3 URL: $TEMPLATE_URL"
else
    print_warn "Using local files. Note: Nested stacks require templates in S3 or you need to manually update TemplateURL in main.yaml"
    TEMPLATE_URL="file://main.yaml"
fi

# Check if stack exists
if aws --profile "$PROFILE" cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$REGION" &> /dev/null; then
    print_warn "Stack '$STACK_NAME' already exists. Updating..."
    OPERATION="update-stack"
else
    print_info "Creating new stack '$STACK_NAME'..."
    OPERATION="create-stack"
fi

# Deploy the stack
print_info "Deploying CloudFormation stack..."
if [ "$TEMPLATE_BUCKET" != "" ]; then
    aws --profile "$PROFILE" cloudformation $OPERATION \
        --stack-name "$STACK_NAME" \
        --template-url "$TEMPLATE_URL" \
        --parameters file://parameters.json \
        --capabilities CAPABILITY_IAM \
        --region "$REGION"
else
    aws --profile "$PROFILE" cloudformation $OPERATION \
        --stack-name "$STACK_NAME" \
        --template-body file://main.yaml \
        --parameters file://parameters.json \
        --capabilities CAPABILITY_IAM \
        --region "$REGION"
fi

print_info "Stack deployment initiated. This will take 15-30 minutes."
print_info "Monitor progress with:"
print_info "  aws --profile $PROFILE cloudformation describe-stack-events --stack-name $STACK_NAME --region $REGION --max-items 10"

# Wait for stack to complete
read -p "Do you want to wait for stack creation/update to complete? [y/N]: " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    print_info "Waiting for stack operation to complete..."
    if [ "$OPERATION" == "create-stack" ]; then
        aws --profile "$PROFILE" cloudformation wait stack-create-complete \
            --stack-name "$STACK_NAME" \
            --region "$REGION"
    else
        aws --profile "$PROFILE" cloudformation wait stack-update-complete \
            --stack-name "$STACK_NAME" \
            --region "$REGION"
    fi
    
    print_info "Stack operation completed!"
    
    # Show outputs
    print_info "Stack Outputs:"
    aws --profile "$PROFILE" cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --region "$REGION" \
        --query 'Stacks[0].Outputs' \
        --output table
fi

print_info "Deployment script completed!"
