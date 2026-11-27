# 유사 프로젝트와 연구 분석

검토일: 2026-11-28. README와 표시된 소스에 대한 검토이며 실행 성능 비교가 아니다. 별 수·데모 영상만으로 정확도·유지보수성·안전성을 판단하지 않는다.

| 프로젝트 | 검토 근거 | 확인한 특징 | Airtype의 검증 과제 |
|---|---|---|---|
| [NonMouse](https://github.com/takeyamayuki/NonMouse) | README, LICENSE | 배치 설정, 실행 파일, 단축키 활성화, Apache-2.0 | 키보드 없는 모드 제어, 내장 카메라 보정 |
| [Gesture Controlled Virtual Mouse](https://github.com/Viral-Doshi/Gesture-Controlled-Virtual-Mouse) | README | Windows 중심, 클릭·스크롤·드래그·음성 기능 | macOS 제품화와 작은 조작 체계 |
| [handTrack](https://github.com/small-cactus/handTrack/blob/main/handTrack.py) | 소스 blob c071b440de484f9f936852e332a21ada58d661dd | 손 크기 기준 핀치, 손 상실 시 mouseUp, 이동/스크롤 스레드 | 모드 충돌·카메라 프레임 중단·종료 복구 |
| [Mac Hand Controller](https://github.com/minwoo19930301/mac-hand-control) | README blob dd40d8a2311aa7f140996d403648bff64fead52f | DMG, 권한 안내, 포인터·스크롤·Space 제스처, README상 미공증 | 한글/열 손가락 통합과 검증된 배포 |
| [AirTouch](https://github.com/alanrbtx/airtouch-macos) | README blob 151e6493679c1bc381f55efa25a436c8af26d49b | Swift·Vision, 메뉴 막대, 로컬 처리, 포인터/스크롤 | 타이핑·개인 보정·사용자별 품질 보고 |

handTrack은 이미 손 상실 시 버튼을 해제한다. Airtype의 차별점을 단순히 '버튼 해제'라고 주장하지 않는다. 카메라 콜백 자체가 멈추는 경우, 모드 전환·추적 회복·권한 변경을 포함한 전체 상태 흐름과 반복 검증을 개선 대상으로 삼는다.

## 타이핑 연구

- [ATK: Ten-Finger Freehand Typing](https://pi.cs.tsinghua.edu.cn/lab/papers/p539-yi.pdf): 손가락 운동과 동반 움직임, 누름 판정, 확률적 보정이 별도 문제임을 보여 준다. 연구의 3D 추적 조건과 보정 결과를 내장 RGB 카메라에 그대로 적용하지 않는다.
- [Probabilistic Mid-Air QWERTY](https://www.hbenko.com/publications/2023/DudleyEtAlTVCGISMAR2023.pdf): VR 손 추적과 확률적 디코딩을 사용한다. 입력 방법·촉각 부재·사용자 평가의 참고 자료다. Airtype이 동일 성능을 달성한다는 근거가 아니다.
- [1€ Filter](https://gery.casiez.net/publications/CHI2012-casiez.pdf): 저속 떨림과 고속 지연의 절충을 다룬다. Airtype의 필터는 논문 개념을 바탕으로 직접 구현하고 파라미터를 실험으로 조정한다.

## 차별화 가설과 증거

| 가설 | 필요한 증거 | 현재 |
|---|---|---|
| 표준 배열의 열 손가락 입력이 보조 작업에 충분하다 | 미학습 문장 CER·WPM, 모든 손가락 역할 검증 | 미검증 |
| 한글·영문을 실제 앱에서 사용할 수 있다 | 조합·삭제·전환·단축키 실기기 과제 | 코드 구현, 미검증 |
| 키보드 없이 활성화부터 복구까지 가능하다 | 일반 사용자 연속 과제 | 흐름 구현, 미검증 |
| 일반 사용자가 설치할 수 있다 | 서명·공증 DMG의 다른 Mac 설치 | 개발 DMG 경로 구현 |

기존 프로젝트의 소스는 복사하지 않았다. 라이선스 파일을 찾지 못한 프로젝트는 재사용 가능한 코드라고 판단하지 않는다. 기능 수보다 재현 가능한 사용성·오류·복구 자료로 차별화를 설명한다.
