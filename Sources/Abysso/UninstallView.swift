import SwiftUI
import CoreServices

// MARK: - 모델

enum AppCategory: String, CaseIterable, Identifiable {
    case all = "전체"
    case unused = "사용 안 함"
    case large = "대용량"
    case recent = "최근 업데이트"
    case helpers = "백그라운드 도구"
    case leftovers = "잔여 파일"

    var id: String { rawValue }
}

enum AppSort: String, CaseIterable, Identifiable {
    case name = "이름순"
    case sizeDesc = "크기 큰 순"
    case sizeAsc = "크기 작은 순"
    case lastUsed = "오래 안 쓴 순"

    var id: String { rawValue }
}

struct InstalledApp: Identifiable {
    let id = UUID()
    let name: String
    let url: URL
    let resolvedURL: URL  // 심볼릭 링크 해석 경로 (크기/아이콘용)
    let bundleID: String?
    let size: Int64
    let lastUsed: Date?
    let modified: Date?
    let isHelper: Bool   // LSUIElement/LSBackgroundOnly/숨김 — 일반 사용자용 GUI 앱이 아님

    var isUnused: Bool {
        guard let lastUsed else { return true }  // 사용 기록 없음 = 미사용
        return lastUsed < Calendar.current.date(byAdding: .month, value: -6, to: .now)!
    }
    var isLarge: Bool { size > 1_000_000_000 }
    var isRecentlyUpdated: Bool {
        guard let modified else { return false }
        return modified > Calendar.current.date(byAdding: .day, value: -30, to: .now)!
    }
}

struct RelatedFile: Identifiable {
    let id = UUID()
    let url: URL
    let size: Int64
    let kind: String  // "캐시", "설정", "지원 파일" 등
    var selected = true

    var displayPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return url.path.replacingOccurrences(of: home, with: "~")
    }
}

struct OrphanFile: Identifiable {
    let id = UUID()
    let url: URL
    let size: Int64
    let bundleID: String
    var selected = false

    var displayPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return url.path.replacingOccurrences(of: home, with: "~")
    }
}

// MARK: - 뷰모델

@MainActor
final class UninstallModel: ObservableObject {
    @Published var apps: [InstalledApp] = []
    @Published var scanning = false
    @Published var category: AppCategory = .all
    @Published var sort: AppSort = .sizeDesc
    @Published var selectedAppID: UUID?
    @Published var relatedFiles: [RelatedFile] = []
    @Published var findingRelated = false
    @Published var orphans: [OrphanFile] = []
    @Published var scanningOrphans = false
    @Published var message: String?

    var selectedApp: InstalledApp? { apps.first { $0.id == selectedAppID } }

    /// 일반 사용자용 GUI 앱 (헬퍼 제외)
    var mainApps: [InstalledApp] { apps.filter { !$0.isHelper } }

    var filteredApps: [InstalledApp] {
        let base: [InstalledApp]
        switch category {
        case .all: base = mainApps
        case .unused: base = mainApps.filter(\.isUnused)
        case .large: base = mainApps.filter(\.isLarge)
        case .recent: base = mainApps.filter(\.isRecentlyUpdated)
        case .helpers: base = apps.filter(\.isHelper)
        case .leftovers: base = []
        }
        switch sort {
        case .name:
            return base.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        case .sizeDesc: return base.sorted { $0.size > $1.size }
        case .sizeAsc: return base.sorted { $0.size < $1.size }
        case .lastUsed:
            return base.sorted {
                ($0.lastUsed ?? .distantPast) < ($1.lastUsed ?? .distantPast)
            }
        }
    }

    // 요약 통계 (GUI 앱 기준)
    var totalSize: Int64 { mainApps.reduce(0) { $0 + $1.size } }
    var unusedCount: Int { mainApps.filter(\.isUnused).count }
    var unusedSize: Int64 { mainApps.filter(\.isUnused).reduce(0) { $0 + $1.size } }
    var topApps: [InstalledApp] {
        Array(mainApps.filter { $0.size > 0 }.sorted { $0.size > $1.size }.prefix(5))
    }

