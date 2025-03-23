#!/bin/bash

set -e  
set -o pipefail  

AWS_REGION="us-east-1"  
VPC_CIDR="10.0.0.0/16"
SUBNET_CIDR="10.0.1.0/24"
SECURITY_GROUP_NAME="payment-api-sg"  # ✅ Fixed Name
AMI_NAME="PaymentProcessing-AMI"
INSTANCE_TYPE="t2.micro"
BASE_AMI="ami-01f5a0b78d6089704"
KEY_NAME="payment-key"  

echo "🔍 Checking for existing VPC..."
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=cidr-block,Values=$VPC_CIDR" --query "Vpcs[0].VpcId" --output text 2>/dev/null)
if [[ -z "$VPC_ID" || "$VPC_ID" == "None" ]]; then
    echo "🚀 Creating VPC..."
    VPC_ID=$(aws ec2 create-vpc --cidr-block $VPC_CIDR --query 'Vpc.VpcId' --output text)
    aws ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-support "{\"Value\":true}"
    aws ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-hostnames "{\"Value\":true}"
fi
echo "✅ Using VPC: $VPC_ID"

echo "🔍 Checking for existing Subnet..."
SUBNET_ID=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" "Name=cidr-block,Values=$SUBNET_CIDR" --query "Subnets[0].SubnetId" --output text 2>/dev/null)
if [[ -z "$SUBNET_ID" || "$SUBNET_ID" == "None" ]]; then
    echo "🚀 Creating Subnet..."
    SUBNET_ID=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block $SUBNET_CIDR --query 'Subnet.SubnetId' --output text)
    aws ec2 modify-subnet-attribute --subnet-id $SUBNET_ID --map-public-ip-on-launch
fi
echo "✅ Using Subnet: $SUBNET_ID"

echo "🔍 Checking for Security Group..."
SECURITY_GROUP_ID=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=$SECURITY_GROUP_NAME" --query "SecurityGroups[0].GroupId" --output text 2>/dev/null)
if [[ -z "$SECURITY_GROUP_ID" || "$SECURITY_GROUP_ID" == "None" ]]; then
    echo "🚀 Creating Security Group..."
    SECURITY_GROUP_ID=$(aws ec2 create-security-group --group-name "$SECURITY_GROUP_NAME" --description "Security group for Payment API" --vpc-id $VPC_ID --query 'GroupId' --output text)
    
    aws ec2 authorize-security-group-ingress --group-id "$SECURITY_GROUP_ID" --protocol tcp --port 22 --cidr 0.0.0.0/0
    aws ec2 authorize-security-group-ingress --group-id "$SECURITY_GROUP_ID" --protocol tcp --port 3000 --cidr 0.0.0.0/0
fi
echo "✅ Using Security Group: $SECURITY_GROUP_ID"

echo "🚀 Launching EC2 Instance..."
INSTANCE_ID=$(aws ec2 run-instances --image-id $BASE_AMI --count 1 --instance-type $INSTANCE_TYPE --key-name $KEY_NAME \
    --security-group-ids $SECURITY_GROUP_ID --subnet-id $SUBNET_ID --iam-instance-profile Name="PaymentProcessingRole" \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=PaymentProcessingInstance}]' \
    --query 'Instances[0].InstanceId' --output text)

echo "⏳ Waiting for EC2 instance to start..."
aws ec2 wait instance-running --instance-ids $INSTANCE_ID
echo "✅ EC2 Instance Running: $INSTANCE_ID"

echo "🚀 Creating AMI from instance..."
AMI_ID=$(aws ec2 create-image --instance-id $INSTANCE_ID --name "$AMI_NAME" --description "AMI for Payment Processing API" \
    --no-reboot --query 'ImageId' --output text)

echo "⏳ Waiting for AMI to become available..."
aws ec2 wait image-available --image-ids $AMI_ID
echo "✅ AMI Created: $AMI_ID"

echo "🗑️ Terminating EC2 Instance..."
aws ec2 terminate-instances --instance-ids $INSTANCE_ID
aws ec2 wait instance-terminated --instance-ids $INSTANCE_ID
echo "✅ Instance Terminated."

echo "🎉 AMI Creation Complete!"
echo "📌 VPC ID: $VPC_ID"
echo "📌 Subnet ID: $SUBNET_ID"
echo "📌 Security Group ID: $SECURITY_GROUP_ID"
echo "📌 AMI ID: $AMI_ID"

