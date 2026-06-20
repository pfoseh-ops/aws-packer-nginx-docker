#!/bin/bash
# Script to launch EC2 instances from the Docker+Nginx AMI
# Usage: ./launch-instance.sh <AMI_ID> [instance-type] [region]

set -e

AMI_ID="${1:?Error: AMI_ID is required. Usage: $0 <AMI_ID> [instance-type] [region]}"
INSTANCE_TYPE="${2:-t3.micro}"
REGION="${3:-us-east-1}"
KEY_NAME="${KEY_NAME:?Error: KEY_NAME environment variable is required}"

# Create security group if it doesn't exist
SG_NAME="nginx-docker-sg"
SG_EXISTS=$(aws ec2 describe-security-groups \
  --group-names "$SG_NAME" \
  --region "$REGION" \
  --output text \
  --query 'SecurityGroups[0].GroupId' 2>/dev/null || echo "")

if [ -z "$SG_EXISTS" ]; then
  echo "Creating security group: $SG_NAME"
  SG_ID=$(aws ec2 create-security-group \
    --group-name "$SG_NAME" \
    --description "Security group for Nginx Docker instances" \
    --region "$REGION" \
    --output text --query 'GroupId')
  
  # Allow HTTP
  aws ec2 authorize-security-group-ingress \
    --group-id "$SG_ID" \
    --protocol tcp --port 80 --cidr 0.0.0.0/0 \
    --region "$REGION"
  
  # Allow HTTPS
  aws ec2 authorize-security-group-ingress \
    --group-id "$SG_ID" \
    --protocol tcp --port 443 --cidr 0.0.0.0/0 \
    --region "$REGION"
  
  # Allow SSH
  aws ec2 authorize-security-group-ingress \
    --group-id "$SG_ID" \
    --protocol tcp --port 22 --cidr 0.0.0.0/0 \
    --region "$REGION"
else
  SG_ID="$SG_EXISTS"
  echo "Using existing security group: $SG_ID"
fi

# Launch instance
echo "Launching EC2 instance..."
echo "  AMI: $AMI_ID"
echo "  Instance Type: $INSTANCE_TYPE"
echo "  Region: $REGION"
echo "  Security Group: $SG_ID"
echo "  Key Pair: $KEY_NAME"

INSTANCE_ID=$(aws ec2 run-instances \
  --image-id "$AMI_ID" \
  --instance-type "$INSTANCE_TYPE" \
  --key-name "$KEY_NAME" \
  --security-group-ids "$SG_ID" \
  --associate-public-ip-address \
  --region "$REGION" \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=nginx-docker-$(date +%s)}]" \
  --output text --query 'Instances[0].InstanceId')

echo "✓ Instance launched: $INSTANCE_ID"
echo ""
echo "Waiting for instance to be running..."
aws ec2 wait instance-running \
  --instance-ids "$INSTANCE_ID" \
  --region "$REGION"

# Get instance details
INSTANCE_INFO=$(aws ec2 describe-instances \
  --instance-ids "$INSTANCE_ID" \
  --region "$REGION" \
  --output json | jq '.Reservations[0].Instances[0]')

PUBLIC_IP=$(echo "$INSTANCE_INFO" | jq -r '.PublicIpAddress')
PRIVATE_IP=$(echo "$INSTANCE_INFO" | jq -r '.PrivateIpAddress')

echo ""
echo "✓ Instance is running!"
echo ""
echo "Connection Details:"
echo "  Instance ID: $INSTANCE_ID"
echo "  Public IP: $PUBLIC_IP"
echo "  Private IP: $PRIVATE_IP"
echo ""
echo "Next steps:"
echo "  1. SSH access: ssh -i your-key.pem ubuntu@$PUBLIC_IP"
echo "  2. Visit Nginx: http://$PUBLIC_IP"
echo "  3. Check service: ssh -i your-key.pem ubuntu@$PUBLIC_IP 'systemctl status nginx-docker.service'"
echo ""
echo "Wait 20-30 seconds for cloud-init and Nginx to start..."
