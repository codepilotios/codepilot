# Cloudflare Setup Wizard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a guided Mac app Cloudflare setup flow that installs/configures `cloudflared`, supports permanent hostnames and TryCloudflare, verifies the public gateway URL, and explains each step clearly.

**Architecture:** Put the automation in a focused shell script with idempotent subcommands, then call that script from a new Mac setup wizard. Keep parsing, status, and error-copy logic testable in Swift and shell tests with temporary HOME and stubbed executables. Preserve existing LaunchAgent behavior while migrating paths to CodePilot naming.

**Tech Stack:** Swift/AppKit/SwiftPM XCTest for the Mac app, zsh/Python stdlib for setup scripts and script tests, Cloudflare `cloudflared`, macOS LaunchAgents.

---

## File Structure

- Create `scripts/setup-cloudflare-remote-access.sh`: subcommand-driven Cloudflare setup automation. It owns detection, config generation, metadata writes, LaunchAgent installation, TryCloudflare start, and URL verification.
- Create `Tests/CodexAccountSwitcherTests/CloudflareSetupTests.swift`: Swift unit tests for setup status labels, metadata redaction, command/error copy, and script output parsing.
- Create `Tests/CodexAccountSwitcherTests/ScriptFixture.swift`: small XCTest helpers for temp directories and executable stubs if not already covered locally.
- Modify `Sources/CodexAccountSwitcher/main.swift`: add Cloudflare setup models and an AppKit wizard window/sheet, wire buttons to the setup script, improve setup status rows.
- Modify `scripts/install-phone-cloudflared-agent.sh`: delegate to the new setup script or keep as a compatibility wrapper.
- Modify `scripts/start-phone-cloudflared.sh`: use the new CodePilot config path with fallback to the old path.
- Create `scripts/test-cloudflare-setup.sh`: local shell test runner with stubbed `cloudflared`, `brew`, `launchctl`, and `curl`.
- Modify `docs/CLOUDFLARE_SETUP.md`, `docs/INSTALL_MAC.md`, `docs/TROUBLESHOOTING.md`: document the in-app path first and manual fallback second.

---

### Task 1: Add Script Test Harness And Failing Script Tests

**Files:**
- Create: `scripts/test-cloudflare-setup.sh`
- Test target: `scripts/setup-cloudflare-remote-access.sh`

- [ ] **Step 1: Create failing script tests**

Create `scripts/test-cloudflare-setup.sh`:

```zsh
#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/scripts/setup-cloudflare-remote-access.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export HOME="$TMP/home"
export PATH="$TMP/bin:/usr/bin:/bin:/usr/sbin:/sbin"
mkdir -p "$HOME" "$TMP/bin"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

write_stub() {
  local name="$1"
  local body="$2"
  cat > "$TMP/bin/$name" <<EOF
#!/bin/zsh
set -euo pipefail
$body
EOF
  chmod +x "$TMP/bin/$name"
}

write_stub cloudflared '
case "$*" in
  "--version") echo "cloudflared version 2026.6.1";;
  "tunnel list --output json") echo "[]";;
  "tunnel create codepilot") echo "{\"id\":\"tun_123\",\"name\":\"codepilot\"}";;
  "tunnel route dns codepilot codepilot.example.com") echo "Added CNAME codepilot.example.com";;
  "tunnel --url http://127.0.0.1:18790") echo "https://temporary.trycloudflare.com"; sleep 1;;
  *) echo "cloudflared $*";;
esac
'
write_stub brew 'echo "brew $*"'
write_stub launchctl 'echo "launchctl $*"'
write_stub curl 'echo "{\"ok\":true}"'

"$SCRIPT" status >/tmp/codepilot-status.json 2>/tmp/codepilot-status.err || true
grep -q "No such file" /tmp/codepilot-status.err && fail "status should not crash when config is missing"

"$SCRIPT" configure-permanent --hostname codepilot.example.com --tunnel-name codepilot
[ -f "$HOME/.cloudflared/codepilot-config.yaml" ] || fail "config file missing"
grep -q "hostname: codepilot.example.com" "$HOME/.cloudflared/codepilot-config.yaml" || fail "hostname missing from config"
grep -q "service: http://127.0.0.1:18790" "$HOME/.cloudflared/codepilot-config.yaml" || fail "gateway service missing from config"
[ -f "$HOME/.codex-account-switcher/cloudflare-setup.json" ] || fail "metadata missing"
! grep -qi "token" "$HOME/.codex-account-switcher/cloudflare-setup.json" || fail "metadata must not contain token"

"$SCRIPT" install-service
[ -f "$HOME/Library/LaunchAgents/io.codepilot.phone-cloudflared.plist" ] || fail "LaunchAgent plist missing"

"$SCRIPT" verify --url https://codepilot.example.com >/tmp/codepilot-verify.out
grep -q "verified" /tmp/codepilot-verify.out || fail "verify output should say verified"

echo "PASS: cloudflare setup script tests"
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
zsh scripts/test-cloudflare-setup.sh
```

