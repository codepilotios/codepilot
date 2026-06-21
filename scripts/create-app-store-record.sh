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

missing=()
for key in FASTLANE_APPLE_ID APPLE_DEVELOPER_TEAM_ID APP_STORE_CONNECT_API_KEY_ID APP_STORE_CONNECT_ISSUER_ID APP_STORE_CONNECT_API_KEY_PATH; do
  [[ -n "${(P)key:-}" ]] || missing+=("$key")
done

if (( ${#missing[@]} > 0 )); then
  echo "Missing required Fastlane env keys in $ENV_FILE:" >&2
  printf ' - %s\n' "${missing[@]}" >&2
  exit 1
fi

if [[ -z "${FASTLANE_SESSION:-}" ]]; then
  echo "FASTLANE_SESSION is missing from $ENV_FILE." >&2
  echo "Run scripts/apple-spaceauth.sh first, then paste the generated session into $ENV_FILE." >&2
  exit 1
fi

cd "$IOS_DIR"

FASTLANE_SKIP_UPDATE_CHECK=1 /opt/homebrew/bin/fastlane ios create_app_record
