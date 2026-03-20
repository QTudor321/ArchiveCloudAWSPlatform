#!/bin/bash
# ================================================================================================
# installation.sh - Amazon Web Services Installation for the Archive Cloud and Monitoring Platform
# Time: ~25 minutes total (EKS takes most of it)
#  Run this in a fresh lab session after destroy.sh
# ================================================================================================

G='\033[0;32m'; Y='\033[1;33m'; C='\033[0;36m'; R='\033[0;31m'; M='\033[0;35m'; NC='\033[0m'
ok()      { echo -e "  ${G}[OK]${NC}  $1"; }
info()    { echo -e "  ${C}[..]${NC}  $1"; }
warn()    { echo -e "  ${Y}[!!]${NC}  $1"; }
err()     { echo -e "  ${R}[XX]${NC}  $1"; exit 1; }
section() { echo -e "\n  ${M}=== $1 ===${NC}"; }

# Wait helper with timeout - prevents infinite loops
# Usage: wait_for <description> <timeout_seconds> <check_command> <expected_value>
wait_for() {
  local DESC="$1"
  local TIMEOUT="$2"
  local CMD="$3"
  local EXPECTED="$4"
  local ELAPSED=0
  info "Waiting for $DESC (timeout: ${TIMEOUT}s)..."
  while true; do
    RESULT=$(eval "$CMD" 2>/dev/null || echo "ERROR")
    [[ "$RESULT" == "$EXPECTED" ]] && { ok "$DESC — $EXPECTED"; return 0; }
    if [[ $ELAPSED -ge $TIMEOUT ]]; then
      warn "$DESC timed out after ${TIMEOUT}s — last status: $RESULT"
      return 1
    fi
    echo "    status: $RESULT — waiting 30s... (${ELAPSED}s / ${TIMEOUT}s)"
    sleep 30
    ELAPSED=$((ELAPSED + 30))
  done
}

export AWS_PAGER=""
REGION="us-east-1"

echo ""
echo "  ArchiveCloud - Installation"
echo "  ============================="
echo "  This will build all 8 AWS services."
echo "  Estimated time: ~25 minutes"
echo ""

# Prerequisites check 
section "Prerequisites"
aws sts get-caller-identity --output text > /dev/null 2>&1 && ok "AWS credentials active" || err "AWS credentials not found - is the lab session running?"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ok "Account: $ACCOUNT_ID"

# Must be run from inside the repo
[[ ! -f "Scripts/initialize.sh" ]] && err "Run this from inside the ArchiveCloudAWSPlatform folder"
ok "Repo folder confirmed"

# PART 1 - IAM
section "IAM"
CLUSTER_ROLE=$(aws iam get-role --role-name LabRole --query "Role.Arn" --output text)
NODE_ROLE=$CLUSTER_ROLE
ok "LabRole ARN: $CLUSTER_ROLE"

# PART 2 - VPC + Networking
section "VPC"
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=isDefault,Values=true" --query "Vpcs[0].VpcId" --output text)
ok "Default VPC: $VPC_ID"
SUBNET_1=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --query "Subnets[0].SubnetId" --output text)
SUBNET_2=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --query "Subnets[1].SubnetId" --output text)
ok "Subnet 1: $SUBNET_1"
ok "Subnet 2: $SUBNET_2"

# PART 3 - EC2
section "EC2 - Launching instance"
AMI_ID=$(aws ec2 describe-images --owners amazon --filters "Name=name,Values=al2023-ami-*-x86_64" "Name=state,Values=available" --query "sort_by(Images,&CreationDate)[-1].ImageId" --output text)
ok "AMI: $AMI_ID"
SG_ID=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=archivecloud-sg" --query "SecurityGroups[0].GroupId" --output text 2>/dev/null || echo "")
if [[ -z "$SG_ID" || "$SG_ID" == "None" ]]; then
  SG_ID=$(aws ec2 create-security-group --group-name archivecloud-sg --description "CloudArchive security group" --vpc-id $VPC_ID --query "GroupId" --output text)
  aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol tcp --port 80 --cidr 0.0.0.0/0
  aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol tcp --port 22 --cidr 0.0.0.0/0
  ok "Security group created: $SG_ID"
else
  ok "Security group reused: $SG_ID"
