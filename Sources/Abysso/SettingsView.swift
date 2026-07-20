import SwiftUI

// MARK: - 로그인 자동 실행 관리 (LaunchAgent plist 직접 생성)
//
// 정식 개발자 인증서 없이 ad-hoc 서명만으로도 확실히 동작하도록
// ~/Library/LaunchAgents 에 plist를 직접 만들고 launchctl로 등록/해제한다.

@MainActor
final class LaunchAtLoginManager: ObservableObject {
    @Published var enabled = false
    @Published var errorText: String?

    static let label = "app.abysso.mac"

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
        #if DEBUG
        guard DevMode.shouldRunCommand("로그인 항목 등록 (plist 작성 + launchctl load): \(Self.label)") else { return }
        #endif
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
            errorText = String(format: NSLocalizedString("자동 실행 설정에 실패했습니다: %@", comment: ""), error.localizedDescription)
        }
    }

    private func unregister() {
        #if DEBUG
        guard DevMode.shouldRunCommand("로그인 항목 해제 (launchctl unload + plist 삭제): \(Self.label)") else { return }
        #endif
        // launchctl unload로 등록 해제 후 plist 삭제
        _ = LaunchAgentManager.run("/bin/launchctl", ["unload", "-w", plistURL.path])
        try? FileManager.default.removeItem(at: plistURL)
    }

    var statusDescription: String {
        enabled ? "로그인 시 자동으로 실행됩니다" : "자동 실행이 꺼져 있습니다"
    }
}

// MARK: - 환경설정 창 (탭 컨테이너)

struct SettingsView: View {
    // 만료 안내 모달의 "라이선스 활성화"에서 이 값을 바꿔 라이선스 탭으로 유도한다.
    @AppStorage("settingsSelectedTab") private var selectedTab = "general"

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsView()
                .tabItem { Label("일반", systemImage: "gearshape") }
                .tag("general")
            // 전면 무료 베타 배포 중에는 라이선스 탭을 숨긴다.
            // 유료 전환 시 아래 두 줄을 복원하면 된다 (LicenseSettingsView는 유지).
            // LicenseSettingsView()
            //     .tabItem { Label("라이선스", systemImage: "key.fill") }
            //     .tag("license")
            #if DEBUG
            // 개발자 테스트 도구 — 릴리스(DMG) 빌드에서는 자동 제외됨
            DeveloperSettingsView()
                .tabItem { Label("개발자", systemImage: "hammer") }
                .tag("developer")
            #endif
        }
        .frame(width: 500, height: 500)
        .preferredColorScheme(.dark)
    }
}

// MARK: - 일반 설정 탭

struct GeneralSettingsView: View {
    @StateObject private var launchManager = LaunchAtLoginManager()
    @ObservedObject private var updater = AppUpdater.shared
    @ObservedObject private var license = LicenseManager.shared
    @AppStorage("menuBarEnabled") private var menuBarEnabled = true
    @AppStorage("fdaPromptSuppressed") private var fdaSuppressed = false
    @AppStorage("ramAlertThreshold") private var ramAlertThreshold: Double = 85.0
    @State private var language = AppLanguage.current
    @State private var languageChanged = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 26))
                    .foregroundStyle(Theme.accentGradient)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Abysso 환경설정")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                    Text(license.versionLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(20)
            Divider()

            // 항목이 창 높이를 넘어도 잘리지 않도록 스크롤 지원
            ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // 표시 언어
                settingRow(
                    icon: "globe", tint: Theme.purple,
                    title: "표시 언어",
                    subtitle: "앱에 표시되는 언어를 선택합니다 (다시 시작 후 적용)"
                ) {
                    Picker("", selection: $language) {
                        ForEach(AppLanguage.allCases) { lang in
                            Text(lang.displayName).tag(lang)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .onChange(of: language) { _, newValue in
                        newValue.apply()
                        languageChanged = true
                    }
                }
                if languageChanged {
                    HStack(spacing: 8) {
                        Text("언어를 적용하려면 앱을 다시 시작하세요.")
                            .font(.caption)
                            .foregroundStyle(Theme.orange)
                        Spacer()
                        Button("지금 다시 시작") { AppLanguage.relaunch() }
                            .controlSize(.small)
                    }
                    .padding(.leading, 54)
                }

                Divider().opacity(0.4)

                // 로그인 자동 실행
                settingRow(
                    icon: "power", tint: Theme.blue,
                    title: "로그인 시 Abysso 자동 실행",
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

                // RAM 모니터링
                settingRow(
                    icon: "memorychip", tint: Theme.orange,
                    title: "RAM 부족 알림 임계값",
                    subtitle: "사용량이 임계값을 넘으면 알림을 보냅니다 (최소 10분 간격)"
                ) {
                    Text("\(Int(ramAlertThreshold))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 40, alignment: .trailing)
                }
                Slider(value: $ramAlertThreshold, in: 70...95, step: 1)
                    .padding(.leading, 54)

                Divider().opacity(0.4)

                // 자동 업데이트
                settingRow(
                    icon: "arrow.down.circle", tint: Theme.green,
                    title: "자동으로 업데이트 확인",
                    subtitle: "새 버전이 나오면 백그라운드에서 확인합니다"
                ) {
                    Toggle("", isOn: Binding(
                        get: { updater.automaticallyChecksForUpdates },
                        set: { updater.automaticallyChecksForUpdates = $0 }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                }
                HStack {
                    Spacer()
                    CheckForUpdatesButton(title: "Abysso 업데이트 확인")
                        .controlSize(.small)
                }
                .padding(.leading, 54)

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
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.bgTop)
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
                Text(LocalizedStringKey(title))
                    .font(.system(size: 14, weight: .medium))
                Text(LocalizedStringKey(subtitle))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            trailing()
        }
    }
}
