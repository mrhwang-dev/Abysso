import SwiftUI

// MARK: - 라이선스 / 체험판 상태

/// 앱의 수익화 상태. 정식 결제 SDK(Paddle) 연동 전까지 앱 내부에서 체험 기간을 추적한다.
enum LicenseStatus: Equatable {
    case trial(daysLeft: Int)  // 무료 체험 중
    case activated             // 라이선스 인증 완료
    case expired               // 체험 만료 — 핵심 기능 잠금
}

/// 체험판 기간 추적 + 라이선스 인증(현재는 Mock) 전역 관리자.
///
/// - 최초 실행 시 시작일을 기록하고 7일 무료 체험을 제공한다.
/// - 시작일/인증 여부는 UserDefaults에 저장한다. (정식 버전에서는 Keychain + 서버 검증으로 대체 예정)
/// - `isLocked`가 true면 각 탭의 핵심 실행 버튼을 `.featureLocked()`로 잠근다.
@MainActor
final class LicenseManager: ObservableObject {
    static let shared = LicenseManager()

    // ⚑ 한시적 전면 무료 배포 스위치.
    //   true  → 라이선스/체험 상태와 무관하게 모든 핵심 기능 잠금 해제 (Free Beta).
    //   false → 아래 체험판/라이선스 잠금 로직이 정상 동작 (유료화 전환 시 이 값만 false로).
    // 기존 잠금 로직은 그대로 보존하고 이 플래그로만 제어한다.
    static let isFreeRelease = true

    // 체험 기간 (일)
    static let trialDays = 7
    // TODO: 정식 Paddle SDK 연동 시 교체 — 실제 결제/구매 페이지 URL로 변경할 것 (현재는 플레이스홀더 더미 URL)
    static let purchaseURL = URL(string: "https://abysso.app/purchase")!

    private let defaults = UserDefaults.standard
    private enum Key {
        static let trialStart = "license.trialStartDate"
        static let activated = "license.activated"
        static let licenseKey = "license.key"
        static let email = "license.email"
    }

    @Published private(set) var status: LicenseStatus = .trial(daysLeft: trialDays)
    /// 만료 상태에서 잠긴 버튼을 눌렀을 때 띄우는 안내 모달 트리거
    @Published var showLockPrompt = false
    /// 인증된 사용자 이메일 (활성화 상태에서 표시용)
    @Published private(set) var activatedEmail: String?

    private init() {
        // 최초 실행: 체험 시작일 기록
        if defaults.object(forKey: Key.trialStart) == nil {
            defaults.set(Date(), forKey: Key.trialStart)
        }
        activatedEmail = defaults.string(forKey: Key.email)
        refresh()
    }

    // MARK: 파생 상태

    private var trialStartDate: Date {
        defaults.object(forKey: Key.trialStart) as? Date ?? Date()
    }

    private var isActivated: Bool { defaults.bool(forKey: Key.activated) }

    /// 남은 체험 일수 (0 이하이면 만료)
    var daysLeft: Int {
        let elapsed = Calendar.current.dateComponents(
            [.day], from: Calendar.current.startOfDay(for: trialStartDate),
            to: Calendar.current.startOfDay(for: Date())
        ).day ?? 0
        return max(0, Self.trialDays - elapsed)
    }

    /// 핵심 기능 잠금 여부
    var isLocked: Bool {
        // 무료 배포 기간에는 절대 잠기지 않는다 (유료화 시 isFreeRelease=false로 원복).
        if Self.isFreeRelease { return false }
        if case .expired = status { return true }
        return false
    }

    /// UserDefaults 값을 읽어 현재 상태를 재평가한다.
    func refresh() {
        if isActivated {
            status = .activated
        } else if daysLeft > 0 {
            status = .trial(daysLeft: daysLeft)
        } else {
            status = .expired
        }
    }

    // MARK: 활성화 (Mock)

    // TODO: 정식 Paddle SDK 연동 시 교체 —
    // 아래 activate(email:key:)의 로컬 포맷 검증(더미 라이선스 키 로직)을 Paddle의
    // 라이선스 검증 API 호출 + 서버 응답 기반 인증으로 대체하고, 인증 상태는 UserDefaults 대신
    // Keychain에 저장할 것. 현재는 SDK 미연동 상태의 플레이스홀더 구현이다.

    /// 라이선스 활성화. 정식 SDK 연동 전까지는 포맷만 검증한다:
    /// 이메일 형식 + 하이픈/공백을 제외한 32자리 영숫자 키.
    /// - Returns: 활성화 성공 여부
    @discardableResult
    func activate(email: String, key: String) -> Bool {
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedKey = Self.normalizeKey(key)
        guard Self.isValidEmail(cleanEmail), Self.isValidKey(normalizedKey) else {
            return false
        }
        defaults.set(true, forKey: Key.activated)
        defaults.set(normalizedKey, forKey: Key.licenseKey)
        defaults.set(cleanEmail, forKey: Key.email)
        activatedEmail = cleanEmail
        refresh()
        return true
    }

    /// 하이픈·공백 제거 후 대문자화
    static func normalizeKey(_ key: String) -> String {
        key.uppercased().filter { $0.isLetter || $0.isNumber }
    }

    /// 32자리 영숫자
    static func isValidKey(_ normalizedKey: String) -> Bool {
        normalizedKey.count == 32 && normalizedKey.allSatisfy { $0.isLetter || $0.isNumber }
    }

    static func isValidEmail(_ email: String) -> Bool {
        guard let at = email.firstIndex(of: "@"), at != email.startIndex else { return false }
        let domain = email[email.index(after: at)...]
        return domain.contains(".") && !domain.hasSuffix(".") && domain.count >= 3
    }

    // MARK: 잠금 안내 / 구매

    func presentLockPrompt() { showLockPrompt = true }

    func openPurchasePage() { NSWorkspace.shared.open(Self.purchaseURL) }

    /// 사이드바 푸터/설정 헤더용 버전 라벨. 상태에 따라 유연하게 변경되며 지역화된다.
    /// 예) "v0.0.1 (체험판)" / "v0.0.1 (정품 인증됨)" — en/ja에서는 각 언어로 표시.
    var versionLabel: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.1"
        let format: String
        if Self.isFreeRelease {
            format = NSLocalizedString("version.freeBeta", comment: "free beta version label")
        } else if case .activated = status {
            format = NSLocalizedString("version.activated", comment: "activated version label")
        } else {
            format = NSLocalizedString("version.trial", comment: "trial version label")
        }
        return String(format: format, version)
    }
}

// MARK: - 기능 잠금 모디파이어

/// 체험 만료(expired) 시 대상 버튼을 시각적으로 비활성화하고, 클릭을 가로채
/// 라이선스 안내 모달을 띄운다. 각 탭의 핵심 실행 버튼에 `.featureLocked()`로 적용한다.
private struct FeatureLockModifier: ViewModifier {
    @ObservedObject private var license = LicenseManager.shared

    func body(content: Content) -> some View {
        content
            .opacity(license.isLocked ? 0.4 : 1)
            // 실제 버튼의 클릭을 차단 (비활성 표현). 오버레이는 이 스코프 밖이라 여전히 클릭 가능.
            .allowsHitTesting(!license.isLocked)
            .overlay {
                if license.isLocked {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { license.presentLockPrompt() }
                        .help("체험판이 만료되었습니다 — 라이선스를 활성화하세요")
                }
            }
    }
}

extension View {
    /// 체험 만료 시 이 뷰(주로 핵심 실행 버튼)를 잠근다.
    func featureLocked() -> some View { modifier(FeatureLockModifier()) }
}