fi
aws iam create-instance-profile --instance-profile-name archivecloud-profile 2>/dev/null || true
aws iam add-role-to-instance-profile --instance-profile-name archivecloud-profile --role-name LabRole 2>/dev/null || true
ok "Instance profile ready"
INSTANCE_ID=$(aws ec2 run-instances --image-id $AMI_ID --instance-type t2.micro --subnet-id $SUBNET_1 --security-group-ids $SG_ID --iam-instance-profile Name=archivecloud-profile --associate-public-ip-address --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=cloudvault-server},{Key=project,Value=hci}]' --query "Instances[0].InstanceId" --output text)
ok "Instance launched: $INSTANCE_ID"
wait_for "EC2 instance running" 300 "aws ec2 describe-instances --instance-ids $INSTANCE_ID --query 'Reservations[0].Instances[0].State.Name' --output text" "running" || err "EC2 instance failed to start"
ok "Instance is running"
PUBLIC_IP=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID --query "Reservations[0].Instances[0].PublicIpAddress" --output text)
ok "Public IP: $PUBLIC_IP"
wait_for "SSM agent online" 300 "aws ssm describe-instance-information --query \"InstanceInformationList[?InstanceId=='$INSTANCE_ID'].PingStatus\" --output text" "Online" || warn "SSM agent slow - continuing anyway"
ok "SSM agent online"
info "Creating project directories on EC2..."
aws ssm send-command --instance-ids $INSTANCE_ID --document-name "AWS-RunShellScript" --parameters 'commands=[
    "mkdir -p /home/ec2-user/ArchiveCloudAWSPlatform/{Scripts,Powershell,UserInterface,Documents}",
    "echo Directories created"
  ]' --output text > /dev/null
info "Installing nginx..."
CMD_ID=$(aws ssm send-command --instance-ids $INSTANCE_ID --document-name "AWS-RunShellScript" --parameters 'commands=[
    "dnf install nginx -y",
    "systemctl start nginx",
    "systemctl enable nginx",
    "echo nginx ready"
  ]' --query "Command.CommandId" --output text)
ELAPSED=0
while true; do
  sleep 15
  ELAPSED=$((ELAPSED + 15))
  STATUS=$(aws ssm get-command-invocation --command-id $CMD_ID --instance-id $INSTANCE_ID --query "Status" --output text 2>/dev/null || echo "Pending")
  [[ "$STATUS" == "Success" ]] && { ok "nginx installed"; break; }
  [[ "$STATUS" == "Failed" ]]  && { warn "nginx install failed — continuing"; break; }
  [[ $ELAPSED -ge 180 ]]       && { warn "nginx install timed out — continuing"; break; }
  echo "    nginx installing... ($STATUS) ${ELAPSED}s"
done

# PART 4 - S3 bucket
section "S3 - Creating bucket"
EXISTING=$(aws s3 ls | grep archivecloud | awk '{print $3}' | head -1)
if [[ -n "$EXISTING" ]]; then
  ARCHIVECLOUD_BUCKET="$EXISTING"
  export ARCHIVECLOUD_BUCKET
  export CLOUDVAULT_BUCKET=$ARCHIVECLOUD_BUCKET
  ok "Reusing existing bucket: $ARCHIVECLOUD_BUCKET"
else
  ARCHIVECLOUD_BUCKET="archivecloud-$(date +%s)"
  export ARCHIVECLOUD_BUCKET
  export CLOUDVAULT_BUCKET=$ARCHIVECLOUD_BUCKET
  aws s3api create-bucket --bucket "$ARCHIVECLOUD_BUCKET" --region $REGION
  ok "Bucket created: $ARCHIVECLOUD_BUCKET"
fi
info "Uploading project files to S3..."
aws s3 cp UserInterface/index.html   s3://$ARCHIVECLOUD_BUCKET/Deploy/UserInterface/index.html --quiet
aws s3 cp UserInterface/styles.css   s3://$ARCHIVECLOUD_BUCKET/Deploy/UserInterface/styles.css --quiet
aws s3 cp UserInterface/script.js    s3://$ARCHIVECLOUD_BUCKET/Deploy/UserInterface/script.js  --quiet
aws s3 cp Scripts/upload.sh          s3://$ARCHIVECLOUD_BUCKET/Deploy/Scripts/upload.sh        --quiet
aws s3 cp Scripts/archive.sh         s3://$ARCHIVECLOUD_BUCKET/Deploy/Scripts/archive.sh       --quiet
aws s3 cp Scripts/monitor.sh         s3://$ARCHIVECLOUD_BUCKET/Deploy/Scripts/monitor.sh       --quiet
aws s3 cp Scripts/initialize.sh      s3://$ARCHIVECLOUD_BUCKET/Deploy/Scripts/initialize.sh    --quiet
aws s3 cp Scripts/eliminate.sh      s3://$ARCHIVECLOUD_BUCKET/Deploy/Scripts/eliminate.sh    --quiet
[[ -f "Documents/services.md" ]]      && aws s3 cp Documents/services.md      s3://$ARCHIVECLOUD_BUCKET/Deploy/Documents/services.md      --quiet
[[ -f "Documents/architecture.jpg" ]] && aws s3 cp Documents/architecture.jpg s3://$ARCHIVECLOUD_BUCKET/Deploy/Documents/architecture.jpg --quiet
ok "All files uploaded to S3"
aws s3api put-bucket-lifecycle-configuration --bucket $ARCHIVECLOUD_BUCKET --lifecycle-configuration '{
    "Rules":[{
      "ID":"archivecloud-auto-glacier",
      "Status":"Enabled",
      "Filter":{"Prefix":"Deploy/"},
      "Transitions":[
        {"Days":30,"StorageClass":"STANDARD_IA"},
        {"Days":90,"StorageClass":"GLACIER"}
      ]
    }]
  }' && ok "Glacier lifecycle policy set"

