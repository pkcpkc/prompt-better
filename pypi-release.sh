#!/bin/bash

# Exit on error
set -e

echo "🔑 Retrieving PyPI API Token from macOS Keychain..."
# Retrieve password (using || true so set -e doesn't crash the script if the item is missing)
PYPI_TOKEN=$(security find-generic-password -s "PyPI Token" -w 2>/dev/null || true)

if [ -z "$PYPI_TOKEN" ]; then
    echo "❌ Error: Could not retrieve PyPI API Token from macOS Keychain."
    echo "Please ensure you have created a generic password item in Keychain Access with:"
    echo "  Keychain Item Name (Service): PyPI API Token"
    echo "  Password: <your-pypi-api-token>"
    exit 1
fi

echo "🧹 Cleaning up previous builds..."
rm -rf dist/ build/ *.egg-info

echo "📦 Building the latest package version..."
mise exec -- uv build

echo "🚀 Uploading to PyPI via Twine..."
export TWINE_USERNAME="__token__"
export TWINE_PASSWORD="$PYPI_TOKEN"

# Upload to PyPI
mise exec -- twine upload dist/*

echo "✅ Package uploaded successfully!"
