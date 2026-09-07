"""Transcription provider adapters."""

from .macwhisper import MacWhisperProvider, ProviderError

__all__ = ["MacWhisperProvider", "ProviderError"]
