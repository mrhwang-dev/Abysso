import SwiftUI

// MARK: - 모델

struct PrivacyItem: Identifiable {
    let id = UUID()
    let name: String
    let urls: [URL]      // 함께 지워야 하는 파일 묶음 (예: db + wal + shm)
    let size: Int64
    var selected = false
}

struct PrivacyCategory: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let icon: String
    let tint: Color
    var items: [PrivacyItem]

    var totalSize: Int64 { items.reduce(0) { $0 + $1.size } }
}

@MainActor
final class PrivacyModel: ObservableObject {
    @Published var categories: [PrivacyCategory] = []
    @Published var scanning = false
    @Published var scanned = false
    @Published var cleaning = false
    @Published var lastCleaned: Int64?

    var selectedCount: Int {
        categories.reduce(0) { $0 + $1.items.filter(\.selected).count }
    }
    var selectedSize: Int64 {
        categories.reduce(0) { $0 + $1.items.filter(\.selected).reduce(0) { $0 + $1.size } }
    }
    var totalFound: Int64 { categories.reduce(0) { $0 + $1.totalSize } }

    func scan() {
        scanning = true
        scanned = true
        lastCleaned = nil
        Task.detached(priority: .userInitiated) {
            let start = Date()
            let result = Self.findPrivacyData()
            // 스캔이 순식간에 끝나면 레이더 애니메이션이 보이도록 최소 표시 시간 확보
            let elapsed = Date().timeIntervalSince(start)
            if elapsed < 1.8 {
                try? await Task.sleep(for: .seconds(1.8 - elapsed))
            }
            await MainActor.run {
                withAnimation {
                    self.categories = result
                    self.scanning = false
                }
            }
        }
    }

    nonisolated static func findPrivacyData() -> [PrivacyCategory] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        var result: [PrivacyCategory] = []

        // 파일 묶음(db + -wal + -shm)을 하나의 항목으로
        func group(_ name: String, base: URL, files: [String]) -> PrivacyItem? {
            var urls: [URL] = []
            var size: Int64 = 0
            for file in files {
                let url = base.appendingPathComponent(file)
                guard fm.fileExists(atPath: url.path) else { continue }
                urls.append(url)
                size += DiskUtil.itemSize(url)
            }
            guard !urls.isEmpty else { return nil }
            return PrivacyItem(name: name, urls: urls, size: size)
        }

        // Safari
        var safariItems: [PrivacyItem] = []
        let safariDir = home.appendingPathComponent("Library/Safari")
        if let item = group("방문 기록", base: safariDir,
                            files: ["History.db", "History.db-wal", "History.db-shm"]) {
            safariItems.append(item)
        }
        if let item = group("다운로드 기록", base: safariDir, files: ["Downloads.plist"]) {
            safariItems.append(item)
        }
        if let item = group("최근 검색어 및 상위 사이트", base: safariDir,
                            files: ["RecentlyClosedTabs.plist", "TopSites.plist", "LastSession.plist"]) {
            safariItems.append(item)
        }
        for cookiePath in [
            "Library/Cookies/Cookies.binarycookies",
            "Library/Containers/com.apple.Safari/Data/Library/Cookies/Cookies.binarycookies",
        ] {
            if let item = group("쿠키", base: home, files: [cookiePath]) {
                safariItems.append(item)
                break
            }
        }
        result.append(PrivacyCategory(
            title: "Safari",
            subtitle: "정리 전 Safari를 종료하세요 — 로그인 상태가 해제될 수 있습니다",
            icon: "safari.fill", tint: Theme.blue,
            items: safariItems
        ))

