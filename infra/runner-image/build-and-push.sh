#!/bin/bash
set -e

AWS_REGION="ap-northeast-2"
AWS_ACCOUNT_ID="763479270202"
ECR_REPO="github-runner-devsecops"
IMAGE_TAG="${1:-latest}"

echo "============================================"
echo "Building GitHub Runner Image with Kaniko"
echo "============================================"
echo "ECR Repository: ${ECR_REPO}"
echo "Image Tag: ${IMAGE_TAG}"
echo "============================================"

# Build the image
echo "Step 1: Building Docker image..."
docker build --platform linux/amd64 -t ${ECR_REPO}:${IMAGE_TAG} .

# Login to ECR
echo "Step 2: Logging in to ECR..."
aws ecr get-login-password --region ${AWS_REGION} | \
  docker login --username AWS --password-stdin ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com

# Tag the image
echo "Step 3: Tagging image..."
docker tag ${ECR_REPO}:${IMAGE_TAG} \
  ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO}:${IMAGE_TAG}

# Push to ECR
echo "Step 4: Pushing to ECR..."
docker push ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO}:${IMAGE_TAG}

echo "============================================"
echo "✅ Successfully pushed:"
echo "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO}:${IMAGE_TAG}"
echo "============================================"
echo ""
echo "Next steps:"
echo "1. The AutoScalingRunnerSet will automatically pull the new image"
echo "2. New runner pods will include Kaniko executor at /usr/local/bin/kaniko"
echo "3. Update your workflow to use 'kaniko' command directly"