# PART 5 - Deploy files to EC2 via SSM
section "SSM - Deploying files to EC2"
CMD_ID=$(aws ssm send-command --instance-ids $INSTANCE_ID --document-name "AWS-RunShellScript" --parameters 'commands=[
    "aws s3 cp s3://'"$ARCHIVECLOUD_BUCKET"'/Deploy/ /home/ec2-user/ArchiveCloudAWSPlatform/ --recursive",
    "chmod +x /home/ec2-user/ArchiveCloudAWSPlatform/Scripts/*.sh",
    "cp /home/ec2-user/ArchiveCloudAWSPlatform/UserInterface/index.html /usr/share/nginx/html/index.html",
    "cp /home/ec2-user/ArchiveCloudAWSPlatform/UserInterface/styles.css /usr/share/nginx/html/styles.css",
    "cp /home/ec2-user/ArchiveCloudAWSPlatform/UserInterface/script.js  /usr/share/nginx/html/script.js",
    "echo Deployed"
  ]' --query "Command.CommandId" --output text)
ELAPSED=0
while true; do
  sleep 15
  ELAPSED=$((ELAPSED + 15))
  STATUS=$(aws ssm get-command-invocation --command-id $CMD_ID --instance-id $INSTANCE_ID --query "Status" --output text 2>/dev/null || echo "Pending")
  [[ "$STATUS" == "Success" ]] && { ok "Files deployed to EC2"; break; }
  [[ "$STATUS" == "Failed" ]]  && { warn "Deploy failed — check SSM logs"; break; }
  [[ $ELAPSED -ge 180 ]]       && { warn "Deploy timed out — continuing"; break; }
  echo "    deploying... ($STATUS) ${ELAPSED}s"
done
ok "Dashboard: http://$PUBLIC_IP"

# PART 6 - EKS cluster (starts in background, takes ~12 min)
section "EKS - Creating cluster (this takes ~12 minutes)"
EXISTING_CLUSTER=$(aws eks list-clusters --query "clusters[?@=='archivecloud-eks']" --output text 2>/dev/null || echo "")
if [[ -n "$EXISTING_CLUSTER" ]]; then
  ok "Cluster already exists - skipping creation"
else
  aws eks create-cluster --name archivecloud-eks --region $REGION --kubernetes-version 1.29 --role-arn $CLUSTER_ROLE --resources-vpc-config subnetIds=$SUBNET_1,$SUBNET_2,endpointPublicAccess=true --output text > /dev/null && ok "Cluster creation started..." || err "Cluster creation failed"
fi
wait_for "EKS cluster ACTIVE" 1200 "aws eks describe-cluster --name archivecloud-eks --query 'cluster.status' --output text" "ACTIVE" || err "EKS cluster failed - check AWS console" 
info "Creating node group (~5 more minutes)..."
EXISTING_NG=$(aws eks list-nodegroups --cluster-name archivecloud-eks --query "nodegroups[?@=='archivecloud-nodes']" --output text 2>/dev/null || echo "")
if [[ -n "$EXISTING_NG" ]]; then
  ok "Node group already exists - skipping"
else
  aws eks create-nodegroup --cluster-name archivecloud-eks --nodegroup-name archivecloud-nodes --node-role $NODE_ROLE --subnets $SUBNET_1 $SUBNET_2 --instance-types t3.small --scaling-config minSize=1,maxSize=2,desiredSize=1 --output text > /dev/null && ok "Node group creation started..." || err "Node group creation failed"
fi
wait_for "EKS node group ACTIVE" 900 "aws eks describe-nodegroup --cluster-name archivecloud-eks --nodegroup-name archivecloud-nodes --query 'nodegroup.status' --output text" "ACTIVE" || warn "Node group timed out - check AWS console and continue manually" 
ok "Node group is ACTIVE"

