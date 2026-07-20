import SwiftUI

// MARK: - 모델

enum FileKind: String, CaseIterable, Identifiable {
    case all = "전체"
    case video = "비디오"
    case image = "이미지"
    case document = "문서"
    case archive = "압축 파일"
    case other = "기타"

    var id: String { rawValue }

    static let videoExts: Set<String> = ["mp4", "mov", "mkv", "avi", "wmv", "m4v", "webm", "flv"]
    static let imageExts: Set<String> = ["jpg", "jpeg", "png", "gif", "heic", "tiff", "raw", "psd", "bmp", "webp"]
    static let docExts: Set<String> = ["pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "key", "pages", "numbers", "txt", "hwp"]
    static let archiveExts: Set<String> = ["zip", "dmg", "tar", "gz", "7z", "rar", "pkg", "iso", "xip", "bz2"]

    static func kind(of url: URL) -> FileKind {
        let ext = url.pathExtension.lowercased()
        if videoExts.contains(ext) { return .video }
        if imageExts.contains(ext) { return .image }
        if docExts.contains(ext) { return .document }
        if archiveExts.contains(ext) { return .archive }
        return .other
    }

    var tint: Color {
        switch self {
        case .all: return Theme.teal
        case .video: return Theme.purple
        case .image: return Theme.blue
        case .document: return Theme.green
        case .archive: return Theme.orange
        case .other: return Color(hex: 0x64748B)
        }
    }
}

enum AccessFilter: String, CaseIterable, Identifiable {
    case any = "전체 기간"
    case oneMonth = "1개월 이상 미사용"
    case sixMonths = "6개월 이상 미사용"

    var id: String { rawValue }

    var cutoff: Date? {
        switch self {
        case .any: return nil
        case .oneMonth: return Calendar.current.date(byAdding: .month, value: -1, to: .now)
        case .sixMonths: return Calendar.current.date(byAdding: .month, value: -6, to: .now)
        }
    }
}

enum SortOrder: String, CaseIterable, Identifiable {
    case size = "크기순"
    case date = "오래된 순"
    case name = "이름순"
    var id: String { rawValue }
}

struct LargeFile: Identifiable {
    let id = UUID()
    let url: URL
    let size: Int64
    let lastAccess: Date?
    let kind: FileKind
    var selected = false

    var displayPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return url.path.replacingOccurrences(of: home, with: "~")
    }

    /// '~/Library' 같은 시스템 경로 대신 사람이 이해하기 쉬운 위치 설명
    var friendlyLocation: String { FriendlyPath.location(of: url) }
}

// MARK: - 친화적 경로 이름

/// 시스템 폴더 경로를 사용자가 이해하기 쉬운 이름으로 바꿔 주는 도우미.
/// 예: ~/Library/Caches/… → "사용자 라이브러리 (시스템 필수 데이터) › Caches"
enum FriendlyPath {
    /// 파일이 들어 있는 폴더의 친화적 설명을 만든다 (파일 이름 자체는 제외).
    nonisolated static func location(of url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = url.deletingLastPathComponent()
        let dirComponents = dir.pathComponents
        let homeComponents = home.pathComponents

        // 홈 폴더 아래: 첫 폴더를 친숙한 이름으로 바꾸고 나머지를 › 로 잇는다
        if dirComponents.count >= homeComponents.count,
           Array(dirComponents.prefix(homeComponents.count)) == homeComponents {
            var rest = Array(dirComponents.dropFirst(homeComponents.count))
            guard let first = rest.first else {
                return NSLocalizedString("홈 폴더", comment: "")
            }
            rest.removeFirst()
            let root = friendlyName(first)
            switch rest.count {
            case 0: return root
            case 1, 2: return ([root] + rest).joined(separator: " › ")
            default:
                // 깊은 경로는 중간을 줄여 마지막 폴더만 보여준다
                return root + " › … › " + rest[rest.count - 1]
            }
        }

        // 외장/네트워크 볼륨
        if dirComponents.count >= 3, dirComponents[1] == "Volumes" {
            return String(format: NSLocalizedString("외장 볼륨 (%@)", comment: ""), dirComponents[2])
        }
        if dir.path == "/Applications" || dir.path.hasPrefix("/Applications/") {
            return NSLocalizedString("응용 프로그램", comment: "")
        }
        return dir.path
    }

