#!/usr/bin/env bash
set -euo pipefail

# Nudge macOS Application Bundle Builder
# Assembles build/Nudge.app with CLI, privileged LaunchDaemon helper, icon, plists, and code signature.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

CONFIG="release"
SIGN_IDENTITY="-"

for arg in "$@"; do
    case "$arg" in
        --debug)
            CONFIG="debug"
            ;;
        --release)
            CONFIG="release"
            ;;
        --sign=*)
            SIGN_IDENTITY="${arg#*=}"
            ;;
        -h|--help)
            echo "Usage: $0 [--debug|--release] [--sign=<identity>]"
            echo "  --debug             Build debug configuration (default: release)"
            echo "  --release           Build release configuration"
            echo "  --sign=<identity>   Codesign identity (default: '-' ad-hoc)"
            exit 0
            ;;
        *)
            echo "Unknown argument: $arg" >&2
            exit 1
            ;;
    esac
done

APP_NAME="Nudge"
BUILD_DIR="${ROOT_DIR}/build"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
LAUNCH_SERVICES_DIR="${CONTENTS_DIR}/Library/LaunchServices"
LAUNCH_DAEMONS_DIR="${CONTENTS_DIR}/Library/LaunchDaemons"

SRC_RESOURCES="${ROOT_DIR}/Resources"
INFO_PLIST="${SRC_RESOURCES}/Info.plist"
HELPER_INFO_PLIST="${SRC_RESOURCES}/HelperInfo.plist"
HELPER_LAUNCHD_PLIST="${SRC_RESOURCES}/com.emrisca.nudge.helper.plist"
ENTITLEMENTS="${SRC_RESOURCES}/Nudge.entitlements"
APP_ICON="${SRC_RESOURCES}/AppIcon.icns"

echo "==> Building Nudge targets (${CONFIG})..."
cd "${ROOT_DIR}"

if [[ ! -f "${APP_ICON}" && -f "${SCRIPT_DIR}/generate-icon.swift" ]]; then
    echo "==> Generating missing Resources/AppIcon.icns..."
    swift "${SCRIPT_DIR}/generate-icon.swift"
fi

swift build -c "${CONFIG}" --product Nudge
swift build -c "${CONFIG}" --product nudge-cli
swift build -c "${CONFIG}" --product nudge-helper

BIN_PATH="$(swift build -c "${CONFIG}" --show-bin-path)"
echo "==> Swift binary directory: ${BIN_PATH}"

NUDGE_BIN="${BIN_PATH}/Nudge"
CLI_BIN="${BIN_PATH}/nudge-cli"
HELPER_BIN="${BIN_PATH}/nudge-helper"

for bin in "${NUDGE_BIN}" "${CLI_BIN}" "${HELPER_BIN}"; do
    if [[ ! -x "${bin}" ]]; then
        echo "Error: expected executable not found at ${bin}" >&2
        exit 1
    fi
done

for req_file in "${INFO_PLIST}" "${HELPER_LAUNCHD_PLIST}" "${ENTITLEMENTS}" "${APP_ICON}"; do
    if [[ ! -f "${req_file}" ]]; then
        echo "Error: required resource not found at ${req_file}" >&2
        exit 1
    fi
done

echo "==> Assembling ${APP_BUNDLE}..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}" "${LAUNCH_SERVICES_DIR}" "${LAUNCH_DAEMONS_DIR}"

# Copy executables
cp "${NUDGE_BIN}" "${MACOS_DIR}/Nudge"
cp "${CLI_BIN}" "${MACOS_DIR}/nudge-cli"
cp "${HELPER_BIN}" "${LAUNCH_SERVICES_DIR}/com.emrisca.nudge.helper"

chmod +x "${MACOS_DIR}/Nudge" "${MACOS_DIR}/nudge-cli" "${LAUNCH_SERVICES_DIR}/com.emrisca.nudge.helper"

# Copy bundle metadata & resources
cp "${INFO_PLIST}" "${CONTENTS_DIR}/Info.plist"
printf 'APPL????' > "${CONTENTS_DIR}/PkgInfo"
cp "${APP_ICON}" "${RESOURCES_DIR}/AppIcon.icns"
cp "${HELPER_LAUNCHD_PLIST}" "${RESOURCES_DIR}/com.emrisca.nudge.helper.plist"
cp "${HELPER_LAUNCHD_PLIST}" "${LAUNCH_DAEMONS_DIR}/com.emrisca.nudge.helper.plist"

if [[ -f "${HELPER_INFO_PLIST}" ]]; then
    cp "${HELPER_INFO_PLIST}" "${RESOURCES_DIR}/HelperInfo.plist"
fi

# Validate plists inside bundle
plutil -lint "${CONTENTS_DIR}/Info.plist" >/dev/null
plutil -lint "${RESOURCES_DIR}/com.emrisca.nudge.helper.plist" >/dev/null
plutil -lint "${LAUNCH_DAEMONS_DIR}/com.emrisca.nudge.helper.plist" >/dev/null

echo "==> Code-signing bundle (identity: ${SIGN_IDENTITY})..."
codesign --force --sign "${SIGN_IDENTITY}" --identifier "com.emrisca.nudge.cli" "${MACOS_DIR}/nudge-cli"
codesign --force --sign "${SIGN_IDENTITY}" --identifier "com.emrisca.nudge.helper" "${LAUNCH_SERVICES_DIR}/com.emrisca.nudge.helper"
codesign --force --deep --sign "${SIGN_IDENTITY}" --entitlements "${ENTITLEMENTS}" "${APP_BUNDLE}"

echo "==> Verifying code signature..."
codesign --verify --deep --strict "${APP_BUNDLE}"

echo ""
echo "Built Nudge.app successfully!"
echo "Bundle: ${APP_BUNDLE}"
echo "Launch: open build/Nudge.app"
