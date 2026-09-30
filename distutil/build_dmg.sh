#!/bin/bash
#
# Builds the SnakeStick release DMG
#
#   archive → export (Developer ID) → check the bundle → notarize and staple the app → DMG
#   → notarize and staple the DMG → verify
#
# Usage
#   distutil/build_dmg.sh                   everything
#   distutil/build_dmg.sh --skip-notarize   skips notarization and stapling; for checking the signing only
#
# Output
#   dist/snakestick-signed-<version>-<commit>-RELEASE.dmg
#
set -euo pipefail

# ==============================================================================
# Settings
# ==============================================================================

SRCROOT="$(git rev-parse --show-toplevel)"

WORKSPACE="$SRCROOT/SnakeStick.xcworkspace"
SCHEME="SnakeStick"
APP_NAME="SnakeStick"
TEAM_ID="XHA76UVA95"

APP_BUNDLE_ID="pl.unstabler.aislop.SnakeStick"
HELPER_NAME="SnakeStickHelper"
HELPER_BUNDLE_ID="pl.unstabler.aislop.SnakeStick.helper"
HELPER_PLIST="Contents/Library/LaunchDaemons/$HELPER_BUNDLE_ID.plist"

RESOURCE_BUNDLE="Contents/Resources/SnakeStickCore_SnakeStickCore.bundle"
UEFI_NTFS_SOURCE="$SRCROOT/SnakeStickCore/Sources/SnakeStickCore/Resources/UEFI-NTFS"

APP_CERT_ID="Developer ID Application: team unstablers Inc. ($TEAM_ID)"

# A Developer ID Application leaf issued to our team. The app and the daemon accept each other
# only when both are signed by the same team (HelperClient.swift, SnakeStickHelper/main.swift), so
# both executables are checked against this.
DEVELOPER_ID_REQUIREMENT="anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] exists and certificate leaf[field.1.2.840.113635.100.6.1.13] exists and certificate leaf[subject.OU] = \"$TEAM_ID\""

# A profile made with 'xcrun notarytool store-credentials'. The same one COSMICOLOR and Noctiluca use.
NOTARY_KEYCHAIN_PROFILE="tu-noctiluca-notarycred"

# dist/ keeps the released DMGs and is never cleared. Each build clears only dist/build/.
DIST_DIR="$SRCROOT/dist"
INTERMEDIATE_DIR="$DIST_DIR/build"
DERIVED_DATA_PATH="$INTERMEDIATE_DIR/DerivedData"
ARCHIVE_PATH="$INTERMEDIATE_DIR/$APP_NAME.xcarchive"
EXPORT_PATH="$INTERMEDIATE_DIR/export"

SKIP_NOTARIZE=0

# ==============================================================================
# Utilities
# ==============================================================================

die() {
    echo "❌ $*" >&2
    exit 1
}

step() {
    echo
    echo "▶ $*"
}

# xcodebuild prints thousands of lines, which would bury the progress. Keep them in a log and show
# the tail only on failure.
run_xcodebuild() {
    local log="$1"
    shift

    if ! xcodebuild "$@" > "$log" 2>&1; then
        echo "❌ xcodebuild failed — $log" >&2
        echo "--- last 40 lines ---" >&2
        tail -40 "$log" >&2
        exit 1
    fi
}

# A .app is a directory and cannot be submitted as is. Submit a ditto archive of it, and staple
# the ticket to the app bundle, not to the zip.
notarize_app() {
    local app="$1"
    local zip="$INTERMEDIATE_DIR/$(basename "$app" .app)-notarize.zip"

    rm -f "$zip"
    ditto -c -k --keepParent "$app" "$zip"

    xcrun notarytool submit "$zip" \
        --keychain-profile "$NOTARY_KEYCHAIN_PROFILE" \
        --wait

    xcrun stapler staple "$app"
}

notarize_file() {
    local target="$1"

    xcrun notarytool submit "$target" \
        --keychain-profile "$NOTARY_KEYCHAIN_PROFILE" \
        --wait

    xcrun stapler staple "$target"
}

# Checks that `path` is signed with our Developer ID under `identifier`, with the hardened runtime.
check_signature() {
    local path="$1"
    local identifier="$2"
    local details

    # A separate argument: '-R=...' would pass the '=' along with the requirement.
    codesign --verify --strict -R "=$DEVELOPER_ID_REQUIREMENT and identifier \"$identifier\"" "$path" \
        || die "$path is not signed with '$APP_CERT_ID' as $identifier"

    details="$(codesign -dv "$path" 2>&1)"
    [[ "$details" == *"(runtime)"* ]] \
        || die "$path is not signed with the hardened runtime"
}

