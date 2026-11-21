#!/usr/bin/env python3
"""ZP Remote — esportazione dei pacchetti dal progetto REAPER (lettura del file .RPP salvato, niente modifiche).

Regole (decise con Paolo, 23/10/2026):
- l'esportazione è limitata alla regione REAPER selezionata; il video, le battute, le note e i marker
  sono ritagliati sui suoi limiti. Le coordinate del manifest restano in secondi progetto e il pacchetto
  include anche un SRT con tempi relativi all'inizio della regione. Ogni marker col nome di un personaggio
  apre un anello per quel personaggio; quelli che iniziano con # aprono un anello condiviso. Sono
  riconosciuti anche i marker-cue numerati di ZP, associati alle battute in base alla posizione;
- le note sono gli item della traccia «Rythmo Band Note» (testo nelle note dell'item);
- le battute sono gli item della traccia «Rythmo Band Testi»: il testo sta nelle note dell'item e il
  personaggio è il prefisso «NOME:» (come nel Gobbo di ZP Suite);
- un pacchetto per la regione selezionata, con tutti i personaggi che vi hanno anelli:
  un proxy video muto, l'audio guida in pezzi FLAC da 30 s (letti solo quando servono, al campione),
  la forma d'onda già calcolata, tutte le battute, le note e gli anelli come punti della timeline;
- nella pagina l'interprete sceglie il suo personaggio (o i suoi) e va sui suoi anelli;
- il pacchetto è anche uno ZIP senza compressione, da mettere su Dropbox e assegnare dal sito.

Uso:
    python3 zp_remote_esporta.py PROGETTO.RPP --region-guid GUID [--uscita CARTELLA] [--personaggi A,B] [--preroll 5] [--postroll 1]
Serve ffmpeg: --ffmpeg PERCORSO (lo passa Crea pacchetto), altrimenti PATH, /usr/local/bin, /opt/homebrew/bin, /opt/local/bin.
"""
import argparse, base64, json, math, os, re, shlex, shutil, subprocess, sys, tempfile, zipfile

# Stesso ordine di remote/zp_ffmpeg.lua (un test controlla che le due liste coincidano).
FFMPEG_CANDIDATI = ("/usr/local/bin/ffmpeg", "/opt/homebrew/bin/ffmpeg", "/opt/local/bin/ffmpeg")


def trova_ffmpeg():
    """PATH, poi i percorsi standard (REAPER aperto dal Finder ha un PATH ridotto); solo file eseguibili."""
    p = shutil.which("ffmpeg")
    if p:
        return p
    for c in FFMPEG_CANDIDATI:
        if os.path.isfile(c) and os.access(c, os.X_OK):
            return c
    return "ffmpeg"
from array import array
from zp_remote_identity import ID_RE, canonical_id, legacy_path_id as old_project_id, project_id_from_lines

TEXT_TRACK = "Rythmo Band Testi"
# Un marker messo a mano cade di solito un po' dopo l'inizio della battuta (o dentro una reazione breve):
# una battuta di quel personaggio che comincia fino a 1,5 s prima del marker appartiene al suo anello.
LEAD = 1.5
NOTES_TRACK = "Rythmo Band Note"
EXPORTER_VERSION = "1.4.0"


# ---------- lettura del .RPP ----------

