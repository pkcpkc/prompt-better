#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$DIR"

BUILD_DIR="$DIR/build"
OUTPUT_XCFRAMEWORK="$BUILD_DIR/AIPromptCore.xcframework"

echo "Building AIPromptCore XCFramework..."

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
    SKIP_INSTALL=NO

# 2. Build for iOS Simulator
echo "Archiving for iOS Simulator..."
xcodebuild archive \
    -scheme AIPromptCore \
    -destination "generic/platform=iOS Simulator" \
    -archivePath "$BUILD_DIR/AIPromptCore-iOS_Simulator.xcarchive" \
    -derivedDataPath "$BUILD_DIR/DerivedData-Sim" \
    BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
    SKIP_INSTALL=NO

# Determine the internal framework path (varies based on SPM xcodebuild)
# xcodebuild places SPM dynamic library frameworks in Products/Library/Frameworks/ or Products/usr/local/lib
FRAMEWORK_IOS=$(find "$BUILD_DIR/AIPromptCore-iOS.xcarchive" -name "AIPromptCore.framework" | head -n 1)
FRAMEWORK_SIM=$(find "$BUILD_DIR/AIPromptCore-iOS_Simulator.xcarchive" -name "AIPromptCore.framework" | head -n 1)

if [ -z "$FRAMEWORK_IOS" ]; then
    echo "Error: Could not find AIPromptCore.framework in iOS archive."
    exit 1
fi

echo "Found iOS framework at: $FRAMEWORK_IOS"
echo "Found Sim framework at: $FRAMEWORK_SIM"

# Harvest swiftmodules from DerivedData and inject them into the .frameworks
# so the compiler can actually import the module.
echo "Injecting Swift modules..."
MOD_IOS=$(find "$BUILD_DIR/DerivedData-iOS" -type d -name "AIPromptCore.swiftmodule" | head -n 1)
MOD_SIM=$(find "$BUILD_DIR/DerivedData-Sim" -type d -name "AIPromptCore.swiftmodule" | head -n 1)

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

# Locate dSYMs inside the xcarchives
DSYM_IOS="$BUILD_DIR/AIPromptCore-iOS.xcarchive/dSYMs/AIPromptCore.framework.dSYM"
DSYM_SIM="$BUILD_DIR/AIPromptCore-iOS_Simulator.xcarchive/dSYMs/AIPromptCore.framework.dSYM"

# 3. Create XCFramework (with debug symbols so archives include the dSYM)
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
CREATE_ARGS+=(-output "$OUTPUT_XCFRAMEWORK")

xcodebuild -create-xcframework "${CREATE_ARGS[@]}"

echo "Success! XCFramework generated at $OUTPUT_XCFRAMEWORK"