# The daemon is a command line tool; its Info.plist lives in its __TEXT,__info_plist section
# (CREATE_INFOPLIST_SECTION_IN_BINARY). segedit reads only thin binaries.
extract_embedded_info_plist() {
    local binary="$1"
    local output="$2"
    local thin="$output.thin"
    local archs

    read -r -a archs <<< "$(lipo -archs "$binary")"
    if [[ ${#archs[@]} -gt 1 ]]; then
        lipo "$binary" -thin "${archs[0]}" -output "$thin"
    else
        cp "$binary" "$thin"
    fi

    rm -f "$output"
    segedit "$thin" -extract __TEXT __info_plist "$output"
    rm -f "$thin"
}

plist_value() {
    /usr/libexec/PlistBuddy -c "Print :$2" "$1"
}

# ==============================================================================
# Arguments
# ==============================================================================

while [[ $# -gt 0 ]]; do
    case "$1" in
        --skip-notarize)
            SKIP_NOTARIZE=1
            shift
            ;;
        *)
            die "unknown argument: $1"
            ;;
    esac
done

# ==============================================================================
# Preflight
#
# The build takes minutes, so missing tools and credentials are caught before it starts.
# ==============================================================================

step "Preflight"

command -v create-dmg >/dev/null \
    || die "create-dmg is missing. Install it with 'brew install create-dmg'."

IDENTITIES="$(security find-identity -v -p codesigning)"
[[ "$IDENTITIES" == *"\"$APP_CERT_ID\""* ]] \
    || die "signing certificate not found: $APP_CERT_ID"

if [[ $SKIP_NOTARIZE -eq 0 ]]; then
    xcrun notarytool history --keychain-profile "$NOTARY_KEYCHAIN_PROFILE" >/dev/null 2>&1 \
        || die "cannot use the notarytool profile '$NOTARY_KEYCHAIN_PROFILE'. Create it with 'xcrun notarytool store-credentials'."
fi

# libntfs-3g and wimlib are built from the submodules. A missing or moved submodule would ship
# binaries that do not match the recorded source.
SUBMODULES="$(git -C "$SRCROOT" submodule status)"
while IFS= read -r line; do
    [[ -z "$line" || "$line" == " "* ]] \
        || die "submodule not at its recorded commit (run 'git submodule update --init'): $line"
done <<< "$SUBMODULES"

echo "  create-dmg    $(create-dmg --version 2>&1 | head -1)"
echo "  certificate   $APP_CERT_ID"
echo "  notarization  $([[ $SKIP_NOTARIZE -eq 1 ]] && echo 'skipped' || echo "$NOTARY_KEYCHAIN_PROFILE")"

rm -rf "$INTERMEDIATE_DIR"
mkdir -p "$INTERMEDIATE_DIR" "$EXPORT_PATH" "$DIST_DIR"

# ==============================================================================
# 1. Archive
#
# The hardened runtime comes from the project (ENABLE_HARDENED_RUNTIME). Notarization requires it,
# and it is not overridden here: the release must be signed the way an Xcode build is.
#
# The private DerivedData also keeps the archive away from the shared Debug products, whose helper
# binary may be the one a running daemon was started from.
# ==============================================================================

step "Archive"

run_xcodebuild "$INTERMEDIATE_DIR/archive.log" \
    -workspace "$WORKSPACE" \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    -archivePath "$ARCHIVE_PATH" \
    archive

# ==============================================================================
# 2. Export
#
# Neither the app nor the daemon has entitlements that need a provisioning profile. Export re-signs
# the daemon in Contents/MacOS with the Developer ID as well (CodeSignOnCopy on "Embed Helper").
# ==============================================================================

step "Export"

cat > "$INTERMEDIATE_DIR/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>$TEAM_ID</string>
    <key>signingCertificate</key>
    <string>$APP_CERT_ID</string>
</dict>
</plist>
EOF

run_xcodebuild "$INTERMEDIATE_DIR/export.log" \
    -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportOptionsPlist "$INTERMEDIATE_DIR/ExportOptions.plist" \
    -exportPath "$EXPORT_PATH" \
    -allowProvisioningUpdates

APP_PATH="$EXPORT_PATH/$APP_NAME.app"
[[ -d "$APP_PATH" ]] || die "the export has no $APP_NAME.app: $EXPORT_PATH"

# The version is read from the built bundle, not scraped from the pbxproj, which holds a
# MARKETING_VERSION for every target including the tests.
VERSION="$(plist_value "$APP_PATH/Contents/Info.plist" CFBundleShortVersionString)"
BUILD="$(plist_value "$APP_PATH/Contents/Info.plist" CFBundleVersion)"

GIT_TAG="$(git -C "$SRCROOT" rev-parse --short HEAD)"
if [[ -n "$(git -C "$SRCROOT" status --porcelain)" ]]; then
    GIT_TAG="$GIT_TAG-dirty"
fi

FINAL_DMG="$DIST_DIR/snakestick-signed-$VERSION-$GIT_TAG-RELEASE.dmg"

echo "  version       $VERSION ($BUILD), $GIT_TAG"
echo "  output        $FINAL_DMG"

# ==============================================================================
# 3. Bundle check
#
# Things that break only in the released app, caught before anything is submitted.
# ==============================================================================

step "Bundle check"

HELPER_PATH="$APP_PATH/Contents/MacOS/$HELPER_NAME"
[[ -x "$HELPER_PATH" ]] || die "the daemon is missing: $HELPER_PATH"

# SMAppService starts the program the plist names, relative to the app bundle.
[[ -f "$APP_PATH/$HELPER_PLIST" ]] || die "the launchd plist is missing: $HELPER_PLIST"
BUNDLE_PROGRAM="$(plist_value "$APP_PATH/$HELPER_PLIST" BundleProgram)"
[[ -x "$APP_PATH/$BUNDLE_PROGRAM" ]] \
    || die "the launchd plist's BundleProgram does not exist in the bundle: $BUNDLE_PROGRAM"
echo "  daemon        $BUNDLE_PROGRAM"

check_signature "$APP_PATH" "$APP_BUNDLE_ID"
check_signature "$HELPER_PATH" "$HELPER_BUNDLE_ID"
echo "  signature     Developer ID ($TEAM_ID), hardened runtime, app and daemon"

# The app reconnects when the daemon reports a version other than its own (HelperClient
# .checkVersion), so a version bumped in one target only would leave the app unable to write.
extract_embedded_info_plist "$HELPER_PATH" "$INTERMEDIATE_DIR/$HELPER_NAME-Info.plist"
HELPER_VERSION="$(plist_value "$INTERMEDIATE_DIR/$HELPER_NAME-Info.plist" CFBundleShortVersionString)"
HELPER_BUILD="$(plist_value "$INTERMEDIATE_DIR/$HELPER_NAME-Info.plist" CFBundleVersion)"
[[ "$HELPER_VERSION" == "$VERSION" && "$HELPER_BUILD" == "$BUILD" ]] \
    || die "the daemon is version $HELPER_VERSION ($HELPER_BUILD), the app $VERSION ($BUILD); set MARKETING_VERSION and CURRENT_PROJECT_VERSION on both targets"
echo "  daemon version $HELPER_VERSION ($HELPER_BUILD)"

# The boot loaders are Microsoft-signed binaries; the bundled copies must be the checked-in ones.
UEFI_NTFS_BUNDLED="$APP_PATH/$RESOURCE_BUNDLE/Contents/Resources/UEFI-NTFS"
[[ -d "$UEFI_NTFS_BUNDLED" ]] || die "the UEFI:NTFS resources are missing: $UEFI_NTFS_BUNDLED"
diff -r "$UEFI_NTFS_SOURCE" "$UEFI_NTFS_BUNDLED" >/dev/null \
    || die "the bundled UEFI:NTFS files differ from $UEFI_NTFS_SOURCE"
echo "  UEFI:NTFS     same as the source"

echo "  architectures app: $(lipo -archs "$APP_PATH/Contents/MacOS/$APP_NAME"), daemon: $(lipo -archs "$HELPER_PATH")"

# ==============================================================================
# 4. App notarization
#
# Stapling only the DMG puts the ticket on the DMG alone. When the user copies the app to
# /Applications and opens it, Gatekeeper then looks the app up online and warns if there is no
# connection. One more submission avoids that.
# ==============================================================================

if [[ $SKIP_NOTARIZE -eq 0 ]]; then
    step "App notarization"
    notarize_app "$APP_PATH"
else
    step "App notarization — skipped"
fi

# ==============================================================================
# 5. DMG
#
# create-dmg returns 2 for non-fatal errors such as failing to set the background.
# ==============================================================================

step "DMG"

DMG_STAGING="$INTERMEDIATE_DIR/dmg-staging"
mkdir -p "$DMG_STAGING"
cp -a "$APP_PATH" "$DMG_STAGING/"

rm -f "$FINAL_DMG"

set +e
create-dmg \
    --volname "$APP_NAME" \
    --window-pos 200 120 \
    --window-size 660 432 \
    --icon-size 128 \
    --icon "$APP_NAME.app" 180 200 \
    --hide-extension "$APP_NAME.app" \
    --app-drop-link 480 200 \
    "$FINAL_DMG" \
    "$DMG_STAGING"
CREATE_DMG_EXIT=$?
set -e

if [[ $CREATE_DMG_EXIT -ne 0 && $CREATE_DMG_EXIT -ne 2 ]]; then
    die "create-dmg failed (exit $CREATE_DMG_EXIT)"
fi

codesign --force --sign "$APP_CERT_ID" --timestamp "$FINAL_DMG"

# ==============================================================================
# 6. DMG notarization
# ==============================================================================

if [[ $SKIP_NOTARIZE -eq 0 ]]; then
    step "DMG notarization"
    notarize_file "$FINAL_DMG"
else
    step "DMG notarization — skipped"
fi

# ==============================================================================
# 7. Verification
# ==============================================================================

step "Verification"

codesign --verify --deep --strict "$APP_PATH"
echo "  signature     valid"

if [[ $SKIP_NOTARIZE -eq 0 ]]; then
    spctl --assess --type exec -v "$APP_PATH"
    spctl --assess --type open --context context:primary-signature -v "$FINAL_DMG"
else
    echo "  Gatekeeper    skipped (rejected is expected without notarization)"
fi

echo
echo "✅ Done"
echo "   $FINAL_DMG"