Expected: FAIL because `scripts/setup-cloudflare-remote-access.sh` does not exist.

- [ ] **Step 3: Commit failing tests**

```bash
git add scripts/test-cloudflare-setup.sh
git commit -m "test: cover Cloudflare setup script behavior"
```

---

### Task 2: Implement Cloudflare Setup Script Core

**Files:**
- Create: `scripts/setup-cloudflare-remote-access.sh`
- Modify: `scripts/start-phone-cloudflared.sh`
- Modify: `scripts/install-phone-cloudflared-agent.sh`
- Test: `scripts/test-cloudflare-setup.sh`

- [ ] **Step 1: Implement the setup script**

Create `scripts/setup-cloudflare-remote-access.sh`:

```zsh
#!/bin/zsh
set -euo pipefail

APP_DIR="$HOME/.codex-account-switcher"
CLOUDFLARED_DIR="$HOME/.cloudflared"
CONFIG_PATH="$CLOUDFLARED_DIR/codepilot-config.yaml"
LEGACY_CONFIG_PATH="$CLOUDFLARED_DIR/codex-phone-config.yaml"
METADATA_PATH="$APP_DIR/cloudflare-setup.json"
LABEL="${CODEPILOT_CLOUDFLARED_LAUNCHD_LABEL:-io.codepilot.phone-cloudflared}"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
GATEWAY_URL="${CODEPILOT_GATEWAY_URL:-http://127.0.0.1:18790}"

mkdir -p "$APP_DIR" "$CLOUDFLARED_DIR"

json_escape() {
  /usr/bin/python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$1"
}

write_metadata() {
  local mode="$1"
  local hostname="$2"
  local tunnel_name="$3"
  local tunnel_id="$4"
  /usr/bin/python3 - "$METADATA_PATH" "$mode" "$hostname" "$tunnel_name" "$tunnel_id" "$CONFIG_PATH" "$LABEL" <<'PY'
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

path = Path(sys.argv[1])
payload = {
    "mode": sys.argv[2],
    "hostname": sys.argv[3],
    "tunnelName": sys.argv[4],
    "tunnelId": sys.argv[5],
    "configPath": sys.argv[6],
    "launchAgentLabel": sys.argv[7],
    "lastVerifiedAt": None,
    "updatedAt": datetime.now(timezone.utc).isoformat(),
}
path.parent.mkdir(parents=True, exist_ok=True)
path.write_text(json.dumps(payload, indent=2) + "\n")
PY
}

cloudflared_bin() {
  if command -v cloudflared >/dev/null 2>&1; then command -v cloudflared; return 0; fi
  if [ -x /opt/homebrew/bin/cloudflared ]; then echo /opt/homebrew/bin/cloudflared; return 0; fi
  if [ -x /usr/local/bin/cloudflared ]; then echo /usr/local/bin/cloudflared; return 0; fi
  return 1
}

brew_bin() {
  if command -v brew >/dev/null 2>&1; then command -v brew; return 0; fi
  if [ -x /opt/homebrew/bin/brew ]; then echo /opt/homebrew/bin/brew; return 0; fi
  if [ -x /usr/local/bin/brew ]; then echo /usr/local/bin/brew; return 0; fi
  return 1
}

status() {
  local cf=""
  local brew=""
  cf="$(cloudflared_bin 2>/dev/null || true)"
  brew="$(brew_bin 2>/dev/null || true)"
  /usr/bin/python3 - "$cf" "$brew" "$CONFIG_PATH" "$LEGACY_CONFIG_PATH" "$METADATA_PATH" "$PLIST" <<'PY'
import json
import sys
from pathlib import Path
cf, brew, config, legacy, metadata, plist = sys.argv[1:]
print(json.dumps({
    "cloudflaredPath": cf or None,
    "homebrewPath": brew or None,
    "configPath": config if Path(config).exists() else None,
    "legacyConfigPath": legacy if Path(legacy).exists() else None,
    "metadataPath": metadata if Path(metadata).exists() else None,
    "launchAgentPath": plist if Path(plist).exists() else None,
}, indent=2))
PY
}

install_cloudflared() {
  if cloudflared_bin >/dev/null 2>&1; then
    echo "cloudflared already installed at $(cloudflared_bin)"
    return 0
  fi
  local brew
  brew="$(brew_bin)" || {
    echo "Homebrew is missing. Install Homebrew or install cloudflared manually from Cloudflare." >&2
    exit 20
  }
  "$brew" install cloudflared
}

login() {
  local cf
  cf="$(cloudflared_bin)" || { echo "cloudflared is missing." >&2; exit 21; }
  "$cf" tunnel login
}

configure_permanent() {
  local hostname=""
  local tunnel_name="codepilot"
  while [ $# -gt 0 ]; do
    case "$1" in
      --hostname) hostname="$2"; shift 2;;
      --tunnel-name) tunnel_name="$2"; shift 2;;
      *) echo "Unknown argument: $1" >&2; exit 2;;
    esac
  done
  [ -n "$hostname" ] || { echo "--hostname is required" >&2; exit 2; }

  local cf tunnel_id
  cf="$(cloudflared_bin)" || { echo "cloudflared is missing." >&2; exit 21; }
  tunnel_id="$("$cf" tunnel create "$tunnel_name" 2>/tmp/codepilot-cloudflared-create.err | /usr/bin/python3 -c 'import json,sys,re; s=sys.stdin.read(); 
try: print(json.loads(s).get("id",""))
except Exception: print((re.search(r"[0-9a-fA-F-]{20,}", s) or [""])[0])' || true)"
  "$cf" tunnel route dns "$tunnel_name" "$hostname"

  cat > "$CONFIG_PATH" <<EOF
tunnel: $tunnel_name
credentials-file: $CLOUDFLARED_DIR/$tunnel_id.json

ingress:
  - hostname: $hostname
    service: $GATEWAY_URL
  - service: http_status:404
EOF
  write_metadata permanent "$hostname" "$tunnel_name" "$tunnel_id"
  echo "Configured Cloudflare Tunnel for https://$hostname"
}

install_service() {
  mkdir -p "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"
  /usr/bin/python3 - "$PLIST" "$LABEL" "$PWD/scripts/start-phone-cloudflared.sh" <<'PY'
import plistlib
import sys
from pathlib import Path
plist_path = Path(sys.argv[1])
label = sys.argv[2]
script = sys.argv[3]
plist = {
    "Label": label,
    "ProgramArguments": [script],
    "RunAtLoad": True,
    "KeepAlive": True,
    "StandardOutPath": str(Path.home() / "Library" / "Logs" / "codepilot-cloudflared.out.log"),
    "StandardErrorPath": str(Path.home() / "Library" / "Logs" / "codepilot-cloudflared.err.log"),
}
plist_path.write_bytes(plistlib.dumps(plist, sort_keys=False))
PY
  launchctl bootout "gui/$(id -u)" "$PLIST" >/dev/null 2>&1 || true
  launchctl bootstrap "gui/$(id -u)" "$PLIST"
  launchctl enable "gui/$(id -u)/$LABEL"
  launchctl kickstart -k "gui/$(id -u)/$LABEL"
  echo "Installed $LABEL"
}

verify_url() {
  local url=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --url) url="$2"; shift 2;;
      *) echo "Unknown argument: $1" >&2; exit 2;;
    esac
  done
  [ -n "$url" ] || { echo "--url is required" >&2; exit 2; }
  curl -fsS "$url/api/health" >/dev/null
  echo "verified $url"
}

start_trycloudflare() {
  local cf
  cf="$(cloudflared_bin)" || { echo "cloudflared is missing." >&2; exit 21; }
  "$cf" tunnel --url "$GATEWAY_URL"
}

case "${1:-}" in
  status) status;;
  install-cloudflared) install_cloudflared;;
  login) login;;
  configure-permanent) shift; configure_permanent "$@";;
  install-service) install_service;;
  restart-service) install_service;;
  verify) shift; verify_url "$@";;
  start-trycloudflare) start_trycloudflare;;
  *) echo "Usage: $0 status|install-cloudflared|login|configure-permanent|install-service|restart-service|verify|start-trycloudflare" >&2; exit 2;;
esac
```