    /// 홈 바로 아래 표준 폴더의 친숙한 표시 이름
    nonisolated private static func friendlyName(_ folder: String) -> String {
        switch folder {
        case "Library": return NSLocalizedString("사용자 라이브러리 (시스템 필수 데이터)", comment: "")
        case "Desktop": return NSLocalizedString("데스크탑", comment: "")
        case "Documents": return NSLocalizedString("문서", comment: "")
        case "Downloads": return NSLocalizedString("다운로드", comment: "")
        case "Movies": return NSLocalizedString("동영상", comment: "")
        case "Music": return NSLocalizedString("음악", comment: "")
        case "Pictures": return NSLocalizedString("사진", comment: "")
        case "Public": return NSLocalizedString("공용 폴더", comment: "")
        case "Applications": return NSLocalizedString("응용 프로그램", comment: "")
        case "Developer": return NSLocalizedString("개발자 폴더", comment: "")
        default: return folder
        }
    }
}

// MARK: - 파일 정체 추론

/// 암호처럼 알아보기 힘든 파일 이름이라도 경로·확장자로 "이게 대체 무엇인지"를 짐작해
/// 사람이 읽을 수 있는 설명을 돌려준다. (예: .git 안의 pack-<해시>.pack → "Git 저장소 데이터")
/// 반환값은 Localizable.strings 키(한국어 리터럴)이므로 표시 시 언어별로 번역된다.
enum FileMeaning {
    nonisolated static func of(_ url: URL) -> String? {
        let comps = Set(url.pathComponents)
        let ext = url.pathExtension.lowercased()
        let path = url.path

        // 1) 위치 기반 (가장 확실한 단서)
        if comps.contains(".git") || (url.lastPathComponent.hasPrefix("pack-") && (ext == "pack" || ext == "idx")) {
            return "Git 저장소 데이터"
        }
        if comps.contains("node_modules") { return "Node.js 패키지 데이터" }
        if comps.contains("DerivedData") { return "Xcode 빌드 캐시" }
        if comps.contains("site-packages") || comps.contains(".venv") || comps.contains("venv") {
            return "Python 패키지 데이터"
        }
        if path.contains("/Library/Developer/") { return "Xcode 개발 데이터" }
        if comps.contains(".gradle") || comps.contains(".m2") || comps.contains(".cargo") {
            return "빌드 도구 캐시"
        }
        if path.contains("com.docker") || comps.contains(".docker") { return "Docker 데이터" }
        if comps.contains("Containers") || comps.contains("Group Containers") { return "앱 저장 데이터" }
        if comps.contains("Caches") || comps.contains("Cache") { return "앱 캐시 데이터" }
        if comps.contains("Logs") { return "로그 데이터" }

        // 2) 확장자 기반
        switch ext {
        case "app": return "응용 프로그램"
        case "dmg", "iso", "sparseimage": return "디스크 이미지"
        case "pkg", "mpkg": return "설치 패키지"
        case "zip", "tar", "gz", "7z", "rar", "bz2", "xz", "tgz": return "압축 파일"
        case "pack", "idx": return "Git 저장소 데이터"
        case "sketch", "psd", "fig", "xd": return "디자인 파일"
        case "sqlite", "sqlite3", "db", "realm": return "데이터베이스 파일"
        case "vmdk", "qcow2", "vdi": return "가상 머신 디스크"
        default: return nil
        }
    }
}

@MainActor
final class LargeFilesModel: ObservableObject {
    @Published var allFiles: [LargeFile] = []
    @Published var scanning = false
    @Published var scanned = false
    @Published var minSizeMB = 100
    @Published var includeLibrary = false
    @Published var kindFilter: FileKind = .all
    @Published var accessFilter: AccessFilter = .any
    @Published var sortOrder: SortOrder = .size
    @Published var lastCleaned: Int64?
    @Published var viewMode = 0  // 0: 렌즈, 1: 목록 (탭 전환에도 유지)
    @Published var diskUsed: Int64 = 0  // 스캔 시점의 전체 디스크 사용량 (타일 점유율 % 계산용)
    /// 결과 스코프 — 0: 전체 보기, 1: 오래된 대용량 파일(30일+ 미사용 & 50MB+).
    /// 스캔은 한 번만 하고(메타데이터 통합 수집) 스코프는 표시 필터로만 동작한다.
    @Published var scope = 0

