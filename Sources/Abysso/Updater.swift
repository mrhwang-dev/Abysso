import SwiftUI
#if canImport(Sparkle)
import Sparkle
#endif

/// 자동 업데이트(Sparkle) 래퍼. 패키지가 없으면(canImport 실패) no-op으로 컴파일된다.
/// 실제 업데이트가 동작하려면:
///   1) Info.plist의 SUFeedURL을 실제 appcast.xml 주소로 교체
///   2) Sparkle의 generate_keys 툴로 EdDSA 키쌍 생성 후 SUPublicEDKey를 Info.plist에 추가
///      (개인키로 배포물에 서명 → sign_update 툴)
@MainActor
final class AppUpdater: ObservableObject {
    static let shared = AppUpdater()

    /// 메뉴/버튼 활성화 여부 (업데이트 확인이 가능한 상태인지)
    @Published var canCheckForUpdates = false

    #if canImport(Sparkle)
    private let controller: SPUStandardUpdaterController

    private init() {
        // startingUpdater: true → 앱 시작과 함께 업데이터 구동
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .assign(to: &$canCheckForUpdates)
    }

    /// "자동으로 업데이트 확인" 설정 (Sparkle 내부 UserDefaults에 저장됨)
    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    /// 사용자가 직접 업데이트 확인 (진행 UI는 Sparkle이 표시)
    func checkForUpdates() {
        controller.updater.checkForUpdates()
    }
    #else
    private init() {}
    var automaticallyChecksForUpdates: Bool {
        get { false }
        set { _ = newValue }
    }
    func checkForUpdates() {}
    #endif
}

// MARK: - 메뉴/설정에서 재사용하는 "업데이트 확인" 버튼

struct CheckForUpdatesButton: View {
    @ObservedObject private var updater = AppUpdater.shared
    var title: LocalizedStringKey = "업데이트 확인…"

    var body: some View {
        Button(title) {
            updater.checkForUpdates()
        }
        .disabled(!updater.canCheckForUpdates)
    }
}