def parse_rpp(path):
    """Restituisce progetto, tracce (con item) e marker. Legge solo quello che serve."""
    with open(path, encoding="utf-8", errors="replace") as source:
        lines = source.read().splitlines()
    proj = {"fps": 25.0, "offset": 0.0, "sample_rate": 48000, "zp_remote_id": project_id_from_lines(lines), "character_ids": {}}
    markers, tracks = [], []
    stack, track, item, take_src = [], None, None, None
    character_ids_bin = None
    for raw in lines:
        l = raw.strip()
        if l.startswith("<"):
            parts = shlex.split(l[1:], posix=True) if '"' in l else l[1:].split()
            tag = parts[0]
            stack.append(tag)
            if tag == "BIN" and len(stack) == 4 and stack[-3:-1] == ["EXTSTATE", "ZP_REMOTE"] and len(parts) > 1 and parts[1] == "CHARACTER_IDS":
                character_ids_bin = []
            if tag == "TRACK":
                track = {"name": "", "guid": parts[1] if len(parts) > 1 else "", "items": []}
                tracks.append(track)
            elif tag == "ITEM" and track is not None:
                item = {"pos": 0.0, "len": 0.0, "soffs": 0.0, "rate": 1.0, "notes": [], "src": None, "src_type": None, "name": ""}
                track["items"].append(item)
            elif tag == "SOURCE" and item is not None and item["src_type"] is None:
                item["src_type"] = parts[1] if len(parts) > 1 else ""
            continue
        if l == ">":
            if stack and stack[-1] == "BIN" and character_ids_bin is not None:
                try:
                    raw_ids = base64.b64decode("".join(character_ids_bin), validate=True).decode("utf-8")
                    proj["character_ids"] = json.loads(raw_ids)
                except (ValueError, UnicodeDecodeError):
                    sys.exit("Mappa ZP_REMOTE/CHARACTER_IDS non valida nel progetto.")
                character_ids_bin = None
            tag = stack.pop() if stack else None
            if tag == "ITEM": item = None
            elif tag == "TRACK": track = None
            continue
        top = stack[-1] if stack else ""
        if top == "BIN" and character_ids_bin is not None:
            character_ids_bin.append(l)
            continue
        if len(stack) == 1:  # livello del progetto
            if l.startswith("MARKER "):
                p = shlex.split(l)
                # Nelle versioni REAPER che salvano le corsie, l'ultimo campo
                # numerico dopo il GUID è il numero di corsia (1-based).
                # I marker legacy senza GUID/corsia appartengono alla corsia principale.
                has_guid = any(re.fullmatch(r"\{[0-9A-Fa-f-]{32,36}\}", token) for token in p[5:])
                lane = int(p[-1]) if has_guid and p[-1].isdigit() else 1
                guid = next((token for token in p[5:] if re.fullmatch(r"\{[0-9A-Fa-f-]{32,36}\}", token)), None)
                markers.append({"idx": int(p[1]), "pos": float(p[2]), "name": p[3], "flags": int(p[4]) if len(p) > 4 else 0, "lane": lane, "guid": guid})
            elif l.startswith("SMPTESYNC "):
                proj["fps"] = float(l.split()[2]) or proj["fps"]
            elif l.startswith("PROJOFFS "):
                proj["offset"] = float(l.split()[1])
            elif l.startswith("SAMPLERATE "):
                proj["sample_rate"] = int(l.split()[1])
        elif len(stack) == 3 and stack[-2:] == ["EXTSTATE", "ZP_REMOTE"] and l.startswith("CHARACTER_IDS "):
            try:
                raw_ids = l.split(None, 1)[1]
                if raw_ids.startswith('"'):
                    decoded = json.loads(raw_ids)
                    raw_ids = decoded if isinstance(decoded, str) else raw_ids
                proj["character_ids"] = json.loads(raw_ids)
            except (ValueError, TypeError): sys.exit("Mappa ZP_REMOTE/CHARACTER_IDS non valida nel progetto.")
        elif top == "TRACK" and track is not None and l.startswith("NAME "):
            track["name"] = shlex.split(l)[1] if '"' in l else l[5:]
        elif top == "ITEM" and item is not None:
            k = l.split(" ", 1)
            if k[0] == "POSITION": item["pos"] = float(k[1])
            elif k[0] == "LENGTH": item["len"] = float(k[1])
            elif k[0] == "SOFFS": item["soffs"] = float(k[1].split()[0])
            elif k[0] == "PLAYRATE": item["rate"] = float(k[1].split()[0])
            elif k[0] == "NAME": item["name"] = shlex.split(l)[1] if '"' in l else k[1]
        elif top == "NOTES" and item is not None and len(stack) >= 2 and stack[-2] == "ITEM":
            item["notes"].append(l[1:] if l.startswith("|") else l)
        elif top == "SOURCE" and item is not None and l.startswith("FILE ") and item["src"] is None:
            item["src"] = shlex.split(l)[1]
    return proj, tracks, markers


def find_text_track(tracks, expected):
    """Resolve an exact track name or a language-qualified Rythmo Band name."""
    key = re.sub(r"[^A-Z0-9]", "", expected.upper())
    exact = [t for t in tracks if re.sub(r"[^A-Z0-9]", "", t["name"].upper()) == key]
    if len(exact) == 1:
        return exact[0]
    if len(exact) > 1:
        names = ", ".join(repr(t["name"]) for t in exact)
        sys.exit(f"Più tracce corrispondono a «{expected}»: {names}.")
    qualified = [t for t in tracks if re.sub(r"[^A-Z0-9]", "", t["name"].upper()).startswith(key)]
    if len(qualified) == 1:
        return qualified[0]
    if len(qualified) > 1:
        names = ", ".join(repr(t["name"]) for t in qualified)
        sys.exit(f"Più tracce iniziano con «{expected}»: {names}. Rinomina la traccia delle battute in modo univoco.")
    return None


def battute_of(tracks, speaker_names=None):
    tr = find_text_track(tracks, TEXT_TRACK)
    if not tr:
        sys.exit(f"Manca una traccia che inizi con «{TEXT_TRACK}» e contenga le battute.")
    speakers = {norm(name): name for name in (speaker_names or []) if norm(name)}
    out = []
    for it in sorted(tr["items"], key=lambda i: i["pos"]):
        text = " ".join(x.strip() for x in it["notes"]).strip()
        m = re.match(r"^\s*([^:\n]{1,40}?)\s*:\s*(.*)$", text)
        candidate = m.group(1).strip() if m else ""
        # Con marker-personaggio noti, un prefisso è un parlante solo se coincide con uno di loro.
        # Così i due punti del dialogo (es. «Beh, è l'insegnante di Joey: ...») restano testo.
        if m and (not speakers or norm(candidate) in speakers):
            who, line = speakers.get(norm(candidate), candidate.upper()), m.group(2).strip()
        else:
            who, line = "", text
        out.append({"s": round(it["pos"], 6), "e": round(it["pos"] + it["len"], 6), "t": line, "p": who})
    return out


def notes_of(tracks):
    tr = find_text_track(tracks, NOTES_TRACK)
    if not tr:
        return []
    return [{"s": round(i["pos"], 6), "e": round(i["pos"] + i["len"], 6), "t": " ".join(x.strip() for x in i["notes"]).strip()}
            for i in sorted(tr["items"], key=lambda i: i["pos"]) if i["notes"]]


