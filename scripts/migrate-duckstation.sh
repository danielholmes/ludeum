#!/usr/bin/env bash
# One-off, by hand (ADR 0024): moves what DuckStation kept in ~/Library/Application Support/DuckStation into the Data
# folder (save states, memory cards, BIOS, game settings, input profiles, screenshots) and into the DuckStation Ludeum
# installs (its settings.ini, play time and caches). A dry run unless --run is given. To be deleted once it has run.
#
#   1. In Ludeum ▸ Emulators…, Install DuckStation, and quit DuckStation if it's open.
#   2. scripts/migrate-duckstation.sh          (see what would move)
#      scripts/migrate-duckstation.sh --run
#   3. swift run ludeum-import duckstation-cards, then with --run
#   4. Open Ludeum. In Dropbox, mark Data/Emulators/DuckStation "Make available offline".
#      Delete /Applications/DuckStation.app and what's left in the old folder by hand.
set -euo pipefail

RUN=0
[[ "${1:-}" == "--run" ]] && RUN=1
OLD="$HOME/Library/Application Support/DuckStation"
LUDEUM="$HOME/Library/Application Support/Ludeum"
ROOT="$LUDEUM/Emulators/DuckStation.app/Contents/MacOS"
DATA="$LUDEUM/Data/Emulators/DuckStation"

if pgrep -xq DuckStation; then echo "Quit DuckStation first." >&2; exit 1; fi
if [[ ! -d "$OLD" ]]; then echo "Nothing at $OLD: already moved?"; exit 0; fi
if [[ ! -x "$ROOT/DuckStation" || ! -f "$ROOT/portable.txt" ]]; then
  echo "Install DuckStation from Ludeum ▸ Emulators… first." >&2; exit 1
fi
if [[ ! -d "$LUDEUM/Data" ]]; then echo "Ludeum's Data folder can't be found." >&2; exit 1; fi

move() {  # from, to: never over something that's there
  if [[ -e "$2" ]]; then echo "stop: $2 is there already" >&2; exit 1; fi
  if (( RUN )); then mkdir -p "$(dirname "$2")"; mv "$1" "$2"; fi
  echo "move  ${1#"$OLD/"}  →  ${2#"$LUDEUM/"}"
}

aside() {  # a name under superseded/ that nothing has yet
  local to="$OLD/superseded/$1" n=2
  while [[ -e "$to" ]]; do to="$OLD/superseded/${1%.*} ($n).${1##*.}"; n=$((n + 1)); done
  echo "$to"
}

# The folders worth keeping, into the Data folder. Where both have a file of one name (a save state backed up
# before), the newer keeps the name and the older goes to superseded/ in the old folder, never deleted.
for pair in "savestates:Save States" "memcards:Memory Cards" "bios:BIOS" "gamesettings:Game Settings" \
  "inputprofiles:Input Profiles" "screenshots:Screenshots"; do
  src="$OLD/${pair%%:*}"; dst="$DATA/${pair#*:}"
  [[ -d "$src" ]] || continue
  for f in "$src"/* "$src"/.[!.]*; do
    [[ -e "$f" ]] || continue
    name="$(basename "$f")"
    if [[ -e "$dst/$name" ]]; then
      if [[ "$f" -nt "$dst/$name" ]]; then
        move "$dst/$name" "$(aside "$name")"
        move "$f" "$dst/$name"
      else
        move "$f" "$(aside "$name")"
      fi
    else
      move "$f" "$dst/$name"
    fi
  done
  if (( RUN )); then rmdir "$src" 2>/dev/null || true; fi
done

# Everything else (settings.ini with its controller and video settings, play time, the caches) into the installed
# copy's data root. Its fresh settings.ini is replaced: Ludeum writes its Standing settings again before the next
# launch it gives DuckStation.
for f in "$OLD"/* "$OLD"/.[!.]*; do
  [[ -e "$f" ]] || continue
  name="$(basename "$f")"
  [[ "$name" == "superseded" ]] && continue
  if [[ "$name" == "settings.ini" ]]; then
    if (( RUN )); then rm -f "$ROOT/settings.ini"; fi
    move "$f" "$ROOT/settings.ini"
  elif [[ -e "$ROOT/$name" ]]; then
    echo "keep  $name: the installed copy has its own"
  else
    move "$f" "$ROOT/$name"
  fi
done

echo
if (( RUN )); then
  echo "Done. Next: swift run ludeum-import duckstation-cards --run, then open Ludeum."
  echo "In Dropbox, mark Data/Emulators/DuckStation \"Make available offline\"."
  echo "Delete /Applications/DuckStation.app and what's left in \"$OLD\" by hand."
else
  echo "A dry run: nothing moved. Run again with --run to do it."
fi
