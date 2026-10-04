#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$DIR"

BUILD_DIR="$DIR/build"
OUTPUT_XCFRAMEWORK="$BUILD_DIR/AIPromptCore.xcframework"

# Feature flags: default is WITHOUT speech support
ENABLE_SPEECH=0

for arg in "$@"; do
    case "$arg" in
        --with-speech|--enable-speech|-with-speech)
            ENABLE_SPEECH=1
            ;;
        --without-speech|--disable-speech)
            ENABLE_SPEECH=0
            ;;
        --help|-h)
            echo "Usage: ./build_xcframework.sh [options]"
            echo "Options:"
            echo "  --with-speech       Build with Speech.framework support (STT)"
            echo "  --without-speech    Build without Speech.framework support (default)"
            echo "  --help, -h          Show this help message"
            exit 0
            ;;
    esac
done

# Also support environment variables
if [ "${WITH_SPEECH:-0}" = "1" ] || [ "${AIPROMPT_ENABLE_SPEECH:-0}" = "1" ]; then
    ENABLE_SPEECH=1
fi

SWIFT_BUILD_SETTINGS=()
if [ "$ENABLE_SPEECH" = "1" ]; then
    echo "Building AIPromptCore Universal Multiplatform XCFramework (with Speech support)..."
    export ENABLE_SPEECH=1
    SWIFT_BUILD_SETTINGS+=("OTHER_SWIFT_FLAGS=\$(inherited) -DENABLE_SPEECH")
    SWIFT_BUILD_SETTINGS+=("SWIFT_ACTIVE_COMPILATION_CONDITIONS=\$(inherited) ENABLE_SPEECH")
else
    echo "Building AIPromptCore Universal Multiplatform XCFramework (default: without Speech support)..."
    export ENABLE_SPEECH=0
fi

# Clean up previous builds
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# 1. Build for iOS Device
echo "Archiving for iOS..."
xcodebuild archive \
    -scheme AIPromptCore \
    -destination "generic/platform=iOS" \
    -archivePath "$BUILD_DIR/AIPromptCore-iOS.xcarchive" \
    -derivedDataPath "$BUILD_DIR/DerivedData-iOS" \
    BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
    SKIP_INSTALL=NO \
    "${SWIFT_BUILD_SETTINGS[@]}"

# 2. Build for iOS Simulator
echo "Archiving for iOS Simulator..."
xcodebuild archive \
    -scheme AIPromptCore \
    -destination "generic/platform=iOS Simulator" \
    -archivePath "$BUILD_DIR/AIPromptCore-iOS_Simulator.xcarchive" \
    -derivedDataPath "$BUILD_DIR/DerivedData-Sim" \
    BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
    SKIP_INSTALL=NO \
    "${SWIFT_BUILD_SETTINGS[@]}"

# 3. Build for macOS
echo "Archiving for macOS..."
xcodebuild archive \
    -scheme AIPromptCore \
    -destination "generic/platform=macOS" \
    -archivePath "$BUILD_DIR/AIPromptCore-macOS.xcarchive" \
    -derivedDataPath "$BUILD_DIR/DerivedData-macOS" \
    BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
    SKIP_INSTALL=NO \
    "${SWIFT_BUILD_SETTINGS[@]}"

# Locate internal frameworks
FRAMEWORK_IOS=$(find "$BUILD_DIR/AIPromptCore-iOS.xcarchive" -name "AIPromptCore.framework" | head -n 1)
FRAMEWORK_SIM=$(find "$BUILD_DIR/AIPromptCore-iOS_Simulator.xcarchive" -name "AIPromptCore.framework" | head -n 1)
FRAMEWORK_MAC=$(find "$BUILD_DIR/AIPromptCore-macOS.xcarchive" -name "AIPromptCore.framework" | head -n 1)

if [ -z "$FRAMEWORK_IOS" ]; then
    echo "Error: Could not find AIPromptCore.framework in iOS archive."
    exit 1
fi

echo "Found iOS framework at: $FRAMEWORK_IOS"
echo "Found Sim framework at: $FRAMEWORK_SIM"
echo "Found macOS framework at: $FRAMEWORK_MAC"

# Inject swiftmodules
echo "Injecting Swift modules..."
MOD_IOS=$(find "$BUILD_DIR/DerivedData-iOS" -type d -name "AIPromptCore.swiftmodule" | head -n 1)
MOD_SIM=$(find "$BUILD_DIR/DerivedData-Sim" -type d -name "AIPromptCore.swiftmodule" | head -n 1)
MOD_MAC=$(find "$BUILD_DIR/DerivedData-macOS" -type d -name "AIPromptCore.swiftmodule" | head -n 1)

if [ -n "$MOD_IOS" ]; then
    mkdir -p "$FRAMEWORK_IOS/Modules"
    cp -R "$MOD_IOS" "$FRAMEWORK_IOS/Modules/"
    echo "Injected iOS modules from $MOD_IOS"
fi

if [ -n "$MOD_SIM" ]; then
    mkdir -p "$FRAMEWORK_SIM/Modules"
    cp -R "$MOD_SIM" "$FRAMEWORK_SIM/Modules/"
    echo "Injected Sim modules from $MOD_SIM"
fi

if [ -n "$MOD_MAC" ]; then
    mkdir -p "$FRAMEWORK_MAC/Modules"
    cp -R "$MOD_MAC" "$FRAMEWORK_MAC/Modules/"
    echo "Injected macOS modules from $MOD_MAC"
fi

# Locate dSYMs inside the xcarchives
DSYM_IOS="$BUILD_DIR/AIPromptCore-iOS.xcarchive/dSYMs/AIPromptCore.framework.dSYM"
DSYM_SIM="$BUILD_DIR/AIPromptCore-iOS_Simulator.xcarchive/dSYMs/AIPromptCore.framework.dSYM"
DSYM_MAC="$BUILD_DIR/AIPromptCore-macOS.xcarchive/dSYMs/AIPromptCore.framework.dSYM"

# 4. Create Universal XCFramework
echo "Creating XCFramework..."

CREATE_ARGS=()
CREATE_ARGS+=(-framework "$FRAMEWORK_IOS")
if [ -d "$DSYM_IOS" ]; then
    CREATE_ARGS+=(-debug-symbols "$DSYM_IOS")
    echo "Including iOS dSYM: $DSYM_IOS"
fi

CREATE_ARGS+=(-framework "$FRAMEWORK_SIM")
if [ -d "$DSYM_SIM" ]; then
    CREATE_ARGS+=(-debug-symbols "$DSYM_SIM")
    echo "Including Simulator dSYM: $DSYM_SIM"
fi

if [ -n "$FRAMEWORK_MAC" ]; then
    CREATE_ARGS+=(-framework "$FRAMEWORK_MAC")
    if [ -d "$DSYM_MAC" ]; then
        CREATE_ARGS+=(-debug-symbols "$DSYM_MAC")
        echo "Including macOS dSYM: $DSYM_MAC"
    fi
fi

CREATE_ARGS+=(-output "$OUTPUT_XCFRAMEWORK")

xcodebuild -create-xcframework "${CREATE_ARGS[@]}"

echo "Success! Universal XCFramework generated at $OUTPUT_XCFRAMEWORK"
