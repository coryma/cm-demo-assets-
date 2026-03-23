#!/usr/bin/env bash
set -euo pipefail

plan_file="${1:-docs/install-plan.json}"

if ! command -v jq >/dev/null 2>&1; then
  echo "Missing required command: jq" >&2
  exit 1
fi

if [[ ! -f "${plan_file}" ]]; then
  echo "Plan file not found: ${plan_file}" >&2
  exit 1
fi

jq -e '.installOrder and .modules and (.modules | type == "array") and (.installOrder | type == "array")' "${plan_file}" >/dev/null

install_order=()
while IFS= read -r line; do
  install_order+=("${line}")
done < <(jq -r '.installOrder[]' "${plan_file}")

contains_item() {
  local needle="$1"
  shift
  local item
  for item in "$@"; do
    [[ "${item}" == "${needle}" ]] && return 0
  done
  return 1
}

declare -a order_seen=()
declare -a module_seen=()
errors=0

for module_id in "${install_order[@]}"; do
  if contains_item "${module_id}" "${order_seen[@]-}"; then
    echo "ERROR: Duplicate installOrder id: ${module_id}" >&2
    errors=$((errors + 1))
    continue
  fi
  order_seen+=("${module_id}")

  if ! jq -e --arg id "${module_id}" '.modules[] | select(.id == $id)' "${plan_file}" >/dev/null; then
    echo "ERROR: installOrder id has no module definition: ${module_id}" >&2
    errors=$((errors + 1))
    continue
  fi

  manifest_path="$(jq -r --arg id "${module_id}" '.modules[] | select(.id == $id) | .manifest' "${plan_file}")"
  if [[ ! -f "${manifest_path}" ]]; then
    echo "ERROR: Manifest file does not exist for ${module_id}: ${manifest_path}" >&2
    errors=$((errors + 1))
  fi
done

module_ids=()
while IFS= read -r line; do
  module_ids+=("${line}")
done < <(jq -r '.modules[].id' "${plan_file}")
for module_id in "${module_ids[@]}"; do
  if contains_item "${module_id}" "${module_seen[@]-}"; then
    echo "ERROR: Duplicate module id in modules list: ${module_id}" >&2
    errors=$((errors + 1))
  fi
  module_seen+=("${module_id}")

  if ! contains_item "${module_id}" "${order_seen[@]-}"; then
    echo "ERROR: Module id is not included in installOrder: ${module_id}" >&2
    errors=$((errors + 1))
  fi
done

declare -a installed_before=()
for module_id in "${install_order[@]}"; do
  declare -a deps=()
  while IFS= read -r dep; do
    deps+=("${dep}")
  done < <(jq -r --arg id "${module_id}" '.modules[] | select(.id == $id) | .dependsOn[]?' "${plan_file}")
  if [[ "${#deps[@]}" -gt 0 ]]; then
    for dep in "${deps[@]}"; do
      if ! contains_item "${dep}" "${module_seen[@]-}"; then
        echo "ERROR: ${module_id} has unknown dependency: ${dep}" >&2
        errors=$((errors + 1))
        continue
      fi
      if ! contains_item "${dep}" "${installed_before[@]-}"; then
        echo "ERROR: ${module_id} dependency appears after it in installOrder: ${dep}" >&2
        errors=$((errors + 1))
      fi
    done
  fi
  installed_before+=("${module_id}")
done

if [[ "${errors}" -gt 0 ]]; then
  echo "Install plan validation failed with ${errors} error(s)." >&2
  exit 1
fi

echo "Install plan validation passed: ${plan_file}"
