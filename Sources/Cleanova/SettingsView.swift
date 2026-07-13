import SwiftUI

// MARK: - 로그인 자동 실행 관리 (LaunchAgent plist 직접 생성)
//
// 정식 개발자 인증서 없이 ad-hoc 서명만으로도 확실히 동작하도록
// ~/Library/LaunchAgents 에 plist를 직접 만들고 launchctl로 등록/해제한다.

@MainActor
final class LaunchAtLoginManager: ObservableObject {
    @Published var enabled = false
    @Published var errorText: String?

    static let label = "app.cleanova.mac"

    private var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(Self.label).plist")
    }

    /// 현재 실행 중인 .app 번들 경로 (설치 위치가 바뀌어도 자동 반영)
    private var appBundlePath: String {
        Bundle.main.bundleURL.path
    }

    init() { refresh() }

    func refresh() {
        enabled = FileManager.default.fileExists(atPath: plistURL.path)
    }

    func set(_ on: Bool) {
        errorText = nil
        if on { register() } else { unregister() }
        refresh()
    }

    private func register() {
        let plist: [String: Any] = [
            "Label": Self.label,
            "ProgramArguments": ["/usr/bin/open", "-g", appBundlePath],  // -g: 백그라운드로 실행
            "RunAtLoad": true,
        ]
        do {
            // LaunchAgents 폴더 보장
            let dir = plistURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(
                fromPropertyList: plist, format: .xml, options: 0
            )
            try data.write(to: plistURL)
            // launchctl load로 즉시 등록 (다음 로그인까지 기다리지 않도록).
            // 이미 로드돼 있을 수 있으니 먼저 unload 후 load (실패해도 파일은 남아 다음 로그인에 적용됨).
            _ = LaunchAgentManager.run("/bin/launchctl", ["unload", plistURL.path])
            _ = LaunchAgentManager.run("/bin/launchctl", ["load", "-w", plistURL.path])
        } catch {
            errorText = "자동 실행 설정에 실패했습니다: \(error.localizedDescription)"
        }
    }

    private func unregister() {
        // launchctl unload로 등록 해제 후 plist 삭제
        _ = LaunchAgentManager.run("/bin/launchctl", ["unload", "-w", plistURL.path])
        try? FileManager.default.removeItem(at: plistURL)
    }

    var statusDescription: String {
        enabled ? "로그인 시 자동으로 실행됩니다" : "자동 실행이 꺼져 있습니다"
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
                    Text("Cleanova 환경설정")
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
                    title: "로그인 시 Cleanova 자동 실행",
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
                } else if launchManager.enabled {
                    Text("메뉴 막대 어시스턴트가 로그인 시 조용히 실행됩니다.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 54)
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
