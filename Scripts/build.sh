#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
DERIVED_DIR="${PROJECT_DIR}/.build/DerivedData"
DIST_DIR="${PROJECT_DIR}/dist"

/usr/bin/xcodebuild \
  -quiet \
  -project "${PROJECT_DIR}/FrictionBlocker.xcodeproj" \
  -scheme FrictionBlocker \
  -configuration Release \
  -derivedDataPath "${DERIVED_DIR}" \
  CODE_SIGN_IDENTITY=- \
  build

/bin/mkdir -p "${DIST_DIR}"
/bin/rm -rf "${DIST_DIR}/FrictionBlocker.app"
/bin/rm -f "${DIST_DIR}/frictionblockerd"
/usr/bin/ditto \
  "${DERIVED_DIR}/Build/Products/Release/FrictionBlocker.app" \
  "${DIST_DIR}/FrictionBlocker.app"
/usr/bin/install -m 0755 \
  "${DERIVED_DIR}/Build/Products/Release/frictionblockerd" \
  "${DIST_DIR}/frictionblockerd"

echo "Built:"
echo "  ${DIST_DIR}/FrictionBlocker.app"
echo "  ${DIST_DIR}/frictionblockerd"
echo "Next: sudo ${PROJECT_DIR}/Scripts/install.sh"
