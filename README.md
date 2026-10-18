# TapBench 오토클릭커

네이티브 Android APK. 선택한 **3개 좌표**를 동시에 반복 터치하고 실제 성능을 측정합니다. HTML, WebView, 웹 호스팅을 사용하지 않습니다. Android 7.0(API 24) 이상에서 동작하며 루트 권한이 필요하지 않습니다.

## 지점 3곳

**위치** 선택 화면에서 지점을 3번 눌러 좌표 3개를 지정합니다. 한 번의 제스처가 스트로크 3개를 담아 세 지점을 **동시에** 누르므로, 완료 제스처 1회는 실제 탭 3회입니다. `dispatchGesture`의 스트로크 상한은 10개이므로 3개는 허용 범위입니다. 번갈아 누르는 방식이 아닙니다.

## 90,000회/초의 의미

목표 속도를 1~90,000 CPS(제스처/초)로 설정할 수 있습니다. **90,000은 목표값이며 실제 90,000번/초 터치를 보장하지 않습니다.** 이 속도의 간격은 약 0.011ms이며, Android 접근성 입력 경로가 이 속도를 처리하지 못합니다. 실제 완료 속도는 기기의 제스처 왕복 응답 시간이 정하며 보통 목표보다 수백 배 낮습니다. 도달하지 못한 목표 슬롯은 `건너뛴 목표 슬롯`에 그대로 표시하고 몰아서 보내지 않습니다. Android 접근성 터치는 양의 정수 밀리초 지속 시간과 시스템 처리 지연을 가지며, 이전 제스처가 진행 중일 때 새 제스처를 보내면 기존 터치가 취소됩니다. 따라서 한 번에 제스처 하나(스트로크 3개 = 지점 3곳)만 보내고 완료 콜백 이후 다음 제스처를 예약합니다. 실제 속도는 기기와 대상 앱에 따라 낮아집니다. CPU 루프의 실행 횟수를 터치 성능으로 표시하지 않습니다.

