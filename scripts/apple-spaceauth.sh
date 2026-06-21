#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IOS_DIR="$ROOT/ios/CodexPhone"
ENV_FILE="$IOS_DIR/fastlane/.env"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing $ENV_FILE" >&2
  exit 1
fi

set -a
source "$ENV_FILE"
set +a

if [[ -z "${FASTLANE_APPLE_ID:-}" ]]; then
  echo "FASTLANE_APPLE_ID is missing from $ENV_FILE" >&2
  exit 1
fi

cd "$IOS_DIR"

echo "Starting Fastlane Apple session generation for $FASTLANE_APPLE_ID"
echo "When Fastlane prints the FASTLANE_SESSION value, add it to:"
echo "$ENV_FILE"
echo
echo "FASTLANE_SESSION='paste-session-here'"
echo

FASTLANE_SKIP_UPDATE_CHECK=1 /opt/homebrew/bin/fastlane spaceauth -u "$FASTLANE_APPLE_ID"
