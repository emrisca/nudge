#!/usr/bin/env bash
set -euo pipefail

# Nudge macOS Installer & Release Packager
# Ad-hoc signed by default (no Apple Developer license, Developer ID certificate,
# notarization, DMG SLA/license prompt, or repo LICENSE file required).
#
# Produces:
#   build/Nudge-<version>-macOS-<arch>.dmg   (compressed UDZO with Applications symlink & custom volume icon)
#   build/Nudge-<version>-macOS-<arch>.zip   (portable ditto archive preserving resource forks & signatures)
#   build/SHA256SUMS.txt                     (SHA-256 checksums for .dmg and .zip)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd -P)"

FORCE_BUILD=0
BUILD_CONFIG="release"
SIGN_IDENTITY="-"
APP_BUNDLE=""
OUT_DIR="${ROOT_DIR}/build"

usage() {
    cat <<EOF
Usage: $0 [options]

Options:
  --build             Run ./scripts/build-app.sh even if build/Nudge.app already exists
  --debug             Build debug configuration when invoking build-app.sh
  --release           Build release configuration when invoking build-app.sh (default)
  --sign=<identity>   Codesign identity (default: '-' ad-hoc; no Apple Developer license needed)
  --app=<path>        Path to existing Nudge.app bundle (default: build/Nudge.app)
  --out-dir=<path>    Output directory for .dmg, .zip, and SHA256SUMS.txt (default: build)
  -h, --help          Show this help message
EOF
}

for arg in "$@"; do
    case "$arg" in
        --build)
            FORCE_BUILD=1
            ;;
        --debug)
            BUILD_CONFIG="debug"
            ;;
        --release)
            BUILD_CONFIG="release"
            ;;
        --sign=*)
            SIGN_IDENTITY="${arg#*=}"
            ;;
        --app=*)
            APP_BUNDLE="${arg#*=}"
            ;;
        --out-dir=*)
            OUT_DIR="${arg#*=}"
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown argument: $arg" >&2
            usage >&2
            exit 1
            ;;
    esac
done

APP_NAME="Nudge"
SRC_RESOURCES="${ROOT_DIR}/Resources"
INFO_PLIST="${SRC_RESOURCES}/Info.plist"
ENTITLEMENTS="${SRC_RESOURCES}/Nudge.entitlements"
APP_ICON="${SRC_RESOURCES}/AppIcon.icns"

if [[ -z "${APP_BUNDLE}" ]]; then
    APP_BUNDLE="${ROOT_DIR}/build/${APP_NAME}.app"
fi

# 1. Optionally build Nudge.app if missing or --build was passed
#    Strictly defaults to ad-hoc signing (--sign=-); never requires Developer ID or notarization.
if [[ "${FORCE_BUILD}" -eq 1 || ! -d "${APP_BUNDLE}" ]]; then
    if [[ "${APP_BUNDLE}" != "${ROOT_DIR}/build/${APP_NAME}.app" ]]; then
        echo "Error: specified app bundle not found at ${APP_BUNDLE}" >&2
        exit 1
    fi
    echo "==> Building ${APP_NAME}.app via scripts/build-app.sh (${BUILD_CONFIG}, sign: ${SIGN_IDENTITY})..."
    "${SCRIPT_DIR}/build-app.sh" "--${BUILD_CONFIG}" "--sign=${SIGN_IDENTITY}"
fi

if [[ ! -d "${APP_BUNDLE}" ]]; then
    echo "Error: ${APP_BUNDLE} not found after build." >&2
    exit 1
fi

# Ensure bundle has at least an ad-hoc signature if packaged without --build (never requires Developer ID)
if ! codesign --verify --deep --strict "${APP_BUNDLE}" >/dev/null 2>&1; then
    echo "==> Applying ad-hoc code signature (${SIGN_IDENTITY})..."
    if [[ -f "${ENTITLEMENTS}" ]]; then
        codesign --force --deep --sign "${SIGN_IDENTITY}" --entitlements "${ENTITLEMENTS}" "${APP_BUNDLE}"
    else
        codesign --force --deep --sign "${SIGN_IDENTITY}" "${APP_BUNDLE}"
    fi
fi