- [ ] **Step 2: Update compatibility scripts**

Modify `scripts/start-phone-cloudflared.sh`:

```zsh
#!/bin/zsh
set -euo pipefail

CONFIG="$HOME/.cloudflared/codepilot-config.yaml"
LEGACY="$HOME/.cloudflared/codex-phone-config.yaml"
if [ ! -f "$CONFIG" ] && [ -f "$LEGACY" ]; then
  CONFIG="$LEGACY"
fi

exec /opt/homebrew/bin/cloudflared tunnel --config "$CONFIG" run
```

Modify `scripts/install-phone-cloudflared-agent.sh`:

```zsh
#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
exec "$ROOT/scripts/setup-cloudflare-remote-access.sh" install-service
```

- [ ] **Step 3: Run script tests**

Run:

```bash
zsh scripts/test-cloudflare-setup.sh
```

Expected: `PASS: cloudflare setup script tests`.

- [ ] **Step 4: Commit script implementation**

```bash
git add scripts/setup-cloudflare-remote-access.sh scripts/start-phone-cloudflared.sh scripts/install-phone-cloudflared-agent.sh scripts/test-cloudflare-setup.sh
git commit -m "feat: add Cloudflare setup automation"
```

---

### Task 3: Add Swift Cloudflare Setup Models And Tests

