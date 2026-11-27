# ADR 0001 — Swift 앱과 독립적인 CV 비교 실험

- 날짜: 2026-11-28
- 상태: 앱 기술 스택 채택 / 인식 엔진 최종 결정 보류

## 맥락

제작자는 다년의 iOS 클라이언트 개발 경험을 갖고 있으며, 6~8주에 배포 가능한 macOS 앱을 목표로 한다. 열 손가락 입력은 출시 필수 조건이다. 일반 사용자에게 Python 설치를 요구할 수 없다.

## 선택지

| 구성 | 유리한 점 | 비용·제약 | 결정 |
|---|---|---|---|
| Swift/SwiftUI/AppKit + Vision | 기존 경험, OS 통합, 작은 배포 구성 | 자세별 인식 품질 미검증 | 기준 앱 구현 |
| Python + MediaPipe + GUI | 빠른 CV 실험 | 런타임·서명·권한·UI 제품화 비용 | 연구 환경에 사용 |
| Swift + MediaPipe helper | 네이티브 UX와 대안 엔진 | 두 프로세스의 통신·복구·패키징 | 조건부 후속 |
| Flutter + MediaPipe | 다른 OS UI 공유 | 새 기술 학습과 네이티브 입력 연동 | v1 제외 |
| 웹 기반 데스크톱 | UI와 Web SDK 활용 | 카메라/추론/UI/네이티브 브리지 통합 | v1 제외 |
| C++ 중심 | 자원 제어 | 빌드·언어·UI 학습 비용 | 병목 증거 전 제외 |

MediaPipe의 iOS용 Swift 지원을 macOS용 SDK 지원과 동일시하지 않는다. Flutter의 macOS 지원 여부와 별개로 이번 일정에서 UI 플랫폼 전환은 우선하지 않는다. [MediaPipe iOS](https://developers.google.com/edge/mediapipe/solutions/setup_ios), [Flutter](https://developers.google.com/edge/mediapipe/solutions/setup_flutter)

## 결정 규칙

동일 영상·입력 판정·평가 세션을 이용한다. 2주차 초기 조건은 기본 키 오류율 10% 이하, 5분 비입력 과제 오입력 1회 이하, 실제 한글 입력과 독립 앱 실행이다.

1. Vision 통과: 제품 엔진으로 채택하고 비교 결과를 ADR에 첨부한다.
2. Vision 미달, MediaPipe 통과: 최소 helper 번들에서 권한·실행·지연·패키징 검증 후 통합한다.
3. 둘 다 미달: 제품 기능 확장을 중단하고 인식·자세·보정을 개선한다. 화면 키 선택형으로 바꾸지 않는다.

현재 선택은 성능 우위 주장이 아니라 개발 가능한 기준선이다. 커밋된 모델 가중치는 없으며 자동 다운로드도 없다. 연구 의존성은 `uv.lock`으로 고정한다. 두 종류의 OpenCV wheel을 함께 설치하지 않는다.