        // Chromium 계열 (Chrome / Edge / Arc)
        let chromiumBrowsers: [(String, String)] = [
            ("Chrome", "Library/Application Support/Google/Chrome"),
            ("Edge", "Library/Application Support/Microsoft Edge"),
            ("Arc", "Library/Application Support/Arc/User Data"),
        ]
        for (browser, basePath) in chromiumBrowsers {
            let base = home.appendingPathComponent(basePath)
            guard fm.fileExists(atPath: base.path) else { continue }
            var items: [PrivacyItem] = []
            var profiles = ["Default"]
            if let subdirs = try? fm.contentsOfDirectory(atPath: base.path) {
                profiles += subdirs.filter { $0.hasPrefix("Profile ") }
            }
            for profile in profiles {
                let profileDir = base.appendingPathComponent(profile)
                guard fm.fileExists(atPath: profileDir.path) else { continue }
                let suffix = profiles.count > 1 ? " (\(profile))" : ""
                if let item = group("방문 기록\(suffix)", base: profileDir,
                                    files: ["History", "History-journal", "Visited Links"]) {
                    items.append(item)
                }
                if let item = group("쿠키\(suffix)", base: profileDir,
                                    files: ["Cookies", "Cookies-journal", "Network/Cookies"]) {
                    items.append(item)
                }
                if let item = group("자동완성 데이터\(suffix)", base: profileDir,
                                    files: ["Web Data", "Web Data-journal"]) {
                    items.append(item)
                }
            }
            if !items.isEmpty {
                result.append(PrivacyCategory(
                    title: browser,
                    subtitle: "정리 전 \(browser)를 종료하세요",
                    icon: "globe", tint: Theme.teal,
                    items: items
                ))
            }
        }

        // Firefox
        let firefoxProfiles = home.appendingPathComponent("Library/Application Support/Firefox/Profiles")
        if let profiles = try? fm.contentsOfDirectory(at: firefoxProfiles, includingPropertiesForKeys: nil) {
            var items: [PrivacyItem] = []
            for profile in profiles {
                if let item = group("방문 기록", base: profile,
                                    files: ["places.sqlite", "places.sqlite-wal", "places.sqlite-shm"]) {
                    items.append(item)
                }
                if let item = group("쿠키", base: profile,
                                    files: ["cookies.sqlite", "cookies.sqlite-wal", "cookies.sqlite-shm"]) {
                    items.append(item)
                }
                if let item = group("자동완성 데이터", base: profile, files: ["formhistory.sqlite"]) {
                    items.append(item)
                }
            }
            if !items.isEmpty {
                result.append(PrivacyCategory(
                    title: "Firefox",
                    subtitle: "정리 전 Firefox를 종료하세요",
                    icon: "flame", tint: Theme.orange,
                    items: items
                ))
            }
        }

        // macOS 최근 사용 항목
        var recentItems: [PrivacyItem] = []
        let sflDir = home.appendingPathComponent("Library/Application Support/com.apple.sharedfilelist")
        if let enumerator = fm.enumerator(
            at: sflDir, includingPropertiesForKeys: [.isRegularFileKey],
            options: [], errorHandler: { _, _ in true }
        ) {
            var urls: [URL] = []
            var size: Int64 = 0
            for case let url as URL in enumerator
            where url.pathExtension.hasPrefix("sfl") {
                urls.append(url)
                size += DiskUtil.itemSize(url)
            }
            if !urls.isEmpty {
                recentItems.append(PrivacyItem(
                    name: "최근 사용한 문서·앱·서버 목록", urls: urls, size: size
                ))
            }
        }
        result.append(PrivacyCategory(
            title: "macOS 최근 사용 항목",
            subtitle: "메뉴와 Dock의 '최근 항목' 흔적 — 지워도 안전합니다",
            icon: "clock.arrow.circlepath", tint: Theme.purple,
            items: recentItems
        ))

