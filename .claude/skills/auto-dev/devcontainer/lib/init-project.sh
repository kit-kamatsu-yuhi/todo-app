#!/bin/bash
set -euo pipefail

echo "[init-project] Detecting project dependencies..."

# Global CLI tools detection from package.json
if [ -f "package.json" ]; then
    for pkg in tsx typescript drizzle-kit; do
        if jq -e ".dependencies[\"$pkg\"] // .devDependencies[\"$pkg\"]" package.json > /dev/null 2>&1; then
            if ! command -v "$pkg" > /dev/null 2>&1; then
                echo "[init-project] Installing global: $pkg"
                npm install -g "$pkg" 2>/dev/null || true
            fi
        fi
    done
fi

# Local dependencies - detect package manager from lockfile
if [ -f "pnpm-lock.yaml" ]; then
    echo "[init-project] Detected pnpm project"
    pnpm install --frozen-lockfile
elif [ -f "yarn.lock" ]; then
    if [ -f ".yarnrc.yml" ]; then
        echo "[init-project] Detected yarn (Berry) project"
        yarn install --immutable || yarn install
    else
        echo "[init-project] Detected yarn (Classic) project"
        yarn install --frozen-lockfile || yarn install
    fi
elif [ -f "package-lock.json" ]; then
    echo "[init-project] Detected npm project"
    npm ci
elif [ -f "bun.lockb" ] || [ -f "bun.lock" ]; then
    echo "[init-project] Detected bun project (fallback to npm)"
    npm install
fi

# Python project
if [ -f "pyproject.toml" ]; then
    echo "[init-project] Detected Python project"
    if command -v uv > /dev/null 2>&1; then
        uv sync 2>/dev/null || true
    elif [ -f "requirements.txt" ]; then
        pip install -r requirements.txt 2>/dev/null || true
    fi
fi

# Go project
if [ -f "go.mod" ]; then
    echo "[init-project] Detected Go project"
    go mod download 2>/dev/null || true
fi

echo "[init-project] Dependencies installed."
