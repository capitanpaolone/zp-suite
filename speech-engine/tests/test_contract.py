from __future__ import annotations

from copy import deepcopy

import pytest

from zp_speech import ContractValidationError, validate_document
from zp_speech.contracts import ERROR_CODES

VALID_FIXTURES = (
    "transcript_with_words.json",
    "transcript_without_words.json",
    "transcript_with_speaker.json",
    "provider_capabilities.json",
    "error.json",
    "search_result.json",
)


@pytest.mark.parametrize("fixture_name", VALID_FIXTURES)
def test_valid_fixtures(fixture_name, load_fixture):
    validate_document(load_fixture(fixture_name))


def test_invalid_fixture_is_rejected(load_fixture):
    with pytest.raises(ContractValidationError, match="contained"):
        validate_document(load_fixture("transcript_invalid.json"))


@pytest.mark.parametrize(
    ("field", "value"),
    (("schema_version", 2), ("api_version", "v2")),
)
def test_only_v1_is_compatible(field, value, load_fixture):
    document = load_fixture("transcript_with_words.json")
    document[field] = value
    with pytest.raises(ContractValidationError):
        validate_document(document)


def test_project_time_is_not_persistent_transcript_data(load_fixture):
    document = load_fixture("transcript_with_words.json")
    document["segments"][0]["project_time"] = 12.5
    with pytest.raises(ContractValidationError):
        validate_document(document)


def test_source_ids_must_agree(load_fixture):
    document = load_fixture("transcript_with_words.json")
    document["source"]["source_id"] = "sha256:" + "f" * 64
    with pytest.raises(ContractValidationError, match="must equal"):
        validate_document(document)


def test_source_id_must_be_content_addressed(load_fixture):
    document = load_fixture("transcript_with_words.json")
    document["source_id"] = "/tmp/voce.wav"
    with pytest.raises(ContractValidationError):
        validate_document(document)


def test_source_id_must_encode_content_digest(load_fixture):
    document = load_fixture("transcript_with_words.json")
    document["source"]["content_hash"]["digest"] = "f" * 64
    with pytest.raises(ContractValidationError, match="digest encoded"):
        validate_document(document)


@pytest.mark.parametrize(("start", "end"), ((-1, 100), (100, 100), (101, 100)))
def test_invalid_segment_intervals_are_rejected(start, end, load_fixture):
    document = load_fixture("transcript_without_words.json")
    document["segments"][0]["start_ms"] = start
    document["segments"][0]["end_ms"] = end
    with pytest.raises(ContractValidationError):
        validate_document(document)


def test_segments_must_be_temporally_ordered(load_fixture):
    document = load_fixture("transcript_without_words.json")
    document["segments"].reverse()
    with pytest.raises(ContractValidationError, match="ordered"):
        validate_document(document)


def test_words_must_be_temporally_ordered(load_fixture):
    document = load_fixture("transcript_with_words.json")
    document["segments"][0]["words"].reverse()
    with pytest.raises(ContractValidationError, match="ordered"):
        validate_document(document)


def test_word_times_must_be_non_negative(load_fixture):
    document = load_fixture("transcript_with_words.json")
    document["segments"][0]["words"][0]["start_ms"] = -1
    with pytest.raises(ContractValidationError):
        validate_document(document)


def test_words_require_declared_capability(load_fixture):
    document = load_fixture("transcript_with_words.json")
    document["capabilities"]["word_timestamps"] = False
    with pytest.raises(ContractValidationError, match="word_timestamps"):
        validate_document(document)


def test_speaker_labels_require_diarization_capability(load_fixture):
    document = load_fixture("transcript_with_speaker.json")
    document["capabilities"]["diarization"] = False
    with pytest.raises(ContractValidationError, match="diarization"):
        validate_document(document)


def test_timed_transcript_requires_segment_timestamp_capability(load_fixture):
    document = load_fixture("transcript_without_words.json")
    document["capabilities"]["segment_timestamps"] = False
    with pytest.raises(ContractValidationError, match="segment_timestamps"):
        validate_document(document)


@pytest.mark.parametrize(
    "fixture_name",
    ("transcript_with_words.json", "provider_capabilities.json"),
)
def test_word_timestamps_imply_segment_timestamps(fixture_name, load_fixture):
    document = load_fixture(fixture_name)
    document["capabilities"]["word_timestamps"] = True
    document["capabilities"]["segment_timestamps"] = False
    with pytest.raises(ContractValidationError, match="segment timestamps"):
        validate_document(document)


def test_search_match_must_use_result_source(load_fixture):
    document = load_fixture("search_result.json")
    document["matches"][0]["source_id"] = "sha256:" + "e" * 64
    with pytest.raises(ContractValidationError, match="result source_id"):
        validate_document(document)


def test_project_time_is_not_persistent_search_data(load_fixture):
    document = load_fixture("search_result.json")
    document["matches"][0]["project_seconds"] = 133.42
    with pytest.raises(ContractValidationError):
        validate_document(document)


def test_search_match_must_be_inside_segment(load_fixture):
    document = load_fixture("search_result.json")
    document["matches"][0]["start_ms"] = 1000
    with pytest.raises(ContractValidationError, match="inside"):
        validate_document(document)


@pytest.mark.parametrize(
    ("field", "value"),
    (("end_ms", 2200), ("segment_end_ms", 1250)),
)
def test_search_intervals_must_be_positive(field, value, load_fixture):
    document = load_fixture("search_result.json")
    document["matches"][0][field] = value
    with pytest.raises(ContractValidationError, match="interval"):
        validate_document(document)


def test_search_match_end_must_be_inside_segment(load_fixture):
    document = load_fixture("search_result.json")
    document["matches"][0]["end_ms"] = 4400
    with pytest.raises(ContractValidationError, match="inside"):
        validate_document(document)


@pytest.mark.parametrize("code", sorted(ERROR_CODES))
def test_every_v1_error_code_is_valid(code, load_fixture):
    document = deepcopy(load_fixture("error.json"))
    document["error"]["code"] = code
    validate_document(document)
