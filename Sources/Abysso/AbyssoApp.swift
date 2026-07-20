import SwiftUI

@main
struct AbyssoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                // 가장 넓은 공간을 요구하는 '앱 제거' 탭(HSplitView: 목록+상세)이
                // 사이드바를 밀어내 Overlay 모드로 붕괴되지 않도록 창 최소 너비를 1050으로 강제.
                // 이 이하로는 macOS 창 시스템 레벨에서 아예 줄어들지 않는다.
                .frame(minWidth: 1050, idealWidth: 1240, minHeight: 650, idealHeight: 820)
        }
        .windowResizability(.contentSize)
        .commands {
            // 앱 메뉴(About Abysso 바로 뒤)에 네이티브 '업데이트 확인…' 항목 추가.
            // 환경설정 항목은 SwiftUI Settings 씬이 자동으로 하나 추가하므로 중복 정의하지 않는다.
            CommandGroup(after: .appInfo) {
                CheckForUpdatesButton()
            }

            // 앱 기능과 무관한 기본 템플릿 메뉴 제거.
            // 편집(Edit) 메뉴는 라이선스 키·버그 제보 입력란의 복사/붙여넣기(Cmd+C/V)에
            // 필요하므로 남겨 둔다 — 지우면 텍스트 입력 단축키가 전부 끊긴다.
            CommandGroup(replacing: .newItem) {}          // 파일 > 새로운 윈도우 (닫기는 시스템이 유지)
            CommandGroup(replacing: .textFormatting) {}   // 포맷 메뉴 (폰트/정렬)
            CommandGroup(replacing: .toolbar) {}          // 보기 > 도구 막대 항목
            CommandGroup(replacing: .help) {}             // 도움말 (별도 문서 없음)
        }

        Settings {
            SettingsView()
        }
    }
}

// MARK: - 앱 델리게이트: 메뉴 막대 어시스턴트 + 백그라운드 상주

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 가장 먼저 오류 수집 초기화 (이후 발생하는 크래시를 포착하도록)
        Telemetry.start()

        // 자동 업데이터 구동 (SPUStandardUpdaterController 생성)
        _ = AppUpdater.shared

        // 라이선스/체험판 관리자 구동 (최초 실행 시 체험 시작일 기록)
        _ = LicenseManager.shared

        // 백그라운드 램 모니터 구동
        RamMonitor.shared.start()

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        // 앱 기능과 무관한 템플릿 메뉴(파일·포맷·보기·도움말)를 메뉴 막대에서 제거.
        // 시스템이 뒤늦게 항목(피드백 보내기 등)을 주입해 메뉴가 되살아날 수 있으므로
        // 창이 활성화될 때마다 약간의 시차를 두고 두 번씩 다시 정리한다.
        // 메뉴 막대 어시스턴트(상태 아이템) 설정과는 무관하므로 항상 실행한다 —
        // 어시스턴트를 꺼도 상단 메뉴 정리와 Cmd+W 복원은 그대로 적용돼야 한다.
        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main
        ) { _ in
            for delay in [0.5, 2.0] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { AppDelegate.pruneTemplateMenus() }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { AppDelegate.pruneTemplateMenus() }

        // 환경설정에서 메뉴 막대를 끈 경우 상태 아이템을 만들지 않음
        let menuBarEnabled = UserDefaults.standard.object(forKey: "menuBarEnabled") as? Bool ?? true
        guard menuBarEnabled else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            let image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "Abysso")
            image?.isTemplate = true  // 메뉴 막대 다크/라이트 자동 대응
            button.image = image
            button.action = #selector(togglePopover(_:))
            button.target = self
        }
        statusItem = item

        popover.contentViewController = NSHostingController(rootView: MenuBarView())
        popover.behavior = .transient  // 바깥 클릭 시 자동 닫힘
        popover.animates = true
    }

    /// 앱에서 쓰지 않는 기본 템플릿 메뉴의 (언어별) 제목 — 편집·윈도우는 남긴다.
    /// 편집은 텍스트 입력 단축키(Cmd+C/V)에, 윈도우는 창 전환·Cmd+W에 필요하다.
    private static let removableMenuTitles: Set<String> = [
        "파일", "File", "ファイル", "檔案",
        "포맷", "Format", "フォーマット", "格式",
        "보기", "View", "表示", "顯示方式",
        "도움말", "Help", "ヘルプ", "輔助說明",
    ]

    /// 템플릿 메뉴를 제목 기준으로 제거하고, 파일 메뉴와 함께 사라진
    /// Cmd+W(닫기)는 윈도우 메뉴 맨 위에 복원한다.
    private static func pruneTemplateMenus() {
        guard let menu = NSApp.mainMenu else { return }
        for item in menu.items.reversed() where removableMenuTitles.contains(item.title) {
            menu.removeItem(item)
        }

        // Cmd+W 확보: 어느 메뉴에도 ⌘W 항목이 없으면 윈도우 메뉴 맨 위에 '닫기' 추가
        let hasCloseShortcut = menu.items.contains { top in
            top.submenu?.items.contains {
                $0.keyEquivalent == "w" && $0.keyEquivalentModifierMask == [.command]
            } ?? false
        }
        if !hasCloseShortcut, let windowsMenu = NSApp.windowsMenu {
            let close = NSMenuItem(
                title: NSLocalizedString("닫기", comment: ""),
                action: #selector(NSWindow.performClose(_:)),
                keyEquivalent: "w"
            )
            windowsMenu.insertItem(close, at: 0)
        }
    }

    /// 마지막 창을 닫아도 종료하지 않고 메뉴 막대에 상주
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    func showPopover() {
        guard let button = statusItem?.button else { return }
        if !popover.isShown {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
