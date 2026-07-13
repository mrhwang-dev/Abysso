import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case dashboard = "시스템 현황"
    case cache = "스마트 정리"
    case largeFiles = "스페이스 렌즈"
    case uninstall = "앱 제거"
    case oldFiles = "오래된 대용량 파일"
    case shredder = "파쇄기"
    case privacy = "개인정보 보호"
    case malware = "악성 프로그램 스캔"
    case optimization = "최적화"
    case maintenance = "유지보수"
    case updater = "업데이트"
    case extensions = "확장 프로그램"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .dashboard: return "gauge.with.dots.needle.50percent"
        case .cache: return "sparkles"
        case .largeFiles: return "circle.hexagongrid.fill"
        case .uninstall: return "trash.square.fill"
        case .shredder: return "flame.fill"
        case .privacy: return "hand.raised.fill"
        case .malware: return "shield.lefthalf.filled"
        case .oldFiles: return "clock.badge.exclamationmark.fill"
        case .optimization: return "bolt.badge.checkmark"
        case .maintenance: return "wrench.and.screwdriver.fill"
        case .updater: return "arrow.triangle.2.circlepath"
        case .extensions: return "puzzlepiece.extension.fill"
        }
    }

    var tint: Color {
        switch self {
        case .dashboard: return Theme.blue
        case .cache: return Theme.teal
        case .largeFiles: return Theme.purple
        case .uninstall: return Theme.orange
        case .shredder: return Theme.red
        case .privacy: return Theme.blue
        case .malware: return Theme.red
        case .oldFiles: return Theme.orange
        case .optimization: return Theme.blue
        case .maintenance: return Theme.teal
        case .updater: return Theme.green
        case .extensions: return Theme.yellow
        }
    }
}

struct ContentView: View {
    @State private var selection: SidebarItem? = .dashboard

    // 탭 전환 시에도 스캔 결과가 유지되도록 모든 모델을 최상단에서 소유
    @StateObject private var cacheModel = CacheModel()
    @StateObject private var lensModel = LargeFilesModel()
    @StateObject private var uninstallModel = UninstallModel()
    @StateObject private var oldFilesModel = OldFilesModel()
    @StateObject private var optimizationModel = OptimizationModel()
    @StateObject private var shredderModel = ShredderModel()
    @StateObject private var privacyModel = PrivacyModel()
    @StateObject private var malwareModel = MalwareModel()
    @StateObject private var maintenanceModel = MaintenanceModel()
    @StateObject private var updaterModel = UpdaterModel()
    @StateObject private var extensionsModel = ExtensionsModel()

    @AppStorage("fdaPromptSuppressed") private var fdaSuppressed = false
    @AppStorage("onboardingCompleted") private var onboardingCompleted = false
    @State private var showFDASheet = false
    @State private var showOnboarding = false

    // 전체 탭 캡처
    enum CaptureState: Equatable { case idle, capturing, done(URL), noPermission, failed }
    @State private var captureState: CaptureState = .idle

