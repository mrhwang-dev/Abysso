import SwiftUI
import AppKit

// MARK: - 모델

/// 항목을 지워도 되는지 한눈에 알려주는 안전도 등급
enum CacheSafety {
    /// 지워도 안전 — 필요하면 앱이 다시 만든다
    case safe
    /// 삭제 가능하지만 확인 권장 — 앱이 실행 중이거나 다시 만드는 비용이 크다
    case caution

    var label: String {
        switch self {
        case .safe: return NSLocalizedString("삭제 권장", comment: "")
        case .caution: return NSLocalizedString("주의", comment: "")
        }
    }

    var tint: Color { self == .safe ? Theme.green : Theme.yellow }
    var icon: String { self == .safe ? "checkmark.shield.fill" : "exclamationmark.triangle.fill" }

    var help: String {
        switch self {
        case .safe:
            return NSLocalizedString("지워도 안전합니다 — 필요하면 앱이 다시 생성합니다", comment: "")
        case .caution:
            return NSLocalizedString("삭제해도 되지만 앱이 실행 중이거나 다시 만드는 데 시간이 걸릴 수 있습니다 — 확인 후 삭제하세요", comment: "")
        }
    }
}

struct CacheItem: Identifiable {
    let id = UUID()
    let name: String
    let url: URL
    let size: Int64
    var selected = false
    var icon: NSImage?
    var safety: CacheSafety = .safe
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
    @Published var remainingTimeText: String?
    @Published var cleaning = false
    @Published var lastCleaned: Int64?
    
    private var timeEstimator: TimeEstimator?

    var selectedSize: Int64 { categories.reduce(0) { $0 + $1.selectedSize } }
    var selectedCount: Int { categories.reduce(0) { $0 + $1.items.filter(\.selected).count } }
    var totalFound: Int64 { categories.reduce(0) { $0 + $1.totalSize } }

