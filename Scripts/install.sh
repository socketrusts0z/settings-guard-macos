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
TOKEN_PATH="${STATE_DIR}/pf-enable-token"
ANCHOR_PATH="/etc/pf.anchors/com.anantchowdhary.frictionblocker"
PF_CONF="/etc/pf.conf"
LABEL="com.anantchowdhary.frictionblocker.daemon"

if [[ ! -x "${DAEMON_SOURCE}" || ! -d "${APP_SOURCE}" ]]; then
  echo "Build artifacts are missing. Run ./Scripts/build.sh first." >&2
  exit 1
fi

/usr/bin/plutil -lint "${PLIST_SOURCE}" >/dev/null

# Stop the previous PF-based daemon before removing its firewall anchor.
/bin/launchctl bootout "system/${LABEL}" 2>/dev/null || true
/sbin/pfctl -a com.anantchowdhary.frictionblocker -F all 2>/dev/null || true

if [[ -f "${PF_CONF}" ]] && {
  /usr/bin/grep -Fq '# Friction Blocker anchor' "${PF_CONF}" ||
  /usr/bin/grep -Fq 'anchor "com.anantchowdhary.frictionblocker"' "${PF_CONF}"
}; then
  TEMP_CONF="$(/usr/bin/mktemp /tmp/settings-guard-pf.XXXXXX)"
  /usr/bin/awk '
    $0 == "# Friction Blocker anchor" { next }
    $0 == "anchor \"com.anantchowdhary.frictionblocker\"" { next }
    $0 == "load anchor \"com.anantchowdhary.frictionblocker\" from \"/etc/pf.anchors/com.anantchowdhary.frictionblocker\"" { next }
    { print }
  ' "${PF_CONF}" > "${TEMP_CONF}"
  /sbin/pfctl -nf "${TEMP_CONF}"
  BACKUP_PATH="/etc/pf.conf.before-settings-guard.$(/bin/date +%Y%m%d%H%M%S)"
  /bin/cp -p "${PF_CONF}" "${BACKUP_PATH}"
  /usr/bin/install -m 0644 "${TEMP_CONF}" "${PF_CONF}"
  /bin/rm -f "${TEMP_CONF}"
  /sbin/pfctl -f "${PF_CONF}"
  echo "Removed the legacy PF anchor; backup: ${BACKUP_PATH}"
fi

if [[ -f "${TOKEN_PATH}" ]]; then
  ENABLE_TOKEN="$(<"${TOKEN_PATH}")"
  if [[ -n "${ENABLE_TOKEN}" ]]; then
    /sbin/pfctl -X "${ENABLE_TOKEN}" 2>/dev/null || true
  fi
  /bin/rm -f "${TOKEN_PATH}"
fi
/bin/rm -f "${ANCHOR_PATH}"

/usr/bin/install -d -m 0755 /Library/PrivilegedHelperTools /Library/LaunchDaemons
/usr/bin/install -d -m 0700 "${STATE_DIR}"
/usr/bin/install -m 0755 "${DAEMON_SOURCE}" "${DAEMON_DEST}"
/usr/bin/install -m 0644 "${PLIST_SOURCE}" "${PLIST_DEST}"
/bin/rm -rf /Applications/FrictionBlocker.app
/usr/bin/ditto "${APP_SOURCE}" /Applications/FrictionBlocker.app
/usr/sbin/chown -R root:wheel /Applications/FrictionBlocker.app

/bin/launchctl bootstrap system "${PLIST_DEST}"
/bin/launchctl enable "system/${LABEL}"
/bin/launchctl kickstart -k "system/${LABEL}"

echo "Settings Guard installed. No Friction Blocker PF rules remain."
echo "Next: open /Applications/FrictionBlocker.app"
