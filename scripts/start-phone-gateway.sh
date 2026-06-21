#!/bin/zsh
set -euo pipefail

cd "$(dirname "$0")/.."
if [[ -x /usr/local/bin/python3 ]]; then
  exec /usr/local/bin/python3 gateway/codex_phone_gateway.py --host 127.0.0.1 --port 18790
fi
exec /usr/bin/python3 gateway/codex_phone_gateway.py --host 127.0.0.1 --port 18790
