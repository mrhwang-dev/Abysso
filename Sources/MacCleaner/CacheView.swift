import SwiftUI

// MARK: - 모델

struct CacheItem: Identifiable {
    let id = UUID()
    let name: String
    let url: URL
    let size: Int64
    var selected = false
}

struct CacheCategory: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String       // 안전성 설명
    let icon: String
    let tint: Color
    var items: [CacheItem]

    var totalSize: Int64 { items.reduce(0) { $0 + $1.size } }
    var selectedSize: Int64 { items.filter(\.selected).reduce(0) { $0 + $1.size } }
}

private struct CategorySpec {
    let title: String
    let subtitle: String
    let icon: String
    let tint: Color
}

@MainActor
final class CacheModel: ObservableObject {
    @Published var categories: [CacheCategory] = []
    @Published var scanning = false
    @Published var scanned = false
    @Published var progress: Double = 0
    @Published var progressLabel = ""
    @Published var cleaning = false
    @Published var lastCleaned: Int64?

    var selectedSize: Int64 { categories.reduce(0) { $0 + $1.selectedSize } }
    var selectedCount: Int { categories.reduce(0) { $0 + $1.items.filter(\.selected).count } }
    var totalFound: Int64 { categories.reduce(0) { $0 + $1.totalSize } }