    private static let sections: [(String, [SidebarItem])] = [
        ("모니터링", [.dashboard]),
        ("정리", [.cache, .largeFiles, .oldFiles, .uninstall, .shredder]),
        ("보안", [.privacy, .malware]),
        ("관리", [.optimization, .maintenance, .updater, .extensions]),
    ]

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(Self.sections, id: \.0) { title, items in
                    Section(title) {
                        ForEach(items) { item in
                            Label {
                                Text(item.rawValue)
                                    .font(.system(size: 13.5, weight: .medium, design: .rounded))
                            } icon: {
                                Image(systemName: item.icon)
                                    .foregroundStyle(item.tint)
                            }
                            .tag(item)
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 190, ideal: 210)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    Button {
                        captureAllTabs()
                    } label: {
                        if captureState == .capturing {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text("캡처 중…")
                            }
                            .frame(maxWidth: .infinity)
                        } else {
                            Label("전체 탭 캡처", systemImage: "camera.viewfinder")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .controlSize(.small)
                    .disabled(captureState == .capturing)
                    .help("모든 탭을 자동으로 캡처해 데스크탑에 한 장의 이미지로 저장합니다")

                    VStack(spacing: 2) {
                        Image(systemName: "sparkles")
                            .foregroundStyle(Theme.accentGradient)
                        Text("Cleanova")
                            .font(.caption.weight(.semibold))
                        Text("v1.0 · 개인용")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 10)
            }
        } detail: {
            Group {
                switch selection ?? .dashboard {
                case .dashboard: DashboardView(selection: $selection)
                case .cache: CacheView()
                case .largeFiles: LargeFilesView()
                case .uninstall: UninstallView()
                case .oldFiles: OldFilesView()
                case .optimization: OptimizationView()
                case .shredder: ShredderView()
                case .privacy: PrivacyView()
                case .malware: MalwareView()
                case .maintenance: MaintenanceView()
                case .updater: UpdaterView()
                case .extensions: ExtensionsView()
                }
            }
            .transition(.opacity)
        }
        .environmentObject(cacheModel)
        .environmentObject(lensModel)
        .environmentObject(uninstallModel)
        .environmentObject(oldFilesModel)
        .environmentObject(optimizationModel)
        .environmentObject(shredderModel)
        .environmentObject(privacyModel)
        .environmentObject(malwareModel)
        .environmentObject(maintenanceModel)
        .environmentObject(updaterModel)
        .environmentObject(extensionsModel)
        .navigationTitle("Cleanova")
        .preferredColorScheme(.dark)
        .tint(Theme.teal)
        .animation(.easeInOut(duration: 0.2), value: selection)
        .overlay(alignment: .bottom) { captureBanner }
        .sheet(isPresented: $showFDASheet) {
            FullDiskAccessSheet(isPresented: $showFDASheet)
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView(isPresented: $showOnboarding)
                .interactiveDismissDisabled()
        }
        .onAppear {
            if !onboardingCompleted {
                // 최초 실행: 온보딩(환영 → EULA → FDA)을 먼저 표시
                showOnboarding = true
            } else if !fdaSuppressed {
                // 재실행: 권한이 없고 사용자가 억제하지 않았을 때만 FDA 안내
                Task.detached(priority: .utility) {
                    let granted = Permissions.hasFullDiskAccess()
                    if !granted {
                        await MainActor.run { showFDASheet = true }
                    }
                }
            }
        }
    }

    // MARK: 전체 탭 캡처 결과 배너

    @ViewBuilder
    private var captureBanner: some View {
        switch captureState {
        case .idle, .capturing:
            EmptyView()
        case .done(let url):
            banner(icon: "checkmark.circle.fill", tint: Theme.green,
                   text: "데스크탑에 저장했습니다 · \(url.lastPathComponent)") {
                Button("Finder에서 보기") {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
                .buttonStyle(.link)
                Button("닫기") { captureState = .idle }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
            }
        case .noPermission:
            banner(icon: "exclamationmark.triangle.fill", tint: Theme.orange,
                   text: "화면 기록 권한이 필요합니다. 허용 후 다시 시도하세요.") {
                Button("설정 열기") { ScreenshotExporter.openScreenRecordingSettings() }
                    .buttonStyle(.link)
                Button("닫기") { captureState = .idle }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
            }
        case .failed:
            banner(icon: "xmark.circle.fill", tint: Theme.red,
                   text: "캡처에 실패했습니다.") {
                Button("닫기") { captureState = .idle }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
            }
        }
    }

    private func banner<Trailing: View>(
        icon: String, tint: Color, text: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(tint)
            Text(text).font(.callout)
            Spacer()
            trailing()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(tint.opacity(0.4), lineWidth: 1))
        .padding(16)
        .shadow(color: .black.opacity(0.3), radius: 10, y: 4)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: 캡처 실행

    private func captureAllTabs() {
        let saved = selection
        withAnimation { captureState = .capturing }
        Task {
            let result = await ScreenshotExporter.captureAllTabs { item in
                selection = item
            }
            selection = saved
            withAnimation {
                switch result {
                case .success(let url): captureState = .done(url)
                case .noPermission: captureState = .noPermission
                case .failed: captureState = .failed
                }
            }
            if case .done(let url) = captureState {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        }
    }
}
