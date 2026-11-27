# 출시와 배포

## 현재 상태

`0.1.0-dev`는 **개발 프리뷰**다. 실제 손 타이핑 성능, 한글 앱 호환성, 외부 평가, 다른 Mac 설치, Developer ID 서명·공증은 미완료다. `docs/release-gate.json`의 qualified는 false다. 개발 DMG가 만들어졌다는 사실을 일반 배포 승인으로 해석하지 않는다.

## 개발 패키지

```bash
bash scripts/check.sh
bash scripts/package.sh
```

생성물: `dist/Airtype-0.1.0-dev-arm64.dmg`와 SHA-256 파일. 로컬 앱은 ad-hoc 서명한다. Gatekeeper 우회 명령이나 SIP/보안 기능 해제를 설치 절차로 안내하지 않는다. 일반 사용자가 바로 설치할 파일은 다음의 서명·공증 절차가 끝난 결과여야 한다.

## 정식 배포 전

1. [PRD](PRD.md)의 모든 측정을 수행하고 참가자별 결과를 보관한다.
2. 실제 검증 OS·Mac 모델·앱 목록을 릴리스 노트에 명시한다.
3. Developer ID Application 인증서를 키체인에 준비한다. 인증서·암호·API key를 저장소에 넣지 않는다.
4. notarytool 자격 증명은 키체인 프로필로 저장한다.
5. release-gate.json에 근거 문서 경로를 연결하고 모든 체크를 검토한 뒤 qualified를 true로 변경한다.
6. `SIGNING_IDENTITY`와 `NOTARY_PROFILE`을 설정하고 `bash scripts/notarize.sh`를 실행한다.
7. 스크립트가 앱 서명→앱 공증→staple→DMG 생성·서명→DMG 공증·staple을 수행한다.
8. 새 사용자/다른 Mac에서 인터넷 유무를 나누어 설치, 권한 안내, 재실행, 종료·복구를 확인한다.
9. GitHub Releases에 DMG·checksum·알려진 한계·변경 사항을 게시한다. 랜딩페이지는 해당 릴리스 파일로 연결한다.

CI가 태그만 보고 정식 릴리스를 자동 발행하지 않도록 한다. 테스트 결과를 인식 정확도 결과로 대체하지 않는다.

## 수동 회귀 체크

- 카메라 거부/허용/중지와 앱 재시작
- 손쉬운 사용 권한 거부·해제, 실제 입력 기본 OFF
- ABC·두벌식 미설치 안내, 조합 중 삭제·받침 변경·Shift·한영 전환
- TextEdit/Safari/Chrome에서 복사·붙여넣기·실행 취소·방향키
- 손이 가려진 드래그, 프레임 콜백 중단, 포커스 변경, 잠자기·복귀
- 메뉴 막대에서 창 다시 열기·정지·종료
- 오버레이가 대상 앱의 포커스를 빼앗지 않음
- 다른 Mac에서 개발 도구 없이 설치와 첫 권한 부여

## 롤백

릴리스별 DMG·checksum·소스 태그를 유지한다. 입력 결함 발견 시 릴리스 노트에 조건을 명시하고 이전 검증 버전을 안내한다. 현재 자동 업데이트 서비스는 없다.