공식 근거: [AccessibilityService.dispatchGesture](https://developer.android.com/reference/android/accessibilityservice/AccessibilityService#dispatchGesture(android.accessibilityservice.GestureDescription,%20android.accessibilityservice.AccessibilityService.GestureResultCallback,%20android.os.Handler)), [StrokeDescription](https://developer.android.com/reference/android/accessibilityservice/GestureDescription.StrokeDescription).

## APK 받기

GitHub 저장소 → **Releases → 최신 TapBench 테스트 APK → Assets → TapBench-1.0.0-debug.apk**를 받으세요. 비공개 저장소이므로 GitHub 로그인이 필요합니다. `SHA256SUMS.txt`로 파일 해시를 확인할 수 있습니다. Actions의 **Android APK and real touch test → Run workflow**로 다시 빌드할 수 있습니다. Actions artifact 저장공간을 사용하지 않고 같은 저장소의 비공개 릴리스에 파일을 첨부합니다.

이 APK는 테스트용 debug 서명입니다. CI 실행마다 서명키가 달라질 수 있으므로 재설치할 때 서명 충돌이 나면 기존 테스트 앱을 제거한 후 설치하세요(앱 설정도 초기화됩니다). 스토어 배포용 개인 서명키는 포함하지 않습니다.

## 사용

1. 앱의 **접근성 설정 열기**에서 TapBench 서비스를 켭니다. Android 13 이상에서 설치 출처에 따라 제한된 설정 안내가 나오면 기기의 앱 정보 메뉴에서 접근성 허용 관련 설정을 확인하세요.
2. 목표 속도와 실행 시간을 입력하고 **설정 저장 · 떠 있는 제어창 열기**를 누릅니다.
3. 대상 앱으로 이동합니다. 떠 있는 창의 **위치**를 누르고 반복 클릭할 화면 지점을 **3번** 선택합니다. 3번째 선택에서 선택 화면이 닫히고, 20초가 지나면 그때까지 고른 지점으로 종료합니다. 선택 터치는 대상 앱으로 전달되지 않습니다.
4. 제어창이 목표 지점 중 하나라도 가리면 제어창 상단을 드래그해서 옮깁니다. **시작**을 누르면 2초 후 클릭을 시작합니다.
5. **정지** 또는 **닫기**로 중지합니다. 화면 꺼짐·화면 구성 변경·입력 취소·응답 시간 초과에도 중지합니다. 화면 회전 후에는 위치를 다시 선택합니다. 이미 전달된 한 번의 터치는 정지 직후 완료될 수 있습니다.

## 기기 성능 테스트

**설정한 속도로 10초 테스트**를 누르면 2초 준비 후 앱의 측정 패드 안 3개 지점에 실제 터치를 보냅니다. 테스트 중 패드를 직접 만지지 마세요. 다른 화면으로 나가면 테스트를 중지합니다.

| 지표 | 뜻 |
|---|---|
| 목표 CPS | 사용자가 설정한 목표(제스처/초). 지점 3곳이면 목표 탭은 그 3배 |
| 완료 CPS | Android가 완료 콜백을 반환한 제스처 수 / 실제 경과 시간 |
| 실제 탭 | 완료 제스처 수 × 지점 수 |
| 수신 CPS | 테스트 패드가 받은 손가락별 터치 종료(ACTION_UP·ACTION_POINTER_UP) 수 / 같은 측정 시간 |
| 취소·거절·시간초과 | Android의 취소/거절, 2초 동안 응답이 없는 요청 |
| 건너뛴 목표 슬롯 | 입력 처리를 기다리느라 놓친 예약 시점; 추가 클릭으로 보충하지 않음 |
| 미확인 | 정지 시 이미 전달되었지만 결과를 아직 확인하지 못한 제스처 |

측정 종료 후 **결과 JSON 저장**으로 기기 모델/API, 목표, 경과 시간, 요청·완료·수신 수와 CPS를 저장할 수 있습니다. 다른 앱의 내부 클릭 처리는 확인할 수 없으므로 외부 클릭은 완료 콜백 기준으로만 표시합니다. 앱 강제 종료 시 현재 측정은 보존되지 않으므로 필요한 결과는 내보내세요.

## 빌드 및 테스트

- JDK 17, Gradle 8.11.1, Android SDK 35 / Build Tools 35.0.0, AGP 8.9.2.
- Gradle이 설치된 환경: `gradle testDebugUnitTest lintDebug assembleDebug assembleDebugAndroidTest`.
- Android Studio에서는 Gradle 8.11.1 로컬 설치를 선택하거나 `gradle wrapper --gradle-version 8.11.1`로 공식 wrapper를 생성할 수 있습니다.
- Actions는 위 버전을 설치하고 9개 JVM 테스트, Android Lint, debug APK 빌드 후 API 35 에뮬레이터에서 실제 입력 경로를 검사합니다.
- 에뮬레이터 테스트는 정지 후 요청이 증가하지 않는지 검사하고 목표 90,000 CPS로 5초 측정하여 실제 터치가 도착하는지 검증합니다. **90,000 CPS 달성을 통과 조건으로 속이지 않습니다.** 에뮬레이터 CPS는 휴대폰 성능을 대표하지 않습니다.
- 릴리스의 `TapBench-test-results.zip`에 테스트 보고서, `benchmark.json`, 에뮬레이터 화면을 저장합니다. 에뮬레이터 테스트가 실패해도 디버깅용 APK와 가능한 보고서를 보존합니다. Actions 성공 상태를 함께 확인하세요.

접근성 서비스는 화면 내용을 읽지 않습니다(`canRetrieveWindowContent=false`). 인터넷, 저장소 전체 접근, 루트 권한을 요청하지 않습니다. JSON 저장은 Android 파일 선택기를 사용합니다.
