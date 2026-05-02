# AWS Setup Guide - ECR Repository and OIDC Role

This guide provides all AWS CLI commands needed to set up:
1. Private ECR repository
2. GitHub OIDC provider
3. IAM role for GitHub Actions with ECR push permissions

## Prerequisites

- AWS CLI configured with appropriate credentials
- GitHub organization/repository name
- AWS Account ID (find with: `aws sts get-caller-identity`)

## Step 1: Set Variables

Replace these with your actual values:

```bash
# Your AWS Account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Your GitHub repository (organization/repository)
GITHUB_REPO="samarthsharma-maker/take_home_assignment"

# ECR repository name
ECR_REPO_NAME="scaler-devsecops-app"

# AWS Region
AWS_REGION="us-east-1"

echo "AWS Account ID: $AWS_ACCOUNT_ID"
echo "GitHub Repo: $GITHUB_REPO"
```

## Step 2: Create Private ECR Repository

```bash
aws ecr create-repository \
  --repository-name "$ECR_REPO_NAME" \
  --region "$AWS_REGION" \
  --encryption-configuration encryptionType=AES \
  --image-tag-mutability IMMUTABLE
```

**Expected output:**
```json
{
  "repository": {
    "repositoryArn": "arn:aws:ecr:us-east-1:123456789012:repository/scaler-devsecops-app",
    "registryId": "123456789012",
    "repositoryName": "scaler-devsecops-app",
    "repositoryUri": "123456789012.dkr.ecr.us-east-1.amazonaws.com/scaler-devsecops-app",
    "imageScanningConfiguration": {
      "scanOnPush": false
    },
    "imageTagMutability": "IMMUTABLE",
    "encryptionConfiguration": {
      "encryptionType": "AES"
    }
  }
}
```

Save the `repositoryUri` - you'll need it in GitHub Actions.

---

## Step 3: Create GitHub OIDC Provider

First, get the GitHub OIDC thumbprint:

```bash
# Get the thumbprint for GitHub's OIDC certificate
THUMBPRINT=$(curl -s https://token.actions.githubusercontent.com/.well-known/openid-configuration | \
  jq -r '.jwks_uri' | \
  sed 's|https://||' | \
  cut -d/ -f1 | \
  xargs -I {} openssl s_client -servername {} -connect {}:443 -showcerts </dev/null 2>/dev/null | \
  openssl x509 -noout -fingerprint | \
  sed 's/SHA1 Fingerprint=//; s/://g' | \
  tr '[:upper:]' '[:lower:]')

echo "GitHub OIDC Thumbprint: $THUMBPRINT"
```

If the above doesn't work, use this simpler approach:

```bash
# Alternative: Manual thumbprint (as of 2024, GitHub's thumbprint is usually this)
THUMBPRINT="6938fd4d98bab03faadb97b34396831e3780aea1"
```

Now create the OIDC provider:

```bash
aws iam create-open-id-connect-provider \
  --url "https://token.actions.githubusercontent.com" \
  --client-id-list "sts.amazonaws.com" \
  --thumbprint-list "$THUMBPRINT"
```

**Expected output:**
```json
{
  "OpenIDConnectProviderArn": "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
}
```

Save this ARN - you'll use it in the trust policy.

---

## Step 4: Create Trust Policy for GitHub Actions

Create a file named `trust-policy.json`:

```bash
cat > trust-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::AWS_ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:GITHUB_REPO:ref:refs/heads/main"
        }
      }
    }
  ]
}
EOF

# Replace placeholders with actual values
sed -i '' "s/AWS_ACCOUNT_ID/$AWS_ACCOUNT_ID/g" trust-policy.json
sed -i '' "s|GITHUB_REPO|$GITHUB_REPO|g" trust-policy.json

cat trust-policy.json
```

---

## Step 5: Create IAM Role

Create the role with the trust policy:

```bash
aws iam create-role \
  --role-name github-actions-role \
  --assume-role-policy-document file://trust-policy.json \
  --description "Role for GitHub Actions to push to ECR"
```

**Expected output:**
```json
{
  "Role": {
    "Path": "/",
    "RoleName": "github-actions-role",
    "RoleId": "AIDAI7EXAMPLE",
    "Arn": "arn:aws:iam::123456789012:role/github-actions-role",
    "CreateDate": "2024-01-15T10:30:00+00:00",
    "AssumeRolePolicyDocument": {...}
  }
}
```

Save the role ARN - this goes in your GitHub secret.

---

## Step 6: Create and Attach ECR Push Policy

Create a file named `ecr-policy.json`:

```bash
cat > ecr-policy.json << 'EOF'
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
      "Resource": "arn:aws:ecr:AWS_REGION:AWS_ACCOUNT_ID:repository/ECR_REPO_NAME"
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

# Replace placeholders
sed -i '' "s/AWS_ACCOUNT_ID/$AWS_ACCOUNT_ID/g" ecr-policy.json
sed -i '' "s/AWS_REGION/$AWS_REGION/g" ecr-policy.json
sed -i '' "s/ECR_REPO_NAME/$ECR_REPO_NAME/g" ecr-policy.json

cat ecr-policy.json
```

Now attach the policy to the role:

