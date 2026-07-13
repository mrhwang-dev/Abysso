import SwiftUI

struct DashboardView: View {
    @Binding var selection: SidebarItem?
    @StateObject private var monitor = SystemMonitor()
    @Environment(\.scenePhase) private var scenePhase
    @State private var purging = false
    @State private var emptyingTrash = false
    @State private var actionMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                headerSection
                if let msg = actionMessage {
                    Label(msg, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Theme.green)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                gaugeRow
                infoRow
            }
            .padding(24)
        }
        .background(Theme.background)
        // 화면에 보이고(onAppear) 앱이 활성(.active)일 때만 폴링.
        // 탭 전환·창 최소화·다른 앱으로 전환 시 즉시 타이머 정지 → 백그라운드 CPU 0%.
        .onAppear { if scenePhase == .active { monitor.start() } }
        .onDisappear { monitor.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { monitor.start() } else { monitor.stop() }
        }
    }

    // MARK: 헤더 — 실제 기기 정보

    private var headerSection: some View {
        HStack(spacing: 16) {
            Image(systemName: "macbook")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Theme.accentGradient)
            VStack(alignment: .leading, spacing: 3) {
                Text(monitor.machine.hostName.isEmpty ? "이 Mac" : monitor.machine.hostName)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Text("\(monitor.machine.osName) \(monitor.machine.osVersion)  ·  \(monitor.machine.chip)  ·  \(monitor.machine.modelID)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            thermalBadge
        }
        .card(padding: 20)
    }

    private var thermalBadge: some View {
        let (label, color): (String, Color) = {
            switch monitor.snapshot.thermalState {
            case .nominal: return ("발열 정상", Theme.green)
            case .fair: return ("발열 보통", Theme.yellow)
            case .serious: return ("발열 높음", Theme.orange)
            case .critical: return ("발열 심각", Theme.red)
            @unknown default: return ("알 수 없음", .gray)
            }
        }()
        return Label(label, systemImage: "thermometer.medium")
            .font(.callout.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(color.opacity(0.12), in: Capsule())
    }

    // MARK: 게이지 카드 (디스크 / 메모리 / CPU)

    private var gaugeRow: some View {
        HStack(spacing: 16) {
            // 디스크
            VStack(spacing: 12) {
                RingGauge(value: monitor.snapshot.diskFraction, label: "디스크")
                VStack(spacing: 2) {
                    Text("\(Format.bytes(monitor.snapshot.diskFree)) 남음")
                        .font(.callout.weight(.medium))
                    Text("전체 \(Format.bytes(monitor.snapshot.diskTotal))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Button {
                    selection = .cache
                } label: {
                    Label("스캔 시작", systemImage: "sparkle.magnifyingglass")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.blue)
                Button {
                    selection = .largeFiles
                } label: {
                    Label("대용량 파일 찾기", systemImage: "doc.zipper")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .card()

            // 메모리
            VStack(spacing: 12) {
                RingGauge(value: monitor.snapshot.memFraction, label: "메모리")
                VStack(spacing: 2) {
                    Text("\(Format.bytes(Int64(monitor.snapshot.memUsed))) 사용 중")
                        .font(.callout.weight(.medium))
                    Text("전체 \(Format.bytes(Int64(monitor.snapshot.memTotal)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
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
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .card()

            // CPU
            VStack(spacing: 12) {
                RingGauge(value: monitor.snapshot.cpuUsage, label: "CPU")
                VStack(spacing: 2) {
                    Text("실시간 사용률")
                        .font(.callout.weight(.medium))
                    Text(monitor.machine.chip.isEmpty ? "—" : monitor.machine.chip)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Button {
                    openActivityMonitor()
                } label: {
                    Label("활성 상태 보기", systemImage: "chart.xyaxis.line")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .help("점유율 높은 앱을 활성 상태 보기에서 확인합니다")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .card()
        }
    }

    private func openActivityMonitor() {
        let url = URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }

    // MARK: 정보 카드 (휴지통 / 배터리 / 네트워크)

    private var infoRow: some View {
        HStack(spacing: 16) {
            // 휴지통
            VStack(alignment: .leading, spacing: 10) {
                Label("휴지통", systemImage: "trash")
                    .font(.headline)
                    .foregroundStyle(Theme.orange)
                Text(Format.bytes(monitor.snapshot.trashSize))
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Spacer(minLength: 4)
                Button {
                    emptyTrash()
                } label: {
                    if emptyingTrash {
                        ProgressView().controlSize(.small).frame(maxWidth: .infinity)
                    } else {
                        Label("휴지통 비우기", systemImage: "trash.slash")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.orange)
                .disabled(emptyingTrash || monitor.snapshot.trashSize == 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .card()

            // 배터리 (노트북) / 디스크 I/O (데스크탑)
            if let pct = monitor.snapshot.batteryPercent {
                VStack(alignment: .leading, spacing: 10) {
                    Label("배터리", systemImage: monitor.snapshot.batteryCharging
                          ? "battery.100.bolt" : "battery.75")
                        .font(.headline)
                        .foregroundStyle(Theme.green)
                    Text("\(pct)%")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    SmoothBar(value: Double(pct) / 100,
                              color: monitor.snapshot.batteryCharging ? Theme.green : nil)
                    Text(monitor.snapshot.batteryCharging ? "충전 중" : "배터리 사용 중")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .card()
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Label("디스크 I/O", systemImage: "internaldrive")
                        .font(.headline)
                        .foregroundStyle(Theme.green)
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 2) {
                            Label(speed(monitor.snapshot.diskReadPerSec), systemImage: "arrow.up.doc")
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundStyle(Theme.green)
                            Text("읽기").font(.caption).foregroundStyle(.secondary)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Label(speed(monitor.snapshot.diskWritePerSec), systemImage: "arrow.down.doc")
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundStyle(Theme.yellow)
                            Text("쓰기").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Text("실시간 (2초 간격)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .card()
            }

            // 네트워크
            VStack(alignment: .leading, spacing: 10) {
                Label("네트워크", systemImage: "network")
                    .font(.headline)
                    .foregroundStyle(Theme.purple)
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Label(speed(monitor.snapshot.netDownPerSec), systemImage: "arrow.down")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.teal)
                        Text("다운로드").font(.caption).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Label(speed(monitor.snapshot.netUpPerSec), systemImage: "arrow.up")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.orange)
                        Text("업로드").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text("실시간 (2초 간격)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .card()
        }
    }

    // MARK: 동작

    private func purgeMemory() {
        purging = true
        Task {
            let before = SystemProbe.usedMemory()
            let ok = await SystemActions.purgeMemory()
            let after = SystemProbe.usedMemory()
            withAnimation {
                purging = false
                if ok {
                    let freed = before > after ? Int64(before - after) : 0
                    actionMessage = freed > 0
                        ? "메모리 정리 완료 — \(Format.bytes(freed)) 확보"
                        : "메모리 정리 완료"
                } else {
                    actionMessage = "메모리 정리가 취소되었거나 실패했습니다 (관리자 권한 필요)"
                }
            }
            clearMessageLater()
        }
    }

    private func emptyTrash() {
        emptyingTrash = true
        Task {
            let size = monitor.snapshot.trashSize
            let ok = await SystemActions.emptyTrash()
            withAnimation {
                emptyingTrash = false
                actionMessage = ok
                    ? "휴지통을 비웠습니다 — \(Format.bytes(size)) 확보"
                    : "휴지통 비우기에 실패했습니다"
            }
            clearMessageLater()
        }
    }

    private func clearMessageLater() {
        Task {
            try? await Task.sleep(for: .seconds(5))
            withAnimation { actionMessage = nil }
        }
    }

    private func speed(_ bytesPerSec: Double) -> String {
        Format.bytes(Int64(max(0, bytesPerSec))) + "/s"
    }
}