# 2. Read CFBundleShortVersionString from Resources/Info.plist and detect architecture
if [[ ! -f "${INFO_PLIST}" ]]; then
    echo "Error: Info.plist not found at ${INFO_PLIST}" >&2
    exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "${INFO_PLIST}" 2>/dev/null || true)"
if [[ -z "${VERSION}" ]]; then
    echo "Error: could not read CFBundleShortVersionString from ${INFO_PLIST}" >&2
    exit 1
fi

APP_EXECUTABLE="${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
ARCH=""
if [[ -f "${APP_EXECUTABLE}" ]] && command -v lipo >/dev/null 2>&1; then
    LIPO_ARCHS="$(lipo -archs "${APP_EXECUTABLE}" 2>/dev/null || true)"
    case "${LIPO_ARCHS}" in
        "arm64")
            ARCH="arm64"
            ;;
        "x86_64")
            ARCH="x86_64"
            ;;
        *"arm64"*"x86_64"*|*"x86_64"*"arm64"*)
            ARCH="universal"
            ;;
    esac
fi

if [[ -z "${ARCH}" ]]; then
    ARCH="$(uname -m)"
fi

mkdir -p "${OUT_DIR}"
OUT_DIR="$(cd "${OUT_DIR}" && pwd -P)"

ARTIFACT_BASE="${APP_NAME}-${VERSION}-macOS-${ARCH}"
DMG_PATH="${OUT_DIR}/${ARTIFACT_BASE}.dmg"
ZIP_PATH="${OUT_DIR}/${ARTIFACT_BASE}.zip"
CHECKSUMS_PATH="${OUT_DIR}/SHA256SUMS.txt"
VOL_NAME="${APP_NAME} ${VERSION}"

WORK_DIR=""
MOUNT_POINT=""
ATTACHED_DEVICE=""

detach_volume() {
    local target="${ATTACHED_DEVICE:-${MOUNT_POINT}}"
    if [[ -z "${target}" ]]; then
        return 0
    fi

    sync || true
    local attempt
    for attempt in 1 2 3 4 5; do
        if hdiutil detach "${target}" -quiet >/dev/null 2>&1; then
            ATTACHED_DEVICE=""
            MOUNT_POINT=""
            return 0
        fi
        sleep 1
    done

    hdiutil detach "${target}" -force -quiet >/dev/null 2>&1 || true
    ATTACHED_DEVICE=""
    MOUNT_POINT=""
}

cleanup() {
    local exit_code=$?
    detach_volume
    if [[ -n "${WORK_DIR}" && -d "${WORK_DIR}" ]]; then
        rm -rf "${WORK_DIR}" || true
    fi
    exit "${exit_code}"
}
trap cleanup EXIT INT TERM

WORK_DIR="$(mktemp -d "${OUT_DIR}/.dmg-staging.XXXXXX")"
STAGE_DIR="${WORK_DIR}/stage"
RW_DMG="${WORK_DIR}/${ARTIFACT_BASE}-rw.dmg"
MOUNT_POINT="${WORK_DIR}/mnt"

mkdir -p "${STAGE_DIR}" "${MOUNT_POINT}"

# 3. Populate clean staging directory (no repo LICENSE file or DMG SLA required)
echo "==> Staging ${APP_NAME} ${VERSION} (${ARCH})..."
ditto "${APP_BUNDLE}" "${STAGE_DIR}/${APP_NAME}.app"
ln -s /Applications "${STAGE_DIR}/Applications"

cat > "${STAGE_DIR}/Install Instructions.txt" <<EOF
Nudge ${VERSION} for macOS (${ARCH})
======================================

1. Install
   Drag Nudge.app onto the Applications folder icon in this window.

2. First Launch (Ad-Hoc Signed / Not Notarized)
   This release is ad-hoc signed (not notarized with an Apple Developer
   license). When downloaded from GitHub, macOS Gatekeeper may warn that
   the app cannot be verified or appears damaged.

   Recommended one-line fix in Terminal after copying to /Applications:

       xattr -cr /Applications/Nudge.app

   Alternatively, you can bypass Gatekeeper via macOS UI:
     - Right-click /Applications/Nudge.app -> Open -> Open, OR
     - Open System Settings -> Privacy & Security -> click "Open Anyway".

   Then launch Nudge normally from /Applications.