def videos_of(tracks, base):
    videos = []
    for t in tracks:
        for it in t["items"]:
            if (it["src_type"] or "").upper() == "VIDEO" and it["src"]:
                src = it["src"] if os.path.isabs(it["src"]) else os.path.join(base, it["src"])
                videos.append({"file": src, "pos": it["pos"], "len": it["len"], "soffs": it["soffs"], "rate": it["rate"]})
    if not videos:
        sys.exit("Nessun item video nel progetto.")
    return videos


def video_for_region(videos, region):
    start, end = region["start_s"], region["end_s"]
    overlaps = [v for v in videos if min(end, v["pos"] + v["len"]) > max(start, v["pos"])]
    if not overlaps:
        spans = ", ".join(f"{v['pos']:.2f}–{v['pos'] + v['len']:.2f} s" for v in videos)
        sys.exit(f"La regione ({start:.2f}–{end:.2f} s) non interseca gli item video del progetto ({spans}). Controlla che la regione sia sulla stessa timeline del video.")
    if len(overlaps) > 1:
        spans = ", ".join(f"{v['pos']:.2f}–{v['pos'] + v['len']:.2f} s" for v in overlaps)
        sys.exit(f"La regione interseca più item video ({spans}). Sposta o accorcia la regione perché contenga un solo item video.")
    return overlaps[0]


def regions_of(markers):
    """Ricostruisce le regioni REAPER dalle coppie MARKER con lo stesso indice."""
    regions = []
    starts = [m for m in markers if (m["flags"] & 1) and m["name"].strip()]
    for start in starts:
        ends = [m for m in markers if (m["flags"] & 1) and m["idx"] == start["idx"]
                and m["pos"] > start["pos"] and not m["name"].strip()]
        if not ends:
            continue
        end = min(ends, key=lambda marker: marker["pos"])
        regions.append({"name": start["name"], "start_s": start["pos"], "end_s": end["pos"],
                        "guid": start.get("guid") or end.get("guid"), "marker_id": start["idx"]})
    return sorted(regions, key=lambda region: region["start_s"])


def select_region(markers, region_guid=None, region_name=None, region_start=None, region_end=None):
    regions = regions_of(markers)
    if region_guid:
        candidates = [region for region in regions if region.get("guid") and region["guid"].upper() == region_guid.upper()]
    elif region_name:
        candidates = [region for region in regions if region["name"] == region_name]
        if region_start is not None:
            candidates = [region for region in candidates if abs(region["start_s"] - region_start) <= 1e-6]
        if region_end is not None:
            candidates = [region for region in candidates if abs(region["end_s"] - region_end) <= 1e-6]
    else:
        sys.exit("Seleziona la regione da esportare nella finestra ZP Remote.")
    if len(candidates) != 1:
        sys.exit(f"Regione da esportare non identificata in modo univoco (corrispondenze: {len(candidates)}). Salva il progetto e riselezionala.")
    region = candidates[0]
    if region["end_s"] <= region["start_s"]:
        sys.exit("La regione selezionata ha una durata non valida.")
    if region_start is not None and abs(region["start_s"] - region_start) > 1e-6:
        sys.exit("L'inizio della regione selezionata non coincide con quello salvato nel progetto.")
    if region_end is not None and abs(region["end_s"] - region_end) > 1e-6:
        sys.exit("La fine della regione selezionata non coincide con quella salvata nel progetto.")
    return region


def clip_video_to_region(video, region):
    start, end = region["start_s"], region["end_s"]
    video_end = video["pos"] + video["len"]
    clipped_start, clipped_end = max(start, video["pos"]), min(end, video_end)
    if clipped_end <= clipped_start:
        sys.exit("La regione selezionata non interseca l'item video.")
    if abs(video["rate"] - 1.0) > 1e-9:
        sys.exit("L'item video ha una velocità diversa da 1×: per evitare disallineamenti, l'export per regione richiede velocità normale.")
    return {**video, "pos": clipped_start, "len": clipped_end - clipped_start,
            "soffs": video["soffs"] + (clipped_start - video["pos"]) * video["rate"]}


def clip_records(records, start, end):
    """Tiene i record che intersecano la regione e ne limita gli estremi."""
    out = []
    for record in records:
        left, right = max(record["s"], start), min(record["e"], end)
        if right <= left:
            continue
        out.append({**record, "s": round(left, 6), "e": round(right, 6)})
    return out


def srt_timestamp(seconds):
    millis = max(0, round(seconds * 1000))
    hours, millis = divmod(millis, 3_600_000)
    minutes, millis = divmod(millis, 60_000)
    secs, millis = divmod(millis, 1000)
    return f"{hours:02d}:{minutes:02d}:{secs:02d},{millis:03d}"


def make_srt(battute, region):
    cues = []
    for b in clip_records(battute, region["start_s"], region["end_s"]):
        text = f"{b['p']}: {b['t']}" if b["p"] and b["t"] else b["t"]
        if not text.strip():
            continue
        start = max(0.0, b["s"] - region["start_s"])
        end = max(start + 0.001, b["e"] - region["start_s"])
        cues.append((start, end, text))
    cues.sort(key=lambda cue: cue[0])
    return "\n\n".join(f"{i}\n{srt_timestamp(start)} --> {srt_timestamp(end)}\n{text}"
                        for i, (start, end, text) in enumerate(cues, 1)) + ("\n" if cues else "")


def norm(x):
    return re.sub(r"[^A-Z0-9]", "", x.upper())


