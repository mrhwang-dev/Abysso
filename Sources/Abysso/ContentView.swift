import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case dashboard = "시스템 현황"
    case cache = "스마트 정리"
    case largeFiles = "대용량 파일"
    case uninstall = "앱 제거"
    case shredder = "완전 삭제"
    case optimization = "최적화"
    case maintenance = "유지보수"
    case updater = "업데이트"
    case extensions = "확장 프로그램"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .dashboard: return "gauge.with.dots.needle.50percent"
        case .cache: return "sparkles"
        case .largeFiles: return "chart.bar.xaxis"
        case .uninstall: return "trash.square.fill"
        case .shredder: return "flame.fill"
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
        case .optimization: return Theme.blue
        case .maintenance: return Theme.teal
        case .updater: return Theme.green
        case .extensions: return Theme.yellow
        }
    }

    // 개인정보 보호는 '스마트 정리' 탭 안으로 병합되어 별도 항목이 없다.
    static let sections: [(String, [SidebarItem])] = [
        ("모니터링", [.dashboard]),
        ("정리", [.cache, .largeFiles, .uninstall, .shredder]),
        ("관리", [.optimization, .maintenance, .extensions, .updater]),
    ]
}

struct ContentView: View {
    @State private var selection: SidebarItem? = .dashboard
    @ObservedObject private var license = LicenseManager.shared

    // 탭 전환 시에도 스캔 결과가 유지되도록 모든 모델을 최상단에서 소유
    @StateObject private var cacheModel = CacheModel()
    @StateObject private var lensModel = LargeFilesModel()
    @StateObject private var uninstallModel = UninstallModel()
    @StateObject private var optimizationModel = OptimizationModel()
    @StateObject private var shredderModel = ShredderModel()
    @StateObject private var privacyModel = PrivacyModel()
    @StateObject private var maintenanceModel = MaintenanceModel()
    @StateObject private var updaterModel = UpdaterModel()
    @StateObject private var extensionsModel = ExtensionsModel()

    @AppStorage("fdaPromptSuppressed") private var fdaSuppressed = false
    @AppStorage("onboardingCompleted") private var onboardingCompleted = false
    @State private var showFDASheet = false
    @State private var showOnboarding = false
    @State private var showBugReport = false

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(SidebarItem.sections, id: \.0) { title, items in
                    Section(LocalizedStringKey(title)) {
                        ForEach(items) { item in
                            Label {
                                Text(LocalizedStringKey(item.rawValue))
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
                // 브랜드 푸터만 (캡처 버튼은 우측 상단 툴바로 이동)
                VStack(spacing: 2) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(Theme.accentGradient)
                    // 버전 라벨이 "Abysso v0.0.1 (Free Beta)" 형태로 브랜드명을 포함한다.
                    Text(license.versionLabel)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
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
                case .optimization: OptimizationView()
                case .shredder: ShredderView()
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
        .environmentObject(optimizationModel)
        .environmentObject(shredderModel)
        .environmentObject(privacyModel)
        .environmentObject(maintenanceModel)
        .environmentObject(updaterModel)
        .environmentObject(extensionsModel)
        .navigationTitle("Abysso")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showBugReport = true } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "ladybug")
                        Text("버그 제보")
                    }
                }
                .help("버그 제보")
            }
        }
        .sheet(isPresented: $showBugReport) {
            BugReportView()
        }
        .preferredColorScheme(.dark)
        .tint(Theme.teal)
        .animation(.easeInOut(duration: 0.2), value: selection)
        .sheet(isPresented: $showFDASheet) {
            FullDiskAccessSheet(isPresented: $showFDASheet)
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView(isPresented: $showOnboarding)
                .interactiveDismissDisabled()
        }
        // 만료 상태에서 잠긴 실행 버튼을 눌렀을 때 뜨는 안내 → 라이선스 활성화 유도
        .alert("체험판이 만료되었습니다", isPresented: $license.showLockPrompt) {
            Button("라이선스 활성화") { openLicenseSettings() }
            Button("나중에", role: .cancel) {}
        } message: {
            Text("체험판이 만료되었습니다. 전체 기능을 사용하려면 라이선스를 활성화하세요.")
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

    /// 환경설정 창을 열고 라이선스 탭으로 전환한다.
    private func openLicenseSettings() {
        UserDefaults.standard.set("license", forKey: "settingsSelectedTab")
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}
