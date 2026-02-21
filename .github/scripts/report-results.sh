#!/usr/bin/env bash
# report-results.sh — Formats Semgrep results and posts as a PR comment
#
# Inputs (env vars):
#   SEMGREP_OUTPUT — Path to semgrep JSON output file
#   REGISTRY_ERRORS — Registry validation error text (may be empty)
#   PR_NUMBER — Pull request number
#   GITHUB_TOKEN — GitHub token for API calls
#   GITHUB_REPOSITORY — owner/repo

set -euo pipefail

SEMGREP_OUTPUT="${SEMGREP_OUTPUT:-semgrep-results.json}"
REGISTRY_ERRORS="${REGISTRY_ERRORS:-}"
PR_NUMBER="${PR_NUMBER:-}"

# ─── Parse Semgrep results ───
critical_count=0
warning_count=0
critical_findings=""
warning_findings=""

if [ -f "$SEMGREP_OUTPUT" ]; then
  total=$(jq '.results | length' "$SEMGREP_OUTPUT")

  for i in $(seq 0 $((total - 1))); do
    result=$(jq ".results[$i]" "$SEMGREP_OUTPUT")
    rule_id=$(echo "$result" | jq -r '.check_id')
    severity=$(echo "$result" | jq -r '.extra.severity')
    message=$(echo "$result" | jq -r '.extra.message' | tr '\n' ' ' | sed 's/  */ /g')
    file=$(echo "$result" | jq -r '.path')
    line_start=$(echo "$result" | jq -r '.start.line')
    line_end=$(echo "$result" | jq -r '.end.line')
    code_snippet=$(echo "$result" | jq -r '.extra.lines // ""' | head -5)

    finding="| \`${rule_id}\` | \`${file}:${line_start}\` | ${message} |"

    if [ "$severity" = "ERROR" ]; then
      critical_count=$((critical_count + 1))
      critical_findings="${critical_findings}\n${finding}"
    else
      warning_count=$((warning_count + 1))
      warning_findings="${warning_findings}\n${finding}"
    fi
  done
fi

# ─── Build comment body ───
body="## 🔍 Plugin Security Scan Results\n\n"

# Registry validation
if [ -n "$REGISTRY_ERRORS" ]; then
  body="${body}### ❌ Registry Validation Failed\n\n"
  body="${body}\`\`\`\n${REGISTRY_ERRORS}\`\`\`\n\n"
else
  body="${body}### ✅ Registry Validation Passed\n\n"
fi

# Overall status
has_critical=false
if [ "$critical_count" -gt 0 ] || [ -n "$REGISTRY_ERRORS" ]; then
  has_critical=true
  body="${body}### ⛔ Scan Status: FAILED\n\n"
else
  if [ "$warning_count" -gt 0 ]; then
    body="${body}### ⚠️ Scan Status: WARNINGS\n\n"
  else
    body="${body}### ✅ Scan Status: PASSED\n\n"
  fi
fi

# Summary counts
body="${body}| Category | Count |\n|----------|-------|\n"
body="${body}| 🔴 Critical findings | ${critical_count} |\n"
body="${body}| 🟡 Warnings | ${warning_count} |\n\n"

# Critical findings detail
if [ "$critical_count" -gt 0 ]; then
  body="${body}### 🔴 Critical Findings (auto-block)\n\n"
  body="${body}These findings **block merging** and must be resolved:\n\n"
  body="${body}| Rule | Location | Description |\n|------|----------|-------------|\n"
  body="${body}$(echo -e "$critical_findings")\n\n"
fi

# Warning findings detail
if [ "$warning_count" -gt 0 ]; then
  body="${body}### 🟡 Warnings (reviewer discretion)\n\n"
  body="${body}These findings require **maintainer review** but don't auto-block:\n\n"
  body="${body}| Rule | Location | Description |\n|------|----------|-------------|\n"
  body="${body}$(echo -e "$warning_findings")\n\n"
fi

# No findings
if [ "$critical_count" -eq 0 ] && [ "$warning_count" -eq 0 ] && [ -z "$REGISTRY_ERRORS" ]; then
  body="${body}No security issues detected. Plugin code looks clean! 🎉\n\n"
fi

# Footer
body="${body}---\n"
body="${body}*Scanned with [Semgrep](https://semgrep.dev) using Agent Zero custom rules.*\n"
body="${body}*Rules: \`.github/semgrep-rules/agent-zero-plugins.yml\`*"

# ─── Post or update PR comment ───
if [ -n "$PR_NUMBER" ] && [ -n "${GITHUB_TOKEN:-}" ]; then
  # Check for existing bot comment to update
  existing_comment_id=$(curl -s \
    -H "Authorization: token $GITHUB_TOKEN" \
    -H "Accept: application/vnd.github.v3+json" \
    "https://api.github.com/repos/${GITHUB_REPOSITORY}/issues/${PR_NUMBER}/comments" \
    | jq -r '.[] | select(.body | startswith("## 🔍 Plugin Security Scan")) | .id' \
    | head -1)

  comment_body=$(echo -e "$body" | jq -Rs '.')

  if [ -n "$existing_comment_id" ] && [ "$existing_comment_id" != "null" ]; then
    # Update existing comment
    curl -s -X PATCH \
      -H "Authorization: token $GITHUB_TOKEN" \
      -H "Accept: application/vnd.github.v3+json" \
      "https://api.github.com/repos/${GITHUB_REPOSITORY}/issues/comments/${existing_comment_id}" \
      -d "{\"body\": ${comment_body}}" > /dev/null
    echo "Updated existing comment #${existing_comment_id}"
  else
    # Create new comment
    curl -s -X POST \
      -H "Authorization: token $GITHUB_TOKEN" \
      -H "Accept: application/vnd.github.v3+json" \
      "https://api.github.com/repos/${GITHUB_REPOSITORY}/issues/${PR_NUMBER}/comments" \
      -d "{\"body\": ${comment_body}}" > /dev/null
    echo "Created new PR comment"
  fi
else
  # No PR context — just print
  echo -e "$body"
fi

# ─── Set exit code ───
if [ "$has_critical" = true ]; then
  echo "::error::Security scan found critical issues"
  exit 1
fi

echo "✅ Security scan complete"
