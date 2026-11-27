# Airtype Lab

앱에 시스템 입력을 보내지 않는 오프라인 비교 도구다. Vision과 MediaPipe가 같은 영상을 처리하고 **같은 Swift 입력 엔진**으로 재생된다. 모델이나 API의 추론 속도를 제품의 타이핑 속도로 바꾸어 보고하지 않는다.

```bash
uv sync --project research --frozen --no-editable
uv run --project research --no-editable pytest research/tests
uv run --project research --no-editable airtype-lab --help
```

## 모델 준비

모델은 앱과 저장소에 포함하지 않는다. 공식 저장소의 특정 파일과 SHA-256을 [manifest](model-manifest.json)에 고정했다. 명시적으로 다운로드하고 검증한다.

```bash
mkdir -p research/models research/data
curl -fL https://storage.googleapis.com/mediapipe-models/hand_landmarker/hand_landmarker/float16/1/hand_landmarker.task -o research/models/hand_landmarker.task
shasum -a 256 research/models/hand_landmarker.task
```

기대 해시: `fbc2a30080c3c557093b5ddfc334698132eb341044ccee322ccf8bcf3607cde1`.

## 자료 수집

직접 동의한 연구 세션에서만 녹화한다. 카메라 번호를 먼저 확인하며, 앱과 녹화 도구를 동시에 실행하지 않는다. iPhone/외장 카메라가 선택되지 않았는지 확인한다.

```bash
uv run --project research --no-editable airtype-lab record --camera 0 --seconds 10 --output research/data/session.mp4
```

이 녹화기는 비교용 30fps 컨테이너를 만든다. 캡처 시 실제 wall-clock 간격을 보존하지 않으므로 이 파일로 WPM이나 실제 입력 지연을 측정하지 않는다. 실제 키 이벤트 시각과 벽시계 시간은 별도 실험 기록으로 수집한다. 연구 영상·JSONL은 기본 gitignore 대상이다.

## 동일 영상 추출

영상은 upright/unmirrored, 회전 메타데이터가 없는 파일이어야 한다. 왼손·오른손 라벨을 확인하는 장면을 포함한다.

```bash
# 프로젝트 루트에서 실행
swift build --build-system native --product vision-export
swift run --build-system native vision-export research/data/session.mp4 research/data/vision.jsonl
uv run --project research --no-editable airtype-lab export \
  --input research/data/session.mp4 --output research/data/mediapipe.jsonl \
  --model research/models/hand_landmarker.task \
  --sha256 fbc2a30080c3c557093b5ddfc334698132eb341044ccee322ccf8bcf3607cde1
```

현재 컴퓨터에서 Xcode 설정이 완료되지 않은 경우 위 Swift 명령 앞에 `DEVELOPER_DIR=/Library/Developer/CommandLineTools`를 지정할 수 있다. 정상 설치된 CLT가 있어야 한다.

MediaPipe의 좌우 손 라벨을 정답 영상과 대조한다. 좌우가 반대면 `--swap-handedness`를 사용하고 결과 메타데이터에 기록한다. confidence가 없는 관절에는 값을 만들지 않는다. 출력 파일은 기존 결과를 덮어쓰지 않는다.

## 입력 판정 재생

```bash
swift run --build-system native airtype-replay \
  --input research/data/vision.jsonl --mode keyboard \
  --profile research/data/calibration.json > research/data/vision-events.jsonl
```

`calibration.json`은 CalibrationProfile v1 계약을 따른다. [합성 예시](../fixtures/calibration.synthetic.json)는 형식 확인용이며 실사용 보정값이 아니다. 엔진별 보정 자료와 평가 자료를 분리하고 같은 판정 로직·임계값 비교를 우선한다.

## 결과 평가

```bash
uv run --project research --no-editable airtype-lab events research/data/expected.jsonl research/data/vision-events.jsonl
uv run --project research --no-editable airtype-lab evaluate fixtures/trials.synthetic.jsonl
```

trial JSONL 필수 필드: `participant`, `session`, `split:evaluation`, `language:en|ko`, `reference`, `raw`, `final`, `elapsed_seconds`. 한글은 `expected_keys`·`actual_keys`도 필요하다. 선택 필드 `processing_ms`는 실제 프레임 수신→이벤트 발행 측정값이다. 원본 입력 문장을 진단 로그나 GitHub에 자동 공개하지 않는다.

합성 예시는 `synthetic:true`이며 출력에 `release_qualified:false`가 붙는다. 개별 trial로 앱 출시 전체를 승인하지 않는다. 자세한 조건은 [실험 프로토콜](../docs/experiments/PROTOCOL.md)을 따른다.
