import SwiftUI

/// 메뉴 막대 팝오버 — 시스템 현황 압축판 + 퀵 액션
struct MenuBarView: View {
    @StateObject private var monitor = SystemMonitor()
    @State private var purging = false
    @State private var emptying = false
    @State private var message: String?

    var body: some View {
        VStack(spacing: 14) {
            // 헤더
            HStack {
                Label {
                    Text("MacCleaner")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                } icon: {
                    Image(systemName: "sparkles")
                        .foregroundStyle(Theme.accentGradient)
                }
                Spacer()
                Button {
                    openMainApp()
                } label: {
                    Label("메인 앱", systemImage: "macwindow")
                        .font(.caption)
                }
                .buttonStyle(.link)
            }

            // 미니 게이지 3종
            HStack(spacing: 14) {
                miniGauge(monitor.snapshot.cpuUsage, "CPU")
                miniGauge(monitor.snapshot.memFraction, "메모리")
                miniGauge(monitor.snapshot.diskFraction, "디스크")
            }

            // 디스크 여유 + 네트워크
            VStack(spacing: 6) {
                HStack {
                    Label("디스크 여유", systemImage: "internaldrive")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(Format.bytes(monitor.snapshot.diskFree))
                        .fontWeight(.semibold)
                        .monospacedDigit()
                }
                HStack {
                    Label("네트워크", systemImage: "network")
                        .foregroundStyle(.secondary)
                    Spacer()
                    HStack(spacing: 8) {
                        Label(rate(monitor.snapshot.netDownPerSec), systemImage: "arrow.down")
                            .foregroundStyle(Theme.teal)
                        Label(rate(monitor.snapshot.netUpPerSec), systemImage: "arrow.up")
                            .foregroundStyle(Theme.orange)
                    }
                    .monospacedDigit()
                }
                HStack {
                    Label("휴지통", systemImage: "trash")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(Format.bytes(monitor.snapshot.trashSize))
                        .fontWeight(.semibold)
                        .monospacedDigit()
                }
            }
            .font(.system(size: 12))
            .padding(12)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 10))

            Divider().opacity(0.4)

            // 퀵 액션
            HStack(spacing: 10) {
                Button {
                    purgeMemory()
                } label: {
                    if purging {
                        ProgressView().controlSize(.small).frame(maxWidth: .infinity)
                    } else {
                        Label("메모리 정리", systemImage: "memorychip")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.teal)
                .disabled(purging)

                Button {
                    emptyTrash()
                } label: {
                    if emptying {
                        ProgressView().controlSize(.small).frame(maxWidth: .infinity)
                    } else {
                        Label("휴지통 비우기", systemImage: "trash.slash")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.orange)
                .disabled(emptying || monitor.snapshot.trashSize == 0)
            }
            .controlSize(.small)

            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(Theme.green)
                    .transition(.opacity)
            }
        }
        .padding(16)
        .frame(width: 320)
        .background(Theme.bgTop)
        .preferredColorScheme(.dark)
        .onAppear { monitor.start() }
        .onDisappear { monitor.stop() }
    }

    private func miniGauge(_ value: Double, _ label: String) -> some View {
        RingGauge(value: value, label: label, size: 68, lineWidth: 7)
            .frame(maxWidth: .infinity)
    }

    private func rate(_ v: Double) -> String {
        Format.bytes(Int64(max(0, v))) + "/s"
    }

    private func openMainApp() {
        // 실행 중인 앱에 reopen 이벤트를 보내 SwiftUI가 메인 창을 다시 만들게 함
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: .init())
        NSApp.activate(ignoringOtherApps: true)
    }

    private func purgeMemory() {
        purging = true
        Task {
            let before = SystemProbe.usedMemory()
            let ok = await SystemActions.purgeMemory()
            let after = SystemProbe.usedMemory()
            withAnimation {
                purging = false
                if ok, before > after {
                    message = "\(Format.bytes(Int64(before - after))) 확보됨"
                } else {
                    message = ok ? "메모리 정리 완료" : "취소되었거나 실패했습니다"
                }
            }
            clearLater()
        }
    }

    private func emptyTrash() {
        emptying = true
        Task {
            let size = monitor.snapshot.trashSize
            let ok = await SystemActions.emptyTrash()
            withAnimation {
                emptying = false
                message = ok ? "휴지통 비움 — \(Format.bytes(size)) 확보" : "휴지통 비우기 실패"
            }
            clearLater()
        }
    }

    private func clearLater() {
        Task {
            try? await Task.sleep(for: .seconds(4))
            withAnimation { message = nil }
        }
    }
}
