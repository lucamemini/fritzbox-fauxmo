#!/usr/bin/env bash
set -euo pipefail

: "${FRITZ_USER:?FRITZ_USER environment variable is required}"
: "${FRITZ_PASS:?FRITZ_PASS environment variable is required}"

docker build -t fritz-fauxmo .

docker rm -f fritz-fauxmo 2>/dev/null || true

docker run -d \
  --name fritz-fauxmo \
  --network host \
  --restart unless-stopped \
  -e FRITZ_USER \
  -e FRITZ_PASS \
  fritz-fauxmo