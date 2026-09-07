"""Constants shared by every ZP Speech API v1 document."""

SCHEMA_VERSION = 1
API_VERSION = "v1"

DOCUMENT_KINDS = frozenset(
    {
        "transcript",
        "provider_capabilities",
        "error",
        "search_result",
    }
)

ERROR_CODES = frozenset(
    {
        "provider_not_found",
        "provider_unavailable",
        "unsupported_capability",
        "unsupported_model",
        "transcription_failed",
        "invalid_source",
        "incompatible_api_schema",
        "timeout",
        "cancelled",
    }
)