```bash
aws iam put-role-policy \
  --role-name github-actions-role \
  --policy-name github-actions-ecr-policy \
  --policy-document file://ecr-policy.json
```

---

## Step 7: Configure GitHub Secrets

In your GitHub repository settings, add these secrets:

1. **AWS_ACCOUNT_ID**
   - Value: `123456789012` (your actual account ID)

2. **AWS_OIDC_ROLE_ARN** (optional, but useful)
   - Value: `arn:aws:iam::123456789012:role/github-actions-role`

**Steps:**
1. Go to GitHub repository > Settings > Secrets and variables > Actions
2. Click "New repository secret"
3. Add `AWS_ACCOUNT_ID` with your account ID
4. The workflow will construct the role ARN from this

---

## Verification Commands

### Verify ECR Repository Created

```bash
aws ecr describe-repositories \
  --repository-names "$ECR_REPO_NAME" \
  --region "$AWS_REGION"
```

### Verify OIDC Provider Created

```bash
aws iam list-open-id-connect-providers
```

### Verify IAM Role Created

```bash
aws iam get-role --role-name github-actions-role
```

### Verify Role Trust Policy

```bash
aws iam get-role-policy \
  --role-name github-actions-role \
  --policy-name github-actions-ecr-policy
```

---

## Complete Setup Script

If you prefer one script, here's the full automation:

```bash
#!/bin/bash

# Variables
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
GITHUB_REPO="samarthsharma-maker/take_home_assignment"
ECR_REPO_NAME="scaler-devsecops-app"
AWS_REGION="us-east-1"
GITHUB_OIDC_THUMBPRINT="6938fd4d98bab03faadb97b34396831e3780aea1"

echo "Starting AWS setup..."
echo "Account ID: $AWS_ACCOUNT_ID"
echo "GitHub Repo: $GITHUB_REPO"

# Step 1: Create ECR Repository
echo "Creating ECR repository..."
aws ecr create-repository \
  --repository-name "$ECR_REPO_NAME" \
  --region "$AWS_REGION" \
  --encryption-configuration encryptionType=AES \
  --image-tag-mutability IMMUTABLE

# Step 2: Create OIDC Provider
echo "Creating OIDC provider..."
aws iam create-open-id-connect-provider \
  --url "https://token.actions.githubusercontent.com" \
  --client-id-list "sts.amazonaws.com" \
  --thumbprint-list "$GITHUB_OIDC_THUMBPRINT"

# Step 3: Create Trust Policy
echo "Creating trust policy..."
cat > /tmp/trust-policy.json << EOFPOLICY
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
EOFPOLICY

# Step 4: Create IAM Role
echo "Creating IAM role..."
aws iam create-role \
  --role-name github-actions-role \
  --assume-role-policy-document file:///tmp/trust-policy.json \
  --description "Role for GitHub Actions to push to ECR"

# Step 5: Create and Attach ECR Policy
echo "Creating ECR policy..."
cat > /tmp/ecr-policy.json << EOFPOL
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
      "Action": ["ecr:GetAuthorizationToken"],
      "Resource": "*"
    }
  ]
}
EOFPOL

aws iam put-role-policy \
  --role-name github-actions-role \
  --policy-name github-actions-ecr-policy \
  --policy-document file:///tmp/ecr-policy.json

echo "Setup complete!"
echo "Add these GitHub secrets:"
echo "  AWS_ACCOUNT_ID: $AWS_ACCOUNT_ID"
```

---

## GitHub Actions Workflow Configuration

In your `.github/workflows/deploy.yml`, the OIDC configuration should be:

```yaml
- name: Configure AWS credentials via OIDC
  uses: aws-actions/configure-aws-credentials@v4
  with:
    role-to-assume: arn:aws:iam::${{ secrets.AWS_ACCOUNT_ID }}:role/github-actions-role
    aws-region: us-east-1
```

---

## Troubleshooting

### Error: "Role already exists"
```bash
# Delete and recreate:
aws iam delete-role --role-name github-actions-role
aws iam delete-role-policy --role-name github-actions-role --policy-name github-actions-ecr-policy
# Then run setup again
```

### Error: "OIDC Provider already exists"
```bash
# List existing providers
aws iam list-open-id-connect-providers

# Delete if needed
aws iam delete-open-id-connect-provider \
  --open-id-connect-provider-arn arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com
```

### Error: "Repository already exists"
```bash
# Delete ECR repository
aws ecr delete-repository \
  --repository-name "$ECR_REPO_NAME" \
  --force \
  --region "$AWS_REGION"
```

### Workflow fails with "User: arn:aws:sts::... is not authorized"
- Verify the role has the ECR policy attached
- Verify the GitHub branch matches the condition (usually `main`)
- Check CloudTrail for detailed error messages

---

## Security Best Practices

1. **Scope to specific branches**: Change the condition to match only your deployment branch
2. **Use IMMUTABLE tags**: Already enabled in ECR setup (prevents image tampering)
3. **Enable image scanning**: Consider `ecr:DescribeImages` and enabling ECR image scanning
4. **Rotate role regularly**: Review IAM role permissions quarterly
5. **Monitor OIDC usage**: Check CloudTrail for all role assumption events