        return result
    }

    func clean() {
        cleaning = true
        let targets = categories.flatMap { $0.items.filter(\.selected) }
        Task.detached(priority: .userInitiated) {
            var freed: Int64 = 0
            for item in targets {
                var allOK = true
                for url in item.urls where !DiskUtil.trash(url) { allOK = false }
                if allOK { freed += item.size }
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

// MARK: - 뷰

struct PrivacyView: View {
    @EnvironmentObject private var model: PrivacyModel

    /// 스캔 중 티커에 표시할 검사 위치 목록
    private static let tickerPaths: [String] = [
        "~/Library/Safari/History.db",
        "~/Library/Safari/Downloads.plist",
        "~/Library/Cookies",
        "~/Library/Application Support/Google/Chrome/Default/History",
        "~/Library/Application Support/Google/Chrome/Default/Cookies",
        "~/Library/Application Support/Microsoft Edge/Default",
        "~/Library/Application Support/Arc/User Data/Default",
        "~/Library/Application Support/Firefox/Profiles",
        "~/Library/Application Support/com.apple.sharedfilelist",
    ].shuffled()

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(
                title: "개인정보 보호",
                subtitle: "브라우저 방문 기록·쿠키와 최근 사용 항목 흔적을 정리합니다",
                icon: "hand.raised.fill", iconColor: Theme.blue
            )
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 12)

            if model.scanning {
                VStack(spacing: 20) {
                    Spacer()
                    ScanRadar(color: Theme.blue, icon: "hand.raised.fill")
                    Text("개인정보 흔적을 찾는 중…")
                        .font(.headline)
                    ScanPathTicker(paths: Self.tickerPaths, color: Theme.blue)
                    Spacer()
                }
            } else if !model.scanned {
                emptyStartView
            } else {
                resultList
            }

            Divider().opacity(0.3)
            bottomBar
        }
        .background(Theme.background)
    }

    private var emptyStartView: some View {
        ZStack {
            ParticleField()
            VStack(spacing: 16) {
                Spacer()
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(Theme.blue.gradient)
                Text("나의 흔적을 깨끗하게")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                Text("브라우저에 쌓인 방문 기록·쿠키·다운로드 기록과 macOS의\n최근 사용 항목을 찾아 한 번에 지울 수 있습니다.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                PulsingGlow(color: Theme.blue) {
                    ProminentScanButton(title: "개인정보 스캔", systemImage: "magnifyingglass") {
                        model.scan()
                    }
                }
                .padding(.top, 6)
                Spacer()
            }
        }
    }

    private var resultList: some View {
        ScrollView {
            VStack(spacing: 14) {
                if let cleaned = model.lastCleaned {
                    Label("\(Format.bytes(cleaned)) 분량의 흔적을 휴지통으로 옮겼습니다", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Theme.green)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach($model.categories) { $category in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Image(systemName: category.icon)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(category.tint)
                                .frame(width: 34, height: 34)
                                .background(category.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(category.title)
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                Text(category.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if category.items.isEmpty {
                                Text("흔적 없음 ✓")
                                    .font(.callout)
                                    .foregroundStyle(Theme.green)
                            } else {
                                Text(Format.bytes(category.totalSize))
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .monospacedDigit()
                                Button("전체 선택") {
                                    model.toggleAll(in: category.id, to: true)
                                }
                                .buttonStyle(.link)
                                .font(.caption)
                            }
                        }
                        if !category.items.isEmpty {
                            Divider().opacity(0.3)
                            ForEach($category.items) { $item in
                                HStack {
                                    Toggle(isOn: $item.selected) {
                                        Text(item.name)
                                    }
                                    .toggleStyle(.checkbox)
                                    Spacer()
                                    Text(Format.bytes(item.size))
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                        .monospacedDigit()
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
    }

    private var bottomBar: some View {
        HStack {
            if model.scanned && !model.scanning {
                Text("\(model.selectedCount)개 항목 선택됨")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if model.scanned && !model.scanning {
                Button {
                    model.scan()
                } label: {
                    Label("다시 스캔", systemImage: "arrow.clockwise")
                }
                .disabled(model.cleaning)
                Button {
                    model.clean()
                } label: {
                    if model.cleaning {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("흔적 지우기 (\(Format.bytes(model.selectedSize)))", systemImage: "hand.raised")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.blue)
                .disabled(model.selectedCount == 0 || model.cleaning)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }
}
