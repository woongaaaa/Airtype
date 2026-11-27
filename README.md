# Airtype

**내장 카메라로 조작하는 macOS 공중 키보드·터치패드.**

물리 키보드를 쓰기 어려운 일반 PC 사용자를 위한 보조 입력기를 만들고 있습니다. 양손 열 손가락 입력, 한글 두벌식·영문 QWERTY, 포인터·스크롤·브라우저 탐색을 하나의 앱으로 제공합니다.

현재 main에는 계획 문서를 먼저 기록했습니다. 실행 가능한 개발 코드는 [구현 PR #7](https://github.com/woongaaaa/Airtype/pull/7)과 [feat/native-app-and-cv-lab 브랜치](https://github.com/woongaaaa/Airtype/tree/feat/native-app-and-cv-lab)에서 검토할 수 있습니다.

> **현재 상태: 개발 프리뷰.** 앱·인식 실험·자동 테스트·DMG 생성 경로가 구현되어 있습니다. 실제 손으로 10 WPM·문자 오류율 5% 이하를 달성했다는 결과는 없습니다. 카메라/IME 실기기 평가, 외부 사용자 평가, 서명·공증 전이며 일반 사용자용 출시가 아닙니다. [출시 기준](docs/RELEASE.md)을 통과하기 전에는 정식 릴리스를 발행하지 않습니다.

## 시작하기

- Apple Silicon Mac, 내장 카메라, macOS 14 이상을 목표로 합니다. 현재 빌드 확인 환경은 M3 Pro·macOS 27.2.1입니다. 이전 OS와 다른 Mac에서의 호환성은 미검증입니다.
- 개발에는 Swift 6 이상을 포함한 Xcode 또는 Command Line Tools가 필요합니다. Python 실험에는 [uv](https://docs.astral.sh/uv/)와 Python 3.12를 사용합니다.

```bash
git clone --branch feat/native-app-and-cv-lab https://github.com/woongaaaa/Airtype.git
cd Airtype
bash scripts/build.sh
open build/Airtype.app
```

1. **카메라 시작**을 누르고 접근을 허용합니다. 앱은 자동으로 카메라를 켜지 않습니다.
2. 양손을 카메라 앞에 놓고 **홈 위치 보정**을 실행합니다.
3. **손가락 보정**에서 안내하는 손가락을 두 번 굽혔다 폅니다. 총 10개 손가락을 측정합니다.
4. **키보드** 모드에서 영문 키 위치 연습 결과를 확인합니다. 연습 문자열은 메모리에만 존재합니다.
5. 실제 입력을 시험할 때 **손쉬운 사용** 권한을 허용하고 **macOS에 실제 입력 보내기**를 켭니다. 키보드 이벤트 전송에는 10개 손가락 보정이 필요합니다.
6. TextEdit 등 대상 앱으로 이동합니다. 한글은 시스템 입력 소스에 **ABC·한국어 두벌식**을 추가한 뒤 사용합니다.

카메라에서 **손까지** 타이핑 40~80cm, 포인터 1~2m가 검증 목표입니다. 아직 보장 범위가 아닙니다. 카메라에 모든 손끝이 보여야 하며, 손을 기울이거나 띄워야 할 수 있습니다.

| 동작 | 개발 프리뷰의 조작 |
|---|---|
| 모드 선택 | 양손을 펼쳐 1.5초 유지 → 원하는 영역을 검지로 1초 가리키기 |
| 포인터 | 선택한 손의 검지 이동 |
| 클릭 / 더블클릭 | 엄지–검지 핀치 / 빠르게 두 번 |
| 드래그 | 핀치를 유지한 채 손 이동 |
| 우클릭 | 엄지–중지 핀치 |
| 스크롤 | 검지·중지를 펴고 약지를 굽힌 채 위아래 이동 |
| 뒤로 / 앞으로 | 펼친 손을 좌우로 이동. Safari·Chrome만 지원 |
| 조합키 | Shift·Command·Option·Control을 선택하면 다음 키에 한 번 적용 |
| 정지 | 모드 선택에서 일시정지, 메뉴 막대에서 카메라 중지 또는 앱 종료 |

손 추적 상실 시 입력을 해제합니다. 추적 복구만으로 자동 재개하지 않고 준비 상태로 돌아갑니다. 자동 반복·물리 키보드 수준의 동시 다중 입력은 지원하지 않습니다.

## 빌드·검증·패키징

```bash
bash scripts/check.sh            # Swift/Python tests, lint, docs, plist
bash scripts/package.sh          # dist/Airtype-0.1.0-dev-arm64.dmg
open build/Airtype.app --args --demo  # camera-free UI preview, no OS input
```

기본 빌드는 로컬 개발용 ad-hoc 서명입니다. 다른 사용자에게 정상 배포하려면 Developer ID 서명·공증과 [출시 검증](docs/RELEASE.md)이 필요합니다. 카메라 권한의 주체를 명확히 하기 위해 `swift run Airtype` 대신 `.app` 번들을 실행하세요. 빌드 후 앱 정체성이 바뀌면 시스템 설정에서 손쉬운 사용 권한을 다시 등록해야 할 수 있습니다.

## 구조와 기록

- [PRD](docs/PRD.md): 사용자, 범위, 수치 기준, 변경 기록
- [아키텍처](docs/ARCHITECTURE.md): 데이터 흐름, 좌표, 입력 상태, 복구
- [기술 결정](docs/adr/0001-native-app-and-tracker-experiments.md): 선택지 비교, 엔진 선택 조건
- [유사 프로젝트 분석](docs/research/RELATED_WORK.md): 확인한 사실과 개선 가설
- [실험 프로토콜](docs/experiments/PROTOCOL.md): 데이터 분리, WPM/CER, 타이밍
- [구현·검증 기록](docs/IMPLEMENTATION.md): 완료한 코드와 미검증 항목
- [로드맵](docs/ROADMAP.md): 8주 일정과 기술 검증 중단 조건
- [Python 실험 도구](research/README.md), [기여 가이드](CONTRIBUTING.md), [변경 기록](CHANGELOG.md)

앱에는 서버, 분석 SDK, 영상 저장, 자동 업로드가 없습니다. 연구 도구의 녹화는 별도 명령을 명시적으로 실행할 때만 동작합니다. 연구 영상·입력 문장·보정 자료는 기본적으로 Git에서 제외하며, 저장된 사용자 자료를 공개 저장소에 올리지 않습니다.

## English

Airtype is an experimental macOS assistive input application using the built-in camera. It combines ten-finger mid-air typing, Korean/English input, and gesture pointer control. The Swift app uses Apple Vision provisionally; the Python lab compares MediaPipe on identical video clips through a shared replay engine.

**Development preview, not release-qualified.** Real-hand accuracy, Korean IME compatibility, clean installation on other Macs, and external usability remain to be evaluated. Run `bash scripts/build.sh`, then open `build/Airtype.app`. All tracking is local. OS input is disabled by default. See the linked specifications and release gate before distributing a binary.

Original code: [MIT](LICENSE). Dependency notices: [THIRD_PARTY.md](docs/THIRD_PARTY.md).
