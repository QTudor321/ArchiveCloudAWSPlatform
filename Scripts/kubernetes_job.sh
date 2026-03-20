#!/bin/bash
# ============================================================
#  ArchiveCloud - kubernetes_job.sh
#  Executes an archive job as a Kubernetes pod from a EKS node
#  Requires: source Scripts/initialize.sh first
# ============================================================

export AWS_PAGER=""

echo ""
echo "  ArchiveCloud - EKS Demo"
echo "  ========================="

# 1. Cluster overview 
echo ""
echo "  === CLUSTER ==="
aws eks describe-cluster --name archivecloud-eks --query "cluster.{Name:name,Status:status,Version:version,Endpoint:endpoint}" --output table

# 2. Node group 
echo ""
echo "  === NODE GROUP ==="
aws eks describe-nodegroup --cluster-name archivecloud-eks --nodegroup-name archivecloud-nodes --query "nodegroup.{Status:status,Instance:instanceTypes[0],Desired:scalingConfig.desiredSize,Min:scalingConfig.minSize,Max:scalingConfig.maxSize}" --output table

# 3. Add-ons installed
echo ""
echo "  === ADD-ONS ==="
aws eks list-addons --cluster-name archivecloud-eks --output table

# 4. Configure kubectl 
echo ""
echo "  === KUBECTL ==="
aws eks update-kubeconfig --name archivecloud-eks --region us-east-1 && echo "  [OK]  kubectl configured" || echo "  [!!]  kubectl config failed"

# 5. Run an S3 archive job as a Kubernetes pod 
echo ""
echo "  === S3 ARCHIVE JOB ==="
echo "  [..]  Submitting archive job to EKS..."
cat <<EOF | kubectl apply -f - 2>/dev/null && echo "  [OK]  Job submitted" || echo "  [!!]  kubectl not available"
apiVersion: batch/v1
kind: Job
metadata:
  name: archivecloud-s3-job
spec:
  ttlSecondsAfterFinished: 120
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: archive-worker
        image: amazon/aws-cli
        command:
        - /bin/sh
        - -c
        - |
          echo "ArchiveCloud EKS Job - \$(date)" > /tmp/eks_job.txt
          aws s3 cp /tmp/eks_job.txt s3://$ARCHIVECLOUD_BUCKET/uploads/eks_job_\$(date +%s).txt
          echo "Job complete - file uploaded to S3"
        env:
        - name: AWS_DEFAULT_REGION
          value: us-east-1
EOF

# 6. Check job status
sleep 10
echo ""
echo "  === JOB STATUS ==="
kubectl get jobs 2>/dev/null && kubectl get pods 2>/dev/null || echo "  [!!]  kubectl not available in this lab"

# 7. Scale the node group up then back 
echo ""
echo "  === SCALING DEMO ==="
echo "  [..]  Scaling node group to 2 nodes..."
aws eks update-nodegroup-config --cluster-name archivecloud-eks --nodegroup-name archivecloud-nodes --scaling-config minSize=1,maxSize=2,desiredSize=2 && echo "  [OK]  Scaled to 2 nodes" || echo "  [!!]  Scale failed"
sleep 5
echo "  [..]  Scaling back to 1 node..."
aws eks update-nodegroup-config --cluster-name archivecloud-eks --nodegroup-name archivecloud-nodes --scaling-config minSize=1,maxSize=2,desiredSize=1 && echo "  [OK]  Scaled back to 1" || echo "  [!!]  Scale failed"

# 8. Log to CloudWatch
echo ""
echo "  === CLOUDWATCH ==="
aws cloudwatch put-metric-data --namespace "ArchiveCloud/IOC" --metric-name "EKSNodesActive" --value 1 --unit Count --dimensions Name=Cluster,Value=archivecloud-eks && echo "  [OK]  EKS metric recorded in CloudWatch"

# 9. Log to SSM
echo ""
echo "  === SSM AUDIT ==="
TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
aws ssm put-parameter --name "/archivecloud/eks/demo_${TIMESTAMP}" --value "cluster=archivecloud-eks|nodes=1|job=s3-archive|time=${TIMESTAMP}" --type "String" --overwrite --output text > /dev/null && echo "  [OK]  SSM audit: /archivecloud/eks/demo_${TIMESTAMP}"

# Summary
echo ""
echo "  ================================"
echo "  [OK]  EKS demo complete"
echo ""
echo "  What just happened:"
echo "    1. Verified cluster + node group status"
echo "    2. Listed installed add-ons"
echo "    3. Submitted a K8s Job that uploads a file to S3"
echo "    4. Scaled nodes from 1 -> 2 -> 1"
echo "    5. Recorded EKS metric in CloudWatch"
echo "    6. Wrote audit entry to SSM"
echo "  ================================"
echo ""