def owner_of(name, people):
    """Il personaggio di un marker: nome intero o abbreviato (inizio del nome). None se non torna o è ambiguo."""
    n = norm(name)
    if len(n) < 2:
        return None
    exact = [p for p in people if norm(p) == n]
    if exact:
        return exact[0]
    pref = [p for p in people if norm(p).startswith(n)]
    return pref[0] if len(pref) == 1 else None


def numbered_cue_marker(name):
    """Formato del worker ZP: nome base + indice progressivo + timecode video."""
    match = re.fullmatch(r"(.+?)\s+(\d{3,})\s+(\d{2}:\d{2}:\d{2}:\d{2})", name.strip())
    return (match.group(1).strip(), int(match.group(2)), match.group(3)) if match else None


def markers_in_region(markers, region):
    """Limita marker e cue al progetto temporale della regione esportata."""
    start, end = region["start_s"], region["end_s"]
    return [m for m in markers if start <= m["pos"] < end]


def character_marker_names(markers):
    """I marker semplici dentro la regione nominano direttamente i personaggi/anelli."""
    names = {
        m["name"].strip() for m in markers
        if not (m["flags"] & 1) and m.get("lane", 1) in (1, 2)
        and m["name"].strip() and not m["name"].strip().startswith("#")
        and not numbered_cue_marker(m["name"])
    }
    return sorted(names, key=str.casefold)


def marker_roles_for_cues(markers, battute):
    """Collega marker numerati agli item RythmoBand; per una sola voce senza prefisso crea un'etichetta esplicita."""
    cue_markers = [(m, numbered_cue_marker(m["name"])) for m in markers
                   if not (m["flags"] & 1) and m.get("lane", 1) in (1, 2)]
    cue_markers = [(m, parsed) for m, parsed in cue_markers if parsed]
    if not cue_markers:
        return battute, {}, set()

    bases = sorted({parsed[0] for _, parsed in cue_markers}, key=lambda value: value.casefold())
    existing_people = sorted({b["p"] for b in battute if b["p"]})
    roles_by_base = {}
    for base in bases:
        role = owner_of(base, existing_people)
        if not role and len(existing_people) == 1 and not base.isdigit():
            role = existing_people[0]
        if not role and not existing_people:
            role = f"Personaggio {base}" if base.isdigit() else base
        if not role and base.isdigit():
            # Nei marker numerici il numero identifica la serie/voce; un colon nel testo può essere punteggiatura,
            # quindi non basta a trasformare una frase in un nome di personaggio.
            role = f"Personaggio {base}"
        if role:
            roles_by_base[base] = role

    roles_by_marker = {}
    for marker, (base, _sequence, _timecode) in cue_markers:
        role = roles_by_base.get(base)
        # Se il testo porta già il personaggio, prevale il prefisso della battuta.
        nearby = [b for b in battute if b["p"] and abs(b["s"] - marker["pos"]) <= 0.25]
        if nearby and not base.isdigit():
            role = min(nearby, key=lambda b: abs(b["s"] - marker["pos"]))["p"]
        if role:
            roles_by_marker[marker["idx"]] = role

    fallback_roles = sorted(set(roles_by_marker.values()))
    enriched = []
    for cue in battute:
        near = [(abs(m["pos"] - cue["s"]), roles_by_marker.get(m["idx"])) for m, _ in cue_markers
                if abs(m["pos"] - cue["s"]) <= 0.25 and roles_by_marker.get(m["idx"])]
        role = min(near, key=lambda pair: pair[0])[1] if near else (cue["p"] or (fallback_roles[0] if len(fallback_roles) == 1 else ""))
        enriched.append({**cue, "p": role})
    return enriched, roles_by_marker, {norm(base) for base in roles_by_base}


def anelli_of(markers, video, people, marker_roles=None, role_bases=None):
    """Anelli: dai marker col nome di un personaggio (anello di quel personaggio) o con # (anello di chi ci parla)."""
    end_video = video["pos"] + video["len"]
    cuts, ignored = [], []
    marker_roles = marker_roles or {}
    role_bases = role_bases or set()
    for m in sorted((m for m in markers if not (m["flags"] & 1) and m.get("lane", 1) in (1, 2)), key=lambda m: m["pos"]):
        if m["idx"] in marker_roles:
            cuts.append({**m, "owner": marker_roles[m["idx"]]})
        elif numbered_cue_marker(m["name"]):
            ignored.append(m["name"])
        elif norm(m["name"]) in role_bases:
            # Marker base (per esempio "1") usato per creare la serie numerata: è un'etichetta, non un cue.
            continue
        elif m["name"].startswith("#"):
            cuts.append({**m, "owner": None})
        elif (who := owner_of(m["name"], people)):
            cuts.append({**m, "owner": who})
        elif m["name"].strip():
            ignored.append(m["name"])
    if not cuts:
        sys.exit("Nessun marker d'anello riconosciuto nelle corsie 1 e 2. Sono accettati il nome del personaggio, #, oppure i marker numerati ZP nel formato «nome 001 HH:MM:SS:FF». La corsia 3 è riservata alle informazioni interne e viene ignorata.")
    if ignored:
        print("Marker ignorati (nessun personaggio riconosciuto):", ", ".join(sorted(set(ignored))))
    out = []
    for k, m in enumerate(cuts):
        aid = f"L{m['idx']:04d}"
        if m["name"].startswith("#") and m["name"][1:].strip().isdigit():
            aid = f"L{int(m['name'][1:]):04d}"
        out.append({"id": aid, "nome": m["name"], "guid": m.get("guid"), "owner": m["owner"], "inizio": m["pos"],
                    "fine": cuts[k + 1]["pos"] if k + 1 < len(cuts) else end_video})
    ids = [a["id"] for a in out]
    if len(set(ids)) != len(ids):
        sys.exit("Due marker producono lo stesso anello: ogni marker # deve avere un numero diverso.")
    return out, sorted(set(ignored))