    func scanApps() {
        scanning = true
        Task.detached(priority: .userInitiated) {
            let result = await Self.findApps()
            await MainActor.run {
                withAnimation { self.apps = result; self.scanning = false }
            }
        }
    }

    nonisolated static func findApps() async -> [InstalledApp] {
        let fm = FileManager.default
        let dirs = [
            URL(fileURLWithPath: "/Applications"),
            fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications"),
        ]
        return await withTaskGroup(of: InstalledApp?.self) { group in
            for dir in dirs {
                guard let items = try? fm.contentsOfDirectory(
                    at: dir, includingPropertiesForKeys: [.contentModificationDateKey]
                ) else { continue }
                for url in items where url.pathExtension == "app" {
                    group.addTask {
                        let resolved = url.resolvingSymlinksInPath()
                        let bundle = Bundle(url: resolved)
                        let bundleID = bundle?.bundleIdentifier
                        let size = DiskUtil.directorySize(resolved)
                        let modified = (try? resolved.resourceValues(forKeys: [.contentModificationDateKey]))?
                            .contentModificationDate

                        // Spotlight 메타데이터에서 마지막 사용일
                        var lastUsed: Date?
                        if let item = MDItemCreate(kCFAllocatorDefault, resolved.path as CFString) {
                            lastUsed = MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
                        }

                        return InstalledApp(
                            name: url.deletingPathExtension().lastPathComponent,
                            url: url, resolvedURL: resolved, bundleID: bundleID, size: size,
                            lastUsed: lastUsed, modified: modified,
                            isHelper: Self.isHelperApp(url: url, info: bundle?.infoDictionary)
                        )
                    }
                }
            }
            var found: [InstalledApp] = []
            for await app in group {
                if let app { found.append(app) }
            }
            found.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            return found
        }
    }

    /// 백그라운드 헬퍼 판별: Dock에 표시되지 않는 앱, 백그라운드 전용, 숨김 파일
    nonisolated static func isHelperApp(url: URL, info: [String: Any]?) -> Bool {
        if url.lastPathComponent.hasPrefix(".") { return true }
        func flag(_ key: String) -> Bool {
            switch info?[key] {
            case let b as Bool: return b
            case let n as NSNumber: return n.boolValue
            case let s as String: return s == "1" || s.lowercased() == "true"
            default: return false
            }
        }
        return flag("LSUIElement") || flag("LSBackgroundOnly")
    }

    // MARK: 관련 파일 탐색

    func findRelated(for app: InstalledApp) {
        selectedAppID = app.id
        relatedFiles = []
        message = nil
        findingRelated = true
        Task.detached(priority: .userInitiated) {
            let result = await Self.relatedFiles(for: app)
            await MainActor.run {
                self.relatedFiles = result
                self.findingRelated = false
            }
        }
    }

    nonisolated static func relatedFiles(for app: InstalledApp) async -> [RelatedFile] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        var candidates: [(String, String)] = []  // (경로, 종류)

        if let bid = app.bundleID {
            candidates += [
                ("Library/Caches/\(bid)", "캐시"),
                ("Library/Preferences/\(bid).plist", "설정"),
                ("Library/Saved Application State/\(bid).savedState", "저장된 상태"),
                ("Library/Containers/\(bid)", "컨테이너"),
                ("Library/Application Support/\(bid)", "지원 파일"),
                ("Library/HTTPStorages/\(bid)", "네트워크 저장소"),
                ("Library/WebKit/\(bid)", "웹 데이터"),
                ("Library/Application Scripts/\(bid)", "스크립트"),
            ]
            // LaunchAgents 중 번들 ID가 이름에 포함된 것
            let agents = home.appendingPathComponent("Library/LaunchAgents")
            if let items = try? fm.contentsOfDirectory(atPath: agents.path) {
                for item in items where item.contains(bid) {
                    candidates.append(("Library/LaunchAgents/\(item)", "시작 항목"))
                }
            }
            // 그룹 컨테이너
            let groups = home.appendingPathComponent("Library/Group Containers")
            if let items = try? fm.contentsOfDirectory(atPath: groups.path) {
                for item in items where item.contains(bid) {
                    candidates.append(("Library/Group Containers/\(item)", "그룹 컨테이너"))
                }
            }
        }
        candidates += [
            ("Library/Application Support/\(app.name)", "지원 파일"),
            ("Library/Caches/\(app.name)", "캐시"),
            ("Library/Logs/\(app.name)", "로그"),
        ]

