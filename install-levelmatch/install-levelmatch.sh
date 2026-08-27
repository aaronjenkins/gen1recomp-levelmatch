#!/usr/bin/env bash
# Install (or refresh) the level_match mod into the local gen1recomp data dir,
# backing up the Crystal save first.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG="$SCRIPT_DIR/install-levelmatch.log"
exec > >(tee -a "$LOG") 2>&1
printf '\n=== install-levelmatch run %s ===\n' "$(date -Iseconds)"

REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
SRC="$REPO/code/level_match"
DATA="$HOME/Library/Application Support/pokemon-love2d"
MODS="$DATA/mods"

[ -d "$SRC" ] || { echo "FATAL: mod source missing at $SRC"; exit 1; }
[ -d "$DATA" ] || { echo "FATAL: gen1recomp data dir missing at $DATA"; exit 1; }

# Saves first -- the mod changes battle state, so keep a known-good copy.
if [ -d "$DATA/saves" ]; then
  STAMP="$(date +%Y%m%d-%H%M%S)"
  BACKUP="$SCRIPT_DIR/saves-backup-$STAMP"
  mkdir -p "$BACKUP"
  cp -R "$DATA/saves/." "$BACKUP/"
  echo "saves backed up -> $BACKUP"
  find "$BACKUP" -type f -exec shasum -a 256 {} \;
else
  echo "note: no saves/ dir yet, nothing to back up"
fi

mkdir -p "$MODS"
rm -rf "$MODS/level_match"
cp -R "$SRC" "$MODS/level_match"
echo "installed -> $MODS/level_match"
ls -la "$MODS/level_match"

echo "done."
