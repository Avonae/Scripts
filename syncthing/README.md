# Syncthing ignore patterns

Ignore lists for my Syncthing folders, kept here so every machine shares one
copy.

Syncthing stores a folder's ignore list in a `.stignore` file at the folder
root, and it never syncs that file between devices. Left alone, each machine
ends up with its own list and they drift apart. Keeping the list in this
repository and fetching it on every machine solves that without the
`#include` indirection Syncthing offers for the same problem.

One file per synced folder:

| File | Folder |
|------|--------|
| `stignore` | `my_files` |

## What it ignores

Mainly the machine-local half of `~/.claude`, which is synced as part of
`my_files`. Plugin caches, session transcripts and the OAuth token all carry
absolute paths or per-host state, so replicating them breaks plugin loading on
the other machine and copies credentials somewhere they cannot be revoked.
Portable configuration -- `CLAUDE.md`, `settings.json`, `agents/` -- keeps
syncing.

## How to use

Fetch it to the folder root:

```bash
curl -fsSL https://raw.githubusercontent.com/Avonae/Scripts/refs/heads/main/syncthing/stignore -o ~/my_files/.stignore
```

Syncthing picks the new list up on its next scan. Adding a pattern does not
delete what is already synced -- those copies stay where they are and simply
stop updating, so clean them up by hand.

Servers get this through the `docker_syncthing` Ansible role, which downloads
the file during the run. See `syncthing_stignore_url` in that role.
