import SwiftUI

@main
struct MacCleanerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 820, minHeight: 560)
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("환경설정…") {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
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
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        // 환경설정에서 메뉴 막대를 끈 경우 상태 아이템을 만들지 않음
        let menuBarEnabled = UserDefaults.standard.object(forKey: "menuBarEnabled") as? Bool ?? true
        guard menuBarEnabled else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            let image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "MacCleaner")
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
}