**Files:**
- Create: `Tests/CodexAccountSwitcherTests/CloudflareSetupTests.swift`
- Modify: `Sources/CodexAccountSwitcher/main.swift`
- Test: `Tests/CodexAccountSwitcherTests/CloudflareSetupTests.swift`

- [ ] **Step 1: Write Swift tests for status and copy**

Create `Tests/CodexAccountSwitcherTests/CloudflareSetupTests.swift`:

```swift
import XCTest
@testable import CodexAccountSwitcher

final class CloudflareSetupTests: XCTestCase {
    func testCloudflareStatusLabelsAreSpecific() {
        XCTAssertEqual(CodePilotSetupRequirement.cloudflareMissing.statusLabel, "Missing")
        XCTAssertEqual(CodePilotSetupRequirement.cloudflareNeedsConfiguration.statusLabel, "Needs setup")
        XCTAssertEqual(CodePilotSetupRequirement.cloudflareReady.statusLabel, "Ready")
    }

    func testCloudflareMetadataDoesNotExposeSecrets() throws {
        let metadata = CodePilotCloudflareMetadata(
            mode: "permanent",
            hostname: "codepilot.example.com",
            tunnelName: "codepilot",
            tunnelId: "tun_123",
            configPath: "/Users/test/.cloudflared/codepilot-config.yaml",
            launchAgentLabel: "io.codepilot.phone-cloudflared",
            lastVerifiedAt: nil
        )
        let summary = metadata.safeSummary
        XCTAssertTrue(summary.contains("codepilot.example.com"))
        XCTAssertFalse(summary.localizedCaseInsensitiveContains("token"))
        XCTAssertFalse(summary.localizedCaseInsensitiveContains("credential"))
    }

    func testCloudflareScriptErrorMapsToRecoveryCopy() {
        XCTAssertEqual(
            CodePilotCloudflareErrorMapper.message(forExitCode: 20),
            "Homebrew is missing. Install Homebrew or use Cloudflare's manual cloudflared installer, then retry."
        )
        XCTAssertEqual(
            CodePilotCloudflareErrorMapper.message(forExitCode: 21),
            "cloudflared is missing. Install it from the Cloudflare setup step before continuing."
        )
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
swift test --filter CloudflareSetupTests
```

