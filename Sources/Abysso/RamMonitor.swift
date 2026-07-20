import Foundation
import SwiftUI
import AppKit
import UserNotifications

// 알림 카테고리/액션 식별자 (파일 스코프 — 델리게이트와 공유)
private let ramAlertCategoryID = "app.abysso.ramAlert"
private let ramAlertReclaimActionID = "app.abysso.ramAlert.reclaim"

@MainActor
final class RamMonitor: ObservableObject {
    static let shared = RamMonitor()

    @AppStorage("ramAlertThreshold") var threshold: Double = 85.0
    @AppStorage("lastRamAlertTime") private var lastAlertTime: Double = 0

    @Published var activeAlert: RamAlert?

    struct RamAlert: Equatable {
        let percentage: Int
        let hogName: String
        let hogPids: [Int32]
        let otherCount: Int
    }

    private var timer: Timer?
    private let notificationDelegate = RamAlertNotificationDelegate()

    private init() {}

    func start() {
        guard timer == nil else { return }
        setupNotifications()
        checkMemory() // Check immediately
        let t = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkMemory()
            }
        }
        t.tolerance = 5
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: 표시 문자열 (팝오버·알림 공용, 현지화 완료 상태로 반환)

    static func alertTitle(_ alert: RamAlert) -> String {
        String(format: NSLocalizedString("RAM 사용량이 %lld%%를 초과했습니다", comment: ""), alert.percentage)
    }

    static func hogDescription(_ alert: RamAlert) -> String {
        alert.otherCount > 0
            ? String(format: NSLocalizedString("'%@' 외 %lld개가 메모리를 과다 점유 중입니다", comment: ""), alert.hogName, alert.otherCount)
            : String(format: NSLocalizedString("'%@' 이(가) 메모리를 과다 점유 중입니다", comment: ""), alert.hogName)
    }

    // MARK: 모니터링

    private func checkMemory() {
        let memUsed = SystemProbe.usedMemory()
        let memTotal = ProcessInfo.processInfo.physicalMemory
        guard memTotal > 0 else { return }

        let percentage = (Double(memUsed) / Double(memTotal)) * 100.0

        if percentage >= threshold {
            triggerAlert(percentage: Int(percentage))
        } else {
            // Memory is healthy, dismiss any active alert
            activeAlert = nil
        }
    }

    private func triggerAlert(percentage: Int) {
        let now = Date().timeIntervalSince1970
        let cooldown: TimeInterval = 10 * 60 // 10 minutes

        // Only trigger if 10 mins have passed since the last alert
        guard now - lastAlertTime > cooldown else { return }

        // Find the top memory hog
        Task.detached(priority: .userInitiated) {
            let topMem = ProcessMonitor.topByMemory(limit: 5)

            await MainActor.run {
                guard let topHog = topMem.first else { return }

                let alert = RamAlert(
                    percentage: percentage,
                    hogName: topHog.name,
                    hogPids: topHog.pids,
                    otherCount: max(0, topMem.count - 1)
                )
                self.activeAlert = alert
                self.lastAlertTime = now

                // 팝오버 자동 오픈 + 네이티브 알림 (메뉴 막대를 꺼둔 경우에도 알림은 도달)
                if let delegate = NSApp.delegate as? AppDelegate {
                    delegate.showPopover()
                }
                self.postNotification(for: alert)
            }
        }
    }

    func resolveAlert(forceQuit: Bool = true) {
        guard let alert = activeAlert else { return }

        #if DEBUG
        if !DevMode.shouldRunCommand("RAM 자동 확보: \(alert.hogName) 외 \(alert.otherCount)개 종료") {
            self.activeAlert = nil
            return
        }
        #endif

        // Quit the hog processes
        for pid in alert.hogPids {
            ProcessMonitor.quit(pid: pid, force: forceQuit)
        }

        // Purge memory
        Task {
            _ = await SystemActions.purgeMemory()
        }

        activeAlert = nil
    }

    // MARK: 네이티브 알림 (UNUserNotificationCenter)

    /// .app 번들 밖(개발용 바이너리 직접 실행)에서는 UNUserNotificationCenter 접근이 크래시하므로 차단
    private var notificationsAvailable: Bool {
        Bundle.main.bundleIdentifier != nil
    }

    private func setupNotifications() {
        guard notificationsAvailable else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = notificationDelegate
        let reclaim = UNNotificationAction(
            identifier: ramAlertReclaimActionID,
            title: NSLocalizedString("즉시 메모리 확보 및 종료", comment: ""),
            options: []
        )
        let category = UNNotificationCategory(
            identifier: ramAlertCategoryID,
            actions: [reclaim],
            intentIdentifiers: []
        )
        center.setNotificationCategories([category])
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func postNotification(for alert: RamAlert) {
        guard notificationsAvailable else { return }
        let content = UNMutableNotificationContent()
        content.title = Self.alertTitle(alert)
        content.body = Self.hogDescription(alert)
        content.sound = .default
        content.categoryIdentifier = ramAlertCategoryID
        // 식별자를 고정해 같은 경고가 알림 센터에 쌓이지 않게 함
        let request = UNNotificationRequest(identifier: ramAlertCategoryID, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

// MARK: - 알림 델리게이트: 앱 실행 중에도 배너 표시 + '즉시 메모리 확보 및 종료' 액션 처리

private final class RamAlertNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let action = response.actionIdentifier
        await MainActor.run {
            if action == ramAlertReclaimActionID {
                // 안전 모드(DevMode.shouldRunCommand) 게이트는 resolveAlert 내부에서 적용됨
                RamMonitor.shared.resolveAlert(forceQuit: true)
            } else if action == UNNotificationDefaultActionIdentifier {
                // 알림 본문 클릭 → 메뉴 막대 팝오버 열기
                (NSApp.delegate as? AppDelegate)?.showPopover()
            }
        }
    }
}
