#!/usr/bin/env python3
"""Read-only validation and normalized plan builder for ZP Remote deliveries."""
from __future__ import annotations
import argparse, hashlib, json, math, re, shlex, struct, sys, zipfile
from pathlib import Path, PurePosixPath
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
        pos, chunks, fmt, data_size, bext, ixml = 12, [], None, None, None, None
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
    return {"chunks": chunks, "frames": frames, "time_reference": bext, "sample_rate": fmt["sample_rate"], "channels": fmt["channels"], "bits": fmt["bits"], "ixml": ixml}

def xml_value(xml, tag):
    m = re.search(r"<" + re.escape(tag) + r"(?:\s[^>]*)?>(.*?)</" + re.escape(tag) + r">", xml, re.S)
    return m.group(1).strip() if m else None

def parse_rpp(path):
    text = path.read_text(encoding="utf-8", errors="replace")
    project_guid = project_id_from_lines(text.splitlines()) or legacy_path_id(path)
    markers = []
    for line in text.splitlines():
        try: parts = shlex.split(line.strip())
        except ValueError: continue
        if len(parts) >= 5 and parts[0] == "MARKER":
            try: mid, pos = int(parts[1]), float(parts[2])
            except ValueError: continue
            is_region = parts[4] == "1"
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
    return {"guid": project_guid, "regions": regions, "missing_media": media}

def zip_manifest(path):
    with zipfile.ZipFile(path) as z:
        bad = z.testzip()
        if bad: fail(f"ZIP corrotto: {bad}")
        names = z.namelist()
        if "manifest.json" not in names: fail("ZIP senza manifest.json")
        for n in names: safe_rel(n, "ZIP")
        return json.loads(z.read("manifest.json"))

