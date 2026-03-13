#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <feature-name> <target-org>" >&2
  exit 1
fi

feature="$1"
target_org="$2"
manifest="manifest/features/${feature}.xml"

if [[ ! -f "${manifest}" ]]; then
  echo "Manifest not found: ${manifest}" >&2
  exit 1
fi

sf project deploy start \
  --manifest "${manifest}" \
  --target-org "${target_org}" \
  --wait 30
