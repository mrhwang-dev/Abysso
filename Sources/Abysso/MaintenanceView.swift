import SwiftUI

// MARK: - 모델

struct MaintenanceTask: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let icon: String
    let tint: Color
    let command: String
}

@MainActor
final class MaintenanceModel: ObservableObject {
    enum TaskStatus { case idle, running, done, failed }

    static let tasks: [MaintenanceTask] = [
        MaintenanceTask(
            id: "ram",
            title: "RAM 확보",
            subtitle: "메모리가 부족하거나 앱 전환이 느릴 때 — 비활성 메모리를 시스템에 반환합니다",
            icon: "memorychip",
            tint: Theme.teal,
            command: "/usr/sbin/purge"
        ),
        MaintenanceTask(
            id: "dns",
            title: "DNS 캐시 플러시",
            subtitle: "웹사이트 접속이 불안정하거나 주소를 못 찾을 때 — 네트워크 이름 캐시를 초기화합니다",
            icon: "network",
            tint: Theme.blue,
            command: "dscacheutil -flushcache; killall -HUP mDNSResponder"
        ),
        MaintenanceTask(
            id: "spotlight",
            title: "Spotlight 인덱스 재구성",
            subtitle: "검색 결과가 이상하거나 누락될 때 — 색인을 다시 만듭니다 (완료까지 수십 분간 Mac이 다소 느려질 수 있습니다)",
            icon: "magnifyingglass",
            tint: Theme.purple,
            command: "mdutil -E /"
        ),
    ]

    @Published var selected: Set<String> = []
    @Published var statuses: [String: TaskStatus] = [:]
    @Published var running = false
    @Published var message: String?

    func toggle(_ id: String) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    func run() {
        guard !running, !selected.isEmpty else { return }
        running = true
        message = nil
        let targets = Self.tasks.filter { selected.contains($0.id) }
        for task in targets { statuses[task.id] = .running }

        // 선택 작업을 한 스크립트로 묶어 관리자 암호를 한 번만 요청
        let combined = targets.map(\.command).joined(separator: " ; ")

        Task {
            let start = Date()
            let ok = await SystemActions.runShellAsAdmin(combined)
            let elapsed = Date().timeIntervalSince(start)
            withAnimation {
                for task in targets {
                    statuses[task.id] = ok ? .done : .failed
                }
                running = false
                if ok {
                    message = String(format: NSLocalizedString("%lld개 작업 완료 (%.1f초). ", comment: ""), targets.count, elapsed) +
                        (selected.contains("spotlight") ? NSLocalizedString("Spotlight 재색인은 백그라운드에서 계속 진행됩니다.", comment: "") : "")
                    selected = []
                } else {
                    message = NSLocalizedString("실행이 취소되었거나 실패했습니다 — 관리자 암호가 필요합니다.", comment: "")
                }
            }
            // 잠시 후 상태 아이콘 초기화
            try? await Task.sleep(for: .seconds(6))
            withAnimation { statuses = [:] }
        }
    }
}

// MARK: - 뷰

struct MaintenanceView: View {
    @EnvironmentObject private var model: MaintenanceModel

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(
                title: "유지보수",
                subtitle: "Mac이 느려지거나 이상할 때 실행하는 시스템 최적화 작업 모음입니다",
                icon: "wrench.and.screwdriver.fill", iconColor: Theme.teal
            )
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 12)

            ScrollView {
                VStack(spacing: 12) {
                    if let msg = model.message {
                        Label(msg, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(Theme.green)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    ForEach(MaintenanceModel.tasks) { task in
                        taskCard(task)
                    }

                    Label("실행 시 관리자 암호를 한 번 입력해야 합니다. 여러 작업을 선택해도 한 번만 묻습니다.",
                          systemImage: "lock.shield")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }

            Divider().opacity(0.3)
            bottomBar
        }
        .background(Theme.background)
    }

    private func taskCard(_ task: MaintenanceTask) -> some View {
        let isSelected = model.selected.contains(task.id)
        let status = model.statuses[task.id] ?? .idle

        return Button {
            guard !model.running else { return }
            model.toggle(task.id)
        } label: {
            HStack(spacing: 14) {
                Toggle("", isOn: Binding(
                    get: { isSelected },
                    set: { _ in model.toggle(task.id) }
                ))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .disabled(model.running)

                Image(systemName: task.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(task.tint)
                    .frame(width: 40, height: 40)
                    .background(task.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 2) {
                    Text(LocalizedStringKey(task.title))
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                    Text(LocalizedStringKey(task.subtitle))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer()

                switch status {
                case .idle:
                    EmptyView()
                case .running:
                    ProgressView().controlSize(.small)
                case .done:
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Theme.green)
                case .failed:
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Theme.red)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? Theme.cardHighlight : Theme.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(
                                isSelected ? task.tint.opacity(0.5) : Color.white.opacity(0.06),
                                lineWidth: 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: isSelected)
    }

    private var bottomBar: some View {
        HStack {
            Text("\(model.selected.count)개 작업 선택됨")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            if model.running {
                // 작업이 길어지면 경과 시간과 이유를 알려준다
                ScanDelayNotice(reason: "시스템 작업이 진행 중입니다 — 작업 종류에 따라 시간이 걸릴 수 있습니다",
                                reasonAfter: 8)
            }
            Button {
                model.run()
            } label: {
                if model.running {
                    ProgressView().controlSize(.small)
                } else {
                    Label("유지보수 실행", systemImage: "wrench.and.screwdriver")
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.teal)
            .disabled(model.selected.isEmpty || model.running)
            .featureLocked()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }
}
