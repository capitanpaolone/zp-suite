#!/bin/bash
# Copia la ZP Suite da questo repo (cartella di lavoro, anche non committata)
# dentro una cartella risorse di REAPER.
#
#   tools/sincronizza_reaper.sh [--prova] "/percorso/cartella risorse REAPER"
#
# --prova   elenca cosa cambierebbe, senza toccare nulla.
#
# Regole:
# - non cancella mai nulla nella destinazione;
# - prima di sovrascrivere un file diverso ne salva la copia in
#   <REAPER>/ZP_backup_sincronizza/<data_ora>/ con lo stesso percorso;
# - copia solo i file che git conosce (tracciati o nuovi non ignorati).

set -u

REPO="$(cd "$(dirname "$0")/.." && pwd)"
PROVA=0
DEST=""

for a in "$@"; do
  case "$a" in
    --prova) PROVA=1 ;;
    -h|--help) sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) DEST="$a" ;;
  esac
done

if [ -z "$DEST" ]; then
  echo "Manca la cartella risorse di REAPER." >&2
  echo "Uso: $0 [--prova] \"/percorso/cartella risorse REAPER\"" >&2
  exit 2
fi
DEST="${DEST%/}"
if [ ! -f "$DEST/reaper.ini" ]; then
  echo "Non sembra una cartella risorse di REAPER (manca reaper.ini):" >&2
  echo "  $DEST" >&2
  exit 2
fi

STAMP="$(date +%Y%m%d_%H%M%S)"
BACKUP="$DEST/ZP_backup_sincronizza/$STAMP"
ELENCO="$(mktemp -t zp_sync)"
trap 'rm -f "$ELENCO"' EXIT

nuovi=0; aggiornati=0; uguali=0; errori=0

# Da percorso nel repo a percorso nella cartella di REAPER (vuoto = non si copia).
destinazione() {
  local f="$1"
  case "$f" in
    "ZP Studio Suite/"*)
      echo "Scripts/ZP Suite/$f" ;;
    "ZP Lab/"*)
      # ZP Lab non fa parte della distribuzione: solo dove c'è già.
      [ -d "$DEST/Effects/ZP Suite/ZP Lab" ] && echo "Effects/ZP Suite/$f" ;;
    "ZP Voce/"*|"ZP Master/"*|"ZP Misura/"*)
      case "$f" in
        *.lua) echo "Scripts/ZP Suite/$f" ;;
        *)     echo "Effects/ZP Suite/$f" ;;
      esac ;;
    "REAPER_Italiano/Italiano (ZP).ReaperLangPack")
      echo "LangPack/Italiano (ZP).ReaperLangPack" ;;
  esac
}

echo "Repo:         $REPO"
echo "Versione:     $(git -C "$REPO" rev-parse --abbrev-ref HEAD) $(git -C "$REPO" rev-parse --short HEAD)$( [ -n "$(git -C "$REPO" status --porcelain)" ] && echo ' + modifiche non committate')"
echo "Destinazione: $DEST"
[ "$PROVA" = 1 ] && echo "(prova: non viene copiato nulla)"
echo

copia_file() {
  local src="$1" rel="$2"
  local dst="$DEST/$rel"
  if [ -f "$dst" ]; then
    if cmp -s "$src" "$dst"; then
      uguali=$((uguali + 1))
      return 0
    fi
    echo "aggiornato  $rel" >> "$ELENCO"
    aggiornati=$((aggiornati + 1))
    if [ "$PROVA" = 0 ]; then
      mkdir -p "$(dirname "$BACKUP/$rel")" && cp -p "$dst" "$BACKUP/$rel" \
        || { echo "ERRORE backup: $rel" >&2; errori=$((errori + 1)); return 1; }
    fi
  else
    echo "nuovo       $rel" >> "$ELENCO"
    nuovi=$((nuovi + 1))
  fi

  if [ "$PROVA" = 0 ]; then
    mkdir -p "$(dirname "$dst")" && cp -p "$src" "$dst" \
      || { echo "ERRORE copia: $rel" >&2; errori=$((errori + 1)); }
  fi
}

while IFS= read -r -d '' f; do
  src="$REPO/$f"
  [ -f "$src" ] || continue
  rel="$(destinazione "$f")"
  [ -n "$rel" ] || continue
  copia_file "$src" "$rel"
  case "$f" in
    "ZP Studio Suite/icons/"*.png)
      copia_file "$src" "Data/toolbar_icons/${f#ZP Studio Suite/icons/}"
      ;;
    "ZP Studio Suite/templates/ZP_Setup_VoiceOver_18LUFS.RPP")
      copia_file "$src" "ProjectTemplates/ZP Setup VoiceOver (-18 LUFS).RPP"
      ;;
    "ZP Studio Suite/templates/ZP_Setup_Mix_Spot_8LUFS.RPP")
      copia_file "$src" "ProjectTemplates/ZP Setup Mix-Spot (-8 LUFS).RPP"
      ;;
  esac
done < <(git -C "$REPO" ls-files -co --exclude-standard -z -- \
  "ZP Studio Suite" "ZP Voce" "ZP Master" "ZP Misura" "ZP Lab" \
  "REAPER_Italiano/Italiano (ZP).ReaperLangPack")

sort "$ELENCO"
[ -s "$ELENCO" ] && echo
echo "Aggiornati: $aggiornati   Nuovi: $nuovi   Già uguali: $uguali   Errori: $errori"
if [ "$PROVA" = 0 ] && [ "$aggiornati" -gt 0 ]; then
  echo "Copie dei file sostituiti: $BACKUP"
fi
if [ "$PROVA" = 0 ] && [ $((aggiornati + nuovi)) -gt 0 ]; then
  echo "Gli script valgono dal prossimo avvio dell'azione; i JSFX vanno riaperti."
fi
[ "$errori" = 0 ]
