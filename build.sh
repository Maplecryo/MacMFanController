#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
app_path="$repo_root/MacMFanController.app"
binary_path="$app_path/Contents/MacOS/MacMFanController"
module_cache="$repo_root/.build/module-cache"

mkdir -p "$module_cache"
xattr -cr "$app_path" 2>/dev/null || true

xcrun swiftc \
  -O \
  -parse-as-library \
  -module-cache-path "$module_cache" \
  "$repo_root/MacMFanController.swift" \
  -o "$binary_path"

codesign --force --deep --sign - "$app_path"

printf 'Built and ad-hoc signed %s\n' "$app_path"
