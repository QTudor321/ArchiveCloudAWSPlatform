#!/bin/bash
# =========================================================================
# eliminate.sh - Elimination of all installed services from installation.sh
# Eliminating all the installed services will also remove any billing
# Requires: source Scripts/initialize.sh first
# =========================================================================

G='\033[0;32m'; Y='\033[1;33m'; C='\033[0;36m'; R='\033[0;31m'; M='\033[0;35m'; NC='\033[0m'
ok()      { echo -e "  ${G}[OK]${NC}  $1"; }
info()    { echo -e "  ${C}[..]${NC}  $1"; }
warn()    { echo -e "  ${Y}[!!]${NC}  $1"; }
err()     { echo -e "  ${R}[XX]${NC}  $1"; }
section() { echo -e "\n  ${M}=== $1 ===${NC}"; }

echo ""
echo "  ArchiveCloud — Destroy"
echo "  ========================"
echo ""
echo -e "  ${R}WARNING: This will delete ALL project resources.${NC}"
echo -e "  ${R}This cannot be undone.${NC}"
echo ""
read -p "  Type DESTROY to confirm: " CONFIRM
[[ "$CONFIRM" != "DESTROY" ]] && { echo "  Cancelled."; exit 0; }

# Restore variables if not set
export AWS_PAGER=""
REGION="${AWS_DEFAULT_REGION:-us-east-1}"
[[ -z "$INSTANCE_ID" ]] && INSTANCE_ID=$(aws ec2 describe-instances --filters "Name=tag:project,Values=hci" "Name=instance-state-name,Values=running" --query "Reservations[0].Instances[0].InstanceId" --output text 2>/dev/null)
[[ -z "$ARCHIVECLOUD_BUCKET" ]] && ARCHIVECLOUD_BUCKET=$(aws s3 ls | grep archivecloud | awk '{print $3}')
[[ -z "$TOPIC_ARN" ]] && TOPIC_ARN=$(aws sns list-topics --query "Topics[?contains(TopicArn,'archivecloud-alerts')].TopicArn | [0]" --output text 2>/dev/null)

# 1. EKS node group
section "EKS — Deleting node group"
NODE_STATUS=$(aws eks describe-nodegroup --cluster-name archivecloud-eks --nodegroup-name archivecloud-nodes --query "nodegroup.status" --output text 2>/dev/null || echo "NOT_FOUND")
if [[ "$NODE_STATUS" != "NOT_FOUND" ]]; then
  info "Deleting node group archivecloud-nodes (~5 min)..."
  aws eks delete-nodegroup --cluster-name archivecloud-eks --nodegroup-name archivecloud-nodes --output text > /dev/null && ok "Node group deletion started" || warn "Node group deletion failed or already gone"
  info "Waiting for node group to be deleted..."
  ELAPSED=0
  while true; do
    STATUS=$(aws eks describe-nodegroup --cluster-name archivecloud-eks --nodegroup-name archivecloud-nodes --query "nodegroup.status" --output text 2>/dev/null || echo "DELETED")
    [[ "$STATUS" == "DELETED" || "$STATUS" == "" ]] && break
    [[ $ELAPSED -ge 1200 ]] && { warn "Node group deletion timed out — check AWS console"; break; }
    echo "    status: $STATUS — waiting 30s... (${ELAPSED}s / 1200s)"
    sleep 30
    ELAPSED=$((ELAPSED + 30))
  done
  ok "Node group deleted"
else
  warn "Node group not found — skipping"
fi

# 2. EKS cluster
section "EKS — Deleting cluster"
CLUSTER_STATUS=$(aws eks describe-cluster --name archivecloud-eks --query "cluster.status" --output text 2>/dev/null || echo "NOT_FOUND")
if [[ "$CLUSTER_STATUS" != "NOT_FOUND" ]]; then
  info "Deleting cluster archivecloud-eks (~5 min)..."
  aws eks delete-cluster --name archivecloud-eks --output text > /dev/null && ok "Cluster deletion started" || warn "Cluster deletion failed or already gone"
  info "Waiting for cluster to be deleted..."
  ELAPSED=0
  while true; do
    STATUS=$(aws eks describe-cluster --name archivecloud-eks --query "cluster.status" --output text 2>/dev/null || echo "DELETED")
    [[ "$STATUS" == "DELETED" || "$STATUS" == "" ]] && break
    [[ $ELAPSED -ge 1200 ]] && { warn "Cluster deletion timed out — check AWS console"; break; }
    echo "    status: $STATUS — waiting 30s... (${ELAPSED}s / 1200s)"
    sleep 30
    ELAPSED=$((ELAPSED + 30))
  done
  ok "Cluster deleted"
else
  warn "Cluster not found — skipping"
fi

# 3. EC2 instance
section "EC2 — Terminating instance"
if [[ -n "$INSTANCE_ID" && "$INSTANCE_ID" != "None" ]]; then
  info "Terminating $INSTANCE_ID..."
  aws ec2 terminate-instances --instance-ids $INSTANCE_ID --output text > /dev/null && ok "Instance termination started" || warn "Could not terminate instance"
  info "Waiting for termination..."
  aws ec2 wait instance-terminated --instance-ids $INSTANCE_ID 2>/dev/null
  ok "Instance terminated"
