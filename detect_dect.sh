#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Configuration
# ============================================================

FRITZ_HOST="${FRITZ_HOST:-http://fritz.box}"
FRITZ_USER="${FRITZ_USER:?FRITZ_USER environment variable is required}"
FRITZ_PASS="${FRITZ_PASS:?FRITZ_PASS environment variable is required}"

OUTPUT_FILE="${OUTPUT_FILE:-config.json}"
BASE_PORT="${BASE_PORT:-12340}"

# ============================================================
# 1. Get challenge
# ============================================================

CHALLENGE=$(curl -fsS "${FRITZ_HOST}/login_sid.lua" \
  | sed -n 's/.*<Challenge>\(.*\)<\/Challenge>.*/\1/p')

if [ -z "$CHALLENGE" ]; then
  echo "Error: unable to get challenge from FRITZ!Box" >&2
  exit 1
fi

# ============================================================
# 2. Calculate response
#    md5(challenge-password) using UTF-16LE
# ============================================================

RESPONSE_HASH=$(
  printf '%s-%s' "$CHALLENGE" "$FRITZ_PASS" \
    | iconv -f UTF-8 -t UTF-16LE \
    | md5sum \
    | awk '{print $1}'
)

RESPONSE="${CHALLENGE}-${RESPONSE_HASH}"

# ============================================================
# 3. Login and get SID
# ============================================================

SID=$(curl -fsS -G "${FRITZ_HOST}/login_sid.lua" \
  --data-urlencode "username=${FRITZ_USER}" \
  --data-urlencode "response=${RESPONSE}" \
  | sed -n 's/.*<SID>\(.*\)<\/SID>.*/\1/p')

if [ -z "$SID" ] || [ "$SID" = "0000000000000000" ]; then
  echo "Error: login failed. Check FRITZ_USER and FRITZ_PASS." >&2
  exit 1
fi

echo "FRITZ!Box login successful"
echo ""

# ============================================================
# 4. Get complete Smart Home device list
# ============================================================

XML=$(curl -fsS -G "${FRITZ_HOST}/webservices/homeautoswitch.lua" \
  --data-urlencode "switchcmd=getdevicelistinfos" \
  --data-urlencode "sid=${SID}")

if [ -z "$XML" ]; then
  echo "Error: empty response from FRITZ!Box" >&2
  exit 1
fi

# ============================================================
# Pass data to Python
# ============================================================

export XML_DATA="$XML"
export FRITZ_HOST_ENV="$FRITZ_HOST"
export BASE_PORT_ENV="$BASE_PORT"
export OUTPUT_FILE_ENV="$OUTPUT_FILE"

echo "=== Devices found ==="

python3 <<'PYEOF'
import os
import re
import json
import sys

xml = os.environ.get("XML_DATA", "")
fritz_host = os.environ.get("FRITZ_HOST_ENV", "")
base_port = int(os.environ.get("BASE_PORT_ENV", "12340"))
output_file = os.environ.get("OUTPUT_FILE_ENV", "config.json")

if not xml.strip():
    print("Error: XML_DATA is empty.", file=sys.stderr)
    sys.exit(1)

device_blocks = re.findall(r'<device\b.*?</device>', xml, re.S)
group_blocks = re.findall(r'<group\b.*?</group>', xml, re.S)

results = []

# ------------------------------------------------------------
# Physical devices
# ------------------------------------------------------------

for block in device_blocks:
    ain_match = re.search(r'identifier="([^"]+)"', block)
    model_match = re.search(r'productname="([^"]+)"', block)
    name_match = re.search(r'<name>([^<]+)</name>', block)

    ain = ain_match.group(1) if ain_match else "?"
    model = model_match.group(1) if model_match else "?"
    name = name_match.group(1) if name_match else "?"

    results.append((ain, model, name))

# ------------------------------------------------------------
# Groups
# ------------------------------------------------------------

for block in group_blocks:
    ain_match = re.search(r'identifier="([^"]+)"', block)
    name_match = re.search(r'<name>([^<]+)</name>', block)

    ain = ain_match.group(1) if ain_match else "?"
    name = name_match.group(1) if name_match else "?"

    results.append((ain, "Group", name))

if not results:
    print(
        "No devices or groups found. "
        "First 500 characters of the response:",
        file=sys.stderr,
    )
    print(xml[:500], file=sys.stderr)
    sys.exit(1)

# ------------------------------------------------------------
# Display discovered devices
# ------------------------------------------------------------

print(f"{'AIN':<20} {'Name':<20} {'Model'}")
print("-" * 60)

for ain, model, name in results:
    print(f"{ain:<20} {name:<20} {model}")

# ------------------------------------------------------------
# Generate Fauxmo configuration
#
# IMPORTANT:
# No FRITZ!Box username/password are stored here.
# The plugin reads them from environment variables.
# ------------------------------------------------------------

devices = []

port = base_port

for ain, model, name in results:
    devices.append({
        "name": name,
        "port": port,
        "fritz_host": fritz_host,
        "ain": ain
    })

    port += 1

config = {
    "FAUXMO": {
        "ip_address": "auto"
    },
    "PLUGINS": {
        "FritzDectPlugin": {
            "path": "/app/fritz_plugin.py",
            "DEVICES": devices
        }
    }
}

with open(output_file, "w", encoding="utf-8") as f:
    json.dump(config, f, indent=2, ensure_ascii=False)

print("")
print(f"Wrote {output_file} with {len(devices)} devices.")
print("")
print("Credentials are NOT stored in config.json.")
PYEOF