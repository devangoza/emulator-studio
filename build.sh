#!/bin/bash
# Build Emulator Studio into a real .app bundle.
set -euo pipefail

cd "$(dirname "$0")"

CONFIG="${1:-release}"
APP_NAME="Emulator Studio"
APP="dist/${APP_NAME}.app"

echo "==> swift build -c ${CONFIG}"
swift build -c "${CONFIG}" --disable-sandbox

BIN=".build/${CONFIG}/EmulatorStudio"
if [ ! -f "${BIN}" ]; then
  echo "Build product not found at ${BIN}" >&2
  exit 1
fi

echo "==> assembling ${APP}"
rm -rf "${APP}"
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"

cp "${BIN}" "${APP}/Contents/MacOS/EmulatorStudio"
cp Resources/Info.plist "${APP}/Contents/Info.plist"

if [ -f Resources/AppIcon.icns ]; then
  cp Resources/AppIcon.icns "${APP}/Contents/Resources/AppIcon.icns"
fi

# Ad-hoc sign so macOS is happy to launch it locally.
codesign --force --sign - --timestamp=none "${APP}" >/dev/null 2>&1 || \
  echo "    (codesign skipped)"

# Nudge Launch Services so the icon/name refresh.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
  -f "${APP}" >/dev/null 2>&1 || true

echo "==> done: ${PWD}/${APP}"