# ---------- esportazione ----------

def safe(s):
    return re.sub(r"[^A-Za-z0-9]+", "-", s).strip("-") or "x"


def marker_key(value):
    return str(value or "").strip().strip("{}").replace("-", "").lower()


def character_marker_map(rings, people):
    mapped = {person: [] for person in people}
    for ring in rings:
        person, guid = ring.get("owner"), ring.get("guid")
        if person in mapped and guid:
            mapped[person].append(guid)
    return {person: sorted(set(guids)) for person, guids in mapped.items()}


def character_ids_for_export(project, rings, people):
    registry = project.get("character_ids") or {}
    by_marker = registry.get("by_marker", {}) if isinstance(registry, dict) else {}
    by_name = registry.get("by_name", {}) if isinstance(registry, dict) else {}
    if not isinstance(by_marker, dict) or not isinstance(by_name, dict):
        sys.exit("Mappa CHARACTER_IDS non valida nel progetto.")
    result, used_ids = {}, {}
    for person in people:
        # Se il nome è già noto, è la mappa per nome a prevalere: corregge marker
        # rinominati da un'etichetta errata senza chiedere di cancellarli/ricrearli.
        named = by_name.get(norm(person))
        if named:
            identity = canonical_id(named, "pers")
            if not identity:
                sys.exit(f"ID personaggio non valido o di tipo diverso per {person}.")
        else:
            candidates = set()
            for ring in rings:
                if ring.get("owner") != person or not ring.get("guid"):
                    continue
                raw = by_marker.get(marker_key(ring["guid"]))
                if raw:
                    identity = canonical_id(raw, "pers")
                    if not identity:
                        sys.exit(f"ID personaggio non valido o di tipo diverso per {person}.")
                    candidates.add(identity)
            if len(candidates) > 1:
                sys.exit(f"Il personaggio {person} è collegato a più ID. Risolvi la mappa CHARACTER_IDS prima di esportare.")
            if not candidates:
                sys.exit(f"ID stabile assente per {person}: usa l'azione REAPER guidata per assegnarlo e salvarlo nel progetto.")
            identity = candidates.pop()
        if identity in used_ids and used_ids[identity] != person:
            sys.exit(f"Lo stesso ID personaggio è assegnato a {used_ids[identity]} e {person}.")
        used_ids[identity] = person
        result[person] = identity
    return result


def inspect_project(rpp, ffmpeg="ffmpeg", region_guid=None, region_name=None, region_start=None, region_end=None):
    """Controllo senza scritture, per l'azione guidata di REAPER."""
    base = os.path.dirname(os.path.abspath(rpp))
    proj, tracks, markers = parse_rpp(rpp)
    notes = notes_of(tracks)
    source_videos = videos_of(tracks, base)
    region = select_region(markers, region_guid, region_name, region_start, region_end)
    region_markers = markers_in_region(markers, region)
    marker_people = character_marker_names(region_markers)
    battute = battute_of(tracks, marker_people or None)
    battute, marker_roles, role_bases = marker_roles_for_cues(region_markers, battute)
    source_video = video_for_region(source_videos, region)
    video = clip_video_to_region(source_video, region)
    if not os.path.isfile(video["file"]):
        sys.exit(f"Video non trovato: {video['file']}")
    people = sorted({b["p"] for b in battute if b["p"]} | set(marker_people))
    rings, ignored = anelli_of(region_markers, video, people, marker_roles, role_bases)
    guid = proj["zp_remote_id"]
    if not guid:
        sys.exit("Il progetto non ha ancora un'identità ZP Remote.")
    if not ID_RE.fullmatch(guid):
        sys.exit("L'identità ZP Remote nel progetto non è valida.")
    if not os.path.isfile(ffmpeg):
        resolved = shutil.which(ffmpeg)
        if resolved:
            ffmpeg = resolved
        else:
            sys.exit("Non trovo FFmpeg. Nel Benvenuto (33 Controllo installazione) usa «Scegli FFmpeg…» o «Come installare FFmpeg…».")
    return {
        "ok": True,
        "progetto": os.path.splitext(os.path.basename(rpp))[0],
        "video": os.path.basename(video["file"]),
        "durata_s": round(video["len"], 1),
        "regione": region["name"],
        "inizio_regione_s": round(region["start_s"], 3),
        "fine_regione_s": round(region["end_s"], 3),
        "personaggi": people,
        "personaggi_marker": character_marker_map(rings, people),
        "anelli_marker": len(rings),
        "marker_ignorati": ignored,
        "battute": len(clip_records(battute, region["start_s"], region["end_s"])),
        "note": len(clip_records(notes, region["start_s"], region["end_s"])),
        "anelli_senza_battuta": sum(1 for ring in rings if ring["owner"] and not any((not b["p"] or b["p"] == ring["owner"]) and ring["inizio"] - LEAD <= b["s"] < ring["fine"] for b in battute)),
    }


def run(cmd):
    r = subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
    if r.returncode:
        sys.exit("ffmpeg non è riuscito:\n" + r.stderr[-800:])