else
  warn "No running instance found — skipping"
fi

# 4. Security group
section "EC2 — Deleting security group"
sleep 15
SG_ID=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=archivecloud-sg" --query "SecurityGroups[0].GroupId" --output text 2>/dev/null || echo "")
if [[ -n "$SG_ID" && "$SG_ID" != "None" ]]; then
  aws ec2 delete-security-group --group-id $SG_ID && ok "Security group deleted: $SG_ID" || warn "Could not delete security group (may still have dependencies)"
else
  warn "Security group not found — skipping"
fi

# 5. NAT Gateways (created by EKS, expensive)
section "VPC — Deleting NAT Gateways"
NAT_IDS=$(aws ec2 describe-nat-gateways --filter "Name=state,Values=available" --query "NatGateways[*].NatGatewayId" --output text 2>/dev/null || echo "")
if [[ -n "$NAT_IDS" && "$NAT_IDS" != "None" ]]; then
  for NAT in $NAT_IDS; do
    info "Deleting NAT Gateway: $NAT"
    aws ec2 delete-nat-gateway --nat-gateway-id $NAT && ok "NAT Gateway deleted: $NAT" || warn "Could not delete NAT Gateway: $NAT"
  done
else
  ok "No NAT Gateways found"
fi

# 6. CloudWatch alarms 
section "CloudWatch — Deleting alarms"
aws cloudwatch delete-alarms --alarm-names "archivecloud-no-uploads" "archivecloud-glacier-activity" && ok "CloudWatch alarms deleted" || warn "Could not delete alarms"

# 7. SNS topic + subscriptions
section "SNS — Deleting topic"
if [[ -n "$TOPIC_ARN" && "$TOPIC_ARN" != "None" ]]; then
  # Unsubscribe all first
  SUBS=$(aws sns list-subscriptions-by-topic --topic-arn $TOPIC_ARN --query "Subscriptions[*].SubscriptionArn" --output text 2>/dev/null || echo "")
  for SUB in $SUBS; do
    [[ "$SUB" == "PendingConfirmation" ]] && continue
    aws sns unsubscribe --subscription-arn $SUB 2>/dev/null || true
  done
  aws sns delete-topic --topic-arn $TOPIC_ARN && ok "SNS topic deleted" || warn "Could not delete SNS topic"
else
  warn "SNS topic not found — skipping"
fi

# 8. Glue crawler + database
section "Glue — Deleting crawler and database"
aws glue delete-crawler --name archivecloud-crawler 2>/dev/null && ok "Glue crawler deleted" || warn "Crawler not found — skipping"
aws glue delete-database --name archivecloud_catalog 2>/dev/null && ok "Glue database deleted" || warn "Database not found — skipping"

# 9. S3 bucket + all contents
section "S3 — Emptying and deleting bucket"
if [[ -n "$ARCHIVECLOUD_BUCKET" && "$ARCHIVECLOUD_BUCKET" != "None" ]]; then
  info "Removing all objects from s3://$ARCHIVECLOUD_BUCKET..."
  aws s3 rm s3://$ARCHIVECLOUD_BUCKET --recursive && ok "Bucket emptied" || warn "Could not empty bucket"
  info "Deleting bucket..."
  aws s3api delete-bucket --bucket $ARCHIVECLOUD_BUCKET --region $REGION && ok "Bucket deleted: $ARCHIVECLOUD_BUCKET" || warn "Could not delete bucket"
else
  warn "No bucket found — skipping"
fi

# 10. SSM parameters
section "SSM — Deleting parameters"
PARAMS=$(aws ssm get-parameters-by-path --path "/archivecloud/" --query "Parameters[*].Name" --output text 2>/dev/null || echo "")
if [[ -n "$PARAMS" && "$PARAMS" != "None" ]]; then
  for PARAM in $PARAMS; do
    aws ssm delete-parameter --name "$PARAM" 2>/dev/null && ok "Deleted: $PARAM" || true
  done
else
  ok "No SSM parameters found"
fi

# 11. IAM instance profile
section "IAM — Removing instance profile"
aws iam remove-role-from-instance-profile --instance-profile-name archivecloud-profile --role-name LabRole 2>/dev/null || true
aws iam delete-instance-profile --instance-profile-name archivecloud-profile 2>/dev/null && ok "Instance profile deleted" || warn "Instance profile not found — skipping"

# Final summary 
echo ""
echo "  ================================"
ok "Destroy complete"
echo "  ================================"
echo ""
info "Remaining (free tier / no cost):"
echo "    CloudWatch metrics namespace — auto expires after 15 months"
echo "    CloudWatch logs              — minimal cost"
echo ""
info "Verify nothing is left:"
echo "    aws ec2 describe-instances --filters Name=tag:project,Values=hci --output table"
echo "    aws eks list-clusters"
echo "    aws s3 ls | grep archivecloud"
echo "    aws ec2 describe-nat-gateways --filter Name=state,Values=available --output table"
echo ""