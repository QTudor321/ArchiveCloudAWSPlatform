#!/bin/bash
# ============================================================
#  ArchiveCloud — archive.sh
#  Moves S3 uploads to Glacier cold storage
#  Requires: initialize.sh to be sourced first
#  Usage:
#    ./archive.sh              # archive everything in uploads/
#    ./archive.sh <s3-key>     # archive one specific file
# ============================================================

G='\033[0;32m'; Y='\033[1;33m'; C='\033[0;36m'; R='\033[0;31m'; NC='\033[0m'
ok()   { echo -e "  ${G}[OK]${NC}  $1"; }
info() { echo -e "  ${C}[..]${NC}  $1"; }
warn() { echo -e "  ${Y}[!!]${NC}  $1"; }
err()  { echo -e "  ${R}[XX]${NC}  $1"; exit 1; }

echo ""
echo "  ArchiveCloud - Archive to Glacier"
echo "  ==================================="

# ── Check initialize was sourced ─────────────
[[ -z "$ARCHIVECLOUD_BUCKET" ]] && err "ARCHIVECLOUD_BUCKET not set. Run: source initialize.sh"

TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)

# Mode: single file or full batch
if [[ -n "${1:-}" ]]; then
  # Single file mode
  KEYS="$1"
  info "Single file mode: $1"
else
  # Batch mode - find everything in uploads/ that is STANDARD
  info "Scanning s3://$ARCHIVECLOUD_BUCKET/uploads/ for STANDARD objects..."
  KEYS=$(aws s3api list-objects-v2 --bucket "$ARCHIVECLOUD_BUCKET" --prefix "uploads/" --query "Contents[?StorageClass=='STANDARD'].Key" --output text 2>/dev/null || echo "")
  if [[ -z "$KEYS" || "$KEYS" == "None" ]]; then
    warn "No STANDARD objects found in uploads/"
    info "Upload something first: ./upload.sh <file>"
    exit 0
  fi
fi

# Archive each file
COUNT=0
for KEY in $KEYS; do
  [[ -z "$KEY" ]] && continue
  info "Archiving: $KEY"
  aws s3 cp "s3://$ARCHIVECLOUD_BUCKET/$KEY" "s3://$ARCHIVECLOUD_BUCKET/$KEY" --storage-class GLACIER --metadata-directive COPY --no-progress && ok "Archived -> GLACIER: $KEY" || warn "Failed to archive: $KEY" COUNT=$((COUNT + 1))
done

# Verify storage class changed
info "Verifying Glacier storage class..."
aws s3api list-objects-v2 --bucket "$ARCHIVECLOUD_BUCKET" --prefix "uploads/" --query "Contents[*].{Key:Key,Class:StorageClass}" --output table

# Log to SSM 
aws ssm put-parameter --name "/archivecloud/archive/${TIMESTAMP}" --value "archived=${COUNT}|bucket=${ARCHIVECLOUD_BUCKET}|time=${TIMESTAMP}" --type "String" --overwrite --output text > /dev/null && ok "SSM audit: /archivecloud/archive/${TIMESTAMP}" || warn "SSM write skipped (non-critical)"

echo ""
ok "$COUNT file(s) moved to Glacier."
echo ""