# PART 7 - Glue
section "Glue - Creating catalog and crawler"
aws glue create-database --database-input '{"Name":"archivecloud_catalog","Description":"ArchiveCloud S3 archive data catalog"}' 2>/dev/null && ok "Glue database created" || ok "Glue database already exists"
aws glue create-crawler --name archivecloud-crawler --role $NODE_ROLE --database-name archivecloud_catalog --targets '{"S3Targets":[{"Path":"s3://'"$ARCHIVECLOUD_BUCKET"'/Deploy/"}]}' 2>/dev/null && ok "Glue crawler created" || ok "Glue crawler already exists"
aws glue start-crawler --name archivecloud-crawler 2>/dev/null && ok "Crawler started - will finish in ~2 minutes" || warn "Crawler already running"

# PART 8 - CloudWatch + SNS
section "CloudWatch - Pushing metrics"
aws cloudwatch put-metric-data --namespace "ArchiveCloud/IOC" --metric-name "FilesUploaded" --value 0 --unit Count --dimensions Name=Bucket,Value=$ARCHIVECLOUD_BUCKET
aws cloudwatch put-metric-data --namespace "ArchiveCloud/IOC" --metric-name "GlacierArchives" --value 0 --unit Count --dimensions Name=Bucket,Value=$ARCHIVECLOUD_BUCKET
aws cloudwatch put-metric-data --namespace "ArchiveCloud/IOC" --metric-name "EKSNodesActive" --value 1 --unit Count --dimensions Name=Cluster,Value=archivecloud-eks
ok "CloudWatch metrics initialized"
section "SNS - Creating alert topic"
TOPIC_ARN=$(aws sns create-topic --name archivecloud-alerts --query "TopicArn" --output text)
ok "SNS topic: $TOPIC_ARN"
aws sns subscribe --topic-arn $TOPIC_ARN --protocol email --notification-endpoint youremail@gmail.com 2>/dev/null && ok "Email subscription created - check inbox to confirm" || ok "Subscription already exists"
aws cloudwatch put-metric-alarm --alarm-name "archivecloud-no-uploads" --alarm-description "No files uploaded in last hour" --namespace "ArchiveCloud/IOC" --metric-name "FilesUploaded" --statistic Sum --period 3600 --threshold 1 --comparison-operator LessThanThreshold --evaluation-periods 1 --alarm-actions $TOPIC_ARN 2>/dev/null && ok "Alarm created: archivecloud-no-uploads" || ok "Alarm already exists"
aws cloudwatch put-metric-alarm --alarm-name "archivecloud-glacier-activity" --alarm-description "Monitors Glacier archive operations" --namespace "ArchiveCloud/IOC" --metric-name "GlacierArchives" --statistic Sum --period 3600 --threshold 1 --comparison-operator GreaterThanOrEqualToThreshold --evaluation-periods 1 --alarm-actions $TOPIC_ARN 2>/dev/null && ok "Alarm created: archivecloud-glacier-activity" || ok "Alarm already exists"

# PART 9 - S3 Glacier test file
section "S3 Glacier - Creating test archive"
echo "ArchiveCloud installation test - $(date)" > /tmp/archive_test.txt
aws s3 cp /tmp/archive_test.txt s3://$ARCHIVECLOUD_BUCKET/Deploy/archive_test.txt --quiet
aws s3 cp s3://$ARCHIVECLOUD_BUCKET/Deploy/archive_test.txt s3://$ARCHIVECLOUD_BUCKET/Deploy/archive_test.txt --storage-class GLACIER --metadata-directive COPY --quiet && ok "Test file archived to Glacier"

# PART 10 - Update initialize.sh bucket name + re-source
section "Finalizing"
echo "export ARCHIVECLOUD_BUCKET=$ARCHIVECLOUD_BUCKET" > .env
echo "export CLOUDVAULT_BUCKET=$ARCHIVECLOUD_BUCKET"   >> .env
ok "Bucket name saved to .env"

# Final summary
echo ""
echo "  ============================================"
ok "Installation complete"
echo "  ============================================"
echo ""
echo "  Instance  : $INSTANCE_ID"
echo "  Public IP : $PUBLIC_IP"
echo "  Bucket    : $ARCHIVECLOUD_BUCKET"
echo "  EKS       : archivecloud-eks (ACTIVE)"
echo "  Dashboard : http://$PUBLIC_IP"
echo ""
info "Next step - load all variables into your session:"
echo ""
echo "    source Scripts/initialize.sh"
echo ""
info "Then test the scripts:"
echo ""
echo "    echo 'test' > test.txt && ./Scripts/upload.sh test.txt"
echo "    ./Scripts/monitor.sh all"
echo "    ./Scripts/archive.sh"
echo ""