    /// '오래된 대용량 파일' 스코프의 고정 조건
    nonisolated static let oldFilesMinBytes: Int64 = 50_000_000
    nonisolated static let oldFilesUnusedDays = 30

    var filtered: [LargeFile] {
        var files = allFiles
        if scope == 1 {
            // 오래된 대용량: 30일 이상 미사용 & 50MB 이상 (스캔 데이터에서 필터링만)
            let cutoff = Calendar.current.date(
                byAdding: .day, value: -Self.oldFilesUnusedDays, to: .now
            ) ?? .now
            files = files.filter {
                $0.size >= Self.oldFilesMinBytes && ($0.lastAccess ?? .distantPast) < cutoff
            }
        } else {
            // 전체 보기: 스캔은 50MB 바닥값으로 하므로 최소 크기는 여기서 걸러 준다
            let minBytes = Int64(minSizeMB) * 1_000_000
            files = files.filter { $0.size >= minBytes }
        }
        if kindFilter != .all {
            files = files.filter { $0.kind == kindFilter }
        }
        if scope == 0, let cutoff = accessFilter.cutoff {
            files = files.filter { ($0.lastAccess ?? .distantPast) < cutoff }
        }
        switch sortOrder {
        case .size: files.sort { $0.size > $1.size }
        case .date: files.sort { ($0.lastAccess ?? .distantPast) < ($1.lastAccess ?? .distantPast) }
        case .name: files.sort { $0.url.lastPathComponent.localizedCaseInsensitiveCompare($1.url.lastPathComponent) == .orderedAscending }
        }
        return files
    }

    var filteredSize: Int64 { filtered.reduce(0) { $0 + $1.size } }
    var selectedFiles: [LargeFile] { allFiles.filter(\.selected) }
    var selectedSize: Int64 { selectedFiles.reduce(0) { $0 + $1.size } }

    /// 검사한 파일 수를 배치(수천 개) 단위로 알려주는 진행 콜백
    typealias ScanProgress = @Sendable (Int) -> Void

    /// 진행 상황 표시용 — 지금까지 검사한 파일 수 (배치 단위로만 갱신되어 UI 부담 없음)
    @Published var scannedCount = 0