    func scan() {
        scanning = true
        scanned = false
        progress = 0
        lastCleaned = nil
        categories = []
        timeEstimator = TimeEstimator()
        remainingTimeText = nil

        // 실행 중인 앱의 캐시는 '주의'로 표시하기 위해 스캔 시점의 실행 목록을 캡처
        let runningBundleIDs = Set(
            NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
        )

        Task.detached(priority: .userInitiated) {
            let home = FileManager.default.homeDirectoryForCurrentUser
            let fm = FileManager.default
            var result: [CacheCategory] = []
            let steps = 5.0

            func report(_ step: Double, _ label: String) async {
                await MainActor.run {
                    self.progress = step / steps
                    self.progressLabel = label
                    if let estimator = self.timeEstimator {
                        self.remainingTimeText = estimator.remainingTimeText(progress: self.progress)
                    }
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
                appCaches = await withTaskGroup(of: CacheItem?.self) { group in
                    for dir in subdirs {
                        group.addTask {
                            let name = dir.lastPathComponent
                            guard !browserPrefixes.contains(where: { name.hasPrefix($0) }) else { return nil }
                            let size = DiskUtil.itemSize(dir)
                            if size > 1_000_000 {
                                let displayName: String
                                var icon: NSImage?
                                if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: name) {
                                    // 설치된 앱: Finder에 표시되는 (현지화된) 앱 이름 사용
                                    displayName = FileManager.default.displayName(atPath: appURL.path)
                                    icon = NSWorkspace.shared.icon(forFile: appURL.path)
                                } else {
                                    // 앱을 못 찾은 번들 ID는 읽기 쉬운 이름으로 변환
                                    displayName = Self.humanizeBundleID(name)
                                    icon = NSWorkspace.shared.icon(forFile: dir.path)
                                }
                                // 실행 중인 앱의 캐시는 삭제해도 되지만 곧바로 다시 생기고
                                // 드물게 앱 동작에 영향을 줄 수 있어 '주의'로 표시한다.
                                let safety: CacheSafety = runningBundleIDs.contains(name) ? .caution : .safe
                                return CacheItem(name: displayName, url: dir, size: size, icon: icon, safety: safety)
                            }
                            return nil
                        }
                    }
                    var items: [CacheItem] = []
                    for await item in group {
                        if let item { items.append(item) }
                    }
                    return items
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
            // Safari는 샌드박스 앱이라 실제 캐시가 컨테이너 내부에 쌓인다 — 두 경로 모두 스캔
            let browserPaths: [(String, String)] = [
                ("Chrome", "Library/Caches/Google/Chrome"),
                ("Safari", "Library/Caches/com.apple.Safari"),
                ("Safari 샌드박스", "Library/Containers/com.apple.Safari/Data/Library/Caches"),
                ("Firefox", "Library/Caches/Firefox"),
                ("Edge", "Library/Caches/com.microsoft.edgemac"),
                ("Arc", "Library/Caches/company.thebrowser.Browser"),
            ]
            browserItems = await withTaskGroup(of: CacheItem?.self) { group in
                for (name, path) in browserPaths {
                    group.addTask {
                        let url = home.appendingPathComponent(path)
                        guard fm.fileExists(atPath: url.path) else { return nil }
                        let size = DiskUtil.itemSize(url)
                        if size > 500_000 {
                            // 브라우저별 "Chrome 캐시" 등은 Localizable.strings에 개별 키가 있어
                            // LocalizedStringKey 표시 시 자동 번역된다.
                            return CacheItem(name: "\(name) 캐시", url: url, size: size)
                        }
                        return nil
                    }
                }
                var items: [CacheItem] = []
                for await item in group {
                    if let item { items.append(item) }
                }
                return items
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
                logItems = await withTaskGroup(of: CacheItem?.self) { group in
                    for dir in subdirs {
                        group.addTask {
                            let size = DiskUtil.itemSize(dir)
                            if size > 100_000 {
                                return CacheItem(name: dir.lastPathComponent, url: dir, size: size)
                            }
                            return nil
                        }
                    }
                    var items: [CacheItem] = []
                    for await item in group {
                        if let item { items.append(item) }
                    }
                    return items
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
            devItems = await withTaskGroup(of: CacheItem?.self) { group in
                for (name, path) in devPaths {
                    group.addTask {
                        let url = home.appendingPathComponent(path)
                        guard fm.fileExists(atPath: url.path) else { return nil }
                        let size = DiskUtil.itemSize(url)
                        if size > 1_000_000 {
                            // 지워도 문제는 없지만 다음 빌드/설치가 느려지므로 '주의'
                            return CacheItem(name: name, url: url, size: size, safety: .caution)
                        }
                        return nil
                    }
                }
                var items: [CacheItem] = []
                for await item in group {
                    if let item { items.append(item) }
                }
                return items
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
            // FDA가 없으면 다운로드 폴더 접근이 시스템 권한 팝업을 띄우므로 조용히 건너뛴다
            if Permissions.hasFullDiskAccess(), let items = try? fm.contentsOfDirectory(
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
            #if DEBUG
            // 테스트 모드: 샌드박스 더미 데이터를 별도 카테고리로 추가
            if DevMode.sandboxScanEnabled, DevMode.sandboxExists {
                result.append(Self.sandboxCategory())
            }
            #endif
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

    // MARK: 전체 선택 (모든 카테고리 일괄)

    /// 스캔된 모든 항목이 선택된 상태인지 (항목이 없으면 false)
    var allSelected: Bool {
        let total = categories.reduce(0) { $0 + $1.items.count }
        return total > 0 && selectedCount == total
    }

    /// 모든 카테고리의 모든 항목을 한 번에 선택/해제
    func toggleAllItems(_ value: Bool) {
        for ci in categories.indices {
            for ii in categories[ci].items.indices {
                categories[ci].items[ii].selected = value
            }
        }
    }

    // MARK: 번들 ID → 표시 이름

    /// 규칙 변환으로는 이상하게 나오는 유명 번들 ID의 실제 앱 이름 사전.
    /// (설치돼 있으면 NSWorkspace가 우선하므로, 여기는 삭제된 앱의 잔여 캐시용 폴백)
    nonisolated static let knownAppNames: [String: String] = [
        "com.apple.dt.xcode": "Xcode",
        "com.googlecode.iterm2": "iTerm2",
        "com.tinyspeck.slackmacgap": "Slack",
        "com.hnc.discord": "Discord",
        "us.zoom.xos": "Zoom",
        "com.microsoft.vscode": "Visual Studio Code",
        "com.todesktop.230313mzl4w4u92": "Cursor",
        "md.obsidian": "Obsidian",
        "com.spotify.client": "Spotify",
        "org.mozilla.firefox": "Firefox",
        "com.google.chrome": "Google Chrome",
        "com.brave.browser": "Brave Browser",
        "com.microsoft.edgemac": "Microsoft Edge",
        "company.thebrowser.browser": "Arc",
        "com.kakao.kakaotalkmac": "카카오톡",
        "com.nhn.works.mac": "네이버웍스",
        "notion.id": "Notion",
        "com.figma.desktop": "Figma",
        "com.postmanlabs.mac": "Postman",
        "com.docker.docker": "Docker",
        "com.jetbrains.intellij": "IntelliJ IDEA",
        "com.sublimetext.4": "Sublime Text",
        "com.readdle.smartemail-macos": "Spark",
        "ru.keepcoder.telegram": "Telegram",
        "net.whatsapp.whatsapp": "WhatsApp",
        "com.openai.chat": "ChatGPT",
        "com.anthropic.claudefordesktop": "Claude",
        // 개발 도구·시스템 데몬 — 규칙 변환으로는 "Swift Swiftpm"·"Apple Helpd"처럼
        // 어색하게 나오는 대표 케이스를 사람이 읽기 좋은 이름으로 고정한다.
        "org.swift.swiftpm": "Swift Package Manager",
        "com.apple.helpd": "macOS Help",
        "com.apple.parsecd": "Siri Suggestions",
        "com.apple.akd": "Apple Account (AuthKit)",
        "com.apple.amsengagementd": "Apple Media Services",
        "com.apple.geod": "Apple Maps",
    ]

    /// 단어만으로는 앱을 특정하지 못하는 군더더기 접미어 — 이름 끝에 오면 잘라낸다.
    /// (com.spotify.client → "Spotify Client" 대신 "Spotify")
    nonisolated private static let genericSuffixes: Set<String> = [
        "client", "desktop", "app", "mac", "macos", "gap", "osx", "x",
    ]

    /// 번들 ID 형태의 캐시 폴더명을 사용자가 알아볼 수 있는 실제 앱 이름으로 변환한다.
    /// 1) 알려진 앱 사전에서 먼저 찾고
    /// 2) 없으면 역방향 DNS를 단어로 풀어 사람이 읽는 이름을 만든다
    ///    (com.apple.AppleMediaServices → "Apple Media Services").
    /// 역방향 DNS 형태가 아니면 그대로 반환한다.
    nonisolated static func humanizeBundleID(_ folderName: String) -> String {
        if let known = knownAppNames[folderName.lowercased()] { return known }

        let tlds: Set<String> = [
            "com", "org", "net", "io", "co", "app", "dev", "me", "us",
            "kr", "jp", "cn", "de", "fr", "uk", "ru", "tv", "gg", "sh", "ai", "so", "md",
        ]
        let parts = folderName.split(separator: ".").map(String.init)
        guard parts.count >= 2, tlds.contains(parts[0].lowercased()) else { return folderName }

        var words: [String] = []
        for component in parts.dropFirst() {
            for word in splitWords(component) {
                var w = word
                // 전부 소문자인 단어만 첫 글자를 대문자로 (iTunes 같은 브랜드 표기는 유지)
                if w.allSatisfy({ $0.isLowercase || $0.isNumber }), let first = w.first {
                    w = first.uppercased() + w.dropFirst()
                }
                // 벤더명이 앱 이름과 겹치면 중복을 정리한다.
                if let last = words.last {
                    let lw = last.lowercased(), ww = w.lowercased()
                    // 완전히 같으면 한 번만 (apple.AppleMediaServices → "Apple Media Services")
                    if lw == ww { continue }
                    // 한쪽이 다른 쪽의 접두어면 더 긴 쪽만 남긴다
                    // (swift.swiftpm → "Swift Swiftpm" 대신 "Swiftpm"). 짧은 조각의
                    // 우연한 일치를 막기 위해 최소 4글자 이상일 때만 적용한다.
                    if min(lw.count, ww.count) >= 4 {
                        if ww.hasPrefix(lw) { words[words.count - 1] = w; continue }
                        if lw.hasPrefix(ww) { continue }
                    }
                }
                words.append(w)
            }
        }
        // 끝에 붙는 군더더기 접미어 제거 — 단, 한 단어만 남을 때까지는 지우지 않는다
        while words.count > 1, let last = words.last, genericSuffixes.contains(last.lowercased()) {
            words.removeLast()
        }
        return words.isEmpty ? folderName : words.joined(separator: " ")
    }

    /// camelCase·하이픈·언더스코어 경계로 단어를 나눈다 ("AppleMediaServices" → Apple / Media / Services).
    nonisolated private static func splitWords(_ s: String) -> [String] {
        var spaced = ""
        var wordLen = 0  // 현재 단어에 쌓인 글자 수 (소문자 한 글자 접두 판별용)
        let chars = Array(s)
        for i in chars.indices {
            let c = chars[i]
            if c == "-" || c == "_" {
                spaced.append(" ")
                wordLen = 0
                continue
            }
            if c.isUppercase, i > 0 {
                let prev = chars[i - 1]
                let nextIsLower = i + 1 < chars.count && chars[i + 1].isLowercase
                // 소문자 한 글자 접두(iTunes, iCloud 등)는 붙여 둔다
                let shouldSplit = (prev.isLowercase && wordLen > 1) || prev.isNumber
                    || (prev.isUppercase && nextIsLower)
                if shouldSplit {
                    spaced.append(" ")
                    wordLen = 0
                }
            }
            spaced.append(c)
            wordLen += 1
        }
        return spaced.split(separator: " ").map(String.init)
    }

    #if DEBUG
    /// 샌드박스(/tmp/AbyssoTestSandbox) 최상위 항목을 정리 카테고리로 노출한다.
    nonisolated static func sandboxCategory() -> CacheCategory {
        let root = URL(fileURLWithPath: DevMode.sandboxRoot)
        var items: [CacheItem] = []
        if let entries = try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) {
            for url in entries {
                let size = DiskUtil.itemSize(url)
                if size > 100_000 {
                    items.append(CacheItem(name: url.lastPathComponent, url: url, size: size))
                }
            }
        }
        items.sort { $0.size > $1.size }
        return CacheCategory(
            title: "🧪 테스트 샌드박스",
            subtitle: "개발자 테스트용 더미 데이터 — /tmp/AbyssoTestSandbox (삭제는 이 폴더 내부만)",
            icon: "testtube.2", tint: Theme.purple,
            items: items
        )
    }
    #endif
}

// MARK: - 메인 뷰

struct CacheView: View {
    /// 스마트 정리 탭 내부 구획 — 캐시 정리 / 개인정보 보호(구 '보안' 섹션에서 병합)
    private enum Section: Int { case cache, privacy }

    @EnvironmentObject private var model: CacheModel
    @State private var browsing: URL?
    @State private var section: Section = .cache

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(
                title: "스마트 정리",
                subtitle: section == .cache
                    ? "캐시·로그·불필요한 파일을 안전하게 정리합니다 (휴지통으로 이동)"
                    : "브라우저 방문 기록·쿠키와 최근 사용 항목 흔적을 정리합니다",
                icon: "sparkles", iconColor: Theme.teal
            )
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 10)

            // 캐시 정리 ↔ 개인정보 보호 전환
            Picker("", selection: $section) {
                Label("캐시 정리", systemImage: "sparkles").tag(Section.cache)
                Label("개인정보 보호", systemImage: "hand.raised.fill").tag(Section.privacy)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 380)
            .padding(.horizontal, 24)
            .padding(.bottom, 10)

            if section == .privacy {
                PrivacyView()
            } else {
                cacheContent
            }
        }
        .background(Theme.background)
        .animation(.easeInOut(duration: 0.2), value: section)
        .sheet(item: Binding(
            get: { browsing.map { BrowseTarget(url: $0) } },
            set: { browsing = $0?.url }
        )) { target in
            FolderBrowserSheet(root: target.url)
        }
    }

    @ViewBuilder
    private var cacheContent: some View {
        Group {
            if model.scanning {
                scanningView
            } else if !model.scanned {
                emptyStartView
            } else if model.categories.isEmpty {
                EmptyStateView(
                    icon: "checkmark.circle.fill",
                    title: "정리할 캐시가 없습니다",
                    message: "현재 시스템은 깨끗한 상태입니다.",
                    actionTitle: "다시 스캔",
                    action: { model.scan() },
                    tint: Theme.green
                )
            } else {
                resultList
            }
        }

        Divider().opacity(0.3)
        bottomBar
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
            VStack(spacing: 4) {
                Text(LocalizedStringKey(model.progressLabel))
                    .font(.headline)
                if let remaining = model.remainingTimeText {
                    Text(remaining)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            ProgressView(value: model.progress)
                .progressViewStyle(.linear)
                .frame(width: 320)
                .tint(Theme.teal)
            // 스캔이 길어지면 경과 시간과 지연 사유를 알려준다
            ScanDelayNotice()
            Spacer()
        }
    }

    // MARK: 시작 전 화면

    private var emptyStartView: some View {
        EmptyStatePane(
            icon: "sparkles",
            iconStyle: AnyShapeStyle(Theme.accentGradient),
            title: "Mac을 가볍게 만들 준비가 되셨나요?",
            message: "캐시, 로그, 깨진 다운로드를 스캔해서 안전하게 정리할 수 있는\n공간을 찾아드립니다. 모든 삭제는 휴지통을 거치므로 복구할 수 있어요.",
            glow: Theme.teal
        ) {
            ProminentScanButton(title: "스마트 스캔 시작", systemImage: "sparkle.magnifyingglass") {
                model.scan()
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
                    // 모든 카테고리 일괄 선택/해제 — 리스트 데이터와 양방향 동기화
                    Toggle(isOn: Binding(
                        get: { model.allSelected },
                        set: { model.toggleAllItems($0) }
                    )) {
                        Text("전체 선택")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                    }
                    .toggleStyle(.checkbox)
                    .disabled(model.cleaning)
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
                .featureLocked()
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
                    Text(LocalizedStringKey(category.title))
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    Text(LocalizedStringKey(category.subtitle))
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
                                HStack(spacing: 6) {
                                    if let icon = item.icon {
                                        Image(nsImage: icon)
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 16, height: 16)
                                    }
                                    Text(LocalizedStringKey(item.name))
                                        .lineLimit(1)
                                }
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
                            SafetyBadge(safety: item.safety)
                            Spacer()
                            Text(Format.bytes(item.size))
                                .foregroundStyle(.secondary)
                                .font(.callout)
                                .monospacedDigit()
                        }
                        // 행 어디에 마우스를 올려도 왜 '삭제 권장'/'주의'인지 설명을 보여준다
                        .contentShape(Rectangle())
                        .help(item.safety.help)
                    }
                }
            }
        }
        .card()
    }
}

// MARK: - 안전도 뱃지

/// 항목 옆에 붙는 '삭제 권장'/'주의' 색상 뱃지 — 지워도 되는지 한눈에 판단하게 한다.
private struct SafetyBadge: View {
    let safety: CacheSafety

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: safety.icon)
                .font(.system(size: 8, weight: .bold))
            Text(safety.label)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(safety.tint)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(safety.tint.opacity(0.13), in: Capsule())
        .overlay(Capsule().strokeBorder(safety.tint.opacity(0.35), lineWidth: 0.5))
        .help(safety.help)
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
                .featureLocked()
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
