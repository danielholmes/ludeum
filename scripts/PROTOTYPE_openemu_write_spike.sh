#!/usr/bin/env bash
# PROTOTYPE — throwaway spike for "Is writing to OpenEmu safe?" (issue #12). Not for main.
#
# Works only on a copy of the OpenEmu library in prototype-output/ (outside Dropbox).
# Never touches the live library; `point live` puts OpenEmu back on it.
#
#   scripts/PROTOTYPE_openemu_write_spike.sh status
#   scripts/PROTOTYPE_openemu_write_spike.sh point copy|live
#   scripts/PROTOTYPE_openemu_write_spike.sh reset          # copy store back from pristine
#   scripts/PROTOTYPE_openemu_write_spike.sh nobump         # round 1: insert a collection WITHOUT bumping Z_MAX
#   scripts/PROTOTYPE_openemu_write_spike.sh sync           # round 2: a whole Sync, done properly
#   scripts/PROTOTYPE_openemu_write_spike.sh report         # state of every test subject
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/prototype-output"
LIB="$OUT/PROTOTYPE-wipe-me-openemu-library"
PRISTINE="$OUT/PROTOTYPE-pristine-store"
DB="$LIB/Library.storedata"
LIVE_PATH="~/Dropbox/games/OpenEmu/Game Library"

sql() { sqlite3 -bail "$DB" "$@"; }
table() { sqlite3 -header -column "$DB" "$@"; echo; }

refuse_if_running() {
  if pgrep -x OpenEmu >/dev/null; then echo "OpenEmu is running: quit it first." >&2; exit 1; fi
}

# Test subjects (Z_PKs read from this library on 2026-09-26)
FEAR_EFFECT_2="1277,1629,1630,1631,1632" # one Game, five OpenEmu games (m3u + 4 Discs)
ZELDA=323                                # Legend of Zelda, The (U) (PRG1) [!]
TODO=26                                  # _TODO
TONY_HAWK=16                             # renamed in place
HARRY_POTTER=39                          # deleted
CASTLEVANIA=463                          # no box art, status 0 -> gets a Cover
MAJORAS_MASK=337                         # no box art, forced to status 3 -> Cover vs OpenVGDB
RATED_3=46                               # CTR - Crash Team Racing (3 stars) -> stars cleared

cmd_status() {
  echo "OpenEmu databasePath: $(defaults read org.openemu.OpenEmu databasePath)"
  pgrep -x OpenEmu >/dev/null && echo "OpenEmu: RUNNING" || echo "OpenEmu: not running"
  ls -la "$LIB"/Library.storedata*
  echo "integrity: $(sql 'PRAGMA integrity_check;')"
}

cmd_point() {
  refuse_if_running
  case "${1:-}" in
    copy) defaults write org.openemu.OpenEmu databasePath "$LIB" ;;
    live) defaults write org.openemu.OpenEmu databasePath "$LIVE_PATH" ;;
    *) echo "point copy|live" >&2; exit 1 ;;
  esac
  echo "OpenEmu databasePath: $(defaults read org.openemu.OpenEmu databasePath)"
}

cmd_reset() {
  refuse_if_running
  rm -f "$LIB"/Library.storedata*
  cp -p "$PRISTINE"/Library.storedata* "$LIB"/
  echo "store reset from pristine"
}

# One collection row, the way Core Data would write it. $1 = name, $2 = bump Z_MAX (1/0).
insert_collection_sql() {
  local bump=""
  [[ "$2" == 1 ]] && bump="UPDATE Z_PRIMARYKEY SET Z_MAX = Z_MAX + 1 WHERE Z_NAME = 'AbstractCollection';"
  cat <<SQL
INSERT INTO ZABSTRACTCOLLECTION (Z_PK, Z_ENT, Z_OPT, ZFOLDER, ZNAME)
  VALUES ((SELECT Z_MAX + 1 FROM Z_PRIMARYKEY WHERE Z_NAME = 'AbstractCollection'),
          (SELECT Z_ENT FROM Z_PRIMARYKEY WHERE Z_NAME = 'Collection'), 1, NULL, '$1');
$bump
SQL
}

