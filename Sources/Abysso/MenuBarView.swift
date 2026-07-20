import SwiftUI

/// 메뉴 막대 팝오버 — 시스템 현황 압축판 + 퀵 액션
struct MenuBarView: View {
    @StateObject private var monitor = SystemMonitor()
    @ObservedObject private var ramMonitor = RamMonitor.shared
    @State private var purging = false
    @State private var emptying = false
    @State private var message: String?

    var body: some View {
        VStack(spacing: 14) {
            // 헤더
            HStack {
                Label {
                    Text("Abysso")
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

            // RAM 경고 알림 UI
            if let alert = ramMonitor.activeAlert {
                VStack(alignment: .leading, spacing: 8) {
                    Label("메모리 경고", systemImage: "exclamationmark.triangle.fill")
                        .font(.headline)
                        .foregroundStyle(Theme.orange)
                    
                    // 인터폴레이션 키는 다국어 번역이 불가능해 미리 현지화된 문자열을 사용
                    Text(verbatim: RamMonitor.alertTitle(alert) + "\n" + RamMonitor.hogDescription(alert))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        ramMonitor.resolveAlert(forceQuit: true)
                        withAnimation { message = NSLocalizedString("메모리 확보 명령을 실행했습니다", comment: "") }
                        clearLater()
                    } label: {
                        Label("즉시 메모리 확보 및 종료", systemImage: "bolt.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.orange)
                    .controlSize(.small)
                    .featureLocked()
                }
                .padding(12)
                .background(Theme.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.orange.opacity(0.3)))
            }

            // 실시간 CPU / RAM (2초 주기 갱신 — 바 차트 + 텍스트)
            VStack(spacing: 10) {
                statBar(
                    icon: "cpu", label: "CPU",
                    value: monitor.snapshot.cpuUsage,
                    trailing: "\(Int(monitor.snapshot.cpuUsage * 100))%"
                )
                statBar(
                    icon: "memorychip", label: "메모리",
                    value: monitor.snapshot.memFraction,
                    trailing: "\(Format.bytes(Int64(monitor.snapshot.memUsed))) / \(Format.bytes(Int64(monitor.snapshot.memTotal)))"
                )
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
                    // 비어 있으면 "0 KB" 대신 상태를 말로 보여준다
                    Text(monitor.snapshot.trashSize > 0
                         ? Format.bytes(monitor.snapshot.trashSize)
                         : NSLocalizedString("비어 있음", comment: ""))
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
                        Label("즉시 메모리 확보", systemImage: "memorychip")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.teal)
                .disabled(purging)
                .featureLocked()

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
                .featureLocked()
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

    private func statBar(icon: String, label: LocalizedStringKey, value: Double, trailing: String) -> some View {
        VStack(spacing: 4) {
            HStack {
                Label(label, systemImage: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(verbatim: trailing)
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
            }
            SmoothBar(value: value)
        }
    }

    private func rate(_ v: Double) -> String {
        // 언어 설정과 무관하게 B/s·KB/s·MB/s 표준 표기로 출력 (NaN/무한대도 안전)
        Format.speed(v)
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
                    message = String(format: NSLocalizedString("%@ 확보됨", comment: ""), Format.bytes(Int64(before - after)))
                } else {
                    message = ok ? NSLocalizedString("메모리 정리 완료", comment: "") : NSLocalizedString("취소되었거나 실패했습니다", comment: "")
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
                message = ok ? String(format: NSLocalizedString("휴지통 비움 — %@ 확보", comment: ""), Format.bytes(size)) : NSLocalizedString("휴지통 비우기 실패", comment: "")
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
