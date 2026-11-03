"""Project identity shared by the REAPER package exporter and delivery preflight."""
import hashlib
import os
import re


ID_RE = re.compile(r"\{(?:[0-9A-Fa-f]{32}|[0-9A-Fa-f-]{36})\}\Z")
UUID_RE = re.compile(r"(?:[0-9A-Fa-f]{32}|[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12})\Z")


def canonical_id(value, kind):
    """Accept REAPER GUID, bare UUID, or canonical typed ID; reject the wrong type."""
    if kind not in ("prj", "pers") or not isinstance(value, str):
        return None
    value = value.strip()
    prefix = value[:4].lower()
    if prefix in ("prj-", "per-") or value.lower().startswith("pers-"):
        actual, value = value.split("-", 1)
        if actual.lower() != kind:
            return None
    elif value.startswith("{") and value.endswith("}"):
        value = value[1:-1]
    if not UUID_RE.fullmatch(value):
        return None
    compact = value.replace("-", "").lower()
    uuid = f"{compact[:8]}-{compact[8:12]}-{compact[12:16]}-{compact[16:20]}-{compact[20:]}"
    return f"{kind}-{uuid}"


def project_id_from_lines(lines):
    """Read the ZP_REMOTE/PROJECT_ID project extension state from a saved RPP."""
    stack = []
    result = None
    for raw in lines:
        line = raw.strip()
        if line.startswith("<"):
            stack.append(line[1:].split(None, 1)[0])
        elif line == ">":
            if stack:
                stack.pop()
        elif len(stack) == 3 and stack[-2:] == ["EXTSTATE", "ZP_REMOTE"] and line.startswith("PROJECT_ID "):
            value = line.split(None, 1)[1].strip()
            if not ID_RE.fullmatch(value):
                raise ValueError("ID ZP Remote non valido nel progetto")
            if result is not None and result.upper() != value.upper():
                raise ValueError("ID ZP Remote duplicato e incoerente nel progetto")
            result = value.upper()
    return result


def legacy_path_id(path):
    """Old package identity, only for validating deliveries made before persistent IDs."""
    return "{" + hashlib.sha1(os.path.abspath(path).encode()).hexdigest()[:32].upper() + "}"
