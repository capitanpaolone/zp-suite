"""Transcription provider adapters and auto-selection."""

from __future__ import annotations

from collections.abc import Callable
from typing import Any

from .macwhisper import MacWhisperProvider, ProviderError
from .openai_whisper import (
    OpenAIWhisperProvider,
    canonical_model_stem,
    default_models_dir,
    default_whisper_python,
    download_model,
    installed_models,
    list_models_status,
    normalize_openai_whisper_json,
    zp_data_root,
)

ENGINE_CHOICES = ("auto", "macwhisper", "openai-whisper")


def detect_provider(
    engine: str = "auto",
    *,
    model: str | None = None,
    macwhisper_detector: Callable[[], Any] = MacWhisperProvider.detect,
    openai_whisper_detector: Callable[[], Any] = OpenAIWhisperProvider.detect,
) -> Any:
    """Resolve a transcription provider explicitly or via auto-detection."""
    choice = (engine or "auto").strip().lower()
    if choice not in ENGINE_CHOICES:
        raise ProviderError(
            "unsupported_capability",
            f"unsupported transcription engine: {engine}",
            provider=None,
        )
    if choice == "macwhisper":
        return macwhisper_detector()
    if choice == "openai-whisper":
        return openai_whisper_detector()

    if model:
        cleaned = model.strip()
        if cleaned.startswith("openai-whisper:"):
            return openai_whisper_detector()
        if ":" in cleaned:
            return macwhisper_detector()

    mw_error: ProviderError | None = None
    try:
        mw = macwhisper_detector()
        mw.capabilities()
        return mw
    except ProviderError as error:
        mw_error = error

    try:
        ow = openai_whisper_detector()
        ow.capabilities()
        return ow
    except ProviderError as ow_error:
        code = (
            "provider_not_found"
            if mw_error.code == "provider_not_found" and ow_error.code == "provider_not_found"
            else "provider_unavailable"
        )
        raise ProviderError(
            code,
            f"Nessun provider pronto (MacWhisper: {mw_error}; OpenAI Whisper: {ow_error})",
            provider=None,
            details={
                "macwhisper": {"code": mw_error.code, "message": str(mw_error)},
                "openai_whisper": {"code": ow_error.code, "message": str(ow_error)},
            },
        ) from ow_error


__all__ = [
    "ENGINE_CHOICES",
    "MacWhisperProvider",
    "OpenAIWhisperProvider",
    "ProviderError",
    "canonical_model_stem",
    "default_models_dir",
    "default_whisper_python",
    "detect_provider",
    "download_model",
    "installed_models",
    "list_models_status",
    "normalize_openai_whisper_json",
    "zp_data_root",
]
