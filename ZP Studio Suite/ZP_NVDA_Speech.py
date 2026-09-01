#!/usr/bin/env python3
"""Tiny NVDA speech bridge for ZP Studio Suite.

This script is intentionally self-contained: REAPER/Lua can call it when the
horizontal prompter needs to announce the current cue on Windows.
"""
from __future__ import annotations

import argparse
import ctypes
import os
import sys


def _load_nvda_client() -> ctypes.WinDLL | None:
    here = os.path.dirname(os.path.abspath(__file__))
    dll_path = os.path.join(here, "nvdaControllerClient64.dll")
    if not os.path.exists(dll_path):
        return None
    try:
        return ctypes.WinDLL(dll_path)
    except Exception:
        return None


def speak(text: str) -> int:
    text = (text or "").strip()
    if not text:
        return 0
    client = _load_nvda_client()
    if client is None:
        return 2
    try:
        client.nvdaController_speakText.argtypes = [ctypes.c_wchar_p]
        client.nvdaController_speakText.restype = ctypes.c_int
        return int(client.nvdaController_speakText(text))
    except Exception:
        return 3


def stop() -> int:
    client = _load_nvda_client()
    if client is None:
        return 2
    try:
        client.nvdaController_cancelSpeech.argtypes = []
        client.nvdaController_cancelSpeech.restype = ctypes.c_int
        return int(client.nvdaController_cancelSpeech())
    except Exception:
        return 3


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--speak", default="")
    parser.add_argument("--stop", action="store_true")
    args = parser.parse_args(argv)
    if args.stop:
        return stop()
    return speak(args.speak)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
