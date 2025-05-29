# Git Autopush Script

This script automatically commits and pushes changes from a local Git repository (e.g., a folder synced via Syncthing) to GitHub. It’s useful for versioning notes, documents, or any files that change frequently without manual Git usage.

## What it does

- Loads the repository path from a `.env` file and adds all changes including deletions
- Signs the commit with a GPG key (if configured)
- Uses the current date in the format `DD-MM-YYYY HH:MM:SS` as the commit message
- Rebases from the remote `origin/main` branch and pushes the result to GitHub

## How to use
### Clone repo
```bash
git clone https://github.com/Avonae/Scripts.git "$HOME/Scripts"
```

Create `.env` file in the same directory as the script:

```env
echo 'REPO_PATH="$HOME/Scripts/"' > ~/Scripts/.env
```

Make the script executable:

```bash
chmod +x ~/Scripts/push-to-github.sh
```

### 3. Run it manually

```bash
~/Scripts/push-to-github.sh
```

### 4. (Optional) Automate with cron

To run the script every hour:

```bash
crontab -e
```

Add the following line:

```cron
0 * * * * /bin/bash "$HOME/Scripts/push-to-github.sh" >> "$HOME/Scripts/logs/git-autosave.log" 2>&1
```
