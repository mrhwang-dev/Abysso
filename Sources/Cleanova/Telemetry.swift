import Foundation
#if canImport(Sentry)
import Sentry
#endif

/// 원격 오류/크래시 수집 (Sentry). 패키지가 없으면(canImport 실패) 전부 no-op이 되어
/// 앱은 문제없이 빌드·실행된다.
enum Telemetry {
    /// 실제 배포 전 Sentry 대시보드에서 발급받은 DSN으로 교체하세요.
    static let dsn = "YOUR_SENTRY_DSN_HERE"

    static func start() {
        #if canImport(Sentry)
        // 플레이스홀더 DSN이면 초기화를 건너뛴다 (개발 중 불필요한 전송 방지).
        guard dsn != "YOUR_SENTRY_DSN_HERE", !dsn.isEmpty else { return }
        SentrySDK.start { options in
            options.dsn = dsn
            options.debug = false
            // 성능 트레이싱 표본 비율 (0.0~1.0). 필요 시 조정.
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
