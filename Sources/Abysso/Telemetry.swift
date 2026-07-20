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
            // 프로덕션 배포 설정: SDK 내부 디버그 로그 비활성화.
            options.debug = false
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

    /// 인앱 피드백(버그 제보/기능 추가 요청)을 Sentry로 전송한다. 사용자가 적은 내용을
    /// 이벤트 메시지로, (선택) 이메일은 사용자 정보로 첨부해 대시보드에서 회신할 수 있게 한다.
    /// Sentry 패키지가 없으면 no-op이라 앱은 문제없이 빌드된다.
    static func reportBug(message: String, email: String, isFeatureRequest: Bool = false) {
        #if canImport(Sentry)
        let prefix = isFeatureRequest ? "💡 기능 추가 요청" : "🐞 사용자 버그 제보"
        SentrySDK.capture(message: "\(prefix)\n\n\(message)") { scope in
            scope.setLevel(.info)
            scope.setTag(value: isFeatureRequest ? "feature-request" : "user-report", key: "report.type")
            let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedEmail.isEmpty {
                let user = User()
                user.email = trimmedEmail
                scope.setUser(user)
            }
            scope.setExtra(value: message, key: "bug_description")
        }
        #endif
    }
}
