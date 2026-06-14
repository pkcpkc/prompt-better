#!/bin/bash
# Shell script to validate, optimize, and convert the optimized JSON prompt specification to Swift.
set -e


# macOS Keychain configurations:
# For security, API keys cannot be stored in the prompt-better.json file.
# To automate API key resolution when running this script, you can store your API keys in the macOS Keychain
# and configure the service and account names below.
# The script will try to load the keys from the keychain.

# Student Keychain Settings
STUDENT_KEYCHAIN_SERVICE="oMLX"
STUDENT_KEYCHAIN_ACCOUNT="API Key"

# Teacher Keychain Settings
TEACHER_KEYCHAIN_SERVICE="oMLX"
TEACHER_KEYCHAIN_ACCOUNT="API Key"

# Get the absolute path to the repository root directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPO_ROOT="$( dirname "$SCRIPT_DIR" )"

cd "$REPO_ROOT"

# Determine the appropriate python command
if command -v mise &> /dev/null; then
    PYTHON_CMD=(mise exec -- python3)
else
    PYTHON_CMD=(python3)
fi

# Resolve student base URL: Environment variable > prompt-better.json config file
if [ -z "${PROMPT_BETTER_STUDENT_BASE_URL:-}" ]; then
    if [ -f "example/prompt-better.json" ]; then
        PROMPT_BETTER_STUDENT_BASE_URL=$("${PYTHON_CMD[@]}" -c "import json; print(json.load(open('example/prompt-better.json')).get('student', {}).get('base_url', ''))")
    fi
fi
export PROMPT_BETTER_STUDENT_BASE_URL

# Trap exit to ensure background macOS bridge process is terminated (safety fallback for early failures)
BRIDGE_PID=""
cleanup() {
    local exit_status=$?
    if [ -n "$BRIDGE_PID" ]; then
        echo ""
        echo "Stopping macOS bridge (PID $BRIDGE_PID)..."
        kill "$BRIDGE_PID" 2>/dev/null || true
        wait "$BRIDGE_PID" 2>/dev/null || true
    fi
    if [ "$exit_status" -eq 0 ]; then
        if [ -f "$REPO_ROOT/AIBridges/macOS/bridge.log" ]; then
            rm -f "$REPO_ROOT/AIBridges/macOS/bridge.log"
        fi
    else
        echo "Script failed. Preserving macOS bridge log at AIBridges/macOS/bridge.log"
    fi
}
trap cleanup EXIT

# Helper function to look up API keys in macOS Keychain
get_keychain_key() {
    local service_name="$1"
    local account_name="$2"
    local val=""
    if command -v security &>/dev/null; then
        val=$(security find-generic-password -s "$service_name" -w 2>/dev/null || true)
        if [ -z "$val" ]; then
            val=$(security find-generic-password -s "prompt-better" -a "$account_name" -w 2>/dev/null || true)
        fi
    fi
    echo "$val"
}

# Resolve API keys: Environment variable > macOS Keychain > Fail
if [ -z "${PROMPT_BETTER_STUDENT_API_KEY:-}" ]; then
    KEYCHAIN_VAL=$(get_keychain_key "$STUDENT_KEYCHAIN_SERVICE" "$STUDENT_KEYCHAIN_ACCOUNT")
    if [ -n "$KEYCHAIN_VAL" ]; then
        export PROMPT_BETTER_STUDENT_API_KEY="$KEYCHAIN_VAL"
        echo "Loaded PROMPT_BETTER_STUDENT_API_KEY from macOS Keychain."
    else
        echo "Error: PROMPT_BETTER_STUDENT_API_KEY not found in environment or macOS Keychain (Service: $STUDENT_KEYCHAIN_SERVICE, Account: $STUDENT_KEYCHAIN_ACCOUNT)." >&2
        exit 1
    fi
fi

if [ -z "${PROMPT_BETTER_TEACHER_API_KEY:-}" ]; then
    KEYCHAIN_VAL=$(get_keychain_key "$TEACHER_KEYCHAIN_SERVICE" "$TEACHER_KEYCHAIN_ACCOUNT")
    if [ -n "$KEYCHAIN_VAL" ]; then
        export PROMPT_BETTER_TEACHER_API_KEY="$KEYCHAIN_VAL"
        echo "Loaded PROMPT_BETTER_TEACHER_API_KEY from macOS Keychain."
    else
        echo "Warning: PROMPT_BETTER_TEACHER_API_KEY not found in environment or macOS Keychain."
        echo "Step 1 (baseline validation) will still run (needs student model only)."
        echo "Step 2 & 3 (optimization & conversion) will be skipped."
    fi
