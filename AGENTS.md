# Agent Instructions for prompt-better

Welcome, Agent! Below are instructions and guidelines for working in the `prompt-better` codebase.

## Environment & Tool Usage

We use **`mise`** (formerly `rtx`) to manage the development environment (Python `3.11`, `uv` package manager).

### Running Commands

When executing Python, `uv`, or test commands, prefix them with `mise exec` to ensure the correct workspace environment is used:

```bash
# Example: Install/update dependencies
mise exec -- uv pip install -e .

# Example: Run prompt optimization
mise exec -- python -m prompt_better.cli optimize ...
```

Alternatively, ensure your shell is activated with `mise` (e.g., via `eval "$(mise activate zsh)"`).