        return await withTaskGroup(of: RelatedFile?.self) { group in
            var seen = Set<String>()
            for (path, kind) in candidates {
                let url = home.appendingPathComponent(path)
                guard !seen.contains(url.path), fm.fileExists(atPath: url.path) else { continue }
                seen.insert(url.path)
                group.addTask {
                    return RelatedFile(url: url, size: DiskUtil.itemSize(url), kind: kind)
                }
            }
            var found: [RelatedFile] = []
            for await file in group {
                if let file { found.append(file) }
            }
            found.sort { $0.size > $1.size }
            return found
        }
    }

    // MARK: 삭제 / 재설정

    func uninstall() {
        guard let app = selectedApp else { return }
        var freed: Int64 = 0
        var appFailed = false

        if DiskUtil.trash(app.url) { freed += app.size } else { appFailed = true }
        for file in relatedFiles.filter(\.selected) where DiskUtil.trash(file.url) {
            freed += file.size
        }

        message = appFailed
            ? String(format: NSLocalizedString("앱 본체를 옮기지 못했습니다 (실행 중이거나 권한 부족). 관련 파일 %@ 는 휴지통으로 옮겼습니다.", comment: ""), Format.bytes(freed))
            : String(format: NSLocalizedString("%@ 및 관련 파일 %@ 를 휴지통으로 옮겼습니다.", comment: ""), app.name, Format.bytes(freed))
        selectedAppID = nil
        relatedFiles = []
        scanApps()
    }

    /// 재설정: 관련 파일만 지우고 앱은 유지
    func reset() {
        guard let app = selectedApp else { return }
        var freed: Int64 = 0
        for file in relatedFiles.filter(\.selected) where DiskUtil.trash(file.url) {
            freed += file.size
        }
        message = String(format: NSLocalizedString("%@ 을(를) 재설정했습니다 — 관련 파일 %@ 를 휴지통으로 옮겼습니다. 앱은 그대로 유지됩니다.", comment: ""), app.name, Format.bytes(freed))
        findRelated(for: app)
    }

    // MARK: 잔여 파일 (고아 파일)

    func scanOrphans() {
        scanningOrphans = true
        let installedIDs = Set(apps.compactMap(\.bundleID))
        Task.detached(priority: .userInitiated) {
            let result = await Self.findOrphans(installedIDs: installedIDs)
            await MainActor.run {
                withAnimation {
                    self.orphans = result
                    self.scanningOrphans = false
                }
            }
        }
    }

    nonisolated static func findOrphans(installedIDs: Set<String>) async -> [OrphanFile] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let dirs = ["Library/Application Support", "Library/Caches", "Library/Containers"]
        // 역방향 DNS 형태(com.회사.앱)이면서 설치된 앱/Apple 항목이 아닌 폴더
        let pattern = try! NSRegularExpression(pattern: #"^[a-z]{2,10}\.[\w-]+\.[\w.-]+$"#)

        return await withTaskGroup(of: OrphanFile?.self) { group in
            for dir in dirs {
                let base = home.appendingPathComponent(dir)
                guard let items = try? fm.contentsOfDirectory(
                    at: base, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
                ) else { continue }
                for url in items {
                    let name = url.lastPathComponent
                    let range = NSRange(name.startIndex..., in: name)
                    guard pattern.firstMatch(in: name, range: range) != nil,
                          !name.hasPrefix("com.apple."),
                          !installedIDs.contains(name),
                          // 설치된 앱 번들 ID의 하위 항목도 제외 (com.foo.app.helper 등)
                          !installedIDs.contains(where: { name.hasPrefix($0 + ".") })
                    else { continue }
                    
                    group.addTask {
                        let size = DiskUtil.itemSize(url)
                        if size > 100_000 {
                            return OrphanFile(url: url, size: size, bundleID: name)
                        }
                        return nil
                    }
                }
            }
            var found: [OrphanFile] = []
            for await orphan in group {
                if let orphan { found.append(orphan) }
            }
            found.sort { $0.size > $1.size }
            return Array(found.prefix(60))
        }
    }

    func trashSelectedOrphans() {
        var freed: Int64 = 0
        for orphan in orphans.filter(\.selected) where DiskUtil.trash(orphan.url) {
            freed += orphan.size
        }
        message = String(format: NSLocalizedString("잔여 파일 %@ 를 휴지통으로 옮겼습니다.", comment: ""), Format.bytes(freed))
        orphans.removeAll(where: \.selected)
    }
}

