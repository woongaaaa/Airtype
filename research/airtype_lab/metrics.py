"""Metrics operate on explicit experiment data, never global keyboard logs."""

from __future__ import annotations

import math
import unicodedata
from collections.abc import Sequence


def edit_distance(reference: Sequence, observed: Sequence) -> int:
    previous = list(range(len(observed) + 1))
    for i, expected in enumerate(reference, start=1):
        current = [i]
        for j, actual in enumerate(observed, start=1):
            current.append(min(current[-1] + 1, previous[j] + 1, previous[j - 1] + (expected != actual)))
        previous = current
    return previous[-1]


def character_error_rate(reference: str, observed: str) -> float:
    """NFC code-point CER. Can exceed 1.0 for excessive insertions; never clamp."""
    reference = unicodedata.normalize("NFC", reference)
    observed = unicodedata.normalize("NFC", observed)
    if not reference:
        raise ValueError("CER requires non-empty reference; use idle false events for empty prompts")
    return edit_distance(reference, observed) / len(reference)


def wpm(text: str, elapsed_seconds: float) -> float:
    if not math.isfinite(elapsed_seconds) or elapsed_seconds <= 0:
        raise ValueError("elapsed_seconds must be positive and finite, including correction time")
    return len(unicodedata.normalize("NFC", text)) / 5 / (elapsed_seconds / 60)


def percentile(values: list[float], quantile: float) -> float | None:
    if not 0 <= quantile <= 1 or any(not math.isfinite(v) for v in values):
        raise ValueError("Invalid percentile input")
    if not values:
        return None
    ordered = sorted(values)
    index = (len(ordered) - 1) * quantile
    low = int(index)
    high = min(low + 1, len(ordered) - 1)
    return ordered[low] + (ordered[high] - ordered[low]) * (index - low)


def match_events(expected: list[dict], actual: list[dict], tolerance: float = 0.15) -> dict:
    """Order-preserving, one-to-one matching; repeated keys cannot reuse a target.

    Dynamic programming maximizes matches, unlike greedy matching which can
    consume a later target and conceal reordering errors.
    """
    if tolerance < 0 or not math.isfinite(tolerance):
        raise ValueError("Invalid event tolerance")
    for events in (expected, actual):
        times = [float(event["timestamp"]) for event in events]
        if any(not math.isfinite(t) or t < 0 for t in times) or times != sorted(times):
            raise ValueError("Events must have finite non-negative monotonic timestamps")
    dp = [[0] * (len(actual) + 1) for _ in range(len(expected) + 1)]
    for i, target in enumerate(expected, start=1):
        for j, event in enumerate(actual, start=1):
            matches = (
                target["key"] == event["key"] and abs(target["timestamp"] - event["timestamp"]) <= tolerance
            )
            dp[i][j] = max(dp[i - 1][j], dp[i][j - 1], dp[i - 1][j - 1] + int(matches))
    count = dp[-1][-1]
    precision = count / len(actual) if actual else (1.0 if not expected else 0.0)
    recall = count / len(expected) if expected else 1.0
    return {
        "matched": count,
        "missed": len(expected) - count,
        "false_events": len(actual) - count,
        "precision": precision,
        "recall": recall,
        "f1": 2 * precision * recall / (precision + recall) if precision + recall else 0.0,
    }


def evaluate_trial(trial: dict) -> dict:
    required = {"participant", "session", "split", "language", "reference", "raw", "final", "elapsed_seconds"}
    if not required.issubset(trial):
        raise ValueError(f"Missing trial fields: {sorted(required - trial.keys())}")
    if trial["split"] != "evaluation":
        raise ValueError("Release evaluation must not mix calibration/training sessions")
    if trial["language"] not in {"en", "ko"}:
        raise ValueError("Supported evaluation languages are en and ko")
    result = {
        "participant": trial["participant"],
        "session": trial["session"],
        "language": trial["language"],
        "raw_cer": character_error_rate(trial["reference"], trial["raw"]),
        "final_cer": character_error_rate(trial["reference"], trial["final"]),
        "processing_ms_p95": percentile(trial.get("processing_ms", []), 0.95),
        "synthetic": bool(trial.get("synthetic", False)),
    }
    # English WPM and Hangul composed-character metrics must not be equated.
    if trial["language"] == "en":
        result["wpm_including_corrections"] = wpm(trial["final"], trial["elapsed_seconds"])
    else:
        if not trial.get("expected_keys") or "actual_keys" not in trial:
            raise ValueError("Korean evaluation requires key-event sequences as well as composed text")
        result["key_error_rate"] = edit_distance(trial["expected_keys"], trial["actual_keys"]) / len(
            trial["expected_keys"]
        )
    # A trial report alone can never certify the application's release gate.
    result["release_qualified"] = False
    return result
