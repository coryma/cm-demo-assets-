#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./scripts/install-by-plan.sh <target-org> [options]

Options:
  --plan <path>            Path to install plan JSON (default: docs/install-plan.json)
  --dry-run                Validate deployment only (no metadata persisted)
  --sync-shared-pages      Retrieve shared FlexiPages before install (recommended for non-empty orgs)
  -h, --help               Show help
EOF
}

if ! command -v sf >/dev/null 2>&1; then
  echo "Missing required command: sf" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "Missing required command: jq" >&2
  exit 1
fi

contains_item() {
  local needle="$1"
  shift
  local item
  for item in "$@"; do
    [[ "${item}" == "${needle}" ]] && return 0
  done
  return 1
}

target_org=""
plan_file="docs/install-plan.json"
dry_run=false
sync_shared_pages=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --plan)
      plan_file="${2:-}"
      shift 2
      ;;
    --dry-run)
      dry_run=true
      shift
      ;;
    --sync-shared-pages)
      sync_shared_pages=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
    *)
      if [[ -n "${target_org}" ]]; then
        echo "Unexpected argument: $1" >&2
        usage >&2
        exit 1
      fi
      target_org="$1"
      shift
      ;;
  esac
done

if [[ -z "${target_org}" ]]; then
  usage >&2
  exit 1
fi

if [[ ! -f "${plan_file}" ]]; then
  echo "Plan file not found: ${plan_file}" >&2
  exit 1
fi

./scripts/verify-install-plan.sh "${plan_file}"

sf org display --target-org "${target_org}" --json >/dev/null

if [[ "${sync_shared_pages}" == "true" ]]; then
  declare -a shared_pages=()
  while IFS= read -r page; do
    shared_pages+=("${page}")
  done < <(jq -r '.sharedPages[]?' "${plan_file}")
  if [[ "${#shared_pages[@]}" -gt 0 ]]; then
    metadata_args=()
    for page in "${shared_pages[@]}"; do
      metadata_args+=(--metadata "FlexiPage:${page}")
    done
    sf project retrieve start \
      --target-org "${target_org}" \
      "${metadata_args[@]}" \
      --wait 20
  fi
fi

declare -a install_order=()
while IFS= read -r module_id; do
  install_order+=("${module_id}")
done < <(jq -r '.installOrder[]' "${plan_file}")

declare -a installed=()
step=0
total="${#install_order[@]}"

for module_id in "${install_order[@]}"; do
  step=$((step + 1))
  name="$(jq -r --arg id "${module_id}" '.modules[] | select(.id == $id) | .name' "${plan_file}")"
  scope="$(jq -r --arg id "${module_id}" '.modules[] | select(.id == $id) | .scope' "${plan_file}")"

  declare -a deps=()
  while IFS= read -r dep; do
    deps+=("${dep}")
  done < <(jq -r --arg id "${module_id}" '.modules[] | select(.id == $id) | .dependsOn[]?' "${plan_file}")
  if [[ "${#deps[@]}" -gt 0 ]]; then
    for dep in "${deps[@]}"; do
      if ! contains_item "${dep}" "${installed[@]-}"; then
        echo "Dependency not installed before ${module_id}: ${dep}" >&2
        exit 1
      fi
    done
  fi

  echo "[${step}/${total}] Deploying ${module_id} (${name}, ${scope})"
  deploy_args=()
  if [[ "${dry_run}" == "true" ]]; then
    deploy_args+=(--dry-run)
  fi

  ./scripts/deploy-feature.sh "${module_id}" "${target_org}" "${deploy_args[@]}"
  installed+=("${module_id}")
done

if [[ "${dry_run}" == "true" ]]; then
  echo "Install plan dry-run completed successfully."
else
  echo "Install plan completed successfully."
fi