    func scan() {
        scanning = true
        lastCleaned = nil
        scannedCount = 0
        // 통합 스캔: '오래된 대용량 파일' 스코프도 같은 데이터를 쓰므로
        // 사용자가 고른 최소 크기와 무관하게 항상 50MB 바닥값으로 수집한다.
        let minBytes = min(Int64(minSizeMB) * 1_000_000, Self.oldFilesMinBytes)
        let skipLibrary = !includeLibrary
        Task.detached(priority: .userInitiated) {
            let disk = SystemProbe.disk()
            let result = await Self.findLargeFiles(minBytes: minBytes, skipLibrary: skipLibrary) { batch in
                // 파일마다가 아니라 수천 개 단위 배치로만 메인 스레드에 반영
                Task { @MainActor in self.scannedCount += batch }
            }
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.4)) {
                    self.diskUsed = max(disk.total - disk.free, 1)
                    self.allFiles = result
                    self.scanning = false
                    self.scanned = true
                }
            }
        }
    }

    nonisolated static func findLargeFiles(
        minBytes: Int64, skipLibrary: Bool, progress: ScanProgress? = nil
    ) async -> [LargeFile] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var found = await enumerateLargeFiles(
            root: home, minBytes: minBytes, skipLibrary: skipLibrary, progress: progress
        )
        #if DEBUG
        // 테스트 모드에서는 홈 폴더뿐 아니라 샌드박스도 함께 추적한다.
        if DevMode.sandboxScanEnabled {
            let sandbox = URL(fileURLWithPath: DevMode.sandboxRoot)
            if FileManager.default.fileExists(atPath: sandbox.path) {
                found += await enumerateLargeFiles(
                    root: sandbox, minBytes: minBytes, skipLibrary: false, progress: progress
                )
            }
        }
        #endif
        found.sort { $0.size > $1.size }
        return Array(found.prefix(300))
    }

    /// TCC(개인정보 보호)가 지키는 홈 하위 경로 — FDA 없이 접근하면 시스템 권한 팝업이
    /// 뜨거나 조용히 거부되므로, 권한이 없을 때는 열거 자체를 하지 않는다.
    /// 데스크탑·문서·다운로드는 폴더별 "접근 허용" 팝업을 직접 유발하는 대표 경로라
    /// FDA가 없으면 반드시 건너뛰어야 팝업이 한 번도 뜨지 않는다.
    nonisolated static let tccProtectedSubpaths = [
        "Desktop", "Documents", "Downloads",
        "Library/Messages", "Library/Mail", "Library/Safari",
        "Library/Cookies", "Library/HomeKit", "Library/Suggestions",
        "Library/CallHistoryDB", "Library/IdentityServices",
        "Library/Metadata/CoreSpotlight", "Library/PersonalizationPortrait",
    ]

    /// 미디어 보관함(음악·사진)은 별도 TCC 권한을 추가로 요구하므로 FDA와 무관하게 항상 건너뛴다.
    /// (경로는 macOS 버전에 따라 ~/Music/Music/… 처럼 중첩될 수 있어 이름 기반 판별도 함께 쓴다.)
    nonisolated static let mediaLibrarySubpaths = [
        // ~/Music(Apple Music)·~/Movies(Apple TV)는 각각 라이브러리 번들뿐 아니라 실제
        // 미디어 파일이 든 Media 폴더를 품고 있다. 시스템 '미디어 보관함' 권한은 음악·비디오를
        // 함께 보호하므로, enumerator가 이 하위 파일들의 크기·접근일을 미리 읽는 것만으로도
        // 권한 팝업이 뜬다. 두 폴더 모두 폴더째 건너뛰어 팝업을 원천 차단한다.
        "Music",
        "Movies",
        "Pictures/Photos Library.photoslibrary",
    ]

    /// 위치와 무관하게 통째로 건너뛸 미디어 보관함 번들 확장자.
    /// 이런 번들은 크기·접근일을 조회하는 것만으로도 '미디어 보관함 접근' 시스템
    /// 권한 팝업을 유발하므로, 경로가 어디에 있든 이름(확장자)으로 판별해 건너뛴다.
    nonisolated static let mediaBundleSuffixes = [
        ".musiclibrary", ".photoslibrary", ".photolibrary",
        ".tvlibrary", ".imovielibrary", ".theater", ".migratedphotolibrary",
    ]

    nonisolated static func isMediaLibraryBundle(_ name: String) -> Bool {
        mediaBundleSuffixes.contains { name.hasSuffix($0) }
    }

    /// FDA가 있어도 개별 시스템 팝업이나 원격 다운로드를 유발할 수 있어 항상 통째로 건너뛰는 경로.
    /// (iCloud Drive는 접근 순간 미다운로드 파일을 내려받으려 할 수 있고,
    ///  CloudStorage는 Dropbox·Google Drive 등 네트워크 볼륨 파일 프로바이더가 마운트되는 곳)
    nonisolated static let alwaysSkippedSubpaths = [
        "Library/Mobile Documents",   // iCloud Drive
        "Library/CloudStorage",       // 서드파티 클라우드 (네트워크 볼륨)
        ".Trash",                     // 휴지통
    ]

    /// 하위 트리 스캔에서 미리 읽어 둘 파일 속성 — enumerator가 한 번의 I/O로 함께
    /// 가져오게(prefetch) 해서 파일마다 별도 시스템 호출이 생기지 않게 한다.
    nonisolated private static let scanKeys: [URLResourceKey] = [
        .isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey,
        .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .contentAccessDateKey,
    ]

    /// 지정한 루트 아래에서 minBytes 이상의 파일을 열거한다 (정렬/개수 제한은 호출측 담당).
    /// 최상위 폴더들을 TaskGroup으로 나눠 병렬 스캔해 전체 소요 시간을 크게 줄인다.
    nonisolated static func enumerateLargeFiles(
        root: URL, minBytes: Int64, skipLibrary: Bool, progress: ScanProgress? = nil
    ) async -> [LargeFile] {
        let fm = FileManager.default
        let hasFDA = Permissions.hasFullDiskAccess()
        // 건너뛸 절대 경로 목록 (FDA 없으면 TCC 보호 경로까지 포함)
        var skipPrefixes = (mediaLibrarySubpaths + alwaysSkippedSubpaths)
            .map { root.appendingPathComponent($0).path }
        if !hasFDA {
            skipPrefixes += tccProtectedSubpaths.map { root.appendingPathComponent($0).path }
        }
        if skipLibrary {
            skipPrefixes.append(root.appendingPathComponent("Library").path)
        }
        // 경계까지 정확히 보는 스킵 판정 ("Desktop"이 "DesktopStuff"와 겹치지 않게)
        let prefixes = skipPrefixes
        let isSkipped: @Sendable (String) -> Bool = { path in
            prefixes.contains { path == $0 || path.hasPrefix($0 + "/") }
        }

        // 1) 최상위 항목을 직접 나열해 폴더/파일을 가른다
        guard let top = try? fm.contentsOfDirectory(
            at: root, includingPropertiesForKeys: scanKeys, options: []
        ) else { return [] }

        var found: [LargeFile] = []
        var subdirs: [URL] = []
        for url in top where !isSkipped(url.path) && !Self.isMediaLibraryBundle(url.lastPathComponent) {
            guard let values = try? url.resourceValues(forKeys: Set(scanKeys)) else { continue }
            if values.isSymbolicLink == true { continue }  // 링크는 따라가지 않는다 (순환 방지)
            if values.isDirectory == true {
                if url.lastPathComponent != ".Trash" { subdirs.append(url) }
            } else if values.isRegularFile == true {
                let size = Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
                if size >= minBytes {
                    found.append(LargeFile(
                        url: url, size: size,
                        lastAccess: values.contentAccessDate,
                        kind: FileKind.kind(of: url)
                    ))
                }
            }
        }

        // 2) 폴더별로 병렬 스캔 — I/O 대기가 겹쳐져 단일 순회보다 훨씬 빠르다
        found += await withTaskGroup(of: [LargeFile].self) { group in
            for dir in subdirs {
                group.addTask {
                    scanSubtree(dir, minBytes: minBytes, isSkipped: isSkipped, progress: progress)
                }
            }
            var merged: [LargeFile] = []
            for await part in group { merged += part }
            return merged
        }
        return found
    }

    /// 한 하위 트리를 순회하며 큰 파일을 수집한다 (TaskGroup 작업 단위).
    nonisolated private static func scanSubtree(
        _ root: URL, minBytes: Int64,
        isSkipped: @Sendable (String) -> Bool, progress: ScanProgress?
    ) -> [LargeFile] {
        var found: [LargeFile] = []
        var sinceReport = 0
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: scanKeys,
            options: [.skipsPackageDescendants],
            errorHandler: { _, _ in true }   // 접근 거부 등은 팝업 없이 즉시 무시하고 계속
        ) else { return [] }

        for case let url as URL in enumerator {
            // 스킵 판정을 resourceValues 읽기보다 먼저 한다.
            // 미디어 보관함(Music Library.musiclibrary 등) 같은 TCC 보호 경로는 크기·접근일을
            // 조회하는 것만으로도 시스템 권한 팝업(음악·미디어 보관함 접근)을 띄우므로,
            // 메타데이터를 읽기 전에 통째로 건너뛰어야 팝업이 뜨지 않는다.
            if url.lastPathComponent == ".Trash"
                || Self.isMediaLibraryBundle(url.lastPathComponent)
                || isSkipped(url.path) {
                enumerator.skipDescendants()
                continue
            }
            guard let values = try? url.resourceValues(forKeys: Set(scanKeys)) else { continue }
            sinceReport += 1
            if sinceReport >= 2000 {
                progress?(sinceReport)   // UI 갱신은 파일마다가 아니라 2,000개 배치로만
                sinceReport = 0
            }
            if values.isDirectory == true { continue }
            guard values.isRegularFile == true else { continue }
            let size = Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
            if size >= minBytes {
                found.append(LargeFile(
                    url: url, size: size,
                    lastAccess: values.contentAccessDate,
                    kind: FileKind.kind(of: url)
                ))
            }
        }
        if sinceReport > 0 { progress?(sinceReport) }
        return found
    }

    func trashSelected() {
        var freed: Int64 = 0
        for file in selectedFiles where DiskUtil.trash(file.url) {
            freed += file.size
        }
        lastCleaned = freed
        allFiles.removeAll(where: \.selected)
    }

    func toggle(_ id: UUID) {
        guard let i = allFiles.firstIndex(where: { $0.id == id }) else { return }
        allFiles[i].selected.toggle()
    }
}