    func scan() {
        scanning = true
        scanned = false
        progress = 0
        lastCleaned = nil
        categories = []

        Task.detached(priority: .userInitiated) {
            let home = FileManager.default.homeDirectoryForCurrentUser
            let fm = FileManager.default
            var result: [CacheCategory] = []
            let steps = 5.0

            func report(_ step: Double, _ label: String) async {
                await MainActor.run {
                    self.progress = step / steps
                    self.progressLabel = label
                }
            }

            // 1. 앱 캐시
            await report(0, "앱 캐시 스캔 중…")
            var appCaches: [CacheItem] = []
            let cachesDir = home.appendingPathComponent("Library/Caches")
            let browserPrefixes = ["Google", "com.apple.Safari", "Firefox", "com.microsoft.edgemac", "company.thebrowser"]
            if let subdirs = try? fm.contentsOfDirectory(
                at: cachesDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
            ) {
                for dir in subdirs {
                    let name = dir.lastPathComponent
                    guard !browserPrefixes.contains(where: { name.hasPrefix($0) }) else { continue }
                    let size = DiskUtil.itemSize(dir)
                    if size > 1_000_000 {
                        appCaches.append(CacheItem(name: name, url: dir, size: size))
                    }
                }
            }
            appCaches.sort { $0.size > $1.size }
            result.append(CacheCategory(
                title: "앱 캐시",
                subtitle: "지워도 안전한 파일 — 앱이 필요하면 다시 생성합니다",
                icon: "shippingbox.fill", tint: Theme.teal,
                items: Array(appCaches.prefix(30))
            ))

            // 2. 브라우저 캐시
            await report(1, "브라우저 캐시 스캔 중…")
            var browserItems: [CacheItem] = []
            let browserPaths: [(String, String)] = [
                ("Chrome", "Library/Caches/Google/Chrome"),
                ("Safari", "Library/Caches/com.apple.Safari"),
                ("Firefox", "Library/Caches/Firefox"),
                ("Edge", "Library/Caches/com.microsoft.edgemac"),
                ("Arc", "Library/Caches/company.thebrowser.Browser"),
            ]
            for (name, path) in browserPaths {
                let url = home.appendingPathComponent(path)
                guard fm.fileExists(atPath: url.path) else { continue }
                let size = DiskUtil.itemSize(url)
                if size > 500_000 {
                    browserItems.append(CacheItem(name: "\(name) 캐시", url: url, size: size))
                }
            }
            result.append(CacheCategory(
                title: "브라우저 캐시",
                subtitle: "웹페이지 이미지·스크립트 임시 사본 — 다시 다운로드됩니다",
                icon: "safari.fill", tint: Theme.blue,
                items: browserItems
            ))

            // 3. 로그 파일
            await report(2, "로그 파일 스캔 중…")
            var logItems: [CacheItem] = []
            let logsDir = home.appendingPathComponent("Library/Logs")
            if let subdirs = try? fm.contentsOfDirectory(
                at: logsDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
            ) {
                for dir in subdirs {
                    let size = DiskUtil.itemSize(dir)
                    if size > 100_000 {
                        logItems.append(CacheItem(name: dir.lastPathComponent, url: dir, size: size))
                    }
                }
            }
            logItems.sort { $0.size > $1.size }
            result.append(CacheCategory(
                title: "앱 로그 파일",
                subtitle: "앱 진단 기록 — 문제 해결 중이 아니라면 지워도 됩니다",
                icon: "doc.text.fill", tint: Theme.yellow,
                items: Array(logItems.prefix(20))
            ))

            // 4. 개발자 캐시
            await report(3, "개발자 캐시 스캔 중…")
            var devItems: [CacheItem] = []
            let devPaths: [(String, String)] = [
                ("Xcode DerivedData", "Library/Developer/Xcode/DerivedData"),
                ("Xcode 기기 지원", "Library/Developer/Xcode/iOS DeviceSupport"),
                ("npm 캐시", ".npm/_cacache"),
                ("yarn 캐시", "Library/Caches/Yarn"),
                ("CocoaPods", "Library/Caches/CocoaPods"),
                ("Homebrew", "Library/Caches/Homebrew"),
                ("pip", "Library/Caches/pip"),
                ("Gradle", ".gradle/caches"),
                ("Cargo 레지스트리", ".cargo/registry/cache"),
            ]
            for (name, path) in devPaths {
                let url = home.appendingPathComponent(path)
                guard fm.fileExists(atPath: url.path) else { continue }
                let size = DiskUtil.itemSize(url)
                if size > 1_000_000 {
                    devItems.append(CacheItem(name: name, url: url, size: size))
                }
            }
            devItems.sort { $0.size > $1.size }
            result.append(CacheCategory(
                title: "개발 도구 캐시",
                subtitle: "빌드 산출물과 패키지 캐시 — 다음 빌드가 조금 느려질 수 있습니다",
                icon: "hammer.fill", tint: Theme.purple,
                items: devItems
            ))

            // 5. 불완전한 다운로드
            await report(4, "불완전한 다운로드 스캔 중…")
            var brokenItems: [CacheItem] = []
            let downloadExts = ["download", "crdownload", "part", "partial", "opdownload"]
            let downloads = home.appendingPathComponent("Downloads")
            if let items = try? fm.contentsOfDirectory(
                at: downloads, includingPropertiesForKeys: nil
            ) {
                for url in items where downloadExts.contains(url.pathExtension.lowercased()) {
                    brokenItems.append(CacheItem(
                        name: url.lastPathComponent, url: url, size: DiskUtil.itemSize(url)
                    ))
                }
            }
            result.append(CacheCategory(
                title: "깨진 다운로드",
                subtitle: "중단된 다운로드 찌꺼기 — 완전히 안전하게 삭제 가능",
                icon: "arrow.down.circle.dotted", tint: Theme.red,
                items: brokenItems
            ))

            await report(5, "완료")
            let final = result
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.4)) {
                    self.categories = final
                    self.scanning = false
                    self.scanned = true
                }
            }
        }
    }

    func clean() {
        cleaning = true
        let targets = categories.flatMap { $0.items.filter(\.selected) }
        Task.detached(priority: .userInitiated) {
            var freed: Int64 = 0
            for item in targets where DiskUtil.trash(item.url) {
                freed += item.size
            }
            let freedFinal = freed
            await MainActor.run {
                self.cleaning = false
                self.lastCleaned = freedFinal
                self.scan()
            }
        }
    }

    func toggleAll(in categoryID: UUID, to value: Bool) {
        guard let ci = categories.firstIndex(where: { $0.id == categoryID }) else { return }
        for ii in categories[ci].items.indices {
            categories[ci].items[ii].selected = value
        }
    }
}

// MARK: - 메인 뷰

