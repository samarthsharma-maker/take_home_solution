#!/bin/bash

# AWS Setup Script for ECR Repository and GitHub OIDC Integration
# This script creates:
# 1. Private ECR repository
# 2. GitHub OIDC provider
# 3. IAM role with ECR push permissions

set -e

# Color output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}================================${NC}"
echo -e "${BLUE}AWS ECR + OIDC Setup${NC}"
echo -e "${BLUE}================================${NC}\n"

# Get AWS Account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo -e "${GREEN}✓ AWS Account ID: ${AWS_ACCOUNT_ID}${NC}"

# Variables (customize these)
read -p "Enter GitHub repository (owner/repo) [samarthsharma-maker/take_home_assignment]: " GITHUB_REPO
GITHUB_REPO=${GITHUB_REPO:-samarthsharma-maker/take_home_assignment}

read -p "Enter ECR repository name [scaler-devsecops-app]: " ECR_REPO_NAME
ECR_REPO_NAME=${ECR_REPO_NAME:-scaler-devsecops-app}

read -p "Enter AWS region [us-east-1]: " AWS_REGION
AWS_REGION=${AWS_REGION:-us-east-1}

echo -e "\n${BLUE}Configuration:${NC}"
echo "  GitHub Repo: $GITHUB_REPO"
echo "  ECR Repository: $ECR_REPO_NAME"
echo "  AWS Region: $AWS_REGION"
echo ""

read -p "Continue with these settings? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 1
fi

# Step 1: Create ECR Repository
echo -e "\n${BLUE}Step 1: Creating ECR repository...${NC}"
if aws ecr create-repository \
  --repository-name "$ECR_REPO_NAME" \
  --region "$AWS_REGION" \
  --encryption-configuration encryptionType=AES \
  --image-tag-mutability IMMUTABLE 2>/dev/null; then
    echo -e "${GREEN}✓ ECR repository created${NC}"
    ECR_URI="$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_REPO_NAME"
    echo "  URI: $ECR_URI"
else
    echo -e "${RED}✗ ECR repository already exists (or error occurred)${NC}"
    ECR_URI="$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_REPO_NAME"
fi

# Step 2: Create OIDC Provider
echo -e "\n${BLUE}Step 2: Creating GitHub OIDC provider...${NC}"
GITHUB_OIDC_THUMBPRINT="6938fd4d98bab03faadb97b34396831e3780aea1"

if aws iam create-open-id-connect-provider \
  --url "https://token.actions.githubusercontent.com" \
  --client-id-list "sts.amazonaws.com" \
  --thumbprint-list "$GITHUB_OIDC_THUMBPRINT" 2>/dev/null; then
    echo -e "${GREEN}✓ OIDC provider created${NC}"
else
    echo -e "${RED}✗ OIDC provider already exists (or error occurred)${NC}"
fi

# Step 3: Create Trust Policy
echo -e "\n${BLUE}Step 3: Creating IAM trust policy...${NC}"
TRUST_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:${GITHUB_REPO}:ref:refs/heads/main"
        }
      }
    }
  ]
}
EOF
)

echo "$TRUST_POLICY" > /tmp/trust-policy.json
echo -e "${GREEN}✓ Trust policy created${NC}"

# Step 4: Create IAM Role
echo -e "\n${BLUE}Step 4: Creating IAM role...${NC}"
if aws iam create-role \
  --role-name github-actions-role \
  --assume-role-policy-document file:///tmp/trust-policy.json \
  --description "Role for GitHub Actions to push to ECR" 2>/dev/null; then
    echo -e "${GREEN}✓ IAM role created${NC}"
    ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/github-actions-role"
else
    echo -e "${RED}✗ IAM role already exists (or error occurred)${NC}"
    ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/github-actions-role"
fi

# Step 5: Create and Attach ECR Policy
echo -e "\n${BLUE}Step 5: Creating ECR policy...${NC}"
ECR_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "ecr:BatchCheckLayerAvailability",
        "ecr:PutImage",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload",
        "ecr:DescribeRepositories",
        "ecr:GetAuthorizationToken"
      ],
      "Resource": "arn:aws:ecr:${AWS_REGION}:${AWS_ACCOUNT_ID}:repository/${ECR_REPO_NAME}"
    },
    {
      "Effect": "Allow",
      "Action": [
        "ecr:GetAuthorizationToken"
      ],
      "Resource": "*"
    }
  ]
}
EOF
)

echo "$ECR_POLICY" > /tmp/ecr-policy.json

aws iam put-role-policy \
  --role-name github-actions-role \
  --policy-name github-actions-ecr-policy \
  --policy-document file:///tmp/ecr-policy.json

echo -e "${GREEN}✓ ECR policy attached${NC}"

# Summary
echo -e "\n${BLUE}================================${NC}"
echo -e "${GREEN}Setup Complete!${NC}"
echo -e "${BLUE}================================${NC}\n"

echo -e "${BLUE}Next Steps:${NC}"
echo "1. Add GitHub Repository Secrets:"
echo -e "   ${GREEN}AWS_ACCOUNT_ID${NC}: $AWS_ACCOUNT_ID"
echo ""
echo "2. Your workflow variables:"
echo -e "   ${GREEN}ECR_REPOSITORY${NC}: $ECR_REPO_NAME"
echo -e "   ${GREEN}ECR_URI${NC}: $ECR_URI"
echo -e "   ${GREEN}ROLE_ARN${NC}: $ROLE_ARN"
echo ""
echo "3. GitHub Actions workflow configuration:"
echo -e "   ${GREEN}role-to-assume:${NC} $ROLE_ARN"
echo -e "   ${GREEN}aws-region:${NC} $AWS_REGION"
echo ""
echo -e "${BLUE}Verification Commands:${NC}"
echo "  # Verify ECR"
echo "  aws ecr describe-repositories --repository-names $ECR_REPO_NAME --region $AWS_REGION"
echo ""
echo "  # Verify OIDC Provider"
echo "  aws iam list-open-id-connect-providers"
echo ""
echo "  # Verify IAM Role"
echo "  aws iam get-role --role-name github-actions-role"
echo ""
echo "  # Test image push (after configuring GitHub secrets)"
echo "  docker build -t $ECR_URI:latest ."
echo "  aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"
echo "  docker push $ECR_URI:latest"
echo ""

# Cleanup
rm -f /tmp/trust-policy.json /tmp/ecr-policy.json

echo -e "${GREEN}Setup script completed successfully!${NC}\n"