3. Menu Bar Utility
   Nudge runs as a lightweight menu bar app (no Dock icon). Look for the
   Nudge battery icon in your macOS menu bar after launching.

4. Optional Privileged Helper (Hardware Charge Limiting)
   Nudge works out of the box for battery monitoring and telemetry.
   To enable hardware charge limiting, discharge control, and MagSafe LED
   control, open Nudge Settings and install the optional privileged helper
   (com.emrisca.nudge.helper). macOS will prompt for administrator approval.

CLI Tool
   A companion CLI is bundled inside the app at:
       /Applications/Nudge.app/Contents/MacOS/nudge-cli
EOF

# 4. Build compressed UDZO disk image directly (non-interactive, no Finder popups, no SLA/license resource)
rm -f "${DMG_PATH}"

if [[ -f "${APP_ICON}" ]] && command -v SetFile >/dev/null 2>&1; then
    echo "==> Creating disk image with custom volume icon..."
    cp "${APP_ICON}" "${STAGE_DIR}/.VolumeIcon.icns"

    hdiutil create \
        -srcfolder "${STAGE_DIR}" \
        -volname "${VOL_NAME}" \
        -fs HFS+ \
        -fsargs "-c c=64,a=16,e=16" \
        -format UDRW \
        -ov \
        "${RW_DMG}" >/dev/null

    ATTACH_OUTPUT="$(hdiutil attach \
        -readwrite \
        -noverify \
        -noautoopen \
        -nobrowse \
        -mountpoint "${MOUNT_POINT}" \
        "${RW_DMG}")"
    ATTACHED_DEVICE="$(printf '%s\n' "${ATTACH_OUTPUT}" | awk '/^\/dev\/disk/ {print $1; exit}')"

    # Set custom volume icon bit and hide .VolumeIcon.icns without touching Finder
    SetFile -a V "${MOUNT_POINT}/.VolumeIcon.icns"
    SetFile -a C "${MOUNT_POINT}"
    rm -rf "${MOUNT_POINT}/.fseventsd" "${MOUNT_POINT}/.Trashes" 2>/dev/null || true

    detach_volume

    echo "==> Compressing disk image (UDZO)..."
    hdiutil convert \
        "${RW_DMG}" \
        -format UDZO \
        -imagekey zlib-level=9 \
        -ov \
        -o "${DMG_PATH}" >/dev/null
else
    echo "==> Creating compressed disk image (UDZO)..."
    if [[ -f "${APP_ICON}" ]]; then
        cp "${APP_ICON}" "${STAGE_DIR}/.VolumeIcon.icns"
    fi
    hdiutil create \
        -srcfolder "${STAGE_DIR}" \
        -volname "${VOL_NAME}" \
        -fs HFS+ \
        -format UDZO \
        -imagekey zlib-level=9 \
        -ov \
        "${DMG_PATH}" >/dev/null
fi

echo "==> Verifying disk image..."
hdiutil verify "${DMG_PATH}" >/dev/null

# 5. Build portable ZIP archive
echo "==> Creating portable ZIP archive..."
rm -f "${ZIP_PATH}"
ditto -c -k --sequesterRsrc --keepParent "${APP_BUNDLE}" "${ZIP_PATH}"

# 6. Generate SHA256SUMS.txt covering both .dmg and .zip
echo "==> Generating SHA-256 checksums..."
(
    cd "${OUT_DIR}"
    shasum -a 256 "$(basename "${DMG_PATH}")" "$(basename "${ZIP_PATH}")" > "${CHECKSUMS_PATH}"
)

DMG_SIZE="$(du -h "${DMG_PATH}" | awk '{print $1}')"
ZIP_SIZE="$(du -h "${ZIP_PATH}" | awk '{print $1}')"

echo ""
echo "Packaged Nudge ${VERSION} (${ARCH}) successfully (signing: ${SIGN_IDENTITY}, no notarization/SLA)!"
echo "  DMG:       ${DMG_PATH} (${DMG_SIZE})"
echo "  ZIP:       ${ZIP_PATH} (${ZIP_SIZE})"
echo "  Checksums: ${CHECKSUMS_PATH}"
echo ""
cat "${CHECKSUMS_PATH}"
