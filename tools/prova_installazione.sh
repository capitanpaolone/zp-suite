#!/bin/bash
# Prova d'installazione della ZP Suite: installa in un REAPER di prova la
# prossima release esattamente come la installera' ReaPack, partendo dalla
# cartella di lavoro di questo repo (anche non committata).
#
#   tools/prova_installazione.sh [--solo-indice] [--senza-beta] "/cartella/REAPER di prova"
#
# 1. Indice: clona il repo in ~/.cache/zp-suite/prova_installazione/repo,
#    parte dall'ultima versione pubblicata (origin/master), ci mette sopra la
#    cartella di lavoro come un unico commit e genera index.xml con
#    reapack-index (indirizzi file://). E' l'indice che uscira' alla prossima
#    pubblicazione: se un pacchetto e' cambiato senza alzare @version, qui si vede.
# 2. Pulizia (solo REAPER chiuso e con il file ZP_BANCO_DI_PROVA): sposta i file
#    ZP in ZP_backup_prova/<data_ora>/, fa dimenticare a ReaPack la ZP Suite e
#    punta il repository "ZP Suite" all'indice locale.
# 3. Beta non ancora selezionate nel profilo di prova: copia gli eventuali file
#    elencati in tools/beta_in_prova.txt, per includerli nello smoke test. Il loro
#    pacchetto ReaPack resta verificato separatamente nell'indice del punto 1.
# 4. Installazione: apre il REAPER di prova, registra le azioni beta, lancia la
#    sincronizzazione di ReaPack e aspetta che finisca. Poi il "fumo JSFX": ogni effetto
#    ZP su una traccia con un tono, 3 secondi di play; un effetto che non si carica o i cui
#    valori restano fermi (tipico di un errore di compilazione) finisce nell'esito.
# 5. Verifica: confronta i file installati con il repo, scrive l'esito in
#    <REAPER>/ZP_prova_installazione_esito.txt.
#
# --solo-indice  solo il punto 1 (per la prova su strada sul REAPER operativo).
# --senza-beta   salta il punto 3 (overlay di prova; non cambia l'indice ReaPack).
#
# Non tocca mai il repo, GitHub, ne' un REAPER senza ZP_BANCO_DI_PROVA.

set -u

REPO="$(cd "$(dirname "$0")/.." && pwd)"
LAVORO="$HOME/.cache/zp-suite/prova_installazione"
CLONE="$LAVORO/repo"
SOLO_INDICE=0; BETA=1; DEST=""

for a in "$@"; do
  case "$a" in
    --solo-indice) SOLO_INDICE=1 ;;
    --senza-beta)  BETA=0 ;;
    -h|--help) sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) DEST="${a%/}" ;;
  esac
done

ferma() { echo "STOP: $*" >&2; exit 2; }

# ---------------------------------------------------------------- controlli
RI="$(command -v reapack-index || gem contents reapack-index 2>/dev/null | grep '/bin/reapack-index$' | tail -1)"
[ -x "$RI" ] || ferma "reapack-index non trovato (gem install reapack-index)."
command -v sqlite3 >/dev/null || ferma "sqlite3 non trovato."