def build(args):
    delivery_dir, package, project_path = map(Path, (args.consegna, args.pacchetto, args.progetto))
    for p in (delivery_dir, package, project_path):
        if not p.exists(): fail(f"input assente: {p}")
    delivery = json.loads((delivery_dir / "consegna.json").read_text(encoding="utf-8"))
    manifest = zip_manifest(package)
    if delivery.get("zp_remote") != 2 or manifest.get("zp_remote") != 2: fail("schema zp_remote non supportato")
    dg, pg = delivery.get("progetto"), manifest.get("project", {}).get("guid")
    project = manifest.get("project", {})
    dg_id, pg_id = canonical_id(dg, "prj"), canonical_id(pg, "prj")
    manifest_id = project.get("id")
    manifest_canonical = canonical_id(manifest_id, "prj") if manifest_id is not None else pg_id
    if not dg_id or not pg_id or not manifest_canonical:
        fail("ID progetto non valido o di tipo diverso tra consegna e ZIP")
    if dg_id != pg_id or manifest_canonical != pg_id:
        fail("ID progetto discordanti tra consegna e ZIP")
    session_type = delivery.get("session_type", project.get("session_type", "ordinary"))
    if session_type not in ("ordinary", "legacy", "retake"): fail("tipo sessione sconosciuto")
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
    if region_guid:
        candidates = [x for x in candidates if x.get("guid") and x["guid"].upper() == str(region_guid).upper()]
    elif region_name:
        candidates = [x for x in candidates if x["name"] == region_name]
    elif len(candidates) != 1:
        fail("la consegna non identifica la regione e il progetto ne contiene più di una; specificare --region-guid o --region-name")
    if len(candidates) != 1: fail(f"regione non identificata in modo univoco (corrispondenze: {len(candidates)})")
    region = candidates[0]
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
        record = {"index": idx, "file": entry["file"], "sha256": digest, "frames": wav["frames"], "time_reference": wav["time_reference"], "sample_rate": SAMPLE_RATE, "role": entry["ruolo"], "character": character, "character_id": character_id, "ring_id": entry.get("ring_id"), "take_version": entry.get("take_version"), "items": []}
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
            if ent < 0 or usc <= ent or usc > duration + 1/SAMPLE_RATE or fin < 0 or fout < 0 or fin + fout > (usc-ent)*1000 + .001: fail(f"limiti taglio/fade non validi: {entry['file']} item {ii}")
            pos = wav["time_reference"] / SAMPLE_RATE - finite_number(manifest["project"].get("start_offset_s", 0), "start_offset_s") + ent + shift/1000
            ring_id = item.get("ring_id", entry.get("ring_id"))
            take_version = item.get("take_version", entry.get("take_version", "1"))
            planned = {"item_index": ii, "lane": lane, "lane_index": lane_index, "ring_id": ring_id, "take_version": take_version, "position_s": pos, "source_offset_s": ent, "length_s": usc-ent, "fade_in_ms": fin, "fade_out_ms": fout, "note": entry.get("nota", ""), "idempotency_key": None}
            planned["outside_region"] = pos < region["start_s"] - 1/SAMPLE_RATE or pos + planned["length_s"] > region["end_s"] + 1/SAMPLE_RATE
            record["items"].append(planned); items.append({"file": entry["file"], **planned})
        files.append(record)
    if not count["P"] and not count["A"] and not count["fuori_traccia"]: fail("la consegna non contiene ruoli importabili")
    alias = None
    rpp_id = canonical_id(rpp["guid"], "prj")
    if not rpp_id: fail("ID progetto non valido nel progetto REAPER")
    if session_type == "retake" and rpp_id != canonical_id(delivery["base_project_id"], "prj"):
        fail("base_project_id della retake non coincide con il progetto RPP")
    if session_type != "retake" and rpp_id != dg_id:
        if not args.legacy_alias: fail(f"GUID progetto RPP {rpp['guid']} diverso da consegna/ZIP {dg}; serve --legacy-alias per la sola eccezione verificata")
        alias = {"delivery_guid": dg, "rpp_guid": rpp["guid"], "region_guid": region["guid"], "region_name": region["name"], "start_s": region["start_s"], "end_s": region["end_s"], "reason": "legacy project-copy identity alias"}
    elif session_type != "retake" and args.legacy_alias and not getattr(args,"legacy_alias_auto",False): fail("--legacy-alias non necessario: GUID progetto e consegna coincidono")
    canonical_delivery = json.dumps(delivery, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    delivery_id = hashlib.sha256(canonical_delivery).hexdigest()
    character_counts, characters_by_id = {}, {}
    for f in files:
        for item in f["items"]:
            if f["character_id"]:
                characters_by_id[f["character_id"]] = characters_by_id.get(f["character_id"], 0) + 1
            if f["character"]:
                character_counts[f["character"]] = character_counts.get(f["character"], 0) + 1
            item["idempotency_key"] = (f"{dg_id}/{region.get('guid')}/{item['ring_id']}/{item['take_version']}/{item['item_index']}" if item["ring_id"] else f"{delivery_id}/{f['sha256']}/{item['item_index']}")
    plan = {"schema": "zp_remote_reaper_import_plan_v1", "delivery_id": delivery_id, "delivery_guid": dg, "delivery_project_id": dg_id, "project_guid": rpp["guid"], "project_id": rpp_id, "session_type": "ordinary" if session_type == "legacy" else session_type, "retake_session_id": delivery.get("retake_session_id"), "base_project_id": delivery.get("base_project_id"), "base_region_id": delivery.get("base_region_id"), "region": region, "region_alias": alias, "sample_rate": SAMPLE_RATE, "inputs": {"delivery_dir": str(delivery_dir.resolve()), "package": str(package.resolve()), "project": str(project_path.resolve())}, "input_hashes": {"delivery_json": sha256(delivery_dir / "consegna.json"), "package": sha256(package), "project": sha256(project_path)}, "counts": {"files": len(files), "P": count["P"], "A": count["A"], "fuori_traccia": count["fuori_traccia"], "items": len(items), "characters": character_counts, "characters_by_id": characters_by_id}, "files": files, "rpp_missing_media": rpp["missing_media"], "warnings": [f"Item fuori regione: {x['file']} #{x['item_index']}" for x in items if x["outside_region"]]}
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
    ap.add_argument("--consegna", required=True); ap.add_argument("--pacchetto", required=True); ap.add_argument("--progetto", required=True); ap.add_argument("--output", required=True)
    ap.add_argument("--legacy-alias", action="store_true")
    ap.add_argument("--legacy-alias-auto", action="store_true", help=argparse.SUPPRESS)
    ap.add_argument("--region-guid")
    ap.add_argument("--region-name")
    ap.add_argument("--status-file", help=argparse.SUPPRESS)
    args=ap.parse_args()
    if args.legacy_alias_auto: args.legacy_alias=True
    try:
        _write_status(args.status_file, {"stato":"in_corso"})
        plan=build(args)
        out=Path(args.output); out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(json.dumps(plan,ensure_ascii=False,indent=2)+"\n", encoding="utf-8")
        report=out.with_suffix(".md")
        missing=plan["rpp_missing_media"]
        report.write_text("\n".join(["# Rapporto preflight ZP Remote", "", f"- Esito: {'BLOCCATO: media RPP mancanti' if missing else 'PRONTO PER ANTEPRIMA'}", f"- Delivery ID: `{plan['delivery_id']}`", f"- File: {plan['counts']['files']} (P {plan['counts']['P']}, A {plan['counts']['A']}, fuori traccia {plan['counts']['fuori_traccia']})", f"- Item: {plan['counts']['items']}", f"- Personaggi: {json.dumps(plan['counts']['characters'],ensure_ascii=False)}", f"- Regione: {plan['region']['name']} {plan['region']['start_s']:.12f}–{plan['region']['end_s']:.12f} s", f"- Alias legacy: {json.dumps(plan['region_alias'],ensure_ascii=False)}", f"- Media RPP mancanti: {len(missing)}", f"- Item fuori regione: {len(plan['warnings'])}", "", *(f"  - `{x}`" for x in missing), "", "Gli originali sono stati letti senza modificarli."]) + "\n", encoding="utf-8")
        _write_status(args.status_file, {"stato":"completato","piano":str(out.resolve()),"rapporto":str(report.resolve()),"counts":plan["counts"],"warnings":plan["warnings"],"rpp_missing_media":missing})
        print(f"Piano: {out}\nRapporto: {report}\nConteggi: {json.dumps(plan['counts'],ensure_ascii=False)}\nMedia RPP mancanti: {len(missing)}")
        return 0
    except (ValueError, OSError, json.JSONDecodeError, zipfile.BadZipFile) as e:
        _write_status(args.status_file, {"stato":"errore","messaggio":str(e)})
        print(f"PREFLIGHT BLOCCATO: {e}", file=sys.stderr)
        return 2
if __name__ == "__main__": raise SystemExit(main())
