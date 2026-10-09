#!/bin/bash

# DevWatch DMG Creation Script
# Creates a distribution DMG file with the compiled app

set -e

echo "📦 Creating DevWatch DMG..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Get the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_DIR="$SCRIPT_DIR"

# Configuration
BUILD_DIR="$PROJECT_DIR/build"
APP_PATH="$BUILD_DIR/Build/Products/Release/DevWatch.app"
DMG_NAME="DevWatch-1.0.dmg"
DMG_PATH="$PROJECT_DIR/$DMG_NAME"
TEMP_DMG_PATH="/tmp/DevWatch-temp.dmg"
MOUNT_POINT="/Volumes/DevWatch"

# Check if app exists
if [ ! -d "$APP_PATH" ]; then
    echo -e "${RED}❌ Error: App not found at $APP_PATH${NC}"
    echo -e "${YELLOW}💡 Run ./build-app.sh first${NC}"
    exit 1
fi

echo -e "${YELLOW}📁 App path: $APP_PATH${NC}"

# Clean up previous DMG if it exists
if [ -f "$DMG_PATH" ]; then
    echo -e "${YELLOW}🧹 Removing previous DMG...${NC}"
    rm -f "$DMG_PATH"
fi

# Unmount if already mounted
if [ -d "$MOUNT_POINT" ]; then
    echo -e "${YELLOW}🔓 Unmounting previous volume...${NC}"
    hdiutil detach "$MOUNT_POINT" 2>/dev/null || true
    sleep 1
fi

# Calculate DMG size (app size + 20% buffer)
APP_SIZE_MB=$(du -sm "$APP_PATH" | cut -f1)
DMG_SIZE_MB=$((APP_SIZE_MB + 150))

echo -e "${YELLOW}📏 DMG size: ${DMG_SIZE_MB}MB${NC}"

# Create temporary DMG
echo -e "${YELLOW}🔨 Creating temporary DMG...${NC}"
hdiutil create \
    -volname "DevWatch" \
    -srcfolder "$APP_PATH" \
    -ov \
    -format UDZO \
    -size "${DMG_SIZE_MB}m" \
    "$TEMP_DMG_PATH" \
    2>/dev/null

if [ ! -f "$TEMP_DMG_PATH" ]; then
    echo -e "${RED}❌ Failed to create DMG${NC}"
    exit 1
fi

# Move to final location
echo -e "${YELLOW}📝 Finalizing DMG...${NC}"
mv "$TEMP_DMG_PATH" "$DMG_PATH"

# Verify DMG
echo -e "${YELLOW}✔️  Verifying DMG...${NC}"
if hdiutil verify "$DMG_PATH" >/dev/null 2>&1; then
    DMG_SIZE=$(ls -lh "$DMG_PATH" | awk '{print $5}')
    echo -e "${GREEN}✅ DMG created successfully!${NC}"
    echo -e "${GREEN}📦 DMG location: $DMG_PATH${NC}"
    echo -e "${GREEN}📊 DMG size: $DMG_SIZE${NC}"
else
    echo -e "${RED}❌ DMG verification failed${NC}"
    rm -f "$DMG_PATH"
    exit 1
fi

echo -e "${GREEN}🎉 DMG creation complete!${NC}"