SEG_S = 30            # durata dei pezzi dell'audio guida
PEAKS_PER_S = 100     # risoluzione della forma d'onda nel manifest
SR = 48000


def make_poster(ffmpeg, video, pkg, poster_jpg=None, poster_project_s=None):
    """Scrive il poster 640×360: JPG scelto dall'utente o fotogramma del video esportato."""
    destination = os.path.join(pkg, "poster.jpg")
    scale_crop = "scale=640:360:force_original_aspect_ratio=increase,crop=640:360"
    if poster_jpg:
        if not os.path.isfile(poster_jpg):
            sys.exit(f"Immagine poster non trovata: {poster_jpg}")
        source = ["-i", poster_jpg]
    else:
        if poster_project_s is None:
            poster_frame_s = video["len"] / 2
        else:
            if not math.isfinite(poster_project_s):
                sys.exit("Posizione del fotogramma poster non valida.")
            poster_frame_s = float(poster_project_s) - video["pos"]
        poster_frame_s = max(0.0, min(poster_frame_s, max(0.0, video["len"] - 0.001)))
        source_time = video["soffs"] + poster_frame_s
        source = ["-ss", f"{source_time:.6f}", "-i", video["file"]]
    run([ffmpeg, "-loglevel", "error", "-y", *source, "-frames:v", "1", "-vf", scale_crop,
         "-q:v", "2", destination])


def guide_segments(ffmpeg, video, pkg):
    """Decodifica l'audio del video una volta sola, lo taglia in pezzi esatti al campione (FLAC) e calcola i picchi."""
    dec_err = tempfile.TemporaryFile()   # errori del decoder: un file, cosi' non si blocca la lettura dell'audio
    dec = subprocess.Popen([ffmpeg, "-loglevel", "error", "-ss", f"{video['soffs']:.6f}", "-i", video["file"], "-t", f"{video['len']:.6f}",
                            "-vn", "-ac", "2", "-ar", str(SR), "-f", "s16le", "-"], stdout=subprocess.PIPE, stderr=dec_err)
    seg_bytes, step = SEG_S * SR * 4, SR // PEAKS_PER_S
    segs, peaks, k = [], bytearray(), 0
    os.makedirs(os.path.join(pkg, "guida"), exist_ok=True)
    while True:
        chunk = dec.stdout.read(seg_bytes)
        if not chunk:
            break
        name = f"guida/{k:04d}.flac"
        enc = subprocess.run([ffmpeg, "-loglevel", "error", "-y", "-f", "s16le", "-ar", str(SR), "-ac", "2", "-i", "-", "-c:a", "flac",
                              os.path.join(pkg, name)], input=chunk)
        if enc.returncode:
            sys.exit("ffmpeg non ha scritto la guida.")
        frames = len(chunk) // 4
        segs.append({"file": name, "s": round(video["pos"] + k * SEG_S, 6), "dur": round(frames / SR, 6)})
        smp = array("h"); smp.frombytes(chunk[: frames * 4])
        for i in range(0, frames, step):
            blk = smp[i * 2:(i + step) * 2]
            p = max(max(blk), -min(blk)) / 32768 if blk else 0
            peaks.append(0 if p <= 0 else max(0, min(255, round(255 * (1 + math.log10(p) / 2.4)))))
        k += 1
    if dec.wait():
        dec_err.seek(0)
        msg = dec_err.read().decode("utf-8", "replace").strip()[-800:]
        sys.exit("ffmpeg non è riuscito a leggere l'audio del video per la guida" + (":\n" + msg if msg else "."))
    return segs, base64.b64encode(bytes(peaks)).decode()


