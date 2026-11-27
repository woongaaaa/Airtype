from __future__ import annotations

import argparse
import hashlib
import json
import sys
import time
from pathlib import Path

from .metrics import evaluate_trial, match_events, percentile

JOINTS = ["wrist", "thumbCMC", "thumbMCP", "thumbIP", "thumbTip"] + [
    finger + joint
    for finger in ("index", "middle", "ring", "little")
    for joint in ("MCP", "PIP", "DIP", "Tip")
]


def export_mediapipe(args: argparse.Namespace) -> None:
    # Optional native libraries are loaded only by the commands that need them.
    import cv2
    import mediapipe as mp

    model = Path(args.model)
    digest = hashlib.sha256(model.read_bytes()).hexdigest()
    if digest != args.sha256:
        raise ValueError("Model SHA-256 does not match the explicitly selected artifact")
    if Path(args.output).exists():
        raise ValueError("Output already exists; select a new experiment output")
    capture = cv2.VideoCapture(args.input)
    if not capture.isOpened():
        raise ValueError("Cannot open video")
    # Both exporters consume upright, unmirrored source pixels and emit mirrored coordinates.
    options = mp.tasks.vision.HandLandmarkerOptions(
        base_options=mp.tasks.BaseOptions(model_asset_path=str(model)),
        running_mode=mp.tasks.vision.RunningMode.VIDEO,
        num_hands=2,
        min_hand_detection_confidence=0.5,
        min_hand_presence_confidence=0.5,
        min_tracking_confidence=0.5,
    )
    durations: list[float] = []
    previous_ms = -1
    count = 0
    try:
        with (
            mp.tasks.vision.HandLandmarker.create_from_options(options) as detector,
            open(args.output, "x") as output,
        ):
            while True:
                success, image = capture.read()
                if not success:
                    break
                timestamp = float(capture.get(cv2.CAP_PROP_POS_MSEC)) / 1000
                timestamp_ms = round(timestamp * 1000)
                if timestamp_ms <= previous_ms:
                    raise ValueError("Video timestamps are not strictly increasing; normalize the clip")
                previous_ms = timestamp_ms
                started = time.perf_counter()
                result = detector.detect_for_video(
                    mp.Image(image_format=mp.ImageFormat.SRGB, data=cv2.cvtColor(image, cv2.COLOR_BGR2RGB)),
                    timestamp_ms,
                )
                durations.append((time.perf_counter() - started) * 1000)
                hands = []
                for landmarks, categories in zip(result.hand_landmarks, result.handedness):
                    if not categories:
                        continue
                    # Tasks returns model handedness for the actual image; validate labels
                    # against the clip's labeled left/right pose before engine selection.
                    side = categories[0].category_name.lower()
                    if args.swap_handedness:
                        side = "right" if side == "left" else "left"
                    hands.append(
                        {
                            "side": side,
                            "joints": {
                                name: {"x": 1 - p.x, "y": p.y, "z": p.z} for name, p in zip(JOINTS, landmarks)
                            },
                        }
                    )
                output.write(json.dumps({"schemaVersion": 1, "timestamp": timestamp, "hands": hands}) + "\n")
                count += 1
    finally:
        capture.release()
    metadata = {
        "engine": "mediapipe",
        "mediapipe_version": mp.__version__,
        "frames": count,
        "model_sha256": digest,
        "source_sha256": hashlib.sha256(Path(args.input).read_bytes()).hexdigest(),
        "inference_ms_p95": percentile(durations, 0.95),
        "swapped_handedness": args.swap_handedness,
        "note": "Offline inference timing is NOT live end-to-end input latency",
    }
    Path(args.output + ".meta.json").write_text(json.dumps(metadata, indent=2) + "\n")


def record(args: argparse.Namespace) -> None:
    import cv2

    if args.seconds <= 0 or args.seconds > 120:
        raise ValueError("Record 1–120 seconds per explicit research session")
    if Path(args.output).exists():
        raise ValueError("Refusing to overwrite an existing recording")
    print(
        "Recording locally. Confirm this camera index is the built-in camera; recordings are never uploaded.",
        file=sys.stderr,
    )
    cap = cv2.VideoCapture(args.camera, cv2.CAP_AVFOUNDATION)
    writer = None
    try:
        if not cap.isOpened():
            raise ValueError("Camera unavailable or permission denied")
        cap.set(cv2.CAP_PROP_FRAME_WIDTH, 640)
        cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)
        started = time.monotonic()
        while time.monotonic() - started < args.seconds:
            success, frame = cap.read()
            if not success:
                raise ValueError("Camera stopped delivering frames")
            if writer is None:
                writer = cv2.VideoWriter(
                    args.output, cv2.VideoWriter_fourcc(*"mp4v"), 30, (frame.shape[1], frame.shape[0])
                )
                if not writer.isOpened():
                    raise ValueError("Cannot create recording")
            writer.write(frame)
    finally:
        cap.release()
        if writer is not None:
            writer.release()
    print(
        "Saved fixed-30-fps comparison clip. Do not use it to measure wall-clock typing speed.",
        file=sys.stderr,
    )


def main() -> None:
    parser = argparse.ArgumentParser(description="Airtype offline experiments; no OS input injection")
    commands = parser.add_subparsers(dest="command", required=True)
    evaluate = commands.add_parser("evaluate")
    evaluate.add_argument("trials", help="JSONL of explicit evaluation trials")
    events = commands.add_parser("events")
    events.add_argument("expected")
    events.add_argument("actual")
    events.add_argument("--tolerance", type=float, default=0.15)
    export = commands.add_parser("export")
    export.add_argument("--input", required=True)
    export.add_argument("--output", required=True)
    export.add_argument("--model", required=True)
    export.add_argument("--sha256", required=True)
    export.add_argument("--swap-handedness", action="store_true")
    recording = commands.add_parser("record")
    recording.add_argument("--camera", type=int, required=True)
    recording.add_argument("--seconds", type=int, default=10)
    recording.add_argument("--output", required=True)
    args = parser.parse_args()
    try:
        if args.command == "evaluate":
            for line in Path(args.trials).read_text().splitlines():
                if line.strip():
                    print(json.dumps(evaluate_trial(json.loads(line)), ensure_ascii=False, allow_nan=False))
        elif args.command == "events":

            def read_keys(path):
                return [
                    event
                    for line in Path(path).read_text().splitlines()
                    if line.strip() and (event := json.loads(line)).get("type", "key") == "key"
                ]

            print(json.dumps(match_events(read_keys(args.expected), read_keys(args.actual), args.tolerance)))
        elif args.command == "export":
            export_mediapipe(args)
        elif args.command == "record":
            record(args)
    except (ValueError, OSError, KeyError) as error:
        parser.exit(2, f"{error}\n")


if __name__ == "__main__":
    main()
