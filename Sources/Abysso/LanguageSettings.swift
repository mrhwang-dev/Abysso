import SwiftUI

/// 앱 표시 언어 관리 — 환경설정의 언어 선택에 사용.
/// 선택 시 macOS 표준 `AppleLanguages` 값을 앱 도메인에 기록하며, 다시 시작하면 적용된다.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system = ""
    case ko
    case en
    case ja
    case zhHant = "zh-Hant"
    case de
    case es
    case fr

    var id: String { rawValue }

    /// 선택 메뉴에 표시할 이름 (각 언어명은 해당 언어로 그대로 표기)
    var displayName: String {
        switch self {
        case .system: return NSLocalizedString("시스템 기본", comment: "system default language")
        case .ko: return "한국어"
        case .en: return "English"
        case .ja: return "日本語"
        case .zhHant: return "繁體中文"
        case .de: return "Deutsch"
        case .es: return "Español"
        case .fr: return "Français"
        }
    }

    /// 현재 선택된 언어 (앱이 기록한 우선 언어 기준)
    static var current: AppLanguage {
        guard let code = UserDefaults.standard.string(forKey: prefKey) else { return .system }
        return AppLanguage(rawValue: code) ?? .system
    }

    private static let prefKey = "app.preferredLanguage"

    /// 언어를 적용한다 (AppleLanguages 기록). 실제 반영은 앱 재시작 후.
    func apply() {
        let defaults = UserDefaults.standard
        switch self {
        case .system:
            defaults.removeObject(forKey: Self.prefKey)
            defaults.removeObject(forKey: "AppleLanguages")
        default:
            defaults.set(rawValue, forKey: Self.prefKey)
            defaults.set([rawValue], forKey: "AppleLanguages")
        }
    }

    /// 언어 변경을 즉시 반영하기 위해 앱을 재시작한다.
    static func relaunch() {
        let path = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        // 현재 인스턴스가 종료된 뒤 새 인스턴스를 실행
        task.arguments = ["-c", "sleep 0.4; open \"\(path)\""]
        try? task.run()
        NSApp.terminate(nil)
    }
}
