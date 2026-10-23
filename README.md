# bobbeori-android

유튜브 요리 영상을 구조화된 레시피로 바꾸고, 현재 조리 단계를 기억하며 대화로 안내하는 Android 앱입니다.

## 기술 기준

- Kotlin
- Jetpack Compose
- Material 3
- Android Gradle Plugin 9.3
- Gradle 9.5
- JDK 21
- compileSdk 37
- targetSdk 36
- minSdk 26

## 앱 식별 정보

- applicationId: `com.bobbeori.bobbeori_app`
- namespace: `com.bobbeori.bobbeori_app`

기존 Google Play 앱의 업데이트로 배포하기 위해 applicationId를 변경하지 않습니다. 릴리스 빌드 전 Play Console의 현재 versionCode와 기존 업로드 키를 반드시 확인해야 합니다.

## 로컬 실행

1. Android Studio에서 저장소 루트를 엽니다.
2. Gradle Sync가 완료될 때까지 기다립니다.
3. API 26 이상의 에뮬레이터 또는 실제 기기에서 `app` 구성을 실행합니다.

로컬 Supabase에 연결할 때는 Git에서 제외되는 `local.properties`에 다음 값을 추가합니다.

```properties
sdk.dir=C\:\\Users\\사용자명\\AppData\\Local\\Android\\Sdk
SUPABASE_URL=http://10.0.2.2:54321
SUPABASE_PUBLISHABLE_KEY=로컬_publishable_key
```

`10.0.2.2`는 Android 에뮬레이터에서 개발 PC를 가리키는 주소입니다. 실제 기기에서는 같은 네트워크에 연결한 뒤 개발 PC의 LAN IP로 바꿔야 합니다. 로컬 Supabase를 먼저 실행한 상태에서 앱을 켜면 익명 로그인과 본인 `profiles` 행 조회까지 자동으로 확인합니다.

Supabase 로컬 환경과 데이터베이스 검증 방법은 [Supabase local development](supabase/README.md)를 참고합니다.

## 릴리스 버전

로컬 디버그 기본값은 `versionCode=1`, `versionName=2.0.0-dev`입니다. 실제 배포 시 저장소에 비밀값을 커밋하지 않고 다음 Gradle 속성을 CI 또는 안전한 로컬 환경에서 전달합니다.

```properties
VERSION_CODE=기존 Play 출시 버전보다 큰 정수
VERSION_NAME=표시할 버전명
```

릴리스 서명 구성은 기존 Play App Signing 및 업로드 키 확인 후 추가합니다.
운영 Supabase 연결값은 `PROD_SUPABASE_URL`, `PROD_SUPABASE_PUBLISHABLE_KEY` Gradle 속성 또는 환경 변수로 주입합니다. 디버그용 로컬 주소가 릴리스 앱에 포함되지 않도록 분리되어 있습니다.

## 문서

- [MVP 제품 요구사항 정의서](docs/product/PRD.md)
- [MVP 사용자 흐름](docs/design/USER_FLOW.md)
- [MVP 화면 명세](docs/design/SCREEN_SPEC.md)
- [MVP 시스템 아키텍처](docs/architecture/SYSTEM_ARCHITECTURE.md)
- [Supabase 데이터 모델](docs/architecture/DATA_MODEL.md)
- [API 계약 초안](docs/architecture/API_CONTRACT.md)
- [초기 사업계획서 SVG](docs/business-plan/)