struct CacheView: View {
    @EnvironmentObject private var model: CacheModel
    @State private var browsing: URL?

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(
                title: "스마트 정리",
                subtitle: "캐시·로그·불필요한 파일을 안전하게 정리합니다 (휴지통으로 이동)",
                icon: "sparkles", iconColor: Theme.teal
            )
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 12)

            if model.scanning {
                scanningView
            } else if !model.scanned {
                emptyStartView
            } else {
                resultList
            }

            Divider().opacity(0.3)
            bottomBar
        }
        .background(Theme.background)
        .sheet(item: Binding(
            get: { browsing.map { BrowseTarget(url: $0) } },
            set: { browsing = $0?.url }
        )) { target in
            FolderBrowserSheet(root: target.url)
        }
    }

    private struct BrowseTarget: Identifiable {
        let url: URL
        var id: String { url.path }
    }

    // MARK: 스캔 중

    private var scanningView: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "sparkle.magnifyingglass")
                .font(.system(size: 44))
                .foregroundStyle(Theme.accentGradient)
                .symbolEffect(.pulse, options: .repeating)
            Text(model.progressLabel)
                .font(.headline)
            ProgressView(value: model.progress)
                .progressViewStyle(.linear)
                .frame(width: 320)
                .tint(Theme.teal)
            Spacer()
        }
    }

    // MARK: 시작 전 화면

    private var emptyStartView: some View {
        ZStack {
            ParticleField()
            VStack(spacing: 16) {
                Spacer()
                Image(systemName: "sparkles")
                    .font(.system(size: 56))
                    .foregroundStyle(Theme.accentGradient)
                    .symbolEffect(.pulse.byLayer, options: .repeating)
                Text("Mac을 가볍게 만들 준비가 되셨나요?")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                Text("캐시, 로그, 깨진 다운로드를 스캔해서 안전하게 정리할 수 있는\n공간을 찾아드립니다. 모든 삭제는 휴지통을 거치므로 복구할 수 있어요.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                PulsingGlow(color: Theme.teal) {
                    ProminentScanButton(title: "스마트 스캔 시작", systemImage: "sparkle.magnifyingglass") {
                        model.scan()
                    }
                }
                .padding(.top, 6)
                Spacer()
            }
        }
    }

    // MARK: 결과 목록

    private var resultList: some View {
        ScrollView {
            VStack(spacing: 14) {
                // 요약 배너
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("정리 가능한 공간")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Text(Format.bytes(model.totalFound))
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.accentGradient)
                            .monospacedDigit()
                    }
                    Spacer()
                    if let cleaned = model.lastCleaned {
                        Label("\(Format.bytes(cleaned)) 를 휴지통으로 옮겼습니다", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(Theme.green)
                    }
                }
                .card(padding: 18)

                ForEach($model.categories) { $category in
                    CategoryCard(category: $category, model: model) { url in
                        browsing = url
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
    }

    // MARK: 하단 바

    private var bottomBar: some View {
        HStack {
            if model.scanned {
                Text("\(model.selectedCount)개 항목 선택됨")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
            Spacer()
            if model.scanned {
                Button {
                    model.scan()
                } label: {
                    Label("다시 스캔", systemImage: "arrow.clockwise")
                }
                .disabled(model.scanning || model.cleaning)

                Button {
                    model.clean()
                } label: {
                    if model.cleaning {
                        ProgressView().controlSize(.small)
                    } else {
                        Label(
                            model.selectedCount == 0
                                ? "선택 항목 없음"
                                : "정리 (\(Format.bytes(model.selectedSize)))",
                            systemImage: "sparkles"
                        )
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.teal)
                .disabled(model.selectedCount == 0 || model.cleaning)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }
}

// MARK: - 카테고리 카드

private struct CategoryCard: View {
    @Binding var category: CacheCategory
    let model: CacheModel
    let onBrowse: (URL) -> Void
    @State private var expanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 헤더
            HStack(spacing: 12) {
                Image(systemName: category.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(category.tint)
                    .frame(width: 38, height: 38)
                    .background(category.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    Text(category.title)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    Text(category.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if category.items.isEmpty {
                    Text("정리할 것 없음 ✓")
                        .font(.callout)
                        .foregroundStyle(Theme.green)
                } else {
                    Text(Format.bytes(category.totalSize))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Button("전체 선택") {
                        model.toggleAll(in: category.id, to: true)
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
                    } label: {
                        Image(systemName: "chevron.down")
                            .rotationEffect(.degrees(expanded ? 0 : -90))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }

            // 항목 목록
            if expanded && !category.items.isEmpty {
                Divider().padding(.vertical, 10).opacity(0.3)
                VStack(spacing: 6) {
                    ForEach($category.items) { $item in
                        HStack {
                            Toggle(isOn: $item.selected) {
                                Text(item.name)
                                    .lineLimit(1)
                            }
                            .toggleStyle(.checkbox)
                            Button {
                                onBrowse(item.url)
                            } label: {
                                Image(systemName: "folder")
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.tertiary)
                            .help("내용 살펴보기")
                            Spacer()
                            Text(Format.bytes(item.size))
                                .foregroundStyle(.secondary)
                                .font(.callout)
                                .monospacedDigit()
                        }
                    }
                }
            }
        }
        .card()
    }
}

// MARK: - 폴더 드릴다운 시트

struct FolderEntry: Identifiable {
    let id = UUID()
    let url: URL
    let size: Int64
    let isDirectory: Bool
    var selected = false
}

struct FolderBrowserSheet: View {
    let root: URL
    @Environment(\.dismiss) private var dismiss
    @State private var stack: [URL] = []
    @State private var entries: [FolderEntry] = []
    @State private var loading = false

    private var current: URL { stack.last ?? root }

    var body: some View {
        VStack(spacing: 0) {
            // 브레드크럼
            HStack {
                Button {
                    if stack.isEmpty { dismiss() } else { stack.removeLast(); load() }
                } label: {
                    Image(systemName: stack.isEmpty ? "xmark" : "chevron.left")
                }
                Text(displayPath(current))
                    .font(.system(.callout, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.head)
                Spacer()
                Button("닫기") { dismiss() }
            }
            .padding(14)
            Divider()

            if loading {
                Spacer()
                ProgressView()
                Spacer()
            } else if entries.isEmpty {
                Spacer()
                Text("빈 폴더입니다")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                List($entries) { $entry in
                    HStack {
                        Toggle(isOn: $entry.selected) { EmptyView() }
                            .toggleStyle(.checkbox)
                            .labelsHidden()
                        Image(systemName: entry.isDirectory ? "folder.fill" : "doc")
                            .foregroundStyle(entry.isDirectory ? Theme.blue : .secondary)
                        if entry.isDirectory {
                            Button(entry.url.lastPathComponent) {
                                stack.append(entry.url)
                                load()
                            }
                            .buttonStyle(.link)
                        } else {
                            Text(entry.url.lastPathComponent)
                        }
                        Spacer()
                        Text(Format.bytes(entry.size))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .scrollContentBackground(.hidden)
            }

            Divider()
            HStack {
                let selected = entries.filter(\.selected)
                let selectedSize = selected.reduce(0) { $0 + $1.size }
                Spacer()
                Button {
                    for entry in selected { DiskUtil.trash(entry.url) }
                    load()
                } label: {
                    Label(
                        selected.isEmpty
                            ? "선택 항목 없음"
                            : "선택 항목 휴지통으로 (\(Format.bytes(selectedSize)))",
                        systemImage: "trash"
                    )
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.orange)
                .disabled(selected.isEmpty)
            }
            .padding(12)
        }
        .frame(width: 560, height: 480)
        .background(Theme.bgTop)
        .onAppear { load() }
    }

    private func displayPath(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return url.path.replacingOccurrences(of: home, with: "~")
    }

    private func load() {
        loading = true
        let target = current
        Task.detached(priority: .userInitiated) {
            var found: [FolderEntry] = []
            if let items = try? FileManager.default.contentsOfDirectory(
                at: target, includingPropertiesForKeys: [.isDirectoryKey]
            ) {
                for url in items {
                    let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                    found.append(FolderEntry(url: url, size: DiskUtil.itemSize(url), isDirectory: isDir))
                }
            }
            found.sort { $0.size > $1.size }
            let result = found
            await MainActor.run {
                entries = result
                loading = false
            }
        }
    }
}
