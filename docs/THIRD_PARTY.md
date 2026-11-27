# 외부 기술과 라이선스

Airtype 원본 코드는 MIT이다. 기존 가상 마우스 프로젝트의 소스를 복사하지 않았다.

| 항목 | 사용 | 확인/배포 정책 |
|---|---|---|
| Apple Vision·AVFoundation·AppKit·SwiftUI·Core Graphics | 앱 | 시스템 프레임워크. Apple SDK 조건 적용 |
| Swift Testing | 개발 테스트 | 툴체인 제공. 앱에 테스트 프레임워크를 포함하지 않음 |
| MediaPipe | Python 연구 | 설치 버전과 패키지 라이선스는 uv.lock 및 upstream 확인 |
| OpenCV contrib·NumPy | Python 연구 | 같은 환경에 두 OpenCV wheel 설치 금지 |
| 모델 가중치 | 명시적 연구 다운로드 | 앱/저장소에 포함하지 않음. 재배포 전 해당 모델 조건 확인 |
| 1€ Filter | 논문 기반 직접 구현 | [Casiez et al. CHI 2012](https://gery.casiez.net/publications/CHI2012-casiez.pdf) 출처 명시 |

연구 도구의 버전 고정은 배포 권리를 자동으로 부여하지 않는다. MediaPipe가 제품 엔진으로 선정되면 helper에 포함하는 모든 wheel·동적 라이브러리·모델의 고지와 라이선스를 별도 검토한다.
