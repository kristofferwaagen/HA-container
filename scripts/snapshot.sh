#!/usr/bin/env bash
set -euo pipefail

# Simple snapshot script: creates a tarball with config + image metadata for reproducibility.
# Usage: ./scripts/snapshot.sh [label]
# Produces: snapshots/ha-snapshot-<date>-<label>.tar.gz

LABEL=${1:-baseline}
DATE=$(date +%Y%m%d-%H%M%S)
OUT_DIR="snapshots"
ARCHIVE="ha-snapshot-${DATE}-${LABEL}.tar.gz"

mkdir -p "$OUT_DIR"

if [[ ! -f .env ]]; then
  echo "ERROR: Copy .env.example to .env first and start the stack so the image is pulled." >&2
  exit 1
fi

source .env

IMAGE="homeassistant/home-assistant:${HA_VERSION}"
# If digest pinned via HA_IMAGE_DIGEST use that for metadata.
META_FILE="${OUT_DIR}/image-metadata-${DATE}-${LABEL}.txt"

echo "Collecting image metadata for $IMAGE ..."
docker image inspect "$IMAGE" > "$META_FILE" || {
  echo "WARNING: Image inspect failed (has the container been started at least once?)." >&2
}

echo "Creating archive $OUT_DIR/$ARCHIVE ..."
# Exclude transient files
 tar --exclude='*.db-wal' \
     --exclude='*.db-shm' \
     --exclude='home-assistant_v2.db' \
     -czf "${OUT_DIR}/${ARCHIVE}" \
     config \
     .env.example \
     docker-compose.yml \
     "$META_FILE"

echo "Snapshot created: ${OUT_DIR}/${ARCHIVE}"
ls -lh "${OUT_DIR}/${ARCHIVE}" "$META_FILE"
