#!/bin/bash

# Load environment variables from .env file
source "$(dirname "$0")/.env"

# Check that REPO_PATH is defined
if [ -z "$REPO_PATH" ]; then
  echo "REPO_PATH is not defined in .env"
  exit 1
fi

# Navigate to the repository directory
cd "$REPO_PATH" || exit 1

# Set up GPG TTY for commit signing
export GPG_TTY=$(tty)

# Stage all changes (including deletions)
git add -A

# If there are staged changes, commit and push
if ! git diff --cached --quiet; then
    git commit -S -m "Autosync: $(date '+%d-%m-%Y %H:%M:%S')"
    git pull --rebase origin main
    git push origin main
else
    echo "No changes to commit ($(date '+%d.%m.%Y %H:%M'))"
fi
