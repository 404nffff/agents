#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
skill_name="grok-search"
dest_root="${HOME}/.codex/skills"
dest="${dest_root}/${skill_name}"

mkdir -p "${dest_root}"

tmp_preserve="$(mktemp -d)"
cleanup() {
  rm -rf "${tmp_preserve}"
}
trap cleanup EXIT

for name in config.json config.local.json; do
  if [[ -f "${dest}/${name}" ]]; then
    cp "${dest}/${name}" "${tmp_preserve}/${name}"
  fi
done

if [[ -d "${dest}" ]]; then
  rm -rf "${dest}"
fi

mkdir -p "${dest}"

cp "${repo_root}/SKILL.md" "${dest}/"
cp "${repo_root}/README.md" "${dest}/"
cp "${repo_root}/install.ps1" "${dest}/"
cp "${repo_root}/install.sh" "${dest}/"
cp "${repo_root}/configure.ps1" "${dest}/"
cp "${repo_root}/config.json" "${dest}/"
cp -R "${repo_root}/scripts" "${dest}/"

for name in config.json config.local.json; do
  if [[ -f "${tmp_preserve}/${name}" ]]; then
    cp "${tmp_preserve}/${name}" "${dest}/${name}"
  fi
done

echo "Installed to: ${dest}"
