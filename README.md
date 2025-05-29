# Git Autopush Script

This script automatically commits and pushes changes from a local Git repository (e.g., a folder synced via Syncthing) to GitHub. It’s useful for versioning notes, documents, or any files that change frequently without manual Git usage.

## What it does

- Loads the repository path from a `.env` file and adds all changes including deletions
- Signs the commit with a GPG key (if configured)
- Uses the current date in the format `DD-MM-YYYY HH:MM:SS` as the commit message
- Rebases from the remote `origin/main` branch and pushes the result to GitHub

## How to use

### 1. Create `.env` file in the same directory as the script:

```env
REPO_PATH=/home/user/syncthing/Obsidian-vault
```

### 2. Make the script executable:

```bash
chmod +x push-to-github.sh
```

### 3. Run it manually:

```bash
./push-to-github.sh
```

### 4. (Optional) Automate with cron

To run the script every hour:

```bash
crontab -e
```

Add the following line:

```cron
0 * * * * /bin/bash "$HOME/git-autosave/push-to-github.sh" >> "$HOME/git-autosave.log" 2>&1
```
Don't forget to change "/path/to/push-to-github.sh" with your path.
