#!/usr/bin/env bash
# sync-config.sh — push agent config files to turnkeyintern/config (private)
# Run after any update to MEMORY.md, TOOLS.md, SOUL.md, USER.md, IDENTITY.md, AGENTS.md, HEARTBEAT.md

set -e

WORKSPACE="/home/vercel-sandbox/.openclaw/workspace"
CONFIG_DIR="/tmp/turnkey-config"
PAT_FILE="$WORKSPACE/MEMORY.md"

# Extract PAT from MEMORY.md
PAT=$(grep -o 'github_pat_[A-Za-z0-9_]*' "$PAT_FILE" | head -1)
if [ -z "$PAT" ]; then
  echo "ERROR: Could not find PAT in MEMORY.md"
  exit 1
fi

# Clone or update the config repo
if [ ! -d "$CONFIG_DIR/.git" ]; then
  echo "Cloning turnkeyintern/config..."
  git clone "https://${PAT}@github.com/turnkeyintern/config.git" "$CONFIG_DIR"
else
  git -C "$CONFIG_DIR" remote set-url origin "https://${PAT}@github.com/turnkeyintern/config.git"
  git -C "$CONFIG_DIR" pull --rebase origin main 2>/dev/null || true
fi

# Copy config files
for file in MEMORY.md TOOLS.md SOUL.md USER.md IDENTITY.md AGENTS.md HEARTBEAT.md; do
  if [ -f "$WORKSPACE/$file" ]; then
    cp "$WORKSPACE/$file" "$CONFIG_DIR/$file"
  fi
done

# Commit and push
cd "$CONFIG_DIR"
git config user.email "agent@turnkeyintern.dev"
git config user.name "Turnkey Agent"
git add .
if git diff --cached --quiet; then
  echo "Nothing changed — config is already up to date."
else
  git commit -m "Config sync $(date -u '+%Y-%m-%d %H:%M UTC')"
  git push origin main
  echo "✓ Config synced to github.com/turnkeyintern/config"
fi