// MARK: - 메인 뷰

struct LargeFilesView: View {
    @EnvironmentObject private var model: LargeFilesModel

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(
                title: "대용량 파일",
                subtitle: "큰 파일을 한눈에 — 막대가 길수록 차지하는 공간이 큽니다",
                icon: "chart.bar.xaxis", iconColor: Theme.purple
            )
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 12)

            scopePicker
            filterBar
            Divider().opacity(0.3)

            if model.scanning {
                VStack(spacing: 14) {
                    Spacer()
                    ProgressView()
                        .controlSize(.large)
                    Text("홈 폴더를 스캔하는 중… 파일이 많으면 시간이 걸립니다")
                        .foregroundStyle(.secondary)
                    // 실시간 진행 카운트 (2,000개 배치 단위로만 갱신)
                    if model.scannedCount > 0 {
                        Text(String(format: NSLocalizedString("%lld개 파일 검사함", comment: ""),
                                    Int64(model.scannedCount)))
                            .font(.callout)
                            .monospacedDigit()
                            .foregroundStyle(.tertiary)
                            .contentTransition(.numericText())
                            .animation(.default, value: model.scannedCount)
                    }
                    // 스캔이 길어지면 경과 시간과 지연 사유를 알려준다
                    ScanDelayNotice()
                    Spacer()
                }
            } else if !model.scanned {
                emptyStartView
            } else if model.filtered.isEmpty {
                EmptyStateView(
                    icon: "magnifyingglass",
                    title: "조건에 맞는 파일이 없습니다",
                    message: "필터를 조정하거나 최소 크기를 낮춰 다시 스캔해보세요.",
                    actionTitle: "조건 초기화",
                    action: {
                        model.minSizeMB = 50
                        model.kindFilter = .all
                        model.accessFilter = .any
                        model.includeLibrary = false
                    },
                    tint: Theme.purple
                )
            } else {
                if model.viewMode == 0 {
                    lensView
                } else {
                    listView
                }
            }

            Divider().opacity(0.3)
            bottomBar
        }
        .background(Theme.background)
    }

    // MARK: 스코프 전환 (전체 ↔ 오래된 대용량 파일)

    /// 한 번의 통합 스캔 결과를 두 관점으로 전환해서 보는 세그먼트.
    private var scopePicker: some View {
        VStack(spacing: 6) {
            Picker("", selection: $model.scope) {
                Text("전체 보기").tag(0)
                Text("오래된 대용량 파일").tag(1)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 360)
            if model.scope == 1 {
                Text("30일 이상 미사용 · 50MB 이상 파일만 표시합니다")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 4)
        .animation(.easeOut(duration: 0.15), value: model.scope)
    }

    // MARK: 필터 바

    private var filterBar: some View {
        HStack(spacing: 8) {
            // 필터 그룹: 공간이 부족하면 세로로 깨지지 않고 가로로 스크롤된다.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    // 크기·미사용 기간 필터는 '오래된 대용량' 스코프의 고정 조건(50MB+/30일+)과
                    // 겹치므로 전체 보기에서만 노출한다.
                    if model.scope == 0 {
                        FilterMenu(
                            icon: "slider.horizontal.3", tint: Theme.purple,
                            options: [(50, "50 MB+"), (100, "100 MB+"), (500, "500 MB+"), (1000, "1 GB+")],
                            selection: $model.minSizeMB
                        )
                    }
                    FilterMenu(
                        icon: "square.grid.2x2", tint: Theme.purple,
                        options: FileKind.allCases.map { ($0, $0.rawValue) },
                        selection: $model.kindFilter
                    )
                    if model.scope == 0 {
                        FilterMenu(
                            icon: "clock", tint: Theme.purple,
                            options: AccessFilter.allCases.map { ($0, $0.rawValue) },
                            selection: $model.accessFilter
                        )
                    }
                    FilterMenu(
                        icon: "arrow.up.arrow.down", tint: Theme.purple,
                        options: SortOrder.allCases.map { ($0, $0.rawValue) },
                        selection: $model.sortOrder
                    )
                    FilterToggle(title: "~/Library", tint: Theme.purple, isOn: $model.includeLibrary)
                }
                .padding(.vertical, 2)  // 캡슐 테두리가 스크롤뷰 경계에 잘리지 않도록
            }

            // 우측 조작부(보기 전환 · 스캔)는 항상 형태 유지
            FilterSegment(
                icons: ["chart.bar.xaxis", "list.bullet"],
                tint: Theme.purple,
                selection: $model.viewMode
            )
            .layoutPriority(1)

            Button {
                model.scan()
            } label: {
                Label("스캔", systemImage: "magnifyingglass")
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.purple)
            .disabled(model.scanning)
            .fixedSize()
            .layoutPriority(1)
            .featureLocked()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
    }

    // MARK: 시작 전 화면

    private var emptyStartView: some View {
        EmptyStatePane(
            icon: "chart.bar.xaxis",
            iconStyle: AnyShapeStyle(
                LinearGradient(colors: [Theme.purple, Theme.blue],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            ),
            title: "Mac에서 가장 큰 파일을 찾아보세요",
            message: "스캔 버튼을 누르면 홈 폴더의 큰 파일을 찾아\n용량이 큰 순서의 막대 차트로 보여드립니다. 공간을 가장 많이\n차지하는 파일을 한눈에 식별할 수 있어요.",
            glow: Theme.purple
        ) {
            ProminentScanButton(title: "스캔 시작", systemImage: "magnifyingglass") {
                model.scan()
            }
        }
    }

    // MARK: 렌즈 (용량 비례 가로 바 차트)

    private var lensView: some View {
        VStack(spacing: 8) {
            summaryStrip
            ScrollView {
                let files = model.filtered
                let maxSize = max(files.map(\.size).max() ?? 1, 1)
                LazyVStack(spacing: 6) {
                    ForEach(files) { file in
                        SizeBarRow(
                            file: file,
                            selected: file.selected,
                            fraction: Double(file.size) / Double(maxSize),
                            diskShare: Double(file.size) / Double(max(model.diskUsed, 1))
                        ) {
                            model.toggle(file.id)
                        }
                        // 스캔 완료 시 막대가 왼쪽에서 부드럽게 나타나는 등장 효과
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
                .animation(.spring(response: 0.45, dampingFraction: 0.8), value: files.map(\.id))
            }
        }
    }

    private var summaryStrip: some View {
        HStack {
            Text("\(model.filtered.count)개 파일 · \(Format.bytes(model.filteredSize))")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            HStack(spacing: 10) {
                ForEach([FileKind.video, .image, .document, .archive, .other]) { kind in
                    HStack(spacing: 4) {
                        Circle().fill(kind.tint).frame(width: 8, height: 8)
                        Text(LocalizedStringKey(kind.rawValue)).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
    }

    // MARK: 목록

    private var listView: some View {
        List {
            ForEach(model.filtered) { file in
                let binding = Binding(
                    get: { file.selected },
                    set: { _ in model.toggle(file.id) }
                )
                HStack {
                    Toggle(isOn: binding) { EmptyView() }
                        .toggleStyle(.checkbox)
                        .labelsHidden()
                    Circle().fill(file.kind.tint).frame(width: 8, height: 8)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(file.url.lastPathComponent)
                        // "이게 무엇인지"(정체) + 이해하기 쉬운 위치. 실제 경로는 툴팁으로.
                        (FileMeaning.of(file.url).map {
                            Text(LocalizedStringKey($0)).foregroundColor(file.kind.tint)
                                + Text("  ·  ").foregroundColor(.secondary)
                                + Text(file.friendlyLocation).foregroundColor(.secondary)
                        } ?? Text(file.friendlyLocation).foregroundColor(.secondary))
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(file.displayPath)
                    }
                    Spacer()
                    if let access = file.lastAccess {
                        Text(access, format: .relative(presentation: .named))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    Text(Format.bytes(file.size))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([file.url])
                    } label: {
                        Image(systemName: "magnifyingglass.circle")
                    }
                    .buttonStyle(.plain)
                    .help("Finder에서 보기")
                }
            }
        }
        .scrollContentBackground(.hidden)
    }

    // MARK: 하단 바

    private var bottomBar: some View {
        HStack {
            if let cleaned = model.lastCleaned {
                Label("\(Format.bytes(cleaned)) 를 휴지통으로 옮겼습니다", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Theme.green)
            }
            Spacer()
            let hasSelection = !model.selectedFiles.isEmpty
            Button {
                model.trashSelected()
            } label: {
                Label(
                    hasSelection
                        ? "선택 항목 휴지통으로 (\(Format.bytes(model.selectedSize)))"
                        : "선택 항목 없음",
                    systemImage: "trash"
                )
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.orange)
            .disabled(!hasSelection)
            .featureLocked()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }
}

// MARK: - 용량 바 행

/// 파일 하나를 나타내는 가로 막대 행 — 막대 길이가 (가장 큰 파일 대비) 용량에 비례한다.
/// 행 전체를 클릭하면 선택/해제된다.
private struct SizeBarRow: View {
    let file: LargeFile
    let selected: Bool
    /// 이 뷰에서 가장 큰 파일 대비 크기 비율 (0~1) — 막대 길이
    let fraction: Double
    /// 전체 디스크 사용량 중 이 파일의 비율 (0~1)
    let diskShare: Double
    let onTap: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 15))
                .foregroundStyle(selected ? AnyShapeStyle(Theme.teal) : AnyShapeStyle(.tertiary))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Circle().fill(file.kind.tint).frame(width: 7, height: 7)
                    Text(file.url.lastPathComponent)
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    // "이게 무엇인지"(정체)를 종류 색으로 먼저, 이어서 위치를 흐리게
                    (FileMeaning.of(file.url).map {
                        Text(LocalizedStringKey($0)).foregroundColor(file.kind.tint)
                            + Text("  ·  ").foregroundColor(.secondary)
                            + Text(file.friendlyLocation).foregroundColor(.secondary)
                    } ?? Text(file.friendlyLocation).foregroundColor(.secondary))
                        .font(.caption2)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 8)
                    Text(Format.bytes(file.size))
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    if diskShare > 0 {
                        // 전체 디스크 사용량 중 점유율
                        Text(String(format: "%.1f%%", diskShare * 100))
                            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .frame(minWidth: 38, alignment: .trailing)
                    }
                }

                // 용량 비례 막대
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.06))
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [file.kind.tint, file.kind.tint.opacity(0.55)],
                                    startPoint: .leading, endPoint: .trailing
                                )
                            )
                            .frame(width: max(geo.size.width * fraction, 5))
                            .shadow(color: file.kind.tint.opacity(0.5), radius: hovering ? 5 : 2)
                    }
                }
                .frame(height: 7)
            }

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([file.url])
            } label: {
                Image(systemName: "magnifyingglass.circle")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tertiary)
            .help("Finder에서 보기")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(hovering || selected ? Color.white.opacity(0.05) : .clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    selected ? Theme.teal.opacity(0.7) : Color.white.opacity(hovering ? 0.12 : 0.05),
                    lineWidth: 1
                )
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .onHover { hovering = $0 }
        .help(String(
            format: NSLocalizedString("%@ — %@ · 디스크 사용량의 %.1f%%", comment: ""),
            file.displayPath, Format.bytes(file.size), diskShare * 100
        ))
        .animation(.easeOut(duration: 0.15), value: hovering)
        .animation(.easeOut(duration: 0.15), value: selected)
    }
}
