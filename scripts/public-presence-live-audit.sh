#!/bin/zsh
set -euo pipefail

repository="codepilotios/codepilot"
expected_description="Public beta Mac and iPhone companion for Codex CLI workflows."
expected_homepage="https://codepilotios.github.io/codepilot/"
gh_command="${CODEPILOT_LIVE_AUDIT_GH:-gh}"
curl_command="${CODEPILOT_LIVE_AUDIT_CURL:-curl}"
failures=0

fail() {
  printf 'public presence live audit: %s\n' "$1" >&2
  failures=$((failures + 1))
  return 0
}

if ! command -v "$gh_command" >/dev/null 2>&1; then
  fail "GitHub CLI is required"
else
  description="$("$gh_command" repo view "$repository" --json description --jq '.description // ""' 2>/dev/null || true)"
  homepage="$("$gh_command" repo view "$repository" --json homepageUrl --jq '.homepageUrl // ""' 2>/dev/null || true)"
  if [[ -z "$description" ]]; then
    fail "could not read repository description and website field"
  else
    [[ "$description" == "$expected_description" ]] || \
      fail "repository description is not the approved public-beta copy"
    [[ "$homepage" == "$expected_homepage" ]] || \
      fail "repository website field is not the verified Pages URL"
  fi

  pages=(${(f)"$("$gh_command" api "repos/$repository/pages" --jq '.status, .html_url, .source.branch, .source.path' 2>/dev/null || true)"})
  if [[ ${#pages[@]} -ne 4 ]]; then
    fail "GitHub Pages is not enabled or its settings are unavailable"
  else
    [[ "${pages[1]}" == "built" ]] || fail "GitHub Pages status is ${pages[1]}"
    [[ "${pages[2]}" == "$expected_homepage" ]] || fail "GitHub Pages URL is not the approved URL"
    [[ "${pages[3]}" == "main" && "${pages[4]}" == "/docs" ]] || \
      fail "GitHub Pages must publish from main:/docs"
  fi

  vulnerability_reporting="$("$gh_command" api "repos/$repository/private-vulnerability-reporting" --jq '.enabled' 2>/dev/null || true)"
  [[ "$vulnerability_reporting" == "true" ]] || fail "private vulnerability reporting is not enabled"
fi

for page in "" "PRIVACY.html" "SUPPORT.html"; do
  url="${expected_homepage}${page}"
  if ! "$curl_command" --fail --location --silent --show-error --max-time 20 --output /dev/null "$url"; then
    fail "$url is not reachable"
  fi
done

if (( failures > 0 )); then
  printf 'public presence live audit failed with %d finding(s)\n' "$failures" >&2
  exit 1
fi

echo "public presence live audit passed"