def export(rpp, out_dir, only=None, preroll=5.0, postroll=1.0, base=None, ffmpeg="ffmpeg", legacy_path_id=False,
           region_guid=None, region_name=None, region_start=None, region_end=None, poster_jpg=None, poster_project_s=None,
           package_name=None, overwrite=False):
    base = base or os.path.dirname(os.path.abspath(rpp))
    proj, tracks, markers = parse_rpp(rpp)
    fps = proj["fps"]
    notes = notes_of(tracks)
    source_videos = videos_of(tracks, base)
    region = select_region(markers, region_guid, region_name, region_start, region_end)
    region_markers = markers_in_region(markers, region)
    marker_people = character_marker_names(region_markers)
    battute = battute_of(tracks, marker_people or None)
    battute, marker_roles, role_bases = marker_roles_for_cues(region_markers, battute)
    source_video = video_for_region(source_videos, region)
    video = clip_video_to_region(source_video, region)
    if not os.path.isfile(video["file"]):
        sys.exit(f"Video non trovato: {video['file']}")
    people = sorted({b["p"] for b in battute if b["p"]} | set(marker_people))
    anelli, _ = anelli_of(region_markers, video, people, marker_roles, role_bases)
    region_battute = clip_records(battute, region["start_s"], region["end_s"])
    if only:
        keep = {x.strip().upper() for x in only}
        people = [p for p in people if p in keep]
    pname = os.path.splitext(os.path.basename(rpp))[0]
    guid = proj["zp_remote_id"]
    if not guid:
        if not legacy_path_id:
            sys.exit("ID ZP Remote assente dal progetto: inizializzalo con l'azione REAPER prima di esportare.")
        guid = old_project_id(rpp)
    if not ID_RE.fullmatch(guid):
        sys.exit("ID ZP Remote non valido nel progetto.")
    project_id = canonical_id(guid, "prj")
    person_ids = character_ids_for_export(proj, anelli, people)
    tracks_by_name = {t["name"].upper(): t["guid"] for t in tracks}

    # ogni battuta va al marker del suo personaggio più recente (fino a LEAD secondi dopo l'inizio della battuta)
    assign = {}
    for b in region_battute:
        cands = [a for a in anelli
                 if (a["owner"] == b["p"] if b["p"] else a["owner"] is not None)
                 and a["inizio"] - LEAD <= b["s"] < a["fine"]]
        if cands:
            # Battute senza prefisso: attribuisci al marker più vicino; una battuta può iniziare
            # pochi frame prima del suo marker, ma non va spostata al personaggio successivo.
            best = min(cands, key=lambda a: abs(a["inizio"] - b["s"])) if not b["p"] else max(cands, key=lambda a: a["inizio"])
            assigned_owner = b["p"] or best["owner"]
            assign.setdefault((best["id"], assigned_owner), []).append(b)
    units, skipped, extra = [], [], []
    for a in anelli:
        owners = [a["owner"]] if a["owner"] else sorted({p for (i, p) in assign if i == a["id"] and p})
        for who in owners:
            if who not in people:
                continue
            mine = assign.get((a["id"], who), [])
            if not mine:
                # marker senza battuta scritta (gemiti, respiri, voci sovrapposte): si registra lo stesso, l'attacco è il marker
                skipped.append(f"{a['nome']} a {a['inizio']:.2f} s")
                extra.append({"s": round(a["inizio"], 6), "e": round(min(a["fine"], a["inizio"] + 3), 6),
                              "t": "(voce senza battuta scritta: vedi le note)", "p": who})
            units.append({
                "id": a["id"], "marker": a["nome"], "personaggio": who, "personaggio_id": person_ids[who], "track_guid": tracks_by_name.get(who, ""),
                "inizio_s": round(a["inizio"], 6), "fine_s": round(a["fine"], 6),
                "attacco_s": round(mine[0]["s"] if mine else a["inizio"], 6),
                "fine_battute_s": round(mine[-1]["e"] if mine else a["fine"], 6),
                "testo": " ".join(b["t"] for b in mine if b["t"]) or "(senza battuta scritta)",
                "senza_battuta": not mine,
            })
    if skipped:
        print("Anelli senza battuta scritta (si registrano lo stesso, attacco sul marker):", ", ".join(skipped))
    if not units:
        sys.exit("Nessun anello da esportare per i personaggi scelti.")

    package_name = safe(package_name or f"{pname}-{region['name']}-{region['marker_id']}")
    final_zip = os.path.join(out_dir, package_name + ".zip")
    if os.path.exists(final_zip) and not overwrite:
        sys.exit("Esiste già uno ZIP con questo nome. Conferma la sovrascrittura oppure scegli un nuovo nome.")
    os.makedirs(out_dir, exist_ok=True)
    pkg = tempfile.mkdtemp(prefix="." + safe(pname) + "-zp-", dir=out_dir)
    staged_zip = pkg + ".zip"
    try:
        return export_to_folder(rpp, pkg, final_zip, staged_zip, video, region, proj, tracks, markers, battute, notes, people, anelli, units, skipped, extra, fps, guid, project_id, person_ids, pname, preroll, ffmpeg, poster_jpg, poster_project_s, overwrite)
    finally:
        shutil.rmtree(pkg, ignore_errors=True)
        try: os.remove(staged_zip)
        except FileNotFoundError: pass