Expected: FAIL because the new enum cases and types are missing.

- [ ] **Step 3: Add minimal Swift models**

In `Sources/CodexAccountSwitcher/main.swift`, extend `CodePilotSetupRequirement`:

```swift
case cloudflareMissing
case cloudflareNeedsConfiguration
```

Update `statusLabel`:

```swift
case .cloudflareNeedsConfiguration:
    return "Needs setup"
case .cloudflareMissing:
    return "Missing"
```

Add near setup models:

```swift
struct CodePilotCloudflareMetadata: Codable, Equatable {
    let mode: String
    let hostname: String
    let tunnelName: String
    let tunnelId: String
    let configPath: String
    let launchAgentLabel: String
    let lastVerifiedAt: String?

    var safeSummary: String {
        let host = hostname.isEmpty ? "No hostname configured" : hostname
        return "\(mode) tunnel \(tunnelName) for \(host)"
    }
}

enum CodePilotCloudflareErrorMapper {
    static func message(forExitCode code: Int32) -> String {
        switch code {
        case 20:
            return "Homebrew is missing. Install Homebrew or use Cloudflare's manual cloudflared installer, then retry."
        case 21:
            return "cloudflared is missing. Install it from the Cloudflare setup step before continuing."
        default:
            return "Cloudflare setup did not finish. Open details, review the last command output, and retry the failed step."
        }
    }
}
```

- [ ] **Step 4: Run Swift tests**

Run:

```bash
swift test --filter CloudflareSetupTests
```

Expected: PASS.

- [ ] **Step 5: Commit Swift setup models**

```bash
git add Sources/CodexAccountSwitcher/main.swift Tests/CodexAccountSwitcherTests/CloudflareSetupTests.swift
git commit -m "feat: model Cloudflare setup state"
```

---

### Task 4: Improve Setup Status Detection

**Files:**
- Modify: `Sources/CodexAccountSwitcher/main.swift`
- Modify: `Tests/CodexAccountSwitcherTests/SetupStatusTests.swift`

- [ ] **Step 1: Extend setup status tests**

Modify `Tests/CodexAccountSwitcherTests/SetupStatusTests.swift`:

```swift
func testCloudflareStatusLabelsAreUserFacing() {
    XCTAssertEqual(CodePilotSetupRequirement.cloudflareReady.statusLabel, "Ready")
    XCTAssertEqual(CodePilotSetupRequirement.cloudflareMissing.statusLabel, "Missing")
    XCTAssertEqual(CodePilotSetupRequirement.cloudflareNeedsConfiguration.statusLabel, "Needs setup")
    XCTAssertEqual(CodePilotSetupRequirement.cloudflareOptional.statusLabel, "Optional")
}
```

- [ ] **Step 2: Run test to verify current behavior fails**

Run:

```bash
swift test --filter SetupStatusTests
```

Expected: FAIL until enum/status changes from Task 3 are present or if not yet integrated.

- [ ] **Step 3: Implement status row logic**

In `CodePilotSetupStatus.load()`, replace the current Cloudflare row with:

```swift
let cloudflareRequirement: CodePilotSetupRequirement
let cloudflareDetail: String
if cloudflared == nil {
    cloudflareRequirement = .cloudflareMissing
    cloudflareDetail = "Install cloudflared to enable remote iPhone access."
} else if cloudflareMetadataExists() || cloudflareConfigExists() {
    cloudflareRequirement = .cloudflareReady
    cloudflareDetail = cloudflareReadyDetail(defaultPath: cloudflared)
} else {
    cloudflareRequirement = .cloudflareNeedsConfiguration
    cloudflareDetail = "cloudflared is installed; set up a tunnel for remote access."
}
```

Add helper methods inside `CodePilotSetupStatus`:

```swift
private static func cloudflareMetadataExists() -> Bool {
    let path = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".codex-account-switcher/cloudflare-setup.json")
    return FileManager.default.fileExists(atPath: path.path)
}

private static func cloudflareConfigExists() -> Bool {
    let home = FileManager.default.homeDirectoryForCurrentUser
    let modern = home.appendingPathComponent(".cloudflared/codepilot-config.yaml")
    let legacy = home.appendingPathComponent(".cloudflared/codex-phone-config.yaml")
    return FileManager.default.fileExists(atPath: modern.path) || FileManager.default.fileExists(atPath: legacy.path)
}

private static func cloudflareReadyDetail(defaultPath: String?) -> String {
    if let metadata = loadCloudflareMetadata(), !metadata.hostname.isEmpty {
        return metadata.hostname
    }
    return defaultPath ?? "Configured"
}

private static func loadCloudflareMetadata() -> CodePilotCloudflareMetadata? {
    let path = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".codex-account-switcher/cloudflare-setup.json")
    guard let data = try? Data(contentsOf: path) else { return nil }
    return try? JSONDecoder().decode(CodePilotCloudflareMetadata.self, from: data)
}
```

- [ ] **Step 4: Run setup status tests**

Run:

```bash
swift test --filter SetupStatusTests
```

Expected: PASS.

- [ ] **Step 5: Commit status detection**

```bash
git add Sources/CodexAccountSwitcher/main.swift Tests/CodexAccountSwitcherTests/SetupStatusTests.swift
git commit -m "feat: improve Cloudflare setup status"
```

---

### Task 5: Add Mac App Cloudflare Wizard UI

**Files:**
- Modify: `Sources/CodexAccountSwitcher/main.swift`
- Test: `swift build`

- [ ] **Step 1: Add a wizard entry button**

In `CodePilotSetupWindowController.buildUI()`, change the Cloudflare section buttons to:

```swift
root.addArrangedSubview(section(
    title: "Cloudflare Remote Access",
    buttons: [
        button("Set Up Remote Access...", #selector(openCloudflareWizard)),
        button("Restart Tunnel", #selector(restartCloudflareTunnel)),
        button("Open Cloudflare Guide", #selector(openCloudflareGuide))
    ]
))
```

- [ ] **Step 2: Add wizard action skeleton**

Add methods to `CodePilotSetupWindowController`:

```swift
@objc private func openCloudflareWizard() {
    let controller = CodePilotCloudflareWizardController(parent: self)
    window?.beginSheet(controller.window!) { [weak self] _ in
        self?.refreshStatus()
    }
}

@objc private func restartCloudflareTunnel() {
    runBundledScript(named: "setup-cloudflare-remote-access.sh", arguments: ["restart-service"])
}
```

Change `runBundledScript` signature:

```swift
private func runBundledScript(named name: String, arguments: [String] = [], force: Bool = false)
```

Build arguments:

```swift
process.arguments = [script.path] + arguments + (force ? ["--force"] : [])
```