// MARK: - 메인 뷰

struct UninstallView: View {
    @EnvironmentObject private var model: UninstallModel
    @State private var confirmingUninstall = false
    @State private var search = ""

    private var visibleApps: [InstalledApp] {
        guard !search.isEmpty else { return model.filteredApps }
        return model.filteredApps.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(
                title: "앱 제거",
                subtitle: "앱과 함께 남는 캐시·설정·지원 파일까지 깨끗하게 제거합니다",
                icon: "trash.square.fill", iconColor: Theme.orange
            )
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 10)

            Picker("", selection: $model.category) {
                ForEach(AppCategory.allCases) { cat in
                    Text(LocalizedStringKey(cat.rawValue))
                        // 좁아지면 세로로 깨지지 않고 폰트가 자연스럽게 줄어들게
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .tag(cat)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            // 세그먼트가 세로로 찌그러지지 않도록 높이는 고유값 유지
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 24)
            .padding(.bottom, 10)
            .onChange(of: model.category) { _, newValue in
                if newValue == .leftovers && model.orphans.isEmpty {
                    model.scanOrphans()
                }
            }

            Divider().opacity(0.3)

            if model.category == .leftovers {
                orphansView
            } else {
                appSplitView
            }
        }
        .background(Theme.background)
        .onAppear {
            if model.apps.isEmpty { model.scanApps() }
        }
        .confirmationDialog(
            "\(model.selectedApp?.name ?? "") 앱과 선택한 관련 파일을 휴지통으로 옮길까요?",
            isPresented: $confirmingUninstall
        ) {
            Button("휴지통으로 이동", role: .destructive) { model.uninstall() }
        } message: {
            Text("휴지통에서 복구할 수 있습니다. 실행 중인 앱은 먼저 종료하세요.")
        }
    }

    // MARK: 앱 목록 + 상세

    private var appSplitView: some View {
        // HSplitView는 NavigationSplitView 상세 컬럼 안에서 상위 사이드바를 Overlay 모드로
        // 강제 붕괴시키는 충돌이 있다. 드래그 분할 대신 고정 2컬럼(HStack)으로 구성해 원천 차단한다.
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                if model.category == .helpers {
                    Label("시스템 확장·백그라운드 헬퍼입니다. 어떤 도구인지 확실할 때만 삭제하세요.", systemImage: "exclamationmark.shield")
                        .font(.caption)
                        .foregroundStyle(Theme.yellow)
                        .padding(.horizontal, 10)
                        .padding(.top, 8)
                }
                HStack(spacing: 8) {
                    TextField("앱 검색", text: $search)
                        .textFieldStyle(.roundedBorder)
                    FilterMenu(
                        icon: "arrow.up.arrow.down", tint: Theme.orange,
                        options: AppSort.allCases.map { ($0, $0.rawValue) },
                        selection: $model.sort
                    )
                }
                .padding(10)
                if model.scanning {
                    Spacer()
                    VStack(spacing: 10) {
                        ProgressView("설치된 앱을 확인하는 중…")
                        ScanDelayNotice(reason: "처리할 항목이 많아 검사가 지연되고 있습니다")
                    }
                    Spacer()
                } else if visibleApps.isEmpty {
                    EmptyStateView(
                        icon: "app.badge",
                        title: "앱을 찾을 수 없습니다",
                        message: "선택한 조건에 맞는 앱이 없습니다.",
                        actionTitle: "조건 초기화",
                        action: { model.category = .all; search = "" },
                        tint: Theme.orange
                    )
                } else {
                    List(visibleApps, selection: Binding(
                        get: { model.selectedAppID },
                        set: { id in
                            if let app = model.apps.first(where: { $0.id == id }) {
                                model.findRelated(for: app)
                            }
                        }
                    )) { app in
                        HStack(spacing: 10) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: app.resolvedURL.path))
                                .resizable()
                                .frame(width: 26, height: 26)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(app.name)
                                if app.isUnused {
                                    Group {
                                        if let used = app.lastUsed {
                                            Text("마지막 사용: \(used.formatted(.relative(presentation: .named)))")
                                        } else {
                                            Text("사용 기록 없음")
                                        }
                                    }
                                    .font(.caption2)
                                    .foregroundStyle(Theme.orange)
                                }
                            }
                            Spacer()
                            if app.size > 0 {
                                Text(Format.bytes(app.size))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            } else {
                                Text(LocalizedStringKey(Format.unknownSize))
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .tag(app.id)
                        .padding(.vertical, 2)
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            // 왼쪽 목록: 300~420 범위. 우선 배치되어 이상적 340 폭을 먼저 확보
            .frame(minWidth: 300, idealWidth: 340, maxWidth: 420)
            .layoutPriority(1)

            Divider()

            // 오른쪽 상세: 남는 공간을 모두 흡수 (최소 360 보장)
            detailPane
                .frame(minWidth: 360, maxWidth: .infinity)
        }
    }

    // MARK: 상세 패널

    @ViewBuilder
    private var detailPane: some View {
        if let message = model.message {
            VStack {
                Spacer()
                Label(message, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Theme.green)
                    .multilineTextAlignment(.center)
                    .padding()
                Button("확인") { model.message = nil }
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else if let app = model.selectedApp {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 14) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: app.resolvedURL.path))
                        .resizable()
                        .frame(width: 52, height: 52)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(app.name).font(.system(size: 20, weight: .bold, design: .rounded))
                        Text(app.bundleID ?? "번들 ID 없음")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            if app.size > 0 {
                                Text("앱 \(Format.bytes(app.size))")
                            } else {
                                Text(LocalizedStringKey(Format.unknownSize))
                            }
                            let relatedSize = model.relatedFiles.reduce(0) { $0 + $1.size }
                            if relatedSize > 0 {
                                Text("+ 관련 파일 \(Format.bytes(relatedSize))")
                                    .foregroundStyle(Theme.orange)
                            }
                        }
                        .font(.callout)
                    }
                    Spacer()
                }
                .padding(16)
                Divider().opacity(0.3)

                if model.findingRelated {
                    Spacer()
                    VStack(spacing: 10) {
                        ProgressView("관련 파일을 찾는 중…")
                        ScanDelayNotice()
                    }
                    .frame(maxWidth: .infinity)
                    Spacer()
                } else {
                    List($model.relatedFiles) { $file in
                        HStack {
                            Toggle(isOn: $file.selected) { EmptyView() }
                                .toggleStyle(.checkbox)
                                .labelsHidden()
                            Image(nsImage: NSWorkspace.shared.icon(forFile: file.url.path))
                                .resizable()
                                .frame(width: 22, height: 22)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(file.displayPath)
                                    .font(.system(.callout, design: .monospaced))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Text(LocalizedStringKey(file.kind))
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            Spacer()
                            Text(Format.bytes(file.size))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .overlay {
                        if model.relatedFiles.isEmpty {
                            Text("관련 파일이 발견되지 않았습니다")
                                .foregroundStyle(.secondary)
                        }
                    }

                    Divider().opacity(0.3)
                    HStack {
                        Button {
                            model.reset()
                        } label: {
                            Label("재설정 (관련 파일만 정리)", systemImage: "arrow.counterclockwise")
                        }
                        .disabled(model.relatedFiles.filter(\.selected).isEmpty)
                        .featureLocked()
                        Spacer()
                        Button(role: .destructive) {
                            confirmingUninstall = true
                        } label: {
                            Label("완전 삭제", systemImage: "trash")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.red)
                        .featureLocked()
                    }
                    .padding(12)
                }
            }
        } else {
            summaryDashboard
        }
    }

    // MARK: 미선택 시 요약 대시보드

    private var summaryDashboard: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("왼쪽 목록에서 앱을 선택하세요")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 18)

                HStack(spacing: 12) {
                    statTile(value: String(format: NSLocalizedString("%lld개", comment: ""), model.apps.count), label: "설치된 앱", color: Theme.blue)
                    statTile(value: Format.bytes(model.totalSize), label: "총 용량", color: Theme.teal)
                    statTile(
                        value: String(format: NSLocalizedString("%lld개", comment: ""), model.unusedCount),
                        label: model.unusedSize > 0
                            ? "6개월+ 미사용 (\(Format.bytes(model.unusedSize)))"
                            : "6개월+ 미사용",
                        color: Theme.orange
                    )
                }

                if !model.topApps.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("용량 상위 앱")
                            .font(.headline)
                        ForEach(model.topApps) { app in
                            HStack {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: app.resolvedURL.path))
                                    .resizable()
                                    .frame(width: 22, height: 22)
                                Text(app.name)
                                    .font(.callout)
                                Spacer()
                                Text(Format.bytes(app.size))
                                    .font(.callout)
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                            SmoothBar(
                                value: Double(app.size) / Double(max(model.topApps.first?.size ?? 1, 1)),
                                color: Theme.blue, height: 5
                            )
                        }
                    }
                    .card()
                }
            }
            .padding(16)
        }
    }

    private func statTile(value: String, label: LocalizedStringKey, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 12)
    }

    // MARK: 잔여 파일 뷰

    private var orphansView: some View {
        VStack(spacing: 0) {
            if model.scanningOrphans {
                Spacer()
                VStack(spacing: 10) {
                    ProgressView("설치된 앱이 없는 잔여 파일을 찾는 중…")
                    ScanDelayNotice()
                }
                Spacer()
            } else if model.orphans.isEmpty {
                EmptyStateView(
                    icon: "checkmark.seal.fill",
                    title: "잔여 파일이 없습니다 — 깨끗합니다!",
                    message: "고립된 설정 파일이나 캐시가 발견되지 않았습니다.",
                    actionTitle: "다시 스캔",
                    action: { model.scanOrphans() },
                    tint: Theme.green
                )
            } else {
                HStack {
                    let total = model.orphans.reduce(0) { $0 + $1.size }
                    Text("삭제된 앱이 남긴 것으로 보이는 항목 \(model.orphans.count)개 · \(Format.bytes(total))")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("⚠︎ 목록을 확인 후 선택하세요 — CLI 도구의 데이터일 수도 있습니다")
                        .font(.caption)
                        .foregroundStyle(Theme.yellow)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 10)

                List($model.orphans) { $orphan in
                    HStack {
                        Toggle(isOn: $orphan.selected) { EmptyView() }
                            .toggleStyle(.checkbox)
                            .labelsHidden()
                        Image(nsImage: NSWorkspace.shared.icon(forFile: orphan.url.path))
                            .resizable()
                            .frame(width: 24, height: 24)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(orphan.bundleID)
                                .font(.system(.callout, design: .monospaced))
                            Text(orphan.displayPath)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        Text(Format.bytes(orphan.size))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([orphan.url])
                        } label: {
                            Image(systemName: "magnifyingglass.circle")
                        }
                        .buttonStyle(.plain)
                        .help("Finder에서 보기")
                    }
                }
                .scrollContentBackground(.hidden)

                Divider().opacity(0.3)
                HStack {
                    Button {
                        model.scanOrphans()
                    } label: {
                        Label("다시 스캔", systemImage: "arrow.clockwise")
                    }
                    Spacer()
                    let selectedSize = model.orphans.filter(\.selected).reduce(0) { $0 + $1.size }
                    Button {
                        model.trashSelectedOrphans()
                    } label: {
                        Label("선택 항목 휴지통으로 (\(Format.bytes(selectedSize)))", systemImage: "trash")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.orange)
                    .disabled(model.orphans.filter(\.selected).isEmpty)
                    .featureLocked()
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
            }
        }
    }
}
