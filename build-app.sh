#!/bin/bash

# DevWatch Build Script
# Compiles the macOS application for both Intel and Apple Silicon

set -e

echo "🔨 Building DevWatch..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Get the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_DIR="$SCRIPT_DIR"

# Build configuration
BUILD_DIR="$PROJECT_DIR/build"
SCHEME="DevWatch"
PROJECT="$PROJECT_DIR/DevWatch.xcodeproj"

# Create build directory if it doesn't exist
mkdir -p "$BUILD_DIR"

echo -e "${YELLOW}📁 Project directory: $PROJECT_DIR${NC}"
echo -e "${YELLOW}📁 Build directory: $BUILD_DIR${NC}"

# Clean previous builds
echo -e "${YELLOW}🧹 Cleaning previous builds...${NC}"
xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    clean 2>/dev/null || true

# Build for Release
echo -e "${YELLOW}🏗️  Building Release configuration...${NC}"
xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR" \
    -arch arm64 \
    -arch x86_64

# Check if build was successful
APP_PATH="$BUILD_DIR/Build/Products/Release/DevWatch.app"
if [ -d "$APP_PATH" ]; then
    echo -e "${GREEN}✅ Build successful!${NC}"
    echo -e "${GREEN}📦 App location: $APP_PATH${NC}"
    
    # Show app size
    APP_SIZE=$(du -sh "$APP_PATH" | cut -f1)
    echo -e "${GREEN}📊 App size: $APP_SIZE${NC}"
    
    # Check code signature
    if codesign -v "$APP_PATH" 2>/dev/null; then
        echo -e "${GREEN}✅ Code signature verified${NC}"
    else
        echo -e "${YELLOW}⚠️  App is not code signed${NC}"
    fi
else
    echo -e "${RED}❌ Build failed! App not found at: $APP_PATH${NC}"
    exit 1
fi

echo -e "${GREEN}🎉 Build complete!${NC}"
