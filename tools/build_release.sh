#!/usr/bin/env bash
# =============================================================================
# build_release.sh — SynologyNotesEnhanced store release builder
#
# Run from the project root on macOS to produce App Store / Play Store builds.
# Output is written to ~/Downloads/SynologyNotesEnhanced_<date>/
#
# Usage:
#   ./scripts/build_release.sh              # build all platforms
#   ./scripts/build_release.sh --clean      # flutter clean first
#   ./scripts/build_release.sh ios macos    # specific platforms only
#
# Platforms: ios  macos  android  (windows is noted but requires Windows)
#
# Notes:
#   • The Wear OS app in android/wearapp/ is bundled automatically in the .aab
#   • Windows builds must be done on a Windows machine (see Windows/BUILD_ON_WINDOWS.md)
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

DATE=$(date +"%Y-%m-%d_%H%M")
OUTPUT_BASE="$HOME/Downloads/SynologyNotesEnhanced_$DATE"

IOS_EXPORT_OPTIONS="$SCRIPT_DIR/ios_export_options.plist"
MACOS_EXPORT_OPTIONS="$SCRIPT_DIR/macos_export_options.plist"

# Xcode workspace / scheme names (Flutter default)
IOS_WORKSPACE="$PROJECT_ROOT/ios/Runner.xcworkspace"
MACOS_WORKSPACE="$PROJECT_ROOT/macos/Runner.xcworkspace"
XCODE_SCHEME="Runner"

# ── Colours ───────────────────────────────────────────────────────────────────

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'

step()  { echo -e "\n${BLUE}${BOLD}▶  $1${NC}"; }
ok()    { echo -e "   ${GREEN}✓  $1${NC}"; }
warn()  { echo -e "   ${YELLOW}⚠  $1${NC}"; }
fail()  { echo -e "\n${RED}✗  $1${NC}\n"; exit 1; }
banner(){ echo -e "\n${BOLD}$1${NC}"; }

# ── Argument parsing ──────────────────────────────────────────────────────────

DO_CLEAN=false
BUILD_IOS=false
BUILD_MACOS=false
BUILD_ANDROID=false
EXPLICIT_TARGETS=false

for arg in "$@"; do
  case "$arg" in
    --clean|-c) DO_CLEAN=true ;;
    ios)        BUILD_IOS=true;     EXPLICIT_TARGETS=true ;;
    macos)      BUILD_MACOS=true;   EXPLICIT_TARGETS=true ;;
    android)    BUILD_ANDROID=true; EXPLICIT_TARGETS=true ;;
    *)          warn "Unknown argument: $arg" ;;
  esac
done

# Default: build everything if no explicit targets supplied
if [ "$EXPLICIT_TARGETS" = false ]; then
  BUILD_IOS=true
  BUILD_MACOS=true
  BUILD_ANDROID=true
fi

# ── Prerequisites ─────────────────────────────────────────────────────────────

banner "SynologyNotesEnhanced — Release Build"
echo "   Output → $OUTPUT_BASE"

step "Checking prerequisites..."

command -v flutter    >/dev/null 2>&1 || fail "flutter not found — ensure Flutter SDK is in your PATH"
command -v xcodebuild >/dev/null 2>&1 || fail "xcodebuild not found — install Xcode from the App Store"

FLUTTER_VERSION=$(flutter --version --machine 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('frameworkVersion','?'))" 2>/dev/null || echo "unknown")
ok "Flutter $FLUTTER_VERSION"

# Print the app version from pubspec.yaml for confirmation
APP_VERSION=$(grep '^version:' "$PROJECT_ROOT/pubspec.yaml" | awk '{print $2}')
ok "App version: $APP_VERSION"

# Optional: xcpretty for nicer xcodebuild output
if command -v xcpretty >/dev/null 2>&1; then
  PRETTY="xcpretty"
else
  PRETTY="cat"
fi

cd "$PROJECT_ROOT"

# ── Output directories ────────────────────────────────────────────────────────

mkdir -p "$OUTPUT_BASE/iOS"
mkdir -p "$OUTPUT_BASE/macOS"
mkdir -p "$OUTPUT_BASE/Android"
mkdir -p "$OUTPUT_BASE/Windows"

# ── Optional clean ────────────────────────────────────────────────────────────

if [ "$DO_CLEAN" = true ]; then
  step "Running flutter clean..."
  flutter clean
  ok "Clean complete"
fi

# ── Flutter pub get ───────────────────────────────────────────────────────────

step "Fetching Flutter dependencies..."
flutter pub get
ok "Dependencies up to date"

# ── Track results ─────────────────────────────────────────────────────────────

RESULTS=()

# =============================================================================
# Android — Play Store .aab  (includes Wear OS bundle automatically)
# =============================================================================

if [ "$BUILD_ANDROID" = true ]; then
  step "Android — building Play Store .aab (includes Wear OS)..."

  if flutter build appbundle --release; then
    AAB="$PROJECT_ROOT/build/app/outputs/bundle/release/app-release.aab"
    if [ -f "$AAB" ]; then
      cp "$AAB" "$OUTPUT_BASE/Android/app-release.aab"
      ok "app-release.aab  →  $OUTPUT_BASE/Android/"
      RESULTS+=("Android:  ✓  app-release.aab  (v$APP_VERSION, Wear OS bundled)")
    else
      warn "Build succeeded but .aab not found at expected path"
      RESULTS+=("Android:  ⚠  build ok but file missing")
    fi
  else
    warn "Android build failed — check output above"
    RESULTS+=("Android:  ✗  build failed")
  fi