fi

echo "Using Python command: ${PYTHON_CMD[*]}"

# Check if local bridge is running, start it if missing
HEALTH_URL="${PROMPT_BETTER_STUDENT_BASE_URL%/v1}/health"
if [[ "$PROMPT_BETTER_STUDENT_BASE_URL" == *"localhost"* || "$PROMPT_BETTER_STUDENT_BASE_URL" == *"127.0.0.1"* ]] && ! curl -s -f --connect-timeout 2 "$HEALTH_URL" > /dev/null; then
    # Parse host and port from student base URL
    HOST="localhost"
    PORT="8080"
    if [[ "$PROMPT_BETTER_STUDENT_BASE_URL" =~ ://([^:/]+):([0-9]+) ]]; then
        HOST="${BASH_REMATCH[1]}"
        PORT="${BASH_REMATCH[2]}"
    fi
    echo "Local bridge server not active. Building and starting macOS bridge on $HOST:$PORT..."
    (cd "$REPO_ROOT/AIBridges/macOS" && swift build -c debug > /dev/null 2>&1)
    LOG_FILE="$REPO_ROOT/AIBridges/macOS/bridge.log"
    
    # Start the bridge server in the background
    "$REPO_ROOT/AIBridges/macOS/.build/debug/App" serve --hostname "$HOST" --port "$PORT" > "$LOG_FILE" 2>&1 &
    BRIDGE_PID=$!
    
    # Poll the health endpoint until it is responsive
    ATTEMPTS=0
    while ! curl -s -f --connect-timeout 1 "$HEALTH_URL" > /dev/null; do
        sleep 0.5
        ATTEMPTS=$((ATTEMPTS + 1))
        if [ "$ATTEMPTS" -ge 20 ]; then
            echo "Error: macOS bridge failed to start."
            [ -f "$LOG_FILE" ] && cat "$LOG_FILE"
            exit 1
        fi
    done
    echo "macOS bridge started successfully (PID: $BRIDGE_PID)."
    echo ""
fi

echo "Step 1: Running baseline validation for TopicClassifierPrompt..."
"${PYTHON_CMD[@]}" -m prompt_better.cli validate \
  --prompts-dir example/prompts \
  --prompt TopicClassifierPrompt \
  --no-requires-permission-to-run

if [ -n "${PROMPT_BETTER_TEACHER_API_KEY:-}" ]; then
    echo ""
    echo "Step 2: Running optimization for TopicClassifierPrompt..."
    # Optimize the prompt. The optimizer mode is configured in example/prompt-better.json as "optimizer": "predict".
    # This compiles with dspy.Predict, which is required for macOS/iOS schema-guided structured outputs.
    "${PYTHON_CMD[@]}" -m prompt_better.cli optimize \
      --prompts-dir example/prompts \
      --prompt TopicClassifierPrompt \
      --no-requires-permission-to-run

    echo ""
    echo "Step 3: Converting optimized JSON prompt specification to Swift..."
    "${PYTHON_CMD[@]}" -m prompt_better.cli generate \
      --source example/prompts/TopicClassifier/results/optimized-prompt.json \
      --target example/prompts/TopicClassifier/results/TopicClassifierPrompt.swift \
      --language swift

    # Clean up/stop the local bridge now that Step 3 is complete
    if [ -n "$BRIDGE_PID" ]; then
        echo ""
        echo "Stopping macOS bridge (PID $BRIDGE_PID)..."
        kill "$BRIDGE_PID" 2>/dev/null || true
        wait "$BRIDGE_PID" 2>/dev/null || true
        BRIDGE_PID=""
    fi

    echo ""
    echo "Successfully generated: example/prompts/TopicClassifier/results/TopicClassifierPrompt.swift"
else
    # Clean up/stop the local bridge now that Step 1 is complete
    if [ -n "$BRIDGE_PID" ]; then
        echo ""
        echo "Stopping macOS bridge (PID $BRIDGE_PID)..."
        kill "$BRIDGE_PID" 2>/dev/null || true
        wait "$BRIDGE_PID" 2>/dev/null || true
        BRIDGE_PID=""
    fi

    echo ""
    echo "Step 2 & 3 skipped because PROMPT_BETTER_TEACHER_API_KEY is not set."
fi
