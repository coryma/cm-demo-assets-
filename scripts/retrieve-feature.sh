#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <feature-name> <target-org> [extra sf retrieve flags...]" >&2
  exit 1
fi

feature="$1"
target_org="$2"
extra_flags=("${@:3}")
manifest="manifest/features/${feature}.xml"

if [[ ! -f "${manifest}" ]]; then
  echo "Manifest not found: ${manifest}" >&2
  exit 1
fi

sf project retrieve start \
  --manifest "${manifest}" \
  --target-org "${target_org}" \
  --wait 20 \
  "${extra_flags[@]}"
