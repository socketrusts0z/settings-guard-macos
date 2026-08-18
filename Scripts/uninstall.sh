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
TOKEN_PATH="${STATE_DIR}/pf-enable-token"
PF_CONF="/etc/pf.conf"

/bin/launchctl bootout "system/${LABEL}" 2>/dev/null || true

# Also remove legacy PF artifacts if this Mac was upgraded from version 1.
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
  /usr/bin/install -m 0644 "${TEMP_CONF}" "${PF_CONF}"
  /bin/rm -f "${TEMP_CONF}"
  /sbin/pfctl -f "${PF_CONF}"
fi

if [[ -f "${TOKEN_PATH}" ]]; then
  ENABLE_TOKEN="$(<"${TOKEN_PATH}")"
  if [[ -n "${ENABLE_TOKEN}" ]]; then
    /sbin/pfctl -X "${ENABLE_TOKEN}" 2>/dev/null || true
  fi
fi

/bin/rm -f /Library/LaunchDaemons/com.anantchowdhary.frictionblocker.daemon.plist
/bin/rm -f /Library/PrivilegedHelperTools/com.anantchowdhary.frictionblocker.daemon
/bin/rm -f /etc/pf.anchors/com.anantchowdhary.frictionblocker
/bin/rm -f /var/run/com.anantchowdhary.frictionblocker.sock
/bin/rm -rf "${STATE_DIR}"
/bin/rm -rf /Applications/FrictionBlocker.app

echo "Settings Guard and any legacy Friction Blocker PF artifacts were removed."