finish() {
  echo "checkpoint (busy, log, checkpointed): $(sql 'PRAGMA wal_checkpoint(TRUNCATE);')"
  echo "integrity: $(sql 'PRAGMA integrity_check;')"
  ls -la "$LIB"/Library.storedata*
}

cmd_nobump() {
  refuse_if_running
  sql "BEGIN; $(insert_collection_sql 'PROTOTYPE no bump' 0) COMMIT;"
  table "SELECT * FROM Z_PRIMARYKEY WHERE Z_ENT <= 4; SELECT Z_PK, Z_ENT, ZNAME FROM ZABSTRACTCOLLECTION ORDER BY Z_PK DESC LIMIT 2;"
  finish
}

# A JPEG in Artwork/ named by a fresh UUID, plus its ZIMAGE row, linked both ways to game $1.
cover_sql() {
  local game=$1 source_image=$2 uuid width height
  uuid=$(uuidgen)
  sips -s format jpeg -s formatOptions 90 "$source_image" --out "$LIB/Artwork/$uuid.jpg" >/dev/null
  mv "$LIB/Artwork/$uuid.jpg" "$LIB/Artwork/$uuid"
  width=$(sips -g pixelWidth "$LIB/Artwork/$uuid" | awk '/pixelWidth/ {print $2}')
  height=$(sips -g pixelHeight "$LIB/Artwork/$uuid" | awk '/pixelHeight/ {print $2}')
  echo "cover for game $game: Artwork/$uuid (${width}x${height})" >&2
  cat <<SQL
INSERT INTO ZIMAGE (Z_PK, Z_ENT, Z_OPT, ZFORMAT, ZBOX, ZHEIGHT, ZWIDTH, ZRELATIVEPATH, ZSOURCE)
  VALUES ((SELECT Z_MAX + 1 FROM Z_PRIMARYKEY WHERE Z_NAME = 'Image'),
          (SELECT Z_ENT FROM Z_PRIMARYKEY WHERE Z_NAME = 'Image'), 1, 3, $game, $height, $width, '$uuid', NULL);
UPDATE Z_PRIMARYKEY SET Z_MAX = Z_MAX + 1 WHERE Z_NAME = 'Image';
UPDATE ZGAME SET ZBOXIMAGE = (SELECT Z_MAX FROM Z_PRIMARYKEY WHERE Z_NAME = 'Image'), Z_OPT = Z_OPT + 1
  WHERE Z_PK = $game AND ZBOXIMAGE IS NULL;
SQL
}

# Membership change: bump Z_OPT on both ends, as Core Data does for a many-to-many.
membership_sql() {
  local collection=$1 op=$2 games=$3
  if [[ $op == add ]]; then
    echo "INSERT OR IGNORE INTO Z_2GAMES (Z_2COLLECTIONS, Z_7GAMES) SELECT $collection, Z_PK FROM ZGAME WHERE Z_PK IN ($games);"
  else
    echo "DELETE FROM Z_2GAMES WHERE Z_2COLLECTIONS = $collection AND Z_7GAMES IN ($games);"
  fi
  echo "UPDATE ZGAME SET Z_OPT = Z_OPT + 1 WHERE Z_PK IN ($games);"
  echo "UPDATE ZABSTRACTCOLLECTION SET Z_OPT = Z_OPT + 1 WHERE Z_PK = $collection;"
}

