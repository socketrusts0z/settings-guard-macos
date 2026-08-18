#!/bin/zsh
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run this uninstaller with sudo." >&2
  exit 1
fi

if [[ "${1:-}" != "--confirm-remove" ]]; then
  echo "This removes Settings Guard and its stored password verifier."
  echo "Re-run with: sudo ./Scripts/uninstall.sh --confirm-remove"
  exit 2
fi

LABEL="com.anantchowdhary.frictionblocker.daemon"
STATE_DIR="/Library/Application Support/FrictionBlocker"

/bin/launchctl bootout "system/${LABEL}" 2>/dev/null || true

/bin/rm -f /Library/LaunchDaemons/com.anantchowdhary.frictionblocker.daemon.plist
/bin/rm -f /Library/PrivilegedHelperTools/com.anantchowdhary.frictionblocker.daemon
/bin/rm -f /var/run/com.anantchowdhary.frictionblocker.sock
/bin/rm -rf "${STATE_DIR}"
/bin/rm -rf /Applications/FrictionBlocker.app

echo "Settings Guard was removed."
