#!/bin/bash
# =====================================================
# initialize.sh - Environment Variables Initialization
# =====================================================

export AWS_PAGER=""

# EC2
INSTANCE_ID=$(aws ec2 describe-instances --filters "Name=tag:project,Values=hci" "Name=instance-state-name,Values=running" --query "Reservations[0].Instances[0].InstanceId" --output text)
PUBLIC_IP=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID --query "Reservations[0].Instances[0].PublicIpAddress" --output text)

# IAM
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
CLUSTER_ROLE=$(aws iam get-role --role-name LabRole --query "Role.Arn" --output text)
NODE_ROLE=$CLUSTER_ROLE

# VPC
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=isDefault,Values=true" --query "Vpcs[0].VpcId" --output text)
SUBNET_1=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --query "Subnets[0].SubnetId" --output text)
SUBNET_2=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --query "Subnets[1].SubnetId" --output text)

# S3
export ARCHIVECLOUD_BUCKET=$(aws s3 ls | grep archivecloud | awk '{print $3}')
export CLOUDVAULT_BUCKET=$ARCHIVECLOUD_BUCKET

# SNS
TOPIC_ARN=$(aws sns list-topics --query "Topics[?contains(TopicArn,'archivecloud-alerts')].TopicArn | [0]" --output text)

# EKS
EKS_CLUSTER="archivecloud-eks"

# Print all to verify
echo "================================"
echo "Instance  : $INSTANCE_ID"
echo "Public IP : $PUBLIC_IP"
echo "Account   : $ACCOUNT_ID"
echo "Bucket    : $ARCHIVECLOUD_BUCKET"
echo "VPC       : $VPC_ID"
echo "Subnet 1  : $SUBNET_1"
echo "Subnet 2  : $SUBNET_2"
echo "SNS Topic : $TOPIC_ARN"
echo "EKS       : $EKS_CLUSTER"
echo "================================"