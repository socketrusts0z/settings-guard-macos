#!/bin/zsh
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run this installer with sudo." >&2
  exit 1
fi

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
DAEMON_SOURCE="${PROJECT_DIR}/dist/frictionblockerd"
APP_SOURCE="${PROJECT_DIR}/dist/FrictionBlocker.app"
PLIST_SOURCE="${PROJECT_DIR}/Daemon/com.anantchowdhary.frictionblocker.daemon.plist"
DAEMON_DEST="/Library/PrivilegedHelperTools/com.anantchowdhary.frictionblocker.daemon"
PLIST_DEST="/Library/LaunchDaemons/com.anantchowdhary.frictionblocker.daemon.plist"
STATE_DIR="/Library/Application Support/FrictionBlocker"
LABEL="com.anantchowdhary.frictionblocker.daemon"

if [[ ! -x "${DAEMON_SOURCE}" || ! -d "${APP_SOURCE}" ]]; then
  echo "Build artifacts are missing. Run ./Scripts/build.sh first." >&2
  exit 1
fi

/usr/bin/plutil -lint "${PLIST_SOURCE}" >/dev/null

# Stop any previously installed daemon before replacing it.
/bin/launchctl bootout "system/${LABEL}" 2>/dev/null || true

/usr/bin/install -d -m 0755 /Library/PrivilegedHelperTools /Library/LaunchDaemons
/usr/bin/install -d -m 0700 "${STATE_DIR}"
/usr/bin/install -m 0755 "${DAEMON_SOURCE}" "${DAEMON_DEST}"
/usr/bin/install -m 0644 "${PLIST_SOURCE}" "${PLIST_DEST}"
# A running app keeps executing its old in-memory binary even after the bundle
# is replaced. Stop it so protocol-changing upgrades cannot leave an old UI
# talking to the newly installed daemon.
/usr/bin/pkill -x FrictionBlocker 2>/dev/null || true
/bin/rm -rf /Applications/FrictionBlocker.app
/usr/bin/ditto "${APP_SOURCE}" /Applications/FrictionBlocker.app
/usr/sbin/chown -R root:wheel /Applications/FrictionBlocker.app

/bin/launchctl bootstrap system "${PLIST_DEST}"
/bin/launchctl enable "system/${LABEL}"
/bin/launchctl kickstart -k "system/${LABEL}"

echo "Settings Guard installed."
echo "Next: open /Applications/FrictionBlocker.app"
