import SwiftUI

// MARK: - 뷰모델

@MainActor
final class OptimizationModel: ObservableObject {
    enum Section: String, CaseIterable, Identifiable {
        case login = "로그인 항목"
        case cpu = "리소스 과다 사용 앱"
        case running = "실행 중인 앱"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .login: return "power"
            case .cpu: return "bolt.fill"
            case .running: return "macwindow.on.rectangle"
            }
        }
        var tint: Color {
            switch self {
            case .login: return Theme.blue
            case .cpu: return Theme.orange
            case .running: return Theme.teal
            }
        }
    }

    @Published var section: Section = .login

    // 로그인 항목 / 백그라운드 도구
    let agents = LaunchAgentManager()

    // 프로세스
    @Published var cpuProcs: [RunningProc] = []
    @Published var memProcs: [RunningProc] = []
    @Published var guiApps: [(app: NSRunningApplication, unresponsive: Bool)] = []
    @Published var loadingProcs = false
    @Published var message: String?

    private var timer: Timer?

    func onAppear() {
        if !agents.loaded { agents.load() }
        refreshProcs()
        startAutoRefresh()
    }

    func onDisappear() {
        timer?.invalidate()
        timer = nil
    }

    private func startAutoRefresh() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshProcs() }
        }
    }

    func refreshProcs() {
        loadingProcs = true
        Task.detached(priority: .utility) {
            let cpu = ProcessMonitor.topByCPU()
            let mem = ProcessMonitor.topByMemory()
            let apps = ProcessMonitor.guiApps()
            await MainActor.run {
                self.cpuProcs = cpu
                self.memProcs = mem
                self.guiApps = apps
                self.loadingProcs = false
            }
        }
    }

    func quit(pid: Int32, name: String, force: Bool) {
        let ok = ProcessMonitor.quit(pid: pid, force: force)
        message = ok
            ? "\(name) 을(를) \(force ? "강제 종료" : "종료")했습니다"
            : "\(name) 종료에 실패했습니다"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self.refreshProcs() }
    }
}

// MARK: - 뷰

