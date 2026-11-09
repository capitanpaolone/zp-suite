#!/usr/bin/env python3
"""Read-only validation and normalized plan builder for ZP Remote deliveries."""
from __future__ import annotations
import argparse, hashlib, json, math, re, shlex, shutil, struct, sys, tempfile, zipfile
from pathlib import Path, PurePosixPath
from datetime import datetime, timezone
from zp_remote_identity import canonical_id, legacy_path_id, project_id_from_lines

SAMPLE_RATE = 48000

def fail(message): raise ValueError(message)
def finite_number(value, label):
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value): fail(f"{label}: numero non valido")
    return float(value)
def safe_rel(value, label):
    if not isinstance(value, str) or not value or "\\" in value or "\x00" in value: fail(f"{label}: percorso non valido")
    p = PurePosixPath(value)
    if p.is_absolute() or any(part in ("", ".", "..") for part in p.parts): fail(f"{label}: percorso relativo non sicuro: {value!r}")
    return p

def sha256(path):
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""): h.update(block)
    return h.hexdigest()

def read_wav(path):
    size = path.stat().st_size
    with path.open("rb") as f:
        head = f.read(12)
        if len(head) != 12 or head[:4] != b"RIFF" or head[8:] != b"WAVE": fail(f"{path.name}: WAV RIFF non valido")
        riff_size = struct.unpack_from("<I", head, 4)[0]
        if riff_size + 8 != size: fail(f"{path.name}: dimensione RIFF incoerente")
        pos, chunks, fmt, data_size, bext, ixml, bext_recorded_at = 12, [], None, None, None, None, None
        while pos < size:
            f.seek(pos); hdr = f.read(8)
            if len(hdr) != 8: fail(f"{path.name}: chunk WAV troncato")
            cid, n = hdr[:4], struct.unpack("<I", hdr[4:])[0]
            body = pos + 8
            if body + n > size: fail(f"{path.name}: chunk WAV oltre EOF")
            chunks.append(cid.decode("ascii", "replace"))
            if cid == b"fmt ":
                f.seek(body); raw = f.read(min(n, 40))
                if len(raw) < 16: fail(f"{path.name}: fmt incompleto")
                tag, channels, sr, byte_rate, align, bits = struct.unpack_from("<HHIIHH", raw)
                fmt = dict(tag=tag, channels=channels, sample_rate=sr, byte_rate=byte_rate, block_align=align, bits=bits)
            elif cid == b"data": data_size = n
            elif cid == b"bext":
                if n < 346: fail(f"{path.name}: bext troppo corto")
                f.seek(body + 320)
                recorded_date = f.read(10).decode("ascii", "replace").strip("\x00 ")
                recorded_time = f.read(8).decode("ascii", "replace").strip("\x00 ")
                try:
                    if recorded_date and recorded_time:
                        datetime.fromisoformat(f"{recorded_date}T{recorded_time}")
                        bext_recorded_at = f"{recorded_date}T{recorded_time}"
                except ValueError:
                    pass
                f.seek(body + 338); lo, hi = struct.unpack("<II", f.read(8)); bext = lo + (hi << 32)
            elif cid == b"iXML":
                if n > 2_000_000: fail(f"{path.name}: iXML troppo grande")
                f.seek(body); ixml = f.read(n).decode("utf-8", "strict")
            pos = body + n + (n & 1)
        if pos != size: fail(f"{path.name}: padding chunk WAV incoerente")
    if not fmt or data_size is None or bext is None or not ixml: fail(f"{path.name}: manca fmt/data/bext/iXML")
    if fmt["tag"] not in (1, 0xFFFE) or fmt["channels"] != 1 or fmt["sample_rate"] != SAMPLE_RATE or fmt["bits"] != 24 or fmt["block_align"] != 3: fail(f"{path.name}: atteso PCM mono 24-bit / 48 kHz")
    if data_size % fmt["block_align"]: fail(f"{path.name}: blocco data non multiplo del frame")
    frames = data_size // fmt["block_align"]
    if not re.search(r"<BWFXML(?:\s|>)", ixml): fail(f"{path.name}: iXML BWFXML assente")
    return {"chunks": chunks, "frames": frames, "time_reference": bext, "sample_rate": fmt["sample_rate"], "channels": fmt["channels"], "bits": fmt["bits"], "ixml": ixml, "bext_recorded_at": bext_recorded_at}

