#!/usr/bin/env bash
# validate-registry.sh — Validates registry.json changes in a PR
# Extracts new/changed plugin entries and checks required fields, URL format, duplicates
#
# Outputs:
#   CHANGED_PLUGINS — newline-separated JSON objects of new/changed plugins
#   VALIDATION_ERRORS — newline-separated error messages (empty = pass)
#   PLUGIN_REPOS — newline-separated "repo_url branch plugin_path" tuples for cloning

set -euo pipefail

# Get the diff of registry.json against the base branch
BASE_BRANCH="${GITHUB_BASE_REF:-main}"
REGISTRY="registry.json"

# Validate JSON syntax
if ! jq empty "$REGISTRY" 2>/dev/null; then
  echo "::error::registry.json is not valid JSON"
  echo "VALIDATION_ERRORS=registry.json is not valid JSON" >> "$GITHUB_OUTPUT"
  exit 1
fi

# Extract current plugins
CURRENT_PLUGINS=$(jq -r '.plugins' "$REGISTRY")
PLUGIN_COUNT=$(echo "$CURRENT_PLUGINS" | jq 'length')

errors=""
repos=""
changed_plugins=""

# Get the base version of registry.json for comparison
BASE_PLUGINS=""
if git show "origin/${BASE_BRANCH}:${REGISTRY}" &>/dev/null; then
  BASE_PLUGINS=$(git show "origin/${BASE_BRANCH}:${REGISTRY}" | jq -r '.plugins // []')
  BASE_IDS=$(echo "$BASE_PLUGINS" | jq -r '.[].id')
else
  BASE_IDS=""
fi

# Find new/changed plugins by comparing IDs
for i in $(seq 0 $((PLUGIN_COUNT - 1))); do
  plugin=$(echo "$CURRENT_PLUGINS" | jq ".[$i]")
  id=$(echo "$plugin" | jq -r '.id // empty')
  name=$(echo "$plugin" | jq -r '.name // empty')
  description=$(echo "$plugin" | jq -r '.description // empty')
  repo_url=$(echo "$plugin" | jq -r '.repo_url // empty')
  plugin_path=$(echo "$plugin" | jq -r '.plugin_path // empty')
  branch=$(echo "$plugin" | jq -r '.branch // "main"')

  # Check if this is a new or changed plugin
  is_new=false
  if [ -n "$BASE_PLUGINS" ]; then
    base_entry=$(echo "$BASE_PLUGINS" | jq -r --arg id "$id" '.[] | select(.id == $id)' 2>/dev/null || true)
    if [ -z "$base_entry" ]; then
      is_new=true
    else
      # Check if any field changed
      current_hash=$(echo "$plugin" | jq -S '.' | md5sum | cut -d' ' -f1)
      base_hash=$(echo "$base_entry" | jq -S '.' | md5sum | cut -d' ' -f1)
      if [ "$current_hash" != "$base_hash" ]; then
        is_new=true
      fi
    fi
  else
    # No base version — all plugins are "new"
    is_new=true
  fi

  # Only validate new/changed plugins
  if [ "$is_new" = false ]; then
    continue
  fi

  changed_plugins="${changed_plugins}${plugin}\n"

  # Required fields
  if [ -z "$id" ]; then
    errors="${errors}Plugin at index $i: missing 'id'\n"
  fi
  if [ -z "$name" ]; then
    errors="${errors}Plugin '$id': missing 'name'\n"
  fi
  if [ -z "$description" ]; then
    errors="${errors}Plugin '$id': missing 'description'\n"
  fi
  if [ -z "$repo_url" ]; then
    errors="${errors}Plugin '$id': missing 'repo_url'\n"
  fi
  if [ -z "$plugin_path" ]; then
    errors="${errors}Plugin '$id': missing 'plugin_path'\n"
  fi

  # URL format validation
  if [ -n "$repo_url" ]; then
    if [[ ! "$repo_url" =~ ^https://github\.com/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+ ]]; then
      errors="${errors}Plugin '$id': repo_url must be a valid GitHub URL (got: $repo_url)\n"
    fi
  fi

  # Check for duplicate IDs
  dupes=$(echo "$CURRENT_PLUGINS" | jq -r --arg id "$id" '[.[] | select(.id == $id)] | length')
  if [ "$dupes" -gt 1 ]; then
    errors="${errors}Plugin '$id': duplicate ID found in registry\n"
  fi

  # Add to clone list
  if [ -n "$repo_url" ] && [ -n "$plugin_path" ]; then
    repos="${repos}${repo_url} ${branch} ${plugin_path}\n"
  fi
done

# Write outputs
{
  echo "CHANGED_PLUGINS<<EOF"
  echo -e "$changed_plugins"
  echo "EOF"
  echo "VALIDATION_ERRORS<<EOF"
  echo -e "$errors"
  echo "EOF"
  echo "PLUGIN_REPOS<<EOF"
  echo -e "$repos"
  echo "EOF"
} >> "$GITHUB_OUTPUT"

# Set exit code
if [ -n "$errors" ]; then
  echo "::error::Registry validation failed"
  echo -e "$errors"
  exit 1
fi

echo "✅ Registry validation passed"