if [ "$SOLO_INDICE" = 0 ]; then
  [ -n "$DEST" ] || ferma "manca la cartella del REAPER di prova. Uso: $0 [--solo-indice] [--senza-beta] \"/cartella/REAPER\""
  [ -f "$DEST/reaper.ini" ] || ferma "non e' una cartella risorse di REAPER (manca reaper.ini): $DEST"
  [ -f "$DEST/ZP_BANCO_DI_PROVA" ] || ferma "in $DEST manca il file ZP_BANCO_DI_PROVA. Questo script svuota la ZP Suite del REAPER indicato: si usa solo su un REAPER di prova, segnato con quel file."
  [ -f "$DEST/ReaPack/registry.db" ] || ferma "ReaPack non risulta installato in $DEST."
  APP=""
  for a in "$DEST"/*.app; do [ -x "$a/Contents/MacOS/REAPER" ] && APP="$a" && break; done
  [ -n "$APP" ] || ferma "in $DEST non trovo l'app di REAPER portatile."
  if ps -axo command= | grep -F "$APP/Contents/MacOS/REAPER" | grep -vq grep; then
    ferma "il REAPER di prova e' aperto. Chiudilo e rilancia."
  fi
fi

echo "Repo:     $REPO"
echo "Versione: $(git -C "$REPO" rev-parse --abbrev-ref HEAD) $(git -C "$REPO" rev-parse --short HEAD)$( [ -n "$(git -C "$REPO" status --porcelain)" ] && echo ' + modifiche non committate')"

# ---------------------------------------------------------------- 1. indice
echo; echo "== 1. Indice della prossima release"
if ! git -C "$REPO" fetch -q origin 2>/dev/null; then
  echo "ATTENZIONE: GitHub non raggiungibile, uso l'ultima origin/master gia' scaricata."
fi
BASE="$(git -C "$REPO" rev-parse --short origin/master)" || ferma "origin/master non trovato."
echo "Pubblicata (origin/master): $BASE"

mkdir -p "$LAVORO"
[ -d "$CLONE/.git" ] || git clone -q --no-checkout "$REPO" "$CLONE" || ferma "clone non riuscito."
(
  set -e
  cd "$CLONE"
  # reapack-index --check ricava gli indirizzi da origin: lo facciamo puntare a GitHub
  git remote set-url origin "$(git -C "$REPO" remote get-url origin)"
  git fetch -q "$REPO" refs/remotes/origin/master
  git checkout -q -f --detach FETCH_HEAD
  git ls-files -z | xargs -0 rm -f
  (cd "$REPO" && git ls-files -co --exclude-standard -z | tar --null -T - -cf -) | tar -xf -
  git checkout -q FETCH_HEAD -- index.xml
  git add -A
  git -c user.name=prova -c user.email=prova@localhost commit -q --allow-empty -m "prova installazione"
) || ferma "preparazione del clone non riuscita."

( cd "$CLONE" && "$RI" --check --no-progress -U "file://$CLONE/\$path" ) > "$LAVORO/check.txt" 2>&1 \
  || { tail -20 "$LAVORO/check.txt"; ferma "reapack-index --check ha trovato errori (dettagli sopra)."; }
echo "Controllo pacchetti: $(tail -1 "$LAVORO/check.txt")"

( cd "$CLONE" && "$RI" --no-commit --no-progress -U "file://$CLONE/\$path" ) > "$LAVORO/indice.txt" 2>&1 \
  || { tail -20 "$LAVORO/indice.txt"; ferma "reapack-index non e' riuscito a generare l'indice."; }
echo "Novita' rispetto alla pubblicata: $(tail -1 "$LAVORO/indice.txt")"
INDICE="$CLONE/index.xml"
echo "Indice locale: file://$INDICE"

if [ "$SOLO_INDICE" = 1 ]; then
  echo
  echo "Per la prova su strada: con REAPER chiuso, nel suo reapack.ini sostituisci"
  echo "l'indirizzo del repository \"ZP Suite\" con  file://$INDICE"
  echo "poi in REAPER: Estensioni > ReaPack > Synchronize packages."
  echo "Dopo la pubblicazione rimetti https://github.com/capitanpaolone/zp-suite/raw/master/index.xml"
  exit 0
fi

# ---------------------------------------------------------------- 2. pulizia
STAMP="$(date +%Y%m%d_%H%M%S)"
BACKUP="$DEST/ZP_backup_prova/$STAMP"
echo; echo "== 2. Pulizia del REAPER di prova (copie in ZP_backup_prova/$STAMP)"
mkdir -p "$BACKUP" || ferma "non riesco a creare $BACKUP"

sposta() {  # sposta un percorso relativo a DEST dentro BACKUP, se esiste
  local rel="$1"
  [ -e "$DEST/$rel" ] || return 0
  mkdir -p "$(dirname "$BACKUP/$rel")" && mv "$DEST/$rel" "$BACKUP/$rel" \
    || ferma "non riesco a spostare $rel"
}
for f in reaper-kb.ini reapack.ini ReaPack/registry.db; do
  mkdir -p "$(dirname "$BACKUP/$f")"; cp -p "$DEST/$f" "$BACKUP/$f" || ferma "backup di $f non riuscito"
done
sposta "Scripts/ZP Suite"
sposta "Effects/ZP Suite"
sposta "LangPack/Italiano (ZP).ReaperLangPack"
sposta "ReaPack/cache/ZP Suite.xml"
( cd "$DEST" && find Data/toolbar_icons -maxdepth 2 -name 'ZP_*' -type f 2>/dev/null ) | while IFS= read -r f; do sposta "$f"; done

sqlite3 "$DEST/ReaPack/registry.db" \
  "BEGIN; DELETE FROM files WHERE entry IN (SELECT id FROM entries WHERE remote='ZP Suite');
   DELETE FROM entries WHERE remote='ZP Suite'; COMMIT;" || ferma "registro ReaPack non aggiornato."

python3 - "$DEST/reapack.ini" "file://$INDICE" <<'PY' || ferma "reapack.ini non aggiornato."
import sys, os, re, urllib.parse
ini, url = sys.argv[1], sys.argv[2]
righe, trovato = open(ini, encoding="utf-8").read().splitlines(), False
for i, r in enumerate(righe):
    m = re.match(r'^(remote\d+)=([^|]*)\|([^|]*)\|(\d)\|(.*)$', r)
    if not m: continue
    chiave, nome, indirizzo, attivo, resto = m.groups()
    if nome == "ZP Suite":
        righe[i] = f"{chiave}=ZP Suite|{url}|1|{resto}"; trovato = True
    elif indirizzo.startswith("file://") and attivo == "1" \
            and not os.path.exists(urllib.parse.unquote(indirizzo[7:])):
        righe[i] = f"{chiave}={nome}|{indirizzo}|0|{resto}"
        print(f"Disattivato il repository \"{nome}\": il suo indice non esiste ({indirizzo}).")
if not trovato:
    n = 1 + max([int(x) for x in re.findall(r'^remote(\d+)=', "\n".join(righe), re.M)] or [-1])
    sezione = righe.index("[remotes]") if "[remotes]" in righe else None
    if sezione is None: righe += ["", "[remotes]"]; sezione = len(righe) - 1
    righe.insert(sezione + 1, f"remote{n}=ZP Suite|{url}|1|2")
    righe = [re.sub(r'^size=(\d+)$', lambda m: f"size={max(int(m.group(1)), n + 1)}", r) for r in righe]
open(ini, "w", encoding="utf-8").write("\n".join(righe) + "\n")
print("Repository \"ZP Suite\" -> indice locale.")
PY

# ---------------------------------------------------------------- 3. beta
destinazione() {  # stessa mappa di sincronizza_reaper.sh
  case "$1" in
    "ZP Studio Suite/"*) echo "Scripts/ZP Suite/$1" ;;
    "ZP Lab/"*)          echo "Effects/ZP Suite/$1" ;;
    "ZP Voce/"*|"ZP Master/"*|"ZP Misura/"*)
      case "$1" in *.lua) echo "Scripts/ZP Suite/$1" ;; *) echo "Effects/ZP Suite/$1" ;; esac ;;
  esac
}
AZIONI="$LAVORO/azioni_beta.txt"; : > "$AZIONI"
BETA_COPIATI="$LAVORO/beta_copiati.txt"; : > "$BETA_COPIATI"
if [ "$BETA" = 1 ] && [ -f "$REPO/tools/beta_in_prova.txt" ]; then
  echo; echo "== 3. Prodotti in maturazione (tools/beta_in_prova.txt)"
  while IFS= read -r riga || [ -n "$riga" ]; do
    riga="${riga%$'\r'}"
    case "$riga" in ""|"#"*) continue ;; esac
    azione=0; case "$riga" in "* "*) azione=1; riga="${riga#\* }" ;; esac
    trovati=0
    while IFS= read -r -d '' f; do
      rel="$(destinazione "$f")"; [ -n "$rel" ] || continue
      mkdir -p "$(dirname "$DEST/$rel")" && cp -p "$REPO/$f" "$DEST/$rel" || ferma "copia beta non riuscita: $f"
      echo "$rel" >> "$BETA_COPIATI"; trovati=$((trovati + 1))
      [ "$azione" = 1 ] && echo "$DEST/$rel" >> "$AZIONI"
    done < <(git -C "$REPO" ls-files -co --exclude-standard -z -- "$riga")
    [ "$trovati" -gt 0 ] && echo "beta   $riga ($trovati)" || echo "ATTENZIONE: in beta_in_prova.txt, nessun file per: $riga"
  done < "$REPO/tools/beta_in_prova.txt"
fi

# ---------------------------------------------------------------- 4. installazione
echo; echo "== 4. Installazione con ReaPack in $(basename "$APP")"
ATTESI="$(python3 - "$BACKUP/ReaPack/registry.db" "$INDICE" <<'PY'
import sqlite3, sys, xml.etree.ElementTree as ET
db = sqlite3.connect(sys.argv[1])
selezionati = {r[0] for r in db.execute("SELECT DISTINCT package FROM entries WHERE remote='ZP Suite'")}
indicizzati = {r.get("name") for r in ET.parse(sys.argv[2]).getroot().iter("reapack")}
print(len(selezionati & indicizzati))
PY
)" || ferma "non riesco a contare i pacchetti ZP selezionati nel backup."
LUA="$LAVORO/avvio_prova.lua"
{
  echo "-- generato da tools/prova_installazione.sh"
  while IFS= read -r p; do echo "reaper.AddRemoveReaScript(true, 0, [==[$p]==], true)"; done < "$AZIONI"
  echo 'local id = reaper.NamedCommandLookup("_REAPACK_SYNC")'
  echo 'if id ~= 0 then reaper.Main_OnCommand(id, 0) else reaper.ShowConsoleMsg("ZP: ReaPack non trovato\n") end'
  echo "local VIA, FATTO = [==[$LAVORO/via_fumo]==], [==[$LAVORO/fumo_fatto.txt]==]"
  cat <<'FUMO'
-- Fumo JSFX: quando lo script shell crea VIA (installazione finita), ogni JSFX della ZP Suite va su una
-- traccia con un generatore di tono davanti, suona 3 secondi e si guarda se qualche suo valore si muove.
local function esiste(p) local f = io.open(p, "r"); if f then f:close(); return true end end
local function elenca(dir, rel, out)
  local i = 0
  while true do local n = reaper.EnumerateFiles(dir, i); if not n then break end
    if n:lower():match("%.jsfx$") then out[#out + 1] = rel .. n end; i = i + 1 end
  i = 0
  while true do local d = reaper.EnumerateSubdirectories(dir, i); if not d then break end
    elenca(dir .. "/" .. d, rel .. d .. "/", out); i = i + 1 end
end
local function valori(tr, fx) local v = {}
  for p = 0, reaper.TrackFX_GetNumParams(tr, fx) - 1 do v[p] = reaper.TrackFX_GetParam(tr, fx, p) end
  return v end
local prove, t0 = {}, 0
local function fine()
  reaper.OnStopButton()
  local out = {}
  for _, p in ipairs(prove) do
    if p.fx < 0 then out[#out + 1] = "NON CARICATO\t" .. p.nome
    else
      local mosso = false
      for k, v in pairs(valori(p.tr, p.fx)) do
        if p.v0[k] and math.abs(v - p.v0[k]) > 0.000000001 then mosso = true; break end
      end
      out[#out + 1] = (mosso and "OK" or "FERMO") .. "\t" .. p.nome
    end
  end
  local f = io.open(FATTO, "w"); f:write(table.concat(out, "\n"), "\n"); f:close()
end
local function attendi() if reaper.time_precise() - t0 < 3 then reaper.defer(attendi) else fine() end end
local function fumo()
  os.remove(VIA)
  reaper.Main_OnCommand(40859, 0) -- nuova scheda di progetto, il progetto aperto non si tocca
  local lista = {}
  elenca(reaper.GetResourcePath() .. "/Effects/ZP Suite", "", lista)
  table.sort(lista)
  for _, rel in ipairs(lista) do
    reaper.InsertTrackAtIndex(reaper.CountTracks(0), false)
    local tr = reaper.GetTrack(0, reaper.CountTracks(0) - 1)
    reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", rel, true)
    reaper.TrackFX_AddByName(tr, "JS:synthesis/tonegenerator", false, -1)
    local fx = reaper.TrackFX_AddByName(tr, "JS:ZP Suite/" .. rel, false, -1)
    prove[#prove + 1] = { nome = rel, tr = tr, fx = fx, v0 = fx >= 0 and valori(tr, fx) or {} }
  end
  reaper.OnPlayButton(); t0 = reaper.time_precise(); reaper.defer(attendi)
end
local function aspetta_via() if esiste(VIA) then fumo() else reaper.defer(aspetta_via) end end
aspetta_via()
FUMO
} > "$LUA"
rm -f "$LAVORO/via_fumo" "$LAVORO/fumo_fatto.txt"
"$APP/Contents/MacOS/REAPER" -newinst -nosplash "$LUA" >/dev/null 2>&1 &
disown 2>/dev/null

conta() { sqlite3 "$DEST/ReaPack/registry.db" "SELECT count(DISTINCT package) FROM entries WHERE remote='ZP Suite';" 2>/dev/null || echo 0; }
n=0; prima=-1; fermo=0
for s in $(seq 1 180); do
  sleep 2; n="$(conta)"
  if [ "$n" -ge "$ATTESI" ] && [ "$n" = "$prima" ]; then fermo=$((fermo + 1)); [ "$fermo" -ge 2 ] && break; else fermo=0; fi
  prima="$n"
done
echo "Pacchetti ZP selezionati ripristinati da ReaPack: $n su $ATTESI"
[ "$n" -ge "$ATTESI" ] || echo "ATTENZIONE: ReaPack non ha ripristinato tutti i pacchetti selezionati entro 6 minuti. Guarda la finestra di ReaPack in REAPER di prova."
sleep 3   # lascia a REAPER il tempo di scrivere reaper-kb.ini

echo; echo "== 4b. Fumo JSFX: ogni effetto ZP caricato e fatto suonare 3 secondi"
touch "$LAVORO/via_fumo"
for s in $(seq 1 45); do [ -s "$LAVORO/fumo_fatto.txt" ] && break; sleep 2; done
if [ -s "$LAVORO/fumo_fatto.txt" ]; then
  echo "OK $(grep -c '^OK' "$LAVORO/fumo_fatto.txt")   FERMI $(grep -c '^FERMO' "$LAVORO/fumo_fatto.txt")   NON CARICATI $(grep -c '^NON CARICATO' "$LAVORO/fumo_fatto.txt")"
else
  echo "ATTENZIONE: il fumo JSFX non ha risposto entro 90 secondi."
fi

# ---------------------------------------------------------------- 5. verifica
echo; echo "== 5. Verifica"
ESITO="$DEST/ZP_prova_installazione_esito.txt"
python3 - "$REPO" "$DEST" "$BETA_COPIATI" "$ESITO" "$n" "$ATTESI" "$LAVORO/fumo_fatto.txt" <<'PY'
import sys, os, subprocess, sqlite3, hashlib
repo, dest, beta_file, esito_file, n, attesi, fumo_file = sys.argv[1:8]
fumo = [r.split("\t", 1) for r in open(fumo_file, encoding="utf-8").read().splitlines() if "\t" in r] if os.path.isfile(fumo_file) else None
non_caricati = [nome for st, nome in (fumo or []) if st == "NON CARICATO"]
import re as _re
def scrive_slider(rel):  # il codice audio scrive qualche slider? altrimenti il fumo non puo' giudicarlo
    try: t = open(os.path.join(dest, "Effects/ZP Suite", rel), encoding="utf-8", errors="replace").read()
    except OSError: return True
    t = _re.sub(r"//[^\n]*", "", t); parti = _re.split(r"\n@(\w+)", t)
    codice = "".join(parti[i + 1] for i in range(1, len(parti) - 1, 2) if parti[i] in ("block", "sample"))
    return bool(_re.search(r"\bslider\(?\d+\)?\s*=(?!=)", codice))
fermi = [nome for st, nome in (fumo or []) if st == "FERMO" and scrive_slider(nome)]
non_verificabili = [nome for st, nome in (fumo or []) if st == "FERMO" and not scrive_slider(nome)]
def h(p):
    with open(p, "rb") as f: return hashlib.sha256(f.read()).hexdigest()
def dest_di(f):
    out = []
    top = f.split("/")[0]
    if top == "ZP Studio Suite": out.append("Scripts/ZP Suite/" + f)
    elif top == "ZP Lab": out.append("Effects/ZP Suite/" + f)
    elif top in ("ZP Voce", "ZP Master", "ZP Misura"):
        out.append(("Scripts/ZP Suite/" if f.endswith(".lua") else "Effects/ZP Suite/") + f)
    elif f == "REAPER_Italiano/Italiano (ZP).ReaperLangPack": out.append("LangPack/Italiano (ZP).ReaperLangPack")
    if f.startswith("ZP Studio Suite/icons/") and f.endswith(".png"):
        out.append("Data/toolbar_icons/" + f[len("ZP Studio Suite/icons/"):])
    return out
files = subprocess.run(["git", "-C", repo, "ls-files", "-co", "--exclude-standard", "-z", "--",
    "ZP Studio Suite", "ZP Voce", "ZP Master", "ZP Misura", "ZP Lab",
    "REAPER_Italiano/Italiano (ZP).ReaperLangPack"], capture_output=True, text=True).stdout.split("\0")
mappa, per_hash = {}, {}
for f in filter(None, files):
    src = os.path.join(repo, f)
    if not os.path.isfile(src): continue
    for d in dest_di(f): mappa[d] = f
    per_hash.setdefault(h(src), f)
db = sqlite3.connect(os.path.join(dest, "ReaPack/registry.db"))
inst = db.execute("SELECT f.path, f.main, e.package, e.version FROM files f JOIN entries e ON e.id=f.entry "
                  "WHERE e.remote='ZP Suite' ORDER BY f.path").fetchall()
beta = set(open(beta_file, encoding="utf-8").read().split("\n")) - {""}
kb = open(os.path.join(dest, "reaper-kb.ini"), encoding="utf-8", errors="replace").read()
uguali, diversi, mancanti_disco, senza_repo, azioni_mancanti = [], [], [], [], []
installati = set()
for path, main, pkg, ver in inst:
    installati.add(path)
    p = os.path.join(dest, path)
    if not os.path.isfile(p): mancanti_disco.append(f"{path}  [{pkg} {ver}]"); continue
    src = mappa.get(path)
    if src is None:
        alt = per_hash.get(h(p))
        (uguali if alt else senza_repo).append(path + (f"  (= {alt})" if alt else f"  [{pkg} {ver}]"))
    elif h(p) == h(os.path.join(repo, src)): uguali.append(path)
    else: diversi.append(f"{path}  [{pkg} {ver}]")
    if main and path.startswith("Scripts/") and path.endswith(".lua") and f'"{path[len("Scripts/"):]}"' not in kb:
        azioni_mancanti.append(path)
non_distribuiti = sorted({f for d, f in mappa.items() if d not in installati and d not in beta
                          and not (f.startswith("ZP Studio Suite/icons/") and d.startswith("Scripts/") and f.endswith(".png"))})
beta_ok = [b for b in sorted(beta) if os.path.isfile(os.path.join(dest, b))]
import re, urllib.parse
link_rotti = []
for radice, _, nomi in os.walk(os.path.join(dest, "Scripts/ZP Suite")):
    for nome in nomi:
        if not nome.endswith((".html", ".htm")): continue
        p = os.path.join(radice, nome)
        testo = open(p, encoding="utf-8", errors="replace").read()
        for u in sorted(set(re.findall(r'(?:src|href)\s*=\s*["\']([^"\'#?]+)', testo))):
            if re.match(r'^[a-z][a-z0-9+.-]*:', u, re.I) or u.startswith("/"): continue
            if not os.path.exists(os.path.normpath(os.path.join(radice, urllib.parse.unquote(u)))):
                link_rotti.append(f"{os.path.relpath(p, dest)} -> {u}")
gravi = len(diversi) + len(mancanti_disco) + len(azioni_mancanti) + len(link_rotti) + len(non_caricati) \
        + (0 if int(n) >= int(attesi) else 1) + (1 if fumo is None else 0)
riga = ("ESITO: INSTALLAZIONE CONFORME AL REPO" if gravi == 0 else f"ESITO: {gravi} PROBLEMI") + \
       f" — pacchetti {n}/{attesi}, file ReaPack {len(inst)}, uguali al repo {len(uguali)}"
out = [riga, ""]
def sez(titolo, el, nota=""):
    if el: out.extend([f"{titolo} ({len(el)}){nota}:"] + ["  " + e for e in el] + [""])
sez("DIVERSI DAL REPO", diversi, " — pacchetto cambiato senza alzare @version, o file non aggiornato")
sez("REGISTRATI MA ASSENTI SUL DISCO", mancanti_disco)
sez("SCRIPT PRINCIPALI SENZA AZIONE IN reaper-kb.ini", azioni_mancanti)
if fumo is None: out.extend(["FUMO JSFX NON ESEGUITO: REAPER di prova non ha risposto.", ""])
sez("JSFX NON CARICATI (file mancante o rifiutato da REAPER)", non_caricati)
sez("JSFX FERMI CON IL TONO (i loro misuratori reagiscono solo a certi segnali: se li hai modificati, aprili e guarda che compilino)", fermi)
sez("JSFX NON VERIFICABILI CON IL FUMO (non scrivono valori dal codice audio: se li hai modificati, aprili e guarda che compilino)", non_verificabili)
sez("COLLEGAMENTI ROTTI NELL'HELP INSTALLATO (immagini o pagine che l'utente non ha)", link_rotti)
sez("INSTALLATI DA REAPACK SENZA CORRISPONDENTE NEL REPO", senza_repo)
sez("NEL REPO MA NON DISTRIBUITI (gli utenti non li ricevono)", non_distribuiti)
sez("BETA AGGIUNTE A PARTE (solo in questo REAPER)", beta_ok)
open(esito_file, "w", encoding="utf-8").write("\n".join(out))
print("\n".join(out[:2]))
for t, el in (("Diversi dal repo", diversi), ("Registrati ma assenti", mancanti_disco),
              ("Azioni mancanti", azioni_mancanti), ("Link rotti nell'help", link_rotti),
              ("JSFX non caricati", non_caricati), ("JSFX fermi con il tono", fermi),
              ("JSFX non verificabili col fumo", non_verificabili), ("Senza corrispondente nel repo", senza_repo),
              ("Non distribuiti", non_distribuiti), ("Beta aggiunte", beta_ok)):
    if el: print(f"{t}: {len(el)}")
PY
echo
echo "Esito completo: $ESITO"
echo "Copie di prima:  $BACKUP"
echo "REAPER di prova resta aperto: la finestra di ReaPack mostra il resoconto dell'installazione."
echo "La scheda di progetto del fumo JSFX non e' salvata: chiudila senza salvare."