def export_to_folder(rpp, pkg, final_zip, staged_zip, video, region, proj, tracks, markers, battute, notes, people, anelli, units, skipped, extra, fps, guid, project_id, person_ids, pname, preroll, ffmpeg, poster_jpg=None, poster_project_s=None, overwrite=False):
    # video unico, muto, con fotogrammi chiave frequenti (si salta in fretta da un anello all'altro)
    run([ffmpeg, "-loglevel", "error", "-y", "-ss", f"{video['soffs']:.6f}", "-i", video["file"], "-t", f"{video['len']:.6f}",
         "-an", "-c:v", "libx264", "-preset", "veryfast", "-crf", "24", "-g", str(int(round(fps))), "-pix_fmt", "yuv420p",
         "-movflags", "+faststart", os.path.join(pkg, "video.mp4")])
    make_poster(ffmpeg, video, pkg, poster_jpg, poster_project_s)
    segs, peaks = guide_segments(ffmpeg, video, pkg)
    clipped_battute = clip_records(battute, region["start_s"], region["end_s"])
    clipped_notes = clip_records(notes, region["start_s"], region["end_s"])
    srt_path = os.path.join(pkg, "sottotitoli.srt")
    with open(srt_path, "w", encoding="utf-8-sig", newline="\n") as subtitle_file:
        subtitle_file.write(make_srt(battute, region))
    counts = {p: sum(1 for u in units if u["personaggio"] == p) for p in people}
    manifest = {
        "zp_remote": 2, "versione": "P0", "esportatore_versione": EXPORTER_VERSION, "esportato_da": os.path.basename(rpp),
        "project": {"name": pname, "guid": guid, "id": project_id, "fps": fps, "sample_rate": SR, "start_offset_s": proj["offset"]},
        "interprete": "", "preroll_s": preroll,
        "region": {"guid": region.get("guid"), "name": region["name"], "start_s": round(region["start_s"], 6), "end_s": round(region["end_s"], 6)},
        "timeline": {"inizio_s": round(video["pos"], 6), "durata_s": round(video["len"], 6)},
        "video": "video.mp4",
        "poster": "poster.jpg",
        "sottotitoli": "sottotitoli.srt",
        "guida": segs,
        "picchi": {"per_s": PEAKS_PER_S, "dati": peaks},
        "personaggi": [{"id": person_ids[p], "nome": p, "anelli": n} for p, n in counts.items() if n],
        "battute": sorted([{"s": b["s"], "e": b["e"], "t": b["t"] or "(reazione)", "p": b["p"]} for b in clipped_battute] + extra, key=lambda b: b["s"]),
        "note": clipped_notes,
        "anelli": units,
    }
    json.dump(manifest, open(os.path.join(pkg, "manifest.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    zpath = staged_zip
    with zipfile.ZipFile(zpath, "w", zipfile.ZIP_STORED) as z:
        for root, _, files in os.walk(pkg):
            for f in sorted(files):
                full = os.path.join(root, f)
                z.write(full, os.path.relpath(full, pkg))
    mb = round(os.path.getsize(zpath) / 1048576, 1)
    if os.path.exists(final_zip) and not overwrite:
        sys.exit("Nel frattempo è apparso uno ZIP con lo stesso nome. Nessun file esistente è stato sovrascritto.")
    os.replace(zpath, final_zip)
    for p, n in counts.items():
        if n:
            print(f"  {p}: {n} anelli")
    print(f"✓ Regione {region['name']}: {len(units)} anelli, {len(clipped_notes)} note, video {video['len']:.1f} s, guida in {len(segs)} pezzi → {os.path.basename(final_zip)} ({mb} MB)")
    return {"zip": final_zip, "anelli": len(units), "personaggi": counts, "mb": mb, "regione": region["name"], "durata_s": video["len"]}


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("rpp")
    ap.add_argument("--uscita", help="cartella dei pacchetti (di solito una cartella Dropbox); predefinita: ZP_Remote_Export accanto al progetto")
    ap.add_argument("--personaggi", help="solo questi personaggi, separati da virgola")
    ap.add_argument("--preroll", type=float, default=5.0)
    ap.add_argument("--postroll", type=float, default=1.0)
    ap.add_argument("--base", help="cartella da cui risolvere i file del progetto (se il .RPP è una copia altrove)")
    ap.add_argument("--ffmpeg", default=trova_ffmpeg())
    ap.add_argument("--legacy-path-id", action="store_true", help="solo compatibilità con vecchi pacchetti: ID derivato dal percorso")
    ap.add_argument("--region-guid", help="GUID della regione REAPER selezionata")
    ap.add_argument("--region-name", help="nome della regione REAPER selezionata")
    ap.add_argument("--region-start", type=float, help=argparse.SUPPRESS)
    ap.add_argument("--region-end", type=float, help=argparse.SUPPRESS)
    ap.add_argument("--poster-jpg", help="JPG personalizzato da includere come poster 640×360")
    ap.add_argument("--poster-project-s", type=float, help="tempo del cursore REAPER in secondi progetto; il fotogramma viene limitato alla parte video dentro la regione")
    ap.add_argument("--nome-pacchetto", help="nome personalizzato dello ZIP, senza estensione")
    ap.add_argument("--sovrascrivi", action="store_true", help="sovrascrive lo ZIP esistente solo dopo conferma esplicita nell'interfaccia REAPER")
    ap.add_argument("--controlla", action="store_true", help="controlla il progetto senza creare file e stampa un riepilogo JSON")
    ap.add_argument("--stato-file", help=argparse.SUPPRESS)
    a = ap.parse_args()
    out = a.uscita or os.path.join(os.path.dirname(os.path.abspath(a.rpp)), "ZP_Remote_Export")
    try:
        if a.controlla:
            try:
                result = inspect_project(a.rpp, a.ffmpeg, a.region_guid, a.region_name, a.region_start, a.region_end)
            except SystemExit as e:
                print(json.dumps({"ok": False, "errore": str(e.code)}, ensure_ascii=False))
                raise
            print(json.dumps(result, ensure_ascii=False))
            raise SystemExit(0)
        if a.stato_file:
            with open(a.stato_file, "w", encoding="utf-8") as f:
                json.dump({"stato": "in_corso"}, f)
        s = export(a.rpp, out, a.personaggi.split(",") if a.personaggi else None, a.preroll, a.postroll, a.base, a.ffmpeg, a.legacy_path_id,
                   a.region_guid, a.region_name, a.region_start, a.region_end, a.poster_jpg, a.poster_project_s,
                   a.nome_pacchetto, a.sovrascrivi)
        print(f"Pacchetto in {s['zip']}")
        result = {"stato": "completato", "zip": s["zip"], "anelli": s["anelli"], "mb": s["mb"], "personaggi": s["personaggi"], "regione": s["regione"], "durata_s": s["durata_s"]}
    except SystemExit as e:
        if not a.stato_file or e.code == 0:
            raise
        result = {"stato": "errore", "messaggio": str(e.code)}
        sys.exit(e.code)
    except Exception as e:
        if not a.stato_file:
            raise
        result = {"stato": "errore", "messaggio": str(e)}
        sys.exit(1)
    finally:
        if a.stato_file and "result" in locals():
            with open(a.stato_file, "w", encoding="utf-8") as f:
                json.dump(result, f, ensure_ascii=False)