struct OptimizationView: View {
    @EnvironmentObject private var model: OptimizationModel

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(
                title: "최적화",
                subtitle: "시작 프로그램과 실행 중인 앱을 관리해 Mac을 가볍게 유지합니다",
                icon: "bolt.badge.checkmark", iconColor: Theme.blue
            )
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 12)

            Picker("", selection: $model.section) {
                ForEach(OptimizationModel.Section.allCases) { s in
                    Text(s.rawValue).tag(s)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 24)
            .padding(.bottom, 10)

            Divider().opacity(0.3)

            ScrollView {
                VStack(spacing: 14) {
                    if let msg = model.message {
                        Label(msg, systemImage: "info.circle.fill")
                            .foregroundStyle(Theme.green)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    switch model.section {
                    case .login: loginSection
                    case .cpu: resourceSection
                    case .running: runningSection
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
        }
        .background(Theme.background)
        .onAppear { model.onAppear() }
        .onDisappear { model.onDisappear() }
    }

    // MARK: 로그인 항목 + 백그라운드 도구

    private var loginSection: some View {
        let logins = model.agents.agents.filter { !$0.displayName.hasPrefix(".") }
        return VStack(spacing: 14) {
            agentCard(
                title: "로그인 항목 및 백그라운드 앱",
                subtitle: "로그인할 때 자동으로 실행되는 항목입니다. 스위치로 켜고 끌 수 있어요.",
                items: logins
            )
        }
    }

    private func agentCard(title: String, subtitle: String, items: [LaunchAgentInfo]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(title, systemImage: "power")
                    .font(.headline)
                    .foregroundStyle(Theme.blue)
                Spacer()
                if !items.isEmpty {
                    Text("\(items.filter(\.enabled).count)/\(items.count)개 켜짐")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)

            if !model.agents.loaded {
                ProgressView().controlSize(.small).padding(.vertical, 8)
            } else if items.isEmpty {
                Text("자동 실행 항목이 없습니다 — 깨끗한 상태입니다 ✨")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            } else {
                Divider().opacity(0.3)
                ForEach(items) { agent in
                    HStack(spacing: 10) {
                        Image(systemName: agent.enabled ? "gearshape.fill" : "gearshape")
                            .foregroundStyle(agent.enabled ? AnyShapeStyle(Theme.teal) : AnyShapeStyle(.tertiary))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(agent.displayName)
                                .font(.system(size: 13.5, weight: .medium))
                            Text(agent.label)
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([agent.url])
                        } label: {
                            Image(systemName: "folder").font(.caption)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.tertiary)
                        .help("Finder에서 보기")
                        Toggle("", isOn: Binding(
                            get: { agent.enabled },
                            set: { model.agents.setEnabled(agent, $0) }
                        ))
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .labelsHidden()
                        .disabled(model.agents.busy.contains(agent.label))
                    }
                    .padding(.vertical, 3)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    // MARK: 리소스 과다 사용 앱 (CPU / 메모리 상위)

    private var resourceSection: some View {
        VStack(spacing: 14) {
            procCard(
                title: "CPU 사용 상위",
                icon: "cpu", tint: Theme.orange,
                procs: model.cpuProcs,
                valueText: { String(format: "%.1f%%", $0.cpu) }
            )
            procCard(
                title: "메모리 사용 상위",
                icon: "memorychip", tint: Theme.purple,
                procs: model.memProcs,
                valueText: { Format.bytes($0.memBytes) }
            )
        }
    }

    private func procCard(
        title: String, icon: String, tint: Color,
        procs: [RunningProc], valueText: @escaping (RunningProc) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(title, systemImage: icon)
                    .font(.headline)
                    .foregroundStyle(tint)
                Spacer()
                Text("4초마다 갱신")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Divider().opacity(0.3)
            if procs.isEmpty {
                Text("측정 중…").foregroundStyle(.secondary).padding(.vertical, 6)
            } else {
                ForEach(procs) { proc in
                    HStack(spacing: 10) {
                        Image(nsImage: proc.icon)
                            .resizable().frame(width: 22, height: 22)
                        Text(proc.name)
                            .font(.system(size: 13))
                            .lineLimit(1)
                        Spacer()
                        Text(valueText(proc))
                            .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(tint)
                            .monospacedDigit()
                        Button {
                            model.quit(pid: proc.pid, name: proc.name, force: false)
                        } label: {
                            Text("종료").font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    // MARK: 실행 중인 앱 (응답 없음 강조 + 강제 종료)

    private var runningSection: some View {
        let hung = model.guiApps.filter(\.unresponsive)
        return VStack(spacing: 14) {
            if !hung.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("응답 없는 앱", systemImage: "exclamationmark.triangle.fill")
                        .font(.headline)
                        .foregroundStyle(Theme.red)
                    Text("아래 앱이 응답하지 않습니다. 강제 종료하면 저장하지 않은 작업이 사라질 수 있습니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Divider().opacity(0.3)
                    ForEach(hung, id: \.app.processIdentifier) { entry in
                        appRow(entry.app, unresponsive: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("실행 중인 앱", systemImage: "macwindow.on.rectangle")
                        .font(.headline)
                        .foregroundStyle(Theme.teal)
                    Spacer()
                    Text("\(model.guiApps.count)개")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Divider().opacity(0.3)
                ForEach(model.guiApps, id: \.app.processIdentifier) { entry in
                    appRow(entry.app, unresponsive: entry.unresponsive)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        }
    }

    private func appRow(_ app: NSRunningApplication, unresponsive: Bool) -> some View {
        HStack(spacing: 10) {
            if let icon = app.icon {
                Image(nsImage: icon).resizable().frame(width: 24, height: 24)
            }
            Text(app.localizedName ?? "알 수 없는 앱")
                .font(.system(size: 13))
            if unresponsive {
                Text("응답 없음")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Theme.red.opacity(0.15), in: Capsule())
                    .foregroundStyle(Theme.red)
            }
            Spacer()
            Button {
                model.quit(pid: app.processIdentifier,
                           name: app.localizedName ?? "앱", force: false)
            } label: {
                Text("종료").font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            Button {
                model.quit(pid: app.processIdentifier,
                           name: app.localizedName ?? "앱", force: true)
            } label: {
                Text("강제 종료").font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(Theme.red)
        }
        .padding(.vertical, 2)
    }
}