fi

# =============================================================================
# iOS — App Store .ipa
# =============================================================================

if [ "$BUILD_IOS" = true ]; then
  step "iOS — building App Store .ipa..."

  if flutter build ipa --release --export-options-plist "$IOS_EXPORT_OPTIONS" 2>&1 | $PRETTY; then
    IPA=$(find "$PROJECT_ROOT/build/ios/ipa" -name "*.ipa" 2>/dev/null | head -1)
    if [ -n "$IPA" ]; then
      cp "$IPA" "$OUTPUT_BASE/iOS/"
      ok "$(basename "$IPA")  →  $OUTPUT_BASE/iOS/"
      RESULTS+=("iOS:      ✓  $(basename "$IPA")  (v$APP_VERSION)")
    else
      warn "flutter build ipa succeeded but no .ipa found — check export options and signing"
      RESULTS+=("iOS:      ⚠  build ok but .ipa missing (signing?)")
    fi
  else
    warn "iOS build failed — check signing certificates and provisioning profiles"
    RESULTS+=("iOS:      ✗  build failed")
  fi
fi

# =============================================================================
# macOS — Mac App Store .pkg
# =============================================================================

if [ "$BUILD_MACOS" = true ]; then
  step "macOS — archiving for Mac App Store..."

  MACOS_ARCHIVE="$PROJECT_ROOT/build/macos_archive.xcarchive"

  # Archive
  ARCHIVE_OK=false
  if xcodebuild archive \
      -workspace "$MACOS_WORKSPACE" \
      -scheme "$XCODE_SCHEME" \
      -configuration Release \
      -archivePath "$MACOS_ARCHIVE" \
      2>&1 | $PRETTY; then
    ARCHIVE_OK=true
    ok "Archive created"
  else
    warn "macOS archive step failed — check signing and provisioning"
    RESULTS+=("macOS:    ✗  archive failed")
  fi

  if [ "$ARCHIVE_OK" = true ]; then
    step "macOS — exporting .pkg for App Store..."
    if xcodebuild -exportArchive \
        -archivePath "$MACOS_ARCHIVE" \
        -exportPath "$OUTPUT_BASE/macOS" \
        -exportOptionsPlist "$MACOS_EXPORT_OPTIONS" \
        2>&1 | $PRETTY; then
      PKG=$(find "$OUTPUT_BASE/macOS" -name "*.pkg" 2>/dev/null | head -1)
      if [ -n "$PKG" ]; then
        ok "$(basename "$PKG")  →  $OUTPUT_BASE/macOS/"
        RESULTS+=("macOS:    ✓  $(basename "$PKG")  (v$APP_VERSION)")
      else
        warn "Export succeeded but no .pkg found — check export options"
        RESULTS+=("macOS:    ⚠  export ok but .pkg missing")
      fi
    else
      warn "macOS export failed — check export options plist and signing"
      RESULTS+=("macOS:    ✗  export failed")
    fi
  fi
fi

# =============================================================================
# Windows — instructions only (requires Windows machine)
# =============================================================================

cat > "$OUTPUT_BASE/Windows/BUILD_ON_WINDOWS.md" << 'WINEOF'
# Windows Build — Must Be Done on a Windows Machine

Flutter Windows apps cannot be cross-compiled from macOS.

## Steps (on a Windows machine with Flutter installed):

### 1. Build the release binary
```
flutter pub get
flutter build windows --release
```
Output: `build\windows\x64\runner\Release\`

### 2. Package as MSIX for Microsoft Store

Add the `msix` package if not already in pubspec.yaml:
```
flutter pub add --dev msix
```

Configure MSIX metadata in `pubspec.yaml` (publisher display name, identity name,
publisher ID from Partner Center), then run:
```
flutter pub run msix:create
```
Output: a `.msix` file ready to upload to Microsoft Partner Center.

### 3. Submit
Upload the `.msix` to https://partner.microsoft.com/dashboard

## Requirements
- Flutter SDK with Windows desktop enabled (`flutter config --enable-windows-desktop`)
- Visual Studio 2022 with "Desktop development with C++" workload
- Code signing certificate from a trusted CA (required for Store distribution)
WINEOF

RESULTS+=("Windows:  —  see BUILD_ON_WINDOWS.md")

# =============================================================================
# Summary
# =============================================================================

echo ""
echo -e "${BOLD}════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}  Build Summary — SynologyNotesEnhanced v$APP_VERSION${NC}"
echo -e "${BOLD}════════════════════════════════════════════════════${NC}"
for r in "${RESULTS[@]}"; do
  echo "  $r"
done
echo ""
echo "  Output folder: $OUTPUT_BASE"
echo -e "${BOLD}════════════════════════════════════════════════════${NC}"

# Open the output folder in Finder
open "$OUTPUT_BASE"
