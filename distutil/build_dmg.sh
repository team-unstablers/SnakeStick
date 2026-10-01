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
# The command line tool the app runs as root through osascript (InstallerRunner.swift), and the
# code signing identifier Xcode gives it (the SwiftPM product name).
CLI_PATH_IN_BUNDLE="Contents/Helpers/snakestick"
CLI_IDENTIFIER="snakestick"

RESOURCE_BUNDLE="Contents/Resources/SnakeStickCore_SnakeStickCore.bundle"
UEFI_NTFS_SOURCE="$SRCROOT/SnakeStickCore/Sources/SnakeStickCore/Resources/UEFI-NTFS"

APP_CERT_ID="Developer ID Application: team unstablers Inc. ($TEAM_ID)"

# A Developer ID Application leaf issued to our team. Notarization needs every executable in the
# bundle signed with it and the hardened runtime, so the app and the bundled tool are both checked.
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
# The private DerivedData also keeps the archive away from the shared Debug products, whose bundled
# tool may be the one a running write was started from.
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
# Neither the app nor the tool has entitlements that need a provisioning profile. Export re-signs
# the tool in Contents/Helpers and the package frameworks in Contents/Frameworks with the
# Developer ID as well (CodeSignOnCopy on "Embed Command Line Tool").
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

CLI_PATH="$APP_PATH/$CLI_PATH_IN_BUNDLE"
[[ -x "$CLI_PATH" ]] || die "the command line tool is missing: $CLI_PATH_IN_BUNDLE"
echo "  tool          $CLI_PATH_IN_BUNDLE"

check_signature "$APP_PATH" "$APP_BUNDLE_ID"
check_signature "$CLI_PATH" "$CLI_IDENTIFIER"
echo "  signature     Developer ID ($TEAM_ID), hardened runtime, app and tool"

# Linked into the app and the tool, the packages are frameworks in Contents/Frameworks. The tool
# finds them through @executable_path/../Frameworks (SnakeStickCore/Package.swift); Xcode also
# gives it an rpath into the build directory, which hides a missing framework on this machine.
CLI_RPATHS="$(otool -l "$CLI_PATH" | awk '$1 == "path" { print $2 }')"
grep -qx '@executable_path/../Frameworks' <<< "$CLI_RPATHS" \
    || die "the tool has no @executable_path/../Frameworks rpath: $(echo $CLI_RPATHS)"
while IFS= read -r library; do
    [[ -e "$APP_PATH/Contents/Frameworks/${library#@rpath/}" ]] \
        || die "the tool links $library, which is not in Contents/Frameworks"
done < <(otool -L "$CLI_PATH" | awk 'NR > 1 && $1 ~ /^@rpath\// { print $1 }')
echo "  tool links    Contents/Frameworks only"

# The boot loaders are Microsoft-signed binaries; the bundled copies must be the checked-in ones.
UEFI_NTFS_BUNDLED="$APP_PATH/$RESOURCE_BUNDLE/Contents/Resources/UEFI-NTFS"
[[ -d "$UEFI_NTFS_BUNDLED" ]] || die "the UEFI:NTFS resources are missing: $UEFI_NTFS_BUNDLED"
diff -r "$UEFI_NTFS_SOURCE" "$UEFI_NTFS_BUNDLED" >/dev/null \
    || die "the bundled UEFI:NTFS files differ from $UEFI_NTFS_SOURCE"
echo "  UEFI:NTFS     same as the source"

echo "  architectures app: $(lipo -archs "$APP_PATH/Contents/MacOS/$APP_NAME"), tool: $(lipo -archs "$CLI_PATH")"

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
