# PR 올리는 방법 (푸시 권한이 없어 중단된 지점부터)

커밋은 이미 만들어 두었습니다.

- 브랜치: `feat/three-points-90000cps`
- 커밋: `567b0b6` — "지점 3곳 동시 입력, 목표 속도 상한 90,000"
- 기준(base) 커밋: `f5c5b073f752a19a4d103a2ecb5f76b133c25c07` (origin/main)
- 변경: 파일 8개, +124 / −61

## 왜 멈췄나

이 세션에 연결된 GitHub 계정은 **luna19219**입니다. 저장소 주인은 **sms2620525-lgtm**이고, 연결된 계정에는 이 저장소에 대한 쓰기 권한이 없습니다. 브랜치 생성과 포크 모두 `403 Resource not accessible by integration`으로 거부되었습니다. 이 Mac의 git 자격증명(osxkeychain)에도 github.com 계정이 저장되어 있지 않아 로컬 푸시도 되지 않습니다.

## 방법 1 — 제가 이어서 올리기

둘 중 하나만 해주시면 제가 푸시하고 PR까지 올립니다.

- GitHub에서 `sms2620525-lgtm/autoclicker-android` → Settings → Collaborators에 **luna19219** 추가, 또는
- 이 세션의 GitHub 커넥터 권한을 그 저장소까지 확장(저장소 소유 계정으로 앱 권한 부여)

## 방법 2 — 직접 올리기 (포크 PR)

1. 브라우저에서 저장소 페이지의 **Fork**를 눌러 `luna19219/autoclicker-android`를 만듭니다.
2. 로컬에 클론한 저장소에서(없으면 새로 클론) 아래를 실행합니다. 패치 파일(`tapbench-3points-90000cps.patch`)과 커밋 메시지(`커밋메시지.txt`)를 같은 폴더에 두세요.

```bash
git fetch origin && git switch -c feat/three-points-90000cps f5c5b073f752a19a4d103a2ecb5f76b133c25c07
git apply tapbench-3points-90000cps.patch
git add -u && git commit -F 커밋메시지.txt
git remote add fork https://github.com/luna19219/autoclicker-android.git
git push -u fork feat/three-points-90000cps
```

3. 아래 링크를 열면 PR 작성 화면이 바로 뜹니다.

   https://github.com/sms2620525-lgtm/autoclicker-android/compare/main...luna19219:feat/three-points-90000cps?expand=1

### 커밋을 그대로 쓰고 싶다면

`tapbench-branch.bundle`에 제가 만든 커밋이 그대로 들어 있습니다. 패치를 적용하는 대신 이렇게 가져올 수 있습니다(클론의 main이 `f5c5b073f752a19a4d103a2ecb5f76b133c25c07`일 때).

```bash
git fetch ./tapbench-branch.bundle feat/three-points-90000cps:feat/three-points-90000cps
```

## PR 본문으로 쓸 내용

### 요약
- 클릭 지점을 1곳 → **3곳**으로. 제스처 하나에 스트로크 3개를 담아 세 지점을 **동시에** 누릅니다(번갈아 누르기 아님). `dispatchGesture` 스트로크 상한은 10개.
- 목표 속도 상한을 5,000 → **90,000**으로. 상한 숫자는 `TapEngine.MAX_CPS` 한 곳에만 둡니다.
- 측정 패드가 `ACTION_POINTER_UP`도 세도록 수정(동시 3점은 손가락 3개로 도착해 `ACTION_UP`은 마지막 1개뿐이었음).
- 결과 JSON `schema_version` 2: `points_per_gesture`, `target_taps_per_second`, `completed_taps`, `completed_taps_per_second` 추가.

### 주의
90,000은 **설정 상한**이며 실제 터치 속도가 아닙니다. 제스처 완료 콜백을 기다리는 단일 비행(single-flight) 구조는 그대로이므로 실제 완료 속도는 기기의 입력 왕복 시간이 정하고, 도달하지 못한 목표 시점은 `건너뛴 목표 슬롯`에 그대로 집계됩니다.

### 검증
로컬에 JDK/Android SDK가 없어 **빌드와 테스트는 실행하지 못했습니다.** CI(`Android APK and real touch test`)로 확인이 필요합니다.