cmd_sync() {
  refuse_if_running
  local todo_drop
  todo_drop=$(sql "SELECT group_concat(Z_7GAMES) FROM (SELECT Z_7GAMES FROM Z_2GAMES WHERE Z_2COLLECTIONS = $TODO ORDER BY Z_7GAMES LIMIT 2);")
  echo "_TODO loses games $todo_drop; game $RATED_3 goes from 3 stars to none"

  local script
  script=$(cat <<SQL
BEGIN IMMEDIATE;
-- Stars: on the OpenEmu game row of every ROM of the Game
UPDATE ZGAME SET ZRATING = 4, Z_OPT = Z_OPT + 1 WHERE Z_PK IN ($FEAR_EFFECT_2);
UPDATE ZGAME SET ZRATING = 5, Z_OPT = Z_OPT + 1 WHERE Z_PK = $ZELDA;
UPDATE ZGAME SET ZRATING = 0, Z_OPT = Z_OPT + 1 WHERE Z_PK = $RATED_3;
-- Overwrite a journal-owned collection in place
$(membership_sql $TODO remove "$todo_drop")
$(membership_sql $TODO add "$FEAR_EFFECT_2")
-- Rename in place
UPDATE ZABSTRACTCOLLECTION SET ZNAME = 'Tony Hawk''s Pro Skater', Z_OPT = Z_OPT + 1 WHERE Z_PK = $TONY_HAWK;
-- Create
$(insert_collection_sql 'PROTOTYPE Journal List' 1)
$(membership_sql "(SELECT Z_MAX FROM Z_PRIMARYKEY WHERE Z_NAME = 'AbstractCollection')" add "$ZELDA,$MAJORAS_MASK")
-- Delete a regular collection and its memberships
UPDATE ZGAME SET Z_OPT = Z_OPT + 1 WHERE Z_PK IN (SELECT Z_7GAMES FROM Z_2GAMES WHERE Z_2COLLECTIONS = $HARRY_POTTER);
DELETE FROM Z_2GAMES WHERE Z_2COLLECTIONS = $HARRY_POTTER;
DELETE FROM ZABSTRACTCOLLECTION WHERE Z_PK = $HARRY_POTTER AND Z_ENT = (SELECT Z_ENT FROM Z_PRIMARYKEY WHERE Z_NAME = 'Collection');
-- Covers for games with no box art
$(cover_sql $CASTLEVANIA "/Library/User Pictures/Flowers/Dahlia.heic")
$(cover_sql $MAJORAS_MASK "/Library/User Pictures/Animals/Penguin.heic")
UPDATE ZGAME SET ZSTATUS = 3, Z_OPT = Z_OPT + 1 WHERE Z_PK = $MAJORAS_MASK; -- probe: pending OpenVGDB lookup
COMMIT;
SQL
)
  echo "$script" > "$OUT/PROTOTYPE-last-sync.sql"
  sql "$script"
  finish
  cmd_report
}

cmd_report() {
  table "SELECT * FROM Z_PRIMARYKEY WHERE Z_NAME IN ('AbstractCollection', 'Game', 'Image');"
  table "SELECT MAX(Z_PK) AS max_collection_pk FROM ZABSTRACTCOLLECTION; SELECT MAX(Z_PK) AS max_image_pk FROM ZIMAGE;"
  table "SELECT g.Z_PK, g.Z_OPT, g.ZRATING, g.ZSTATUS, g.ZBOXIMAGE, i.ZRELATIVEPATH, i.ZSOURCE, substr(g.ZNAME, 1, 45) AS name
         FROM ZGAME g LEFT JOIN ZIMAGE i ON i.Z_PK = g.ZBOXIMAGE
         WHERE g.Z_PK IN ($FEAR_EFFECT_2, $ZELDA, $CASTLEVANIA, $MAJORAS_MASK)
            OR g.Z_PK = $RATED_3;"
  table "SELECT c.Z_PK, c.Z_ENT, c.Z_OPT, c.ZNAME, COUNT(j.Z_7GAMES) AS games
         FROM ZABSTRACTCOLLECTION c LEFT JOIN Z_2GAMES j ON j.Z_2COLLECTIONS = c.Z_PK
         WHERE c.Z_PK IN ($TODO, $TONY_HAWK, $HARRY_POTTER) OR c.Z_PK > 58 OR c.ZNAME LIKE 'PROTOTYPE%' OR c.ZNAME LIKE 'Made in%'
         GROUP BY c.Z_PK ORDER BY c.Z_PK;"
  table "SELECT COUNT(*) AS dangling_memberships FROM Z_2GAMES j
         WHERE NOT EXISTS (SELECT 1 FROM ZABSTRACTCOLLECTION c WHERE c.Z_PK = j.Z_2COLLECTIONS)
            OR NOT EXISTS (SELECT 1 FROM ZGAME g WHERE g.Z_PK = j.Z_7GAMES);"
}

"cmd_${1:-status}" "${@:2}"
