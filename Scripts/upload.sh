#!/bin/bash
# ============================================================
#  ArchiveCloud — upload.sh
#  Uploads a file to S3 and logs to SSM
#  Requires: initialize.sh to be executed first
#  Usage:
#    ./upload.sh <file>
#    ./upload.sh report.pdf
# ============================================================

# Colors
G='\033[0;32m'; Y='\033[1;33m'; C='\033[0;36m'; R='\033[0;31m'; NC='\033[0m'
ok()   { echo -e "  ${G}[OK]${NC}  $1"; }
info() { echo -e "  ${C}[..]${NC}  $1"; }
warn() { echo -e "  ${Y}[!!]${NC}  $1"; }
err()  { echo -e "  ${R}[XX]${NC}  $1"; exit 1; }

echo ""
echo "  ArchiveCloud - Upload"
echo "  ====================="

# Check initialize was sourced for environment variables initialization
[[ -z "$ARCHIVECLOUD_BUCKET" ]] && err "ARCHIVECLOUD_BUCKET not set. Run: source initialize.sh"
[[ -z "$1" ]]                   && err "No file specified. Usage: ./upload.sh <file>"
[[ ! -f "$1" ]]                 && err "File not found: $1"

TARGET="$1"
FILENAME=$(basename "$TARGET")
S3_KEY="uploads/$FILENAME"
TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)

# Step 1: Upload to S3
info "Uploading $FILENAME -> s3://$ARCHIVECLOUD_BUCKET/$S3_KEY"

aws s3 cp "$TARGET" "s3://$ARCHIVECLOUD_BUCKET/$S3_KEY" --sse AES256 --no-progress && ok "Uploaded: s3://$ARCHIVECLOUD_BUCKET/$S3_KEY" || err "Upload failed"

# Step 2: Verify it landed
info "Verifying upload..."
aws s3api head-object --bucket "$ARCHIVECLOUD_BUCKET" --key "$S3_KEY" --query "{Key:ContentLength,Encryption:ServerSideEncryption,Modified:LastModified}" --output table && ok "File confirmed in S3" || warn "Could not verify - file may still have uploaded"

# Step 3: Log to SSM Parameter Store
info "Writing audit entry to SSM..."
aws ssm put-parameter --name "/archivecloud/uploads/${TIMESTAMP}_${FILENAME}" --value "file=${FILENAME}|key=${S3_KEY}|bucket=${ARCHIVECLOUD_BUCKET}|time=${TIMESTAMP}" --type "String" --overwrite --output text > /dev/null && ok "SSM audit: /archivecloud/uploads/${TIMESTAMP}_${FILENAME}" || warn "SSM write skipped (non-critical)"

echo ""
ok "Done. s3://$ARCHIVECLOUD_BUCKET/$S3_KEY is live."
echo ""