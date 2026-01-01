#!/bin/bash
set -e

# Configuration
APP_NAME="Lan Lens"
DMG_NAME="LanLens"
VERSION="${1:-1.0.0}"

# Paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
OUTPUT_DIR="$PROJECT_ROOT/releases"
DMG_TEMP="/tmp/dmg-build-$$"
DMG_FILE="$OUTPUT_DIR/${DMG_NAME}-${VERSION}.dmg"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}═══════════════════════════════════════════${NC}"
echo -e "${BLUE}  Lan Lens DMG Creator${NC}"
echo -e "${BLUE}═══════════════════════════════════════════${NC}"
echo ""

# Check for app path argument or find it
if [ -n "$2" ]; then
    APP_PATH="$2"
elif [ -d "$PROJECT_ROOT/$APP_NAME.app" ]; then
    APP_PATH="$PROJECT_ROOT/$APP_NAME.app"
elif [ -d "$HOME/Desktop/$APP_NAME.app" ]; then
    APP_PATH="$HOME/Desktop/$APP_NAME.app"
else
    echo -e "${RED}Error: Cannot find '$APP_NAME.app'${NC}"
    echo ""
    echo "Usage: $0 [version] [path/to/app]"
    echo ""
    echo "Examples:"
    echo "  $0 1.0.0 ~/Desktop/Lan\\ Lens.app"
    echo "  $0 1.0.0 /path/to/exported/Lan\\ Lens.app"
    exit 1
fi

# Verify app exists
if [ ! -d "$APP_PATH" ]; then
    echo -e "${RED}Error: App not found at: $APP_PATH${NC}"
    exit 1
fi

echo -e "App path:    ${GREEN}$APP_PATH${NC}"
echo -e "Version:     ${GREEN}$VERSION${NC}"
echo -e "Output:      ${GREEN}$DMG_FILE${NC}"
echo ""

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Clean up any previous temp directory
rm -rf "$DMG_TEMP"
mkdir -p "$DMG_TEMP"

echo -e "${BLUE}[1/4]${NC} Copying app..."
cp -R "$APP_PATH" "$DMG_TEMP/"

echo -e "${BLUE}[2/4]${NC} Creating Applications symlink..."
ln -s /Applications "$DMG_TEMP/Applications"

echo -e "${BLUE}[3/4]${NC} Creating DMG..."
# Remove existing DMG if present
rm -f "$DMG_FILE"

hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$DMG_TEMP" \
    -ov \
    -format UDZO \
    "$DMG_FILE"

echo -e "${BLUE}[4/5]${NC} Cleaning up..."
rm -rf "$DMG_TEMP"

echo ""
echo -e "${GREEN}═══════════════════════════════════════════${NC}"
echo -e "${GREEN}  DMG created successfully!${NC}"
echo -e "${GREEN}═══════════════════════════════════════════${NC}"
echo ""
echo -e "Location: ${BLUE}$DMG_FILE${NC}"
echo ""

# GitHub Release
TAG="v$VERSION"
DMG_FILENAME="${DMG_NAME}-${VERSION}.dmg"

echo -e "${BLUE}[5/5]${NC} Publishing to GitHub..."

# Check if release exists
if gh release view "$TAG" &>/dev/null; then
    echo -e "Release ${GREEN}$TAG${NC} exists. Updating..."

    # Delete existing DMG asset if present
    if gh release view "$TAG" --json assets --jq '.assets[].name' | grep -q "^${DMG_FILENAME}$"; then
        echo "  Removing old $DMG_FILENAME..."
        gh release delete-asset "$TAG" "$DMG_FILENAME" --yes
    fi

    # Upload new DMG
    echo "  Uploading new $DMG_FILENAME..."
    gh release upload "$TAG" "$DMG_FILE"
else
    echo -e "Creating new release ${GREEN}$TAG${NC}..."
    gh release create "$TAG" "$DMG_FILE" --title "Lan Lens $VERSION" --generate-notes
fi

echo ""
echo -e "${GREEN}═══════════════════════════════════════════${NC}"
echo -e "${GREEN}  Release published!${NC}"
echo -e "${GREEN}═══════════════════════════════════════════${NC}"
echo ""
echo -e "View release: ${BLUE}https://github.com/eovidiu/LanLens/releases/tag/$TAG${NC}"
echo ""
