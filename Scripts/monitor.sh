#!/bin/bash
# ============================================================
#  ArchiveCloud — monitor.sh
#  Checks status of all 8 AWS services
#  Requires: initialize.sh to be sourced first
#  Usage:
#    ./monitor.sh          # check all services
#    ./monitor.sh iam
#    ./monitor.sh ec2
#    ./monitor.sh s3
#    ./monitor.sh glacier
#    ./monitor.sh eks
#    ./monitor.sh glue
#    ./monitor.sh cloudwatch
#    ./monitor.sh sns
#    ./monitor.sh ssm
# ============================================================

G='\033[0;32m'; Y='\033[1;33m'; C='\033[0;36m'; R='\033[0;31m'; M='\033[0;35m'; NC='\033[0m'
ok()      { echo -e "  ${G}[OK]${NC}  $1"; }
info()    { echo -e "  ${C}[..]${NC}  $1"; }
warn()    { echo -e "  ${Y}[!!]${NC}  $1"; }
err()     { echo -e "  ${R}[XX]${NC}  $1"; }
section() { echo -e "\n  ${M}=== $1 ===${NC}"; }

COMMAND="${1:-all}"

echo ""
echo "  ArchiveCloud - Monitor"
echo "  ========================"

# Guard
[[ -z "$ARCHIVECLOUD_BUCKET" ]] && {
  echo -e "  ${R}[XX]${NC}  ARCHIVECLOUD_BUCKET not set. Run: source initialize.sh"
  exit 1
}

check_iam() {
  section "IAM"
  ARN=$(aws sts get-caller-identity --query "Arn" --output text 2>/dev/null)
  ACCOUNT=$(aws sts get-caller-identity --query "Account" --output text 2>/dev/null)
  ok "Account  : $ACCOUNT"
  ok "Identity : $ARN"
}

check_ec2() {
  section "EC2"
  aws ec2 describe-instances --filters "Name=tag:project,Values=hci" --query "Reservations[*].Instances[*].{ID:InstanceId,State:State.Name,IP:PublicIpAddress,Type:InstanceType}" --output table 2>/dev/null && ok "EC2 query complete" || warn "No EC2 instances found"
}

check_s3() {
  section "S3"
  info "Bucket: $ARCHIVECLOUD_BUCKET"
  aws s3api list-objects-v2 --bucket "$ARCHIVECLOUD_BUCKET" --query "{TotalObjects:KeyCount}" --output table 2>/dev/null && ok "S3 query complete" || warn "Could not query bucket"
}

check_glacier() {
  section "S3 Glacier"
  info "Objects by storage class in s3://$ARCHIVECLOUD_BUCKET"
  for CLASS in STANDARD STANDARD_IA GLACIER; do
    COUNT=$(aws s3api list-objects-v2 --bucket "$ARCHIVECLOUD_BUCKET" --query "length(Contents[?StorageClass=='$CLASS'] || \`[]\`)" --output text 2>/dev/null || echo "0")
    printf "    %-20s %s objects\n" "$CLASS" "${COUNT:-0}"
  done
  ok "Glacier query complete"
}

check_eks() {
  section "EKS"
  aws eks describe-cluster --name archivecloud-eks --query "cluster.{Name:name,Status:status,Version:version}" --output table 2>/dev/null || warn "Cluster archivecloud-eks not found"
  aws eks describe-nodegroup --cluster-name archivecloud-eks --nodegroup-name archivecloud-nodes --query "nodegroup.{Status:status,Instance:instanceTypes[0],Desired:scalingConfig.desiredSize}" --output table 2>/dev/null || warn "Node group not found"
  ok "EKS query complete"
}

check_glue() {
  section "AWS Glue"
  aws glue get-crawler --name archivecloud-crawler --query "Crawler.{Name:Name,State:State,LastUpdated:LastUpdated}" --output table 2>/dev/null || warn "Crawler archivecloud-crawler not found"
  aws glue get-tables --database-name archivecloud_catalog --query "TableList[*].{Name:Name,Location:StorageDescriptor.Location}" --output table 2>/dev/null || warn "No tables found in archivecloud_catalog"
  ok "Glue query complete"
}

check_cloudwatch() {
  section "CloudWatch"
  aws cloudwatch list-metrics --namespace "ArchiveCloud/IOC" --query "Metrics[*].{Metric:MetricName,Dimension:Dimensions[0].Value}" --output table 2>/dev/null || warn "No metrics found in ArchiveCloud/IOC"
  aws cloudwatch describe-alarms --alarm-name-prefix "archivecloud" --query "MetricAlarms[*].{Name:AlarmName,State:StateValue}" --output table 2>/dev/null || warn "No alarms found"
  ok "CloudWatch query complete"
}

check_sns() {
  section "SNS"
  aws sns list-topics --query "Topics[?contains(TopicArn,'archivecloud')].TopicArn" --output table 2>/dev/null || warn "No archivecloud SNS topics found"
  aws sns list-subscriptions-by-topic --topic-arn "$TOPIC_ARN" --query "Subscriptions[*].{Protocol:Protocol,Endpoint:Endpoint,Status:SubscriptionArn}" --output table 2>/dev/null || warn "No subscriptions found (or TOPIC_ARN not set)"
  ok "SNS query complete"
}

check_ssm() {
  section "Systems Manager"
  aws ssm describe-instance-information --query "InstanceInformationList[*].{ID:InstanceId,Ping:PingStatus,Platform:PlatformName}" --output table 2>/dev/null || warn "No SSM managed instances found"
  aws ssm get-parameters-by-path --path "/archivecloud/" --query "Parameters[*].{Name:Name,Modified:LastModifiedDate}" --output table 2>/dev/null || warn "No /archivecloud/ SSM parameters yet"
  ok "SSM query complete"
}

# Dispatch
case "$COMMAND" in
  iam)        check_iam ;;
  ec2)        check_ec2 ;;
  s3)         check_s3 ;;
  glacier)    check_glacier ;;
  eks)        check_eks ;;
  glue)       check_glue ;;
  cloudwatch) check_cloudwatch ;;
  sns)        check_sns ;;
  ssm)        check_ssm ;;
  all)
    check_iam
    check_ec2
    check_s3
    check_glacier
    check_eks
    check_glue
    check_cloudwatch
    check_sns
    check_ssm
    echo ""
    ok "All services checked."
    ;;
  *)
    echo "  Usage: ./monitor.sh [service]"
    echo ""
    echo "  Services: iam + ec2 + s3 + glacier + eks + glue + cloudwatch + sns + ssm"
    echo "  Default : all"
    ;;
esac

echo ""