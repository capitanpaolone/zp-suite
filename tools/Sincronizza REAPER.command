#!/bin/bash
# Doppio clic dal Finder: sceglie un REAPER e lo aggiorna con la ZP Suite
# di questo repo. Le destinazioni stanno, una per riga, in
#   ~/.config/zp-suite/destinazioni_reaper.txt

QUI="$(cd "$(dirname "$0")" && pwd)"
LISTA="$HOME/.config/zp-suite/destinazioni_reaper.txt"
ALTRA="Altra cartella…"

mkdir -p "$(dirname "$LISTA")"
[ -f "$LISTA" ] || echo "$HOME/Library/Application Support/REAPER" > "$LISTA"

voci=""
while IFS= read -r riga; do
  [ -n "$riga" ] || continue
  voci="$voci\"$(printf '%s' "$riga" | sed 's/\\/\\\\/g; s/"/\\"/g')\", "
done < "$LISTA"

DEST="$(osascript -e "choose from list {${voci}\"$ALTRA\"} with title \"ZP Suite\" with prompt \"Quale REAPER aggiorno dal repo?\"" 2>/dev/null)"
[ "$DEST" = "false" ] || [ -z "$DEST" ] && exit 0

if [ "$DEST" = "$ALTRA" ]; then
  DEST="$(osascript -e 'POSIX path of (choose folder with prompt "Cartella risorse di REAPER (quella con reaper.ini)")' 2>/dev/null)"
  [ -n "$DEST" ] || exit 0
  DEST="${DEST%/}"
  if [ -f "$DEST/reaper.ini" ] && ! grep -qxF "$DEST" "$LISTA"; then
    echo "$DEST" >> "$LISTA"
  fi
fi

echo
bash "$QUI/sincronizza_reaper.sh" "$DEST"
echo
read -n 1 -s -r -p "Premi un tasto per chiudere."
echo
