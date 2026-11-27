import pytest

from airtype_lab.metrics import (
    character_error_rate,
    edit_distance,
    evaluate_trial,
    match_events,
    percentile,
    wpm,
)


def test_edit_distance_counts_missing_duplicate_and_wrong_keys():
    assert edit_distance("hello", "helo") == 1
    assert edit_distance("abc", "abcc") == 1
    assert edit_distance("abc", "axc") == 1
    assert edit_distance([], ["space"]) == 1


def test_cer_preserves_insertions_and_normalizes_hangul():
    assert character_error_rate("a", "aaaa") == 3
    assert character_error_rate("한", "한") == 0
    with pytest.raises(ValueError):
        character_error_rate("", "")


def test_wpm_uses_total_time_including_corrections():
    assert wpm("hello world", 60) == 2.2
    for time in (0, -1, float("nan"), float("inf")):
        with pytest.raises(ValueError):
            wpm("hello", time)


def test_event_matching_does_not_reuse_or_reorder_ground_truth():
    reference = [{"timestamp": 1, "key": "a"}, {"timestamp": 1.1, "key": "b"}]
    actual = [{"timestamp": 1, "key": "b"}, {"timestamp": 1.1, "key": "a"}]
    result = match_events(reference, actual)
    assert result["matched"] == 1
    assert result["false_events"] == 1
    assert match_events(reference[:1], [actual[1], actual[1]])["matched"] == 1


def test_missing_predictions_are_not_a_success():
    result = match_events([{"timestamp": 1, "key": "a"}], [])
    assert result["f1"] == 0
    assert result["missed"] == 1


def test_event_time_validation():
    with pytest.raises(ValueError):
        match_events([], [{"timestamp": float("nan"), "key": "a"}])


def test_percentile_interpolates_and_handles_empty_data():
    assert percentile([], 0.95) is None
    assert percentile([0, 100], 0.95) == 95


def test_trial_is_not_release_certification():
    trial = {
        "participant": "synthetic",
        "session": "s1",
        "split": "evaluation",
        "language": "en",
        "reference": "hello",
        "raw": "hello",
        "final": "hello",
        "elapsed_seconds": 1,
        "synthetic": True,
    }
    result = evaluate_trial(trial)
    assert result["synthetic"]
    assert not result["release_qualified"]
    trial["split"] = "calibration"
    with pytest.raises(ValueError):
        evaluate_trial(trial)


def test_korean_requires_key_events_and_does_not_report_english_wpm():
    trial = {
        "participant": "synthetic",
        "session": "s1",
        "split": "evaluation",
        "language": "ko",
        "reference": "한",
        "raw": "한",
        "final": "한",
        "elapsed_seconds": 1,
        "synthetic": True,
    }
    with pytest.raises(ValueError):
        evaluate_trial(trial)
    trial.update(expected_keys=["g", "k", "s"], actual_keys=["g", "k", "s"])
    result = evaluate_trial(trial)
    assert result["key_error_rate"] == 0
    assert "wpm_including_corrections" not in result
