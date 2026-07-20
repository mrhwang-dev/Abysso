import SwiftUI

// MARK: - 메인 화면 (대시보드)
//
// 2026-07-19 전면 개편: 여백을 줄인 조밀한 카드 그리드 + 반투명(글래스) 재질.
// 구성 — ① 기기 정보 헤더 ② 집중 모드 바 ③ 게이지 3열(디스크·메모리·CPU, 링 게이지를
// 좌측에 두고 수치·버튼을 우측에 배치해 세로 공간 절약) ④ 정보 타일 3열(휴지통·전원/디스크 I/O·네트워크).

struct DashboardView: View {
    @Binding var selection: SidebarItem?
    @StateObject private var monitor = SystemMonitor()
    @ObservedObject private var focus = FocusMode.shared
    // 대시보드 버튼에서 탭 이동과 동시에 스캔을 바로 시작하기 위한 공유 모델
    @EnvironmentObject private var cacheModel: CacheModel
    @EnvironmentObject private var lensModel: LargeFilesModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var purging = false
    @State private var emptyingTrash = false
    @State private var actionMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                headerSection
                focusModeBar
                if let fmsg = focus.message {
                    Label(fmsg, systemImage: focus.active ? "bolt.fill" : "checkmark.circle.fill")
                        .foregroundStyle(focus.active ? Theme.teal : Theme.green)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                if let msg = actionMessage {
                    Label(LocalizedStringKey(msg), systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Theme.green)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                gaugeRow
                infoRow
            }
            .padding(20)
        }
        .background(Theme.heroBackground)
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
        HStack(spacing: 12) {
            Image(systemName: "macbook")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Theme.accentGradient)
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(monitor.machine.hostName.isEmpty ? "이 Mac" : monitor.machine.hostName))
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                Text("\(monitor.machine.osName) \(monitor.machine.osVersion)  ·  \(monitor.machine.chip)  ·  \(monitor.machine.modelID)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            thermalBadge
        }
        .glassCard(padding: 14)
    }

    private var thermalBadge: some View {
        let (label, color): (LocalizedStringKey, Color) = {
            switch monitor.snapshot.thermalState {
            case .nominal: return ("발열 정상", Theme.green)
            case .fair: return ("발열 보통", Theme.yellow)
            case .serious: return ("발열 높음", Theme.orange)
            case .critical: return ("발열 심각", Theme.red)
            @unknown default: return ("알 수 없음", .gray)
            }
        }()
        return Label(label, systemImage: "thermometer.medium")
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color.opacity(0.12), in: Capsule())
    }

    // MARK: 집중(부스트) 모드 바

    private var focusModeBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(focus.active ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Theme.yellow))
                .frame(width: 34, height: 34)
                .background((focus.active ? Theme.teal : Theme.yellow).opacity(0.14),
                            in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 1) {
                Text("집중 모드")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                Text("암호 입력 없이 비활성 메모리를 즉시 회수해 최대 성능을 확보합니다")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button {
                focus.toggle()
            } label: {
                HStack(spacing: 6) {
                    if focus.working {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: focus.active ? "checkmark.circle.fill" : "bolt.fill")
                    }
                    Text(focus.active ? "집중 모드 켜짐" : "집중 모드 시작")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(
                    focus.active ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Theme.cardHighlight),
                    in: Capsule()
                )
                .foregroundStyle(focus.active ? .white : .primary)
            }
            .buttonStyle(.plain)
            .disabled(focus.working)
            .help("집중 모드로 비활성 메모리를 즉시 회수합니다 — 암호 창이 뜨지 않습니다")
            .featureLocked()
        }
        .glassCard(padding: 12)
        // 활성화 순간 테마 강조색으로 잠시 빛나는 피드백
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Theme.accentGradient, lineWidth: 2)
                .opacity(focus.flash ? 1 : 0)
        )
        .shadow(color: Theme.teal.opacity(focus.flash ? 0.55 : 0), radius: focus.flash ? 18 : 0)
        .animation(.easeInOut(duration: 0.4), value: focus.flash)
    }

    // MARK: 게이지 카드 (디스크 / 메모리 / CPU)

    private var gaugeRow: some View {
        HStack(alignment: .top, spacing: 14) {
            // 디스크
            gaugeCard(
                value: monitor.snapshot.diskFraction, tint: Theme.blue,
                icon: "internaldrive.fill", category: "저장 공간",
                line1: Text("\(Format.bytes(monitor.snapshot.diskFree)) 남음"),
                line2: Text("전체 \(Format.bytes(monitor.snapshot.diskTotal))")
            ) {
                Button {
                    // 탭 이동과 동시에 스캔을 즉시 시작 (버튼 두 번 누를 필요 없음)
                    selection = .cache
                    if !cacheModel.scanning && !cacheModel.cleaning { cacheModel.scan() }
                } label: {
                    Label("스캔 시작", systemImage: "sparkle.magnifyingglass")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.blue)
                Button {
                    selection = .largeFiles
                    if !lensModel.scanning { lensModel.scan() }
                } label: {
                    Label("대용량 파일 찾기", systemImage: "doc.zipper")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            // 메모리
            gaugeCard(
                value: monitor.snapshot.memFraction, tint: Theme.teal,
                icon: "memorychip.fill", category: "메모리",
                line1: Text("\(Format.bytes(Int64(monitor.snapshot.memUsed))) 사용 중"),
                line2: Text("전체 \(Format.bytes(Int64(monitor.snapshot.memTotal)))")
            ) {
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
                .featureLocked()
                .animation(.easeInOut, value: purging)
            }

            // CPU
            gaugeCard(
                value: monitor.snapshot.cpuUsage, tint: Theme.orange,
                icon: "cpu.fill", category: "CPU",
                line1: Text("\(Int(monitor.snapshot.cpuUsage * 100))%"),
                line2: Text(monitor.machine.chip.isEmpty ? "실시간 사용률" : monitor.machine.chip)
            ) {
                Button {
                    selection = .optimization
                } label: {
                    Label("상세 보기", systemImage: "list.dash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.orange)
                Button {
                    openActivityMonitor()
                } label: {
                    Label("활성 상태 보기", systemImage: "chart.xyaxis.line")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .help("점유율 높은 앱을 활성 상태 보기에서 확인합니다")
            }
        }
    }

    /// 좌상단 라벨 · 큰 수치 · 사용량 바 · 우상단 광택 아이콘의 대형 히어로 카드.
    /// 하단에 작은 액션 버튼들을 세로로 쌓는다.
    private func gaugeCard(
        value: Double, tint: Color, icon: String, category: LocalizedStringKey,
        line1: Text, line2: Text,
        @ViewBuilder buttons: @escaping () -> some View
    ) -> some View {
        HeroCard(tint: tint, icon: icon) {
            VStack(alignment: .leading, spacing: 8) {
                // 텍스트 블록은 우상단 아이콘과 겹치지 않게 오른쪽 여백을 준다
                VStack(alignment: .leading, spacing: 3) {
                    Text(category)
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.7))
                    line1
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                    line2
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.trailing, 46)

                SmoothBar(value: value, color: tint, height: 6)

                Spacer(minLength: 8)
                VStack(spacing: 6) { buttons() }
                    .controlSize(.small)
            }
        }
    }

    private func openActivityMonitor() {
        let url = URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }

    // MARK: 정보 타일 (휴지통 / 배터리·디스크 I/O / 네트워크)

    private var infoRow: some View {
        HStack(alignment: .top, spacing: 12) {
            // 휴지통
            VStack(alignment: .leading, spacing: 8) {
                Label("휴지통", systemImage: "trash")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.orange)
                // 비어 있으면 "0 KB" 대신 상태를 말로 보여준다
                Text(monitor.snapshot.trashSize > 0
                     ? Format.bytes(monitor.snapshot.trashSize)
                     : NSLocalizedString("비어 있음", comment: ""))
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(monitor.snapshot.trashSize > 0 ? .primary : .secondary)
                Spacer(minLength: 2)
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
                .controlSize(.small)
                .disabled(emptyingTrash || monitor.snapshot.trashSize == 0)
                .featureLocked()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .glassCard(padding: 14)

            // 배터리 (노트북) / 디스크 I/O (데스크탑)
            if let pct = monitor.snapshot.batteryPercent {
                VStack(alignment: .leading, spacing: 8) {
                    Label("배터리", systemImage: monitor.snapshot.batteryCharging
                          ? "battery.100.bolt" : "battery.75")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.green)
                    Text("\(pct)%")
                        .font(.system(size: 21, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    SmoothBar(value: Double(pct) / 100,
                              color: monitor.snapshot.batteryCharging ? Theme.green : nil)
                    Text(monitor.snapshot.batteryCharging ? "충전 중" : "배터리 사용 중")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .glassCard(padding: 14)
            } else {
                miniStatTile(
                    title: "디스크 I/O", icon: "internaldrive", tint: Theme.green,
                    left: (speed(monitor.snapshot.diskReadPerSec), "읽기", "arrow.up.doc", Theme.green),
                    right: (speed(monitor.snapshot.diskWritePerSec), "쓰기", "arrow.down.doc", Theme.yellow)
                )
            }

            // 네트워크
            miniStatTile(
                title: "네트워크", icon: "network", tint: Theme.purple,
                left: (speed(monitor.snapshot.netDownPerSec), "다운로드", "arrow.down", Theme.teal),
                right: (speed(monitor.snapshot.netUpPerSec), "업로드", "arrow.up", Theme.orange)
            )
        }
    }

    /// 좌우 2개의 실시간 수치를 담는 컴팩트 정보 타일 (디스크 I/O·네트워크 공용)
    private func miniStatTile(
        title: LocalizedStringKey, icon: String, tint: Color,
        left: (String, LocalizedStringKey, String, Color),
        right: (String, LocalizedStringKey, String, Color)
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Label(left.0, systemImage: left.2)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(left.3)
                        .monospacedDigit()
                    Text(left.1).font(.caption).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Label(right.0, systemImage: right.2)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(right.3)
                        .monospacedDigit()
                    Text(right.1).font(.caption).foregroundStyle(.secondary)
                }
            }
            Text("실시간 (2초 간격)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassCard(padding: 14)
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
                        ? String(format: NSLocalizedString("메모리 정리 완료 — %@ 확보", comment: ""), Format.bytes(freed))
                        : NSLocalizedString("메모리 정리 완료", comment: "")
                } else {
                    // 비관리자 방식으로 전환되어 암호는 더 이상 필요 없음 (기존 현지화 키 재사용)
                    actionMessage = NSLocalizedString("취소되었거나 실패했습니다", comment: "")
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
                    ? String(format: NSLocalizedString("휴지통을 비웠습니다 — %@ 확보", comment: ""), Format.bytes(size))
                    : NSLocalizedString("휴지통 비우기에 실패했습니다", comment: "")
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
        // 언어 설정과 무관하게 B/s·KB/s·MB/s 표준 표기로 출력 (NaN/무한대도 안전)
        Format.speed(bytesPerSec)
    }
}
