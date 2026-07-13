import Foundation
#if canImport(Sentry)
import Sentry
#endif

/// 원격 오류/크래시 수집 (Sentry). 패키지가 없으면(canImport 실패) 전부 no-op이 되어
/// 앱은 문제없이 빌드·실행된다.
enum Telemetry {
    /// Sentry 대시보드에서 발급받은 DSN.
    static let dsn = "https://23a80b1f3f74958d1288984466abfef0@o4511726173159424.ingest.us.sentry.io/4511726200291333"

    static func start() {
        #if canImport(Sentry)
        guard !dsn.isEmpty, dsn != "YOUR_SENTRY_DSN_HERE" else { return }
        SentrySDK.start { options in
            options.dsn = dsn
            // 설치 초기에는 로그를 남겨 연동을 확인하기 좋다. 안정화되면 false로.
            options.debug = true
            // 사용자 IP 등 기본 개인정보 포함 (Sentry 권장 설정).
            options.sendDefaultPii = true
            // 성능 트레이싱 표본 비율 (0.0~1.0).
            options.tracesSampleRate = 0.2
            #if DEBUG
            options.environment = "development"
            #else
            options.environment = "production"
            #endif
        }
        #endif
    }
}
