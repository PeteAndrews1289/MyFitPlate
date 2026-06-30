#!/usr/bin/env bash
#
# On-demand Firestore export (backup) for MyFitPlate.
#
#   scripts/firestore-backup.sh [gs://BUCKET]
#
# Exports the (default) Firestore database to a timestamped path under the bucket.
# Run this BEFORE any production migration. For automated daily backups, prefer
# native scheduled backups — see docs/data-safety.md.
set -euo pipefail

PROJECT="${FIREBASE_PROJECT:-caloriebeta-d28de}"
BUCKET="${1:-${FIRESTORE_BACKUP_BUCKET:-gs://${PROJECT}-firestore-backups}}"
STAMP="$(date -u +%Y-%m-%dT%H-%M-%SZ)"
DEST="${BUCKET%/}/manual/${STAMP}"

if ! command -v gcloud >/dev/null 2>&1; then
  echo "error: gcloud is not installed — https://cloud.google.com/sdk" >&2
  exit 1
fi

echo "Project : ${PROJECT}"
echo "Export  : ${DEST}"
echo
echo "If the bucket does not exist yet, create it in Firestore's region first, e.g.:"
echo "  gsutil mb -p ${PROJECT} -l nam5 ${BUCKET}"
echo

gcloud firestore export "${DEST}" \
  --project="${PROJECT}" \
  --database='(default)'

echo
echo "Backup complete. To restore this snapshot:"
echo "  gcloud firestore import ${DEST} --project=${PROJECT} --database='(default)'"
