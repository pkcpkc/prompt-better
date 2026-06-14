# Publishing to PyPI

Here is the quick guide to build, test, and publish `prompt-better` to PyPI.

## Prerequisites
Ensure your environment is set up and activated via `mise`:
```bash
# Verify uv is available
mise exec -- uv --version
```

---

## 1. Test
Always run the test suite and ensure all tests pass before building:
```bash
mise exec -- pytest
```

---

## 2. Build
Clean up old distributions and build the package (wheel and source distribution):
```bash
# Clean previous builds
rm -rf dist/ build/ *.egg-info

# Build using uv
mise exec -- uv build
```

---

## 3. Upload to TestPyPI (Optional but Recommended)
Test the upload and installation from the TestPyPI registry.

### Upload:
```bash
# Upload to TestPyPI (requires TestPyPI token / credentials)
mise exec -- uv publish --publish-url https://test.pypi.org/legacy/
```

### Test Install:
```bash
# Install from TestPyPI in a new temporary environment
uv pip install --index-url https://test.pypi.org/simple/ --extra-index-url https://pypi.org/simple/ prompt-better
```

---

## 4. Publish to PyPI
Once verified, upload the release candidate to the live PyPI registry:
```bash
# Upload to PyPI (requires PyPI API token)
mise exec -- uv publish
```
