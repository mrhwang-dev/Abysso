import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case dashboard = "시스템 현황"
    case cache = "스마트 정리"
    case largeFiles = "스페이스 렌즈"
    case uninstall = "앱 제거"
    case shredder = "파쇄기"
    case privacy = "개인정보 보호"
    case malware = "악성 프로그램 스캔"
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
    @StateObject private var shredderModel = ShredderModel()
    @StateObject private var privacyModel = PrivacyModel()
    @StateObject private var malwareModel = MalwareModel()
    @StateObject private var updaterModel = UpdaterModel()
    @StateObject private var extensionsModel = ExtensionsModel()

    @AppStorage("fdaPromptSuppressed") private var fdaSuppressed = false
    @State private var showFDASheet = false

    private static let sections: [(String, [SidebarItem])] = [
        ("모니터링", [.dashboard]),
        ("정리", [.cache, .largeFiles, .uninstall, .shredder]),
        ("보안", [.privacy, .malware]),
        ("관리", [.updater, .extensions]),
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
                VStack(spacing: 2) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(Theme.accentGradient)
                    Text("MacCleaner")
                        .font(.caption.weight(.semibold))
                    Text("v1.0 · 개인용")
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
                case .shredder: ShredderView()
                case .privacy: PrivacyView()
                case .malware: MalwareView()
                case .updater: UpdaterView()
                case .extensions: ExtensionsView()
                }
            }
            .transition(.opacity)
        }
        .environmentObject(cacheModel)
        .environmentObject(lensModel)
        .environmentObject(uninstallModel)
        .environmentObject(shredderModel)
        .environmentObject(privacyModel)
        .environmentObject(malwareModel)
        .environmentObject(updaterModel)
        .environmentObject(extensionsModel)
        .navigationTitle("MacCleaner")
        .preferredColorScheme(.dark)
        .tint(Theme.teal)
        .animation(.easeInOut(duration: 0.2), value: selection)
        .sheet(isPresented: $showFDASheet) {
            FullDiskAccessSheet(isPresented: $showFDASheet)
        }
        .onAppear {
            if !fdaSuppressed {
                Task.detached(priority: .utility) {
                    let granted = Permissions.hasFullDiskAccess()
                    if !granted {
                        await MainActor.run { showFDASheet = true }
                    }
                }
            }
        }
    }
}
