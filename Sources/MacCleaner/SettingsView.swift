import SwiftUI
import ServiceManagement

// MARK: - 로그인 자동 실행 관리 (SMAppService)

@MainActor
final class LaunchAtLoginManager: ObservableObject {
    @Published var enabled = false
    @Published var errorText: String?

    init() { refresh() }

    func refresh() {
        enabled = SMAppService.mainApp.status == .enabled
    }

    func set(_ on: Bool) {
        errorText = nil
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // 권한 승인 대기(.requiresApproval) 등은 실패로 보지 않도록 상태를 다시 읽음
            errorText = "설정을 적용하지 못했습니다: \(error.localizedDescription)"
        }
        refresh()
        // status가 requiresApproval이면 시스템 설정으로 안내
        if on, SMAppService.mainApp.status == .requiresApproval {
            errorText = "시스템 설정 > 일반 > 로그인 항목에서 MacCleaner를 허용해 주세요."
        }
    }

    var statusDescription: String {
        switch SMAppService.mainApp.status {
        case .enabled: return "로그인 시 자동으로 실행됩니다"
        case .requiresApproval: return "시스템 설정에서 승인이 필요합니다"
        case .notRegistered: return "자동 실행이 꺼져 있습니다"
        case .notFound: return "등록 정보를 찾을 수 없습니다"
        @unknown default: return ""
        }
    }
}

// MARK: - 환경설정 창

struct SettingsView: View {
    @StateObject private var launchManager = LaunchAtLoginManager()
    @AppStorage("menuBarEnabled") private var menuBarEnabled = true
    @AppStorage("fdaPromptSuppressed") private var fdaSuppressed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 26))
                    .foregroundStyle(Theme.accentGradient)
                VStack(alignment: .leading, spacing: 1) {
                    Text("MacCleaner 환경설정")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                    Text("버전 1.0 · 개인용")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(20)
            Divider()

            VStack(alignment: .leading, spacing: 18) {
                // 로그인 자동 실행
                settingRow(
                    icon: "power", tint: Theme.blue,
                    title: "로그인 시 MacCleaner 자동 실행",
                    subtitle: launchManager.statusDescription
                ) {
                    Toggle("", isOn: Binding(
                        get: { launchManager.enabled },
                        set: { launchManager.set($0) }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                }

                if let err = launchManager.errorText {
                    Label(err, systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(Theme.orange)
                        .padding(.leading, 4)
                }

                Divider().opacity(0.4)

                // 메뉴 막대
                settingRow(
                    icon: "menubar.arrow.up.rectangle", tint: Theme.teal,
                    title: "메뉴 막대 어시스턴트 표시",
                    subtitle: "상태표시줄에서 빠른 정리 도구를 사용합니다 (앱 재시작 후 적용)"
                ) {
                    Toggle("", isOn: $menuBarEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }

                Divider().opacity(0.4)

                // FDA 안내 재표시
                settingRow(
                    icon: "lock.shield", tint: Theme.purple,
                    title: "전체 디스크 접근 권한 안내 다시 보기",
                    subtitle: "다음 실행 때 권한 안내 창을 다시 표시합니다"
                ) {
                    Button("안내 다시 보기") { fdaSuppressed = false }
                        .controlSize(.small)
                }
            }
            .padding(20)

            Spacer()
        }
        .frame(width: 480, height: 340)
        .background(Theme.bgTop)
        .preferredColorScheme(.dark)
        .onAppear { launchManager.refresh() }
    }

    private func settingRow<Trailing: View>(
        icon: String, tint: Color, title: String, subtitle: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            trailing()
        }
    }
}