- [ ] **Step 3: Add the wizard controller**

Add a new `CodePilotCloudflareWizardController: NSWindowController` near `CodePilotSetupWindowController`. It should include:

```swift
private final class CodePilotCloudflareWizardController: NSWindowController {
    private weak var parentSetup: CodePilotSetupWindowController?
    private let outputLabel = NSTextField(wrappingLabelWithString: "")
    private let hostnameField = NSTextField(string: "")
    private let tunnelNameField = NSTextField(string: "codepilot")

    init(parent: CodePilotSetupWindowController) {
        self.parentSetup = parent
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 520),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Set Up Cloudflare Remote Access"
        super.init(window: window)
        buildUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
```

The UI must show:

- Explanation text covering outbound tunnel, config path, LaunchAgent, and token requirement.
- Buttons:
  - `Install cloudflared`
  - `Sign in or Create Cloudflare Account`
  - `Configure Permanent Hostname`
  - `Start Temporary Test URL`
  - `Close`
- Hostname field with placeholder `codepilot.example.com`.
- Tunnel name field default `codepilot`.
- Output label for current step.

- [ ] **Step 4: Wire wizard commands**

Add helper:

```swift
private func runCloudflareStep(_ arguments: [String], successMessage: String) {
    // Locate setup-cloudflare-remote-access.sh using the same candidate logic as runBundledScript.
    // Run /bin/zsh with [script.path] + arguments.
    // Capture stdout/stderr.
    // On success show successMessage plus last output.
    // On failure show CodePilotCloudflareErrorMapper.message(forExitCode: process.terminationStatus).
}
```

Button actions:

```swift
@objc private func installCloudflared() {
    runCloudflareStep(["install-cloudflared"], successMessage: "cloudflared is installed.")
}

@objc private func loginCloudflare() {
    runCloudflareStep(["login"], successMessage: "Cloudflare login completed.")
}

@objc private func configurePermanent() {
    let hostname = hostnameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    let tunnelName = tunnelNameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "codepilot" : tunnelNameField.stringValue
    guard !hostname.isEmpty else {
        outputLabel.stringValue = "Enter a hostname such as codepilot.example.com."
        return
    }
    runCloudflareStep(["configure-permanent", "--hostname", hostname, "--tunnel-name", tunnelName, "install-service", "verify", "--url", "https://\(hostname)"], successMessage: "Remote access is configured for https://\(hostname).")
}

@objc private func startTemporary() {
    runCloudflareStep(["start-trycloudflare"], successMessage: "Temporary Cloudflare URL started. Use this only for testing.")
}
```

If the combined command shape is too awkward, call the script steps sequentially from Swift and stop on first failure.

- [ ] **Step 5: Build**

Run:

```bash
swift build
```

Expected: Build succeeds.

- [ ] **Step 6: Commit wizard UI**

```bash
git add Sources/CodexAccountSwitcher/main.swift
git commit -m "feat: add Cloudflare setup wizard"
```

---

### Task 6: Add Documentation Updates

**Files:**
- Modify: `docs/CLOUDFLARE_SETUP.md`
- Modify: `docs/INSTALL_MAC.md`
- Modify: `docs/TROUBLESHOOTING.md`

- [ ] **Step 1: Update Cloudflare setup guide**

Replace `docs/CLOUDFLARE_SETUP.md` with:

```markdown
# Cloudflare Setup

Cloudflare Tunnel is the recommended way to reach the CodePilot gateway from outside the Mac's local network.

## Recommended: In-App Setup

Open **CodePilot > Setup CodePilot... > Cloudflare Remote Access > Set Up Remote Access...**.

The wizard explains and can configure:

- `cloudflared`, Cloudflare's local tunnel daemon.
- A Cloudflare sign-in or account creation step.
- A permanent hostname such as `codepilot.example.com`.
- A temporary TryCloudflare URL for testing without a domain.
- A macOS LaunchAgent that keeps the tunnel running.

CodePilot does not open inbound ports. Cloudflare Tunnel makes outbound connections to Cloudflare. The iPhone app still needs the CodePilot gateway token.

## Permanent Hostname

Choose this for regular use. You need a Cloudflare account and a domain managed by Cloudflare.

The wizard creates or reuses a tunnel, writes:

```text
~/.cloudflared/codepilot-config.yaml
```

and installs:

```text
~/Library/LaunchAgents/io.codepilot.phone-cloudflared.plist
```

## Temporary TryCloudflare

Choose this only for testing. Cloudflare creates a temporary `trycloudflare.com` URL. It can change and should not be treated as a permanent iPhone setup URL.

## Manual Fallback

Run:

```sh
scripts/setup-cloudflare-remote-access.sh status
scripts/setup-cloudflare-remote-access.sh install-cloudflared
scripts/setup-cloudflare-remote-access.sh login
scripts/setup-cloudflare-remote-access.sh configure-permanent --hostname codepilot.example.com --tunnel-name codepilot
scripts/setup-cloudflare-remote-access.sh install-service
scripts/setup-cloudflare-remote-access.sh verify --url https://codepilot.example.com
```

## Troubleshooting

- **Homebrew missing**: install Homebrew or install `cloudflared` manually from Cloudflare.
- **Hostname not on Cloudflare**: add the domain to Cloudflare first or use TryCloudflare.
- **502 from Cloudflare**: start the CodePilot gateway and restart the Cloudflare tunnel.
- **401/403**: copy the current gateway token from the Mac app into the iPhone app.
- **Works locally but not remotely**: check the Cloudflare LaunchAgent logs in `~/Library/Logs/`.
```

- [ ] **Step 2: Update Mac install guide**

In `docs/INSTALL_MAC.md`, add:

```markdown
## Remote iPhone Access

For access away from the local network, open **Setup CodePilot...** in the Mac menu bar app and use **Cloudflare Remote Access**. The setup wizard can install `cloudflared`, sign in to Cloudflare, configure a permanent hostname, or start a temporary TryCloudflare URL for testing.
```

- [ ] **Step 3: Update troubleshooting guide**

In `docs/TROUBLESHOOTING.md`, add:

```markdown
## Cloudflare Setup Fails

Open **Setup CodePilot... > Cloudflare Remote Access** and expand the details for the failed step.

- If `cloudflared` is missing, run the install step or install it manually from Cloudflare.
- If Homebrew is missing, install Homebrew or use Cloudflare's manual package.
- If login fails, rerun **Sign in or Create Cloudflare Account**.
- If DNS routing fails, confirm the hostname belongs to a Cloudflare-managed domain.
- If public verification fails, confirm the local gateway is running and restart the tunnel.
```

- [ ] **Step 4: Commit docs**

```bash
git add docs/CLOUDFLARE_SETUP.md docs/INSTALL_MAC.md docs/TROUBLESHOOTING.md
git commit -m "docs: document Cloudflare setup wizard"
```

---

### Task 7: Full Verification And Cleanup

**Files:**
- Verify all changed files.

- [ ] **Step 1: Run script tests**

Run:

```bash
zsh scripts/test-cloudflare-setup.sh
```

Expected: `PASS: cloudflare setup script tests`.

- [ ] **Step 2: Run Swift tests**

Run:

```bash
swift test
```

Expected: All tests pass.

- [ ] **Step 3: Run Swift build**

Run:

```bash
swift build
```

Expected: Build succeeds.

- [ ] **Step 4: Inspect git status**

Run:

```bash
git status --short
```

Expected: only unrelated pre-existing files remain modified, or a clean tree if those are separately handled.

- [ ] **Step 5: Final commit if needed**

If verification caused small fixes:

```bash
git add Sources/CodexAccountSwitcher/main.swift Tests/CodexAccountSwitcherTests scripts docs
git commit -m "test: verify Cloudflare setup wizard"
```