def utc_recorded_at(value, label):
    if value is None: return None
    if not isinstance(value, str) or not value.strip(): fail(f"{label}: data UTC non valida")
    try:
        moment = datetime.fromisoformat(value.strip().replace("Z", "+00:00"))
    except ValueError:
        fail(f"{label}: data UTC non valida")
    if moment.tzinfo is None or moment.utcoffset().total_seconds() != 0:
        fail(f"{label}: attesa data UTC ISO 8601")
    return moment.astimezone(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")

def xml_value(xml, tag):
    m = re.search(r"<" + re.escape(tag) + r"(?:\s[^>]*)?>(.*?)</" + re.escape(tag) + r">", xml, re.S)
    return m.group(1).strip() if m else None

def parse_rpp(path):
    text = path.read_text(encoding="utf-8", errors="replace")
    project_guid = project_id_from_lines(text.splitlines()) or legacy_path_id(path)
    start_offset_s = 0.0
    for line in text.splitlines():
        if line.strip().startswith("PROJOFFS "):
            try:
                start_offset_s = float(line.strip().split()[1])
            except (IndexError, ValueError):
                fail("PROJOFFS non valido nel progetto REAPER.")
            if not math.isfinite(start_offset_s):
                fail("PROJOFFS non finito nel progetto REAPER.")
            break
    markers = []
    for line in text.splitlines():
        try: parts = shlex.split(line.strip())
        except ValueError: continue
        if len(parts) >= 5 and parts[0] == "MARKER":
            try: mid, pos, flags = int(parts[1]), float(parts[2]), int(parts[4])
            except ValueError: continue
            is_region = bool(flags & 1)
            guid = next((x for x in parts if re.fullmatch(r"\{[0-9A-Fa-f-]{32,36}\}", x)), None)
            markers.append({"id": mid, "position": pos, "name": parts[3], "is_region": is_region, "guid": guid})
    regions = []
    for start in markers:
        if not start["is_region"] or not start["name"]: continue
        ends = [x for x in markers if x["is_region"] and x["id"] == start["id"] and x["position"] > start["position"] and not x["name"]]
        if ends:
            end = min(ends, key=lambda x: x["position"])
            regions.append({"name": start["name"], "start_s": start["position"], "end_s": end["position"], "guid": start["guid"]})
    media = []
    for name in re.findall(r'^\s*FILE\s+"([^"]+)"', text, re.M):
        p = Path(name)
        if not p.is_absolute(): p = path.parent / p
        if not p.exists(): media.append(name)
    return {"guid": project_guid, "regions": regions, "missing_media": media, "start_offset_s": start_offset_s}

def zip_manifest(path):
    with zipfile.ZipFile(path) as z:
        bad = z.testzip()
        if bad: fail(f"ZIP corrotto: {bad}")
        names = z.namelist()
        if "manifest.json" not in names: fail("ZIP senza manifest.json")
        for n in names: safe_rel(n, "ZIP")
        return json.loads(z.read("manifest.json"))

def unpack_delivery(archive, destination):
    """Stage the manifest and its WAVs from one delivery in a private directory."""
    with zipfile.ZipFile(archive) as z:
        members = [info for info in z.infolist() if not info.is_dir()]
        manifests = [info for info in members if PurePosixPath(info.filename).name == "consegna.json"]
        if not manifests:
            if any(PurePosixPath(info.filename).name == "manifest.json" for info in members):
                fail("Questo è il pacchetto di partenza. In ZIP consegna scegli lo ZIP di ritorno con le registrazioni.")
            fail("Nello ZIP manca consegna.json.")
        if len(manifests) != 1:
            fail("Lo ZIP contiene più consegne. Estrai e seleziona la cartella della consegna che vuoi importare.")
        manifest = manifests[0]
        parent = safe_rel(manifest.filename, "Consegna ZIP").parent
        raw = z.read(manifest)
        delivery = json.loads(raw.decode("utf-8"))
        if not isinstance(delivery, dict) or not isinstance(delivery.get("files"), list):
            fail("consegna.json non contiene una lista valida di WAV.")
        by_name = {}
        for member in members:
            by_name.setdefault(member.filename, []).append(member)
        for entry in delivery["files"]:
            if not isinstance(entry, dict):
                fail("Voce WAV non valida in consegna.json.")
            name = safe_rel(entry.get("file"), "Nome WAV")
            if len(name.parts) != 1 or name.suffix.lower() != ".wav":
                fail(f"Nome WAV non valido nella consegna: {name}")
            matches = by_name.get(str(parent / name), [])
            if len(matches) != 1:
                fail(f"WAV mancante o duplicato nello ZIP: {name}")
            with z.open(matches[0]) as source, (destination / name.name).open("xb") as output:
                shutil.copyfileobj(source, output, 1024 * 1024)
        (destination / "consegna.json").write_bytes(raw)


def matching_video(project_path, region, package, manifest, source_start, same_region):
    from zp_remote_esporta import parse_rpp as parse_media

    try:
        _, tracks, _ = parse_media(project_path)
    except (ValueError, SystemExit):
        return False
    start = region["start_s"]
    candidates = [
        item for track in tracks for item in track["items"]
        if item["src_type"] == "VIDEO" and item["src"] and abs(item["rate"] - 1) < 1e-9
        and item["pos"] <= start + 1/SAMPLE_RATE and item["pos"] + item["len"] > start
    ]
    if len(candidates) != 1:
        return False
    item = candidates[0]
    video = project_path.parent / item["src"]
    if not video.is_file():
        return False
    if same_region:
        return True
    timeline = manifest.get("timeline")
    video_start = timeline.get("inizio_s") if isinstance(timeline, dict) else None
    if not isinstance(video_start, (int, float)) or not math.isfinite(video_start):
        return False
    if abs((start - item["pos"] + item["soffs"]) - (source_start - video_start)) > 1/SAMPLE_RATE:
        return False
    with zipfile.ZipFile(package) as z:
        video_name = manifest.get("video")
        if not isinstance(video_name, str) or video_name not in z.namelist():
            return False
        digest = hashlib.sha256()
        with z.open(video_name) as source:
            for block in iter(lambda: source.read(1024 * 1024), b""):
                digest.update(block)
    return digest.hexdigest() == sha256(video)


def build(args):
    delivery_dir, project_path = map(Path, (args.consegna, args.progetto))
    package = Path(args.pacchetto) if args.pacchetto else None
    flexible = getattr(args, "allow_unanchored", False)
    for p in (delivery_dir, project_path):
        if not p.exists(): fail(f"input assente: {p}")
    delivery_manifest = delivery_dir / "consegna.json"
    if not delivery_manifest.is_file():
        if (delivery_dir / "manifest.json").is_file():
            fail("Questa è la cartella del pacchetto di partenza. Usa ZIP consegna per scegliere lo ZIP di ritorno.")
        fail("Nella cartella manca consegna.json. Se hai lo ZIP di ritorno, selezionalo con ZIP consegna.")
    delivery = json.loads(delivery_manifest.read_text(encoding="utf-8"))
    dg = delivery.get("progetto")
    dg_id = canonical_id(dg, "prj")
    if delivery.get("zp_remote") != 2: fail("schema zp_remote non supportato")
    browser_id = None
    if flexible and isinstance(dg, str):
        prefix, _, suffix = dg.lower().partition("-")
        if prefix in ("sess", "demo") and canonical_id(suffix, "prj") == f"prj-{suffix}":
            browser_id = dg.lower()
    if not (dg_id or browser_id): fail("ID progetto non valido o di tipo diverso nella consegna")
    reference_warning = None
    if browser_id:
        reference_warning = "Sessione creata nel browser"
        manifest, project, package = {}, {}, None
    else:
        try:
            if not package: fail("ZIP originale assente")
            manifest = zip_manifest(package)
            if not isinstance(manifest, dict) or manifest.get("zp_remote") != 2: fail("schema zp_remote non supportato")
            project = manifest.get("project")
            if not isinstance(project, dict): fail("Progetto assente dal manifest ZIP")
            pg_id = canonical_id(project.get("guid"), "prj")
            manifest_id = canonical_id(project.get("id"), "prj") if project.get("id") is not None else pg_id
            if not pg_id or not manifest_id: fail("ID progetto non valido o di tipo diverso tra consegna e ZIP")
            if dg_id != pg_id or manifest_id != pg_id: fail("ID progetto discordanti tra consegna e ZIP")
        except (ValueError, OSError, zipfile.BadZipFile) as error:
            if not flexible: raise
            reference_warning = str(error)
            manifest, project, package = {}, {}, None
    session_type = delivery.get("session_type", project.get("session_type", "ordinary"))
    if session_type not in ("ordinary", "legacy", "retake"): fail("tipo sessione sconosciuto")
    if browser_id and session_type == "retake": fail("Una sessione del browser non identifica il progetto base di una retake")
    if session_type == "retake":
        for key in ("retake_session_id", "base_project_id", "base_region_id"):
            if not isinstance(delivery.get(key), str) or not delivery[key].strip(): fail(f"sessione retake senza {key}")
        if args.legacy_alias and not getattr(args,"legacy_alias_auto",False): fail("--legacy-alias è consentito solo per la consegna legacy ordinaria")
    entries = delivery.get("files")
    if not isinstance(entries, list) or not entries: fail("la consegna deve contenere almeno un file")
    rpp = parse_rpp(project_path)
    region_ref = delivery.get("region") or manifest.get("region") or manifest.get("project", {}).get("region")
    region_guid = delivery.get("region_guid") or manifest.get("region_guid") or manifest.get("project", {}).get("region_guid")
    region_name = None
    if isinstance(region_ref, dict):
        region_guid = region_ref.get("guid") or region_guid
        region_name = region_ref.get("name")
    elif isinstance(region_ref, str):
        region_guid = region_ref if region_ref.startswith("{") else region_guid
        region_name = None if region_ref.startswith("{") else region_ref
    region_guid = getattr(args, "region_guid", None) or region_guid
    region_name = getattr(args, "region_name", None) or region_name
    candidates = list(rpp["regions"])
    if getattr(args, "region_name", None) and not getattr(args, "region_guid", None) and flexible:
        region_guid = None
    if region_guid:
        candidates = [x for x in candidates if x.get("guid") and x["guid"].upper() == str(region_guid).upper()]
    elif region_name:
        candidates = [x for x in candidates if x["name"] == region_name]
    elif len(candidates) != 1 and not flexible:
        fail("la consegna non identifica la regione e il progetto ne contiene più di una; specificare --region-guid o --region-name")
    if len(candidates) != 1 and not flexible: fail(f"regione non identificata in modo univoco (corrispondenze: {len(candidates)})")
    region = candidates[0] if len(candidates) == 1 else None
    if region is not None and flexible:
        from zp_remote_esporta import parse_rpp as parse_media
        _, tracks, _ = parse_media(project_path)
        has_region_video = any(item["src_type"] == "VIDEO" and item["src"]
                               and item["pos"] <= region["start_s"] + 1/SAMPLE_RATE
                               and item["pos"] + item["len"] > region["start_s"]
                               for track in tracks for item in track["items"])
        if not has_region_video:
            region = None
    video_anchor = None
    selected_type = getattr(args, "selected_item_type", None)
    if region is None and flexible and selected_type is not None:
        if selected_type != "VIDEO": fail("L'item selezionato non è un video; scegli un item VIDEO o una regione.")
        selected_start = finite_number(getattr(args, "selected_item_start", None), "inizio item video")
        selected_file = getattr(args, "selected_item_file", None)
        if not isinstance(selected_file, str) or not selected_file: fail("Sorgente dell'item video selezionato assente")
        from zp_remote_esporta import parse_rpp as parse_media
        _, tracks, _ = parse_media(project_path)
        wanted = Path(selected_file).resolve()
        matches = [item for track in tracks for item in track["items"]
                   if item["src_type"] == "VIDEO" and item["src"]
                   and abs(item["pos"] - selected_start) <= 1/SAMPLE_RATE
                   and (project_path.parent / item["src"]).resolve() == wanted]
        if len(matches) != 1: fail("L'item VIDEO selezionato non corrisponde a un video unico nel progetto salvato.")
        video_anchor = matches[0]
        region = {"guid": "video-" + hashlib.sha256((str(wanted) + "|" + str(selected_start)).encode()).hexdigest()[:32],
                  "name": "Item VIDEO selezionato", "start_s": video_anchor["pos"],
                  "end_s": video_anchor["pos"] + video_anchor["len"]}
    rpp_id = canonical_id(rpp["guid"], "prj")
    if not rpp_id: fail("ID progetto non valido nel progetto REAPER")
    canonical_delivery = json.dumps(delivery, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    delivery_id = hashlib.sha256(canonical_delivery).hexdigest()
    shift_region = 0
    placement = None
    warnings = []
    direct_project_anchor = False
    if flexible:
        # La regione sorgente viene dal pacchetto, la destinazione dal progetto aperto.
        source_region = manifest.get("region") or project.get("region")
        same_project = rpp_id == dg_id
        if session_type == "retake":
            same_project = rpp_id == canonical_id(delivery["base_project_id"], "prj")
        source_start = source_region.get("start_s") if isinstance(source_region, dict) else None
        same_region = bool(region and isinstance(source_region, dict) and region["guid"]
                           and region["guid"].upper() == str(source_region.get("guid", "")).upper() and same_project)
        if session_type == "retake":
            same_region = same_region and region["guid"].upper() == str(delivery["base_region_id"]).upper()
        direct_project_anchor = bool(
            package is None and reference_warning == "ZIP originale assente" and same_project
            and session_type != "retake" and region and region.get("guid")
        )
        reason = None if direct_project_anchor else reference_warning
        if video_anchor is not None:
            if session_type == "retake" and rpp_id != canonical_id(delivery["base_project_id"], "prj"):
                fail("Il video selezionato appartiene a un progetto diverso dalla base della retake.")
            if not same_project and not isinstance(source_start, (int, float)):
                fail("Il pacchetto non indica l'inizio della regione sorgente: non posso allinearlo al video selezionato.")
            placement = {"mode": "video", "separate_tracks": False, "anchor": "selected-video-v1",
                         "video_start_s": video_anchor["pos"], "video_file": selected_file}
            shift_region = 0 if same_project else video_anchor["pos"] - source_start
            reason = None
        elif not reason and (not region or not region["guid"] or not isinstance(source_start, (int, float)) or not math.isfinite(source_start)):
            if not direct_project_anchor:
                reason = "Regione originale o di destinazione non identificata"
        if video_anchor is None and not reason and session_type == "retake" and not same_region and not direct_project_anchor:
            reason = "Progetto o regione base della retake non corrispondenti"
        if video_anchor is None and not reason and not direct_project_anchor:
            try:
                if not matching_video(project_path, region, package, manifest, source_start, same_region):
                    reason = "Video di riferimento assente o senza un punto di partenza verificabile"
            except (OSError, zipfile.BadZipFile):
                reason = "Video di riferimento non leggibile"
        if reason:
            placement = {"mode": "cursor", "separate_tracks": True, "reason": reason}
        elif video_anchor is not None:
            pass
        elif direct_project_anchor:
            placement = {"mode": "region", "separate_tracks": False, "anchor": "same-project-bwf-v1"}
        else:
            placement = {"mode": "region", "separate_tracks": not same_region}
            shift_region = region["start_s"] - source_start
    files, items, count = [], [], {"P": 0, "A": 0, "fuori_traccia": 0}
    seen = set()
    for idx, entry in enumerate(entries):
        rel = safe_rel(entry.get("file"), f"files[{idx}].file")
        if rel.parts in seen: fail(f"file duplicato nel manifest: {entry['file']}")
        seen.add(rel.parts)
        src = delivery_dir.joinpath(*rel.parts)
        if not src.is_file(): fail(f"file consegnato mancante: {entry['file']}")
        digest = sha256(src)
        if digest.lower() != str(entry.get("sha256", "")).lower(): fail(f"SHA-256 errato: {entry['file']}")
        wav = read_wav(src)
        if direct_project_anchor:
            wav_project = xml_value(wav["ixml"], "ZP_PROGETTO_GUID")
            if canonical_id(wav_project, "prj") != dg_id:
                fail(f"GUID progetto iXML assente o diverso dalla consegna: {entry['file']}")
            wav_offset = xml_value(wav["ixml"], "ZP_OFFSET_PROGETTO_S")
            try:
                wav_offset = finite_number(float(wav_offset), "ZP_OFFSET_PROGETTO_S")
            except (TypeError, ValueError):
                fail(f"Offset progetto iXML assente o non valido: {entry['file']}")
            if abs(wav_offset - rpp["start_offset_s"]) > 1 / SAMPLE_RATE:
                fail(f"Offset progetto iXML diverso dal progetto REAPER: {entry['file']}")
        if wav["frames"] != entry.get("frames"): fail(f"frames diversi dal manifest: {entry['file']}")
        if wav["time_reference"] != entry.get("time_reference"): fail(f"TimeReference diverso: {entry['file']}")
        for tag in ("PROJECT", "SCENE", "TAKE"):
            if not xml_value(wav["ixml"], tag): fail(f"iXML {tag} assente: {entry['file']}")
        for tag, expected in (("FILE_SAMPLE_RATE", SAMPLE_RATE), ("TIMESTAMP_SAMPLE_RATE", SAMPLE_RATE), ("TIMESTAMP_SAMPLES_SINCE_MIDNIGHT_LO", wav["time_reference"] & 0xFFFFFFFF), ("TIMESTAMP_SAMPLES_SINCE_MIDNIGHT_HI", wav["time_reference"] >> 32)):
            value = xml_value(wav["ixml"], tag)
            if value is None or not value.isdigit() or int(value) != expected: fail(f"iXML {tag} incoerente: {entry['file']}")
        if entry.get("ruolo") not in count: fail(f"ruolo non supportato: {entry.get('ruolo')}")
        count[entry["ruolo"]] += 1
        if entry["ruolo"] == "fuori_traccia" and entry.get("items"):
            fail(f"un file fuori_traccia non può avere item: {entry['file']}")
        duration = wav["frames"] / SAMPLE_RATE
        character_id = entry.get("character_id")
        character = entry.get("personaggio")
        if character_id is not None:
            character_id = canonical_id(character_id, "pers")
            if not character_id: fail(f"character_id non valido o di tipo diverso: {entry['file']}")
        if entry["ruolo"] in ("P", "A") and not character_id and not (isinstance(character, str) and character.strip()):
            fail(f"personaggio non specificato: {entry['file']}")
        ring_id = entry.get("ring_id") if entry.get("ring_id") is not None else entry.get("anello")
        take_version = entry.get("take_version") if entry.get("take_version") is not None else entry.get("take", "1")
        explicit_time = utc_recorded_at(entry.get("registrato_il"), f"files[{idx}].registrato_il")
        recorded_at = explicit_time or wav["bext_recorded_at"]
        recorded_source = "registrato_il" if explicit_time else ("bext" if recorded_at else "take_version")
        record = {"index": idx, "file": entry["file"], "sha256": digest, "frames": wav["frames"], "time_reference": wav["time_reference"], "sample_rate": SAMPLE_RATE, "role": entry["ruolo"], "character": character, "character_id": character_id, "ring_id": ring_id, "take_version": take_version, "recorded_at": recorded_at, "recorded_at_source": recorded_source, "items": []}
        for ii, item in enumerate(entry.get("items", [])):
            lane = item.get("lane", "P1")
            if not isinstance(lane, str) or not lane.strip(): fail(f"lane non valida: {entry['file']} item {ii}")
            lane_index = {"P1":0,"P2":1,"A1":2,"A2":3,"A3":4}.get(lane.upper())
            if lane_index is None and lane.isdigit(): lane_index = max(0, int(lane)-1)
            if entry["ruolo"] == "A" and (lane_index is None or lane_index < 2 or lane_index > 4):
                fail(f"un file A deve usare una lane Alternativo A1–A3: {entry['file']} item {ii}")
            ent = finite_number(item.get("entrata_s"), "entrata_s"); usc = finite_number(item.get("uscita_s"), "uscita_s")
            shift = finite_number(item.get("spostamento_ms", 0), "spostamento_ms")
            fin = finite_number(item.get("fade_in_ms", 0), "fade_in_ms"); fout = finite_number(item.get("fade_out_ms", 0), "fade_out_ms")
            if flexible and duration < usc <= duration + .001:
                warnings.append(f"Fine taglio ricondotta al WAV: {entry['file']} #{ii}")
                usc = duration
            if ent < 0 or usc <= ent or usc > duration + 1/SAMPLE_RATE or fin < 0 or fout < 0 or fin + fout > (usc-ent)*1000 + .001: fail(f"limiti taglio/fade non validi: {entry['file']} item {ii}")
            pos = wav["time_reference"] / SAMPLE_RATE - finite_number(project.get("start_offset_s", rpp["start_offset_s"]), "start_offset_s") + ent + shift/1000 + shift_region
            ring_id = item.get("ring_id") if item.get("ring_id") is not None else record["ring_id"]
            take_version = item.get("take_version") if item.get("take_version") is not None else record["take_version"]
            planned = {"item_index": ii, "lane": lane, "lane_index": lane_index, "ring_id": ring_id, "take_version": take_version, "position_s": pos, "source_offset_s": ent, "length_s": usc-ent, "fade_in_ms": fin, "fade_out_ms": fout, "note": entry.get("nota", ""), "idempotency_key": None}
            planned["outside_region"] = (not placement or placement["mode"] == "region") and (pos < region["start_s"] - 1/SAMPLE_RATE or pos + planned["length_s"] > region["end_s"] + 1/SAMPLE_RATE)
            record["items"].append(planned); items.append(planned)
        files.append(record)
    if not count["P"] and not count["A"] and not count["fuori_traccia"]: fail("la consegna non contiene ruoli importabili")
    alias = None
    if not flexible:
        if session_type == "retake" and rpp_id != canonical_id(delivery["base_project_id"], "prj"):
            fail("base_project_id della retake non coincide con il progetto RPP")
        if session_type != "retake" and rpp_id != dg_id:
            if not args.legacy_alias: fail(f"GUID progetto RPP {rpp['guid']} diverso da consegna/ZIP {dg}; serve --legacy-alias per la sola eccezione verificata")
            alias = {"delivery_guid": dg, "rpp_guid": rpp["guid"], "region_guid": region["guid"], "region_name": region["name"], "start_s": region["start_s"], "end_s": region["end_s"], "reason": "legacy project-copy identity alias"}
        elif session_type != "retake" and args.legacy_alias and not getattr(args,"legacy_alias_auto",False): fail("--legacy-alias non necessario: GUID progetto e consegna coincidono")
    elif placement["mode"] in ("region", "video") and any(item["outside_region"] for item in items):
        if direct_project_anchor:
            fail("Alcune take cadono fuori dall'ancora video/regione scelta. Controlla il riferimento video e riprova.")
        placement = {"mode": "cursor", "separate_tracks": True, "reason": "Le take escono dalla regione di destinazione"}
    if placement and placement["mode"] == "cursor":
        region = {"guid": f"cursor-{delivery_id}", "name": "Al cursore", "start_s": 0, "end_s": 0}
        first_position = min((item["position_s"] for item in items), default=0)
        for item in items:
            item["position_s"] -= first_position
            item["outside_region"] = False
    character_counts, characters_by_id = {}, {}
    for f in files:
        for item in f["items"]:
            if f["character_id"]:
                characters_by_id[f["character_id"]] = characters_by_id.get(f["character_id"], 0) + 1
            if f["character"]:
                character_counts[f["character"]] = character_counts.get(f["character"], 0) + 1
            item["idempotency_key"] = (f"{dg_id or browser_id}/{region.get('guid')}/{item['ring_id']}/{item['take_version']}/{item['item_index']}" if item["ring_id"] else f"{delivery_id}/{f['sha256']}/{item['item_index']}")
    plan = {"schema": "zp_remote_reaper_import_plan_v1", "delivery_id": delivery_id, "delivery_guid": dg, "project_guid": rpp["guid"], "project_id": rpp_id, "session_type": "ordinary" if session_type == "legacy" else session_type, "session_date": delivery.get("data"), "retake_session_id": delivery.get("retake_session_id"), "base_project_id": delivery.get("base_project_id"), "base_region_id": delivery.get("base_region_id"), "region": region, "region_alias": alias, "sample_rate": SAMPLE_RATE, "inputs": {"delivery_dir": str(delivery_dir.resolve()), "package": str(package.resolve()) if package else None, "project": str(project_path.resolve())}, "input_hashes": {"delivery_json": sha256(delivery_dir / "consegna.json"), "package": sha256(package) if package else None, "project": sha256(project_path)}, "counts": {"files": len(files), "P": count["P"], "A": count["A"], "fuori_traccia": count["fuori_traccia"], "items": len(items), "characters": character_counts, "characters_by_id": characters_by_id}, "files": files, "rpp_missing_media": rpp["missing_media"], "warnings": warnings + [f"Item fuori regione: {f['file']} #{x['item_index']}" for f in files for x in f["items"] if x["outside_region"]]}
    if dg_id:
        plan["delivery_project_id"] = dg_id
    if placement:
        plan["placement"] = placement
    plan["cues"] = [{"file": f, "item": item, "legacy_key": item["idempotency_key"]} for f in files if f["role"] in ("P", "A") for item in f["items"]]
    return plan

def _write_status(path, payload):
    if not path:
        return
    target = Path(path)
    target.parent.mkdir(parents=True, exist_ok=True)
    tmp = target.with_suffix(target.suffix + ".tmp")
    tmp.write_text(json.dumps(payload, ensure_ascii=False) + "\n", encoding="utf-8")
    tmp.replace(target)


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--consegna", required=True, help="ZIP di ritorno o cartella con consegna.json"); ap.add_argument("--pacchetto"); ap.add_argument("--progetto", required=True); ap.add_argument("--output", required=True)
    ap.add_argument("--legacy-alias", action="store_true")
    ap.add_argument("--legacy-alias-auto", action="store_true", help=argparse.SUPPRESS)
    ap.add_argument("--allow-unanchored", action="store_true")
    ap.add_argument("--selected-item-type")
    ap.add_argument("--selected-item-start", type=float)
    ap.add_argument("--selected-item-file")
    ap.add_argument("--region-guid")
    ap.add_argument("--region-name")
    ap.add_argument("--status-file", help=argparse.SUPPRESS)
    args=ap.parse_args()
    if args.legacy_alias_auto: args.legacy_alias=True
    staged = None
    try:
        _write_status(args.status_file, {"stato":"in_corso"})
        archive = Path(args.consegna)
        if archive.is_file():
            staged = Path(tempfile.mkdtemp(prefix="zp-remote-consegna-"))
            unpack_delivery(archive, staged)
            args.consegna = str(staged)
        plan=build(args)
        out=Path(args.output); out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(json.dumps(plan,ensure_ascii=False,indent=2)+"\n", encoding="utf-8")
        report=out.with_suffix(".md")
        missing=plan["rpp_missing_media"]
        report.write_text("\n".join(["# Rapporto preflight ZP Remote", "", f"- Esito: {'BLOCCATO: media RPP mancanti' if missing and not plan.get('placement') else 'PRONTO PER ANTEPRIMA'}", f"- Delivery ID: `{plan['delivery_id']}`", f"- File: {plan['counts']['files']} (P {plan['counts']['P']}, A {plan['counts']['A']}, fuori traccia {plan['counts']['fuori_traccia']})", f"- Item: {plan['counts']['items']}", f"- Personaggi: {json.dumps(plan['counts']['characters'],ensure_ascii=False)}", f"- Regione: {plan['region']['name']} {plan['region']['start_s']:.12f}–{plan['region']['end_s']:.12f} s", f"- Alias legacy: {json.dumps(plan['region_alias'],ensure_ascii=False)}", f"- Media RPP mancanti: {len(missing)}", f"- Item fuori regione: {len(plan['warnings'])}", "", *(f"  - `{x}`" for x in missing), "", "Gli originali sono stati letti senza modificarli."]) + "\n", encoding="utf-8")
        _write_status(args.status_file, {"stato":"completato","piano":str(out.resolve()),"rapporto":str(report.resolve()),"counts":plan["counts"],"warnings":plan["warnings"],"rpp_missing_media":missing})
        print(f"Piano: {out}\nRapporto: {report}\nConteggi: {json.dumps(plan['counts'],ensure_ascii=False)}\nMedia RPP mancanti: {len(missing)}")
        return 0
    except (ValueError, OSError, RuntimeError, zipfile.BadZipFile) as e:
        if staged:
            shutil.rmtree(staged, ignore_errors=True)
        _write_status(args.status_file, {"stato":"errore","messaggio":str(e)})
        print(f"PREFLIGHT BLOCCATO: {e}", file=sys.stderr)
        return 2
if __name__ == "__main__": raise SystemExit(main())
