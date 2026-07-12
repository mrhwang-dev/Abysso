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

    var filtered: [LargeFile] {
        var files = allFiles
        if kindFilter != .all {
            files = files.filter { $0.kind == kindFilter }
        }
        if let cutoff = accessFilter.cutoff {
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

    func scan() {
        scanning = true
        lastCleaned = nil
        let minBytes = Int64(minSizeMB) * 1_000_000
        let skipLibrary = !includeLibrary
        Task.detached(priority: .userInitiated) {
            let result = Self.findLargeFiles(minBytes: minBytes, skipLibrary: skipLibrary)
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.4)) {
                    self.allFiles = result
                    self.scanning = false
                    self.scanned = true
                }
            }
        }
    }

    nonisolated static func findLargeFiles(minBytes: Int64, skipLibrary: Bool) -> [LargeFile] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let keys: [URLResourceKey] = [
            .isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .contentAccessDateKey,
        ]
        var found: [LargeFile] = []

        if let enumerator = FileManager.default.enumerator(
            at: home,
            includingPropertiesForKeys: keys,
            options: [.skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) {
            let libraryPath = home.appendingPathComponent("Library").path
            for case let url as URL in enumerator {
                if skipLibrary && url.path.hasPrefix(libraryPath) {
                    enumerator.skipDescendants()
                    continue
                }
                if url.lastPathComponent == ".Trash" {
                    enumerator.skipDescendants()
                    continue
                }
                guard let values = try? url.resourceValues(forKeys: Set(keys)),
                      values.isRegularFile == true else { continue }
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
        found.sort { $0.size > $1.size }
        return Array(found.prefix(300))
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

// MARK: - Squarified Treemap 레이아웃

enum Treemap {
    static func squarify(_ values: [Double], in rect: CGRect) -> [CGRect] {
        guard !values.isEmpty, rect.width > 0, rect.height > 0 else { return [] }
        let total = values.reduce(0, +)
        guard total > 0 else { return [] }
        let scale = Double(rect.width * rect.height) / total
        let areas = values.map { $0 * scale }
        var result: [CGRect] = []
        var remaining = rect
        var i = 0

        while i < areas.count {
            var row: [Double] = []
            var best = Double.infinity
            let side = Double(min(remaining.width, remaining.height))
            var j = i
            while j < areas.count {
                row.append(areas[j])
                let worst = worstRatio(row, side: side)
                if worst > best {
                    row.removeLast()
                    break
                }
                best = worst
                j += 1
            }
            if row.isEmpty { row.append(areas[i]) }
            let rowArea = row.reduce(0, +)

            if remaining.width >= remaining.height {
                let w = CGFloat(rowArea) / remaining.height
                var y = remaining.minY
                for area in row {
                    let h = CGFloat(area) / w
                    result.append(CGRect(x: remaining.minX, y: y, width: w, height: h))
                    y += h
                }
                remaining = CGRect(
                    x: remaining.minX + w, y: remaining.minY,
                    width: remaining.width - w, height: remaining.height
                )
            } else {
                let h = CGFloat(rowArea) / remaining.width
                var x = remaining.minX
                for area in row {
                    let w = CGFloat(area) / h
                    result.append(CGRect(x: x, y: remaining.minY, width: w, height: h))
                    x += w
                }
                remaining = CGRect(
                    x: remaining.minX, y: remaining.minY + h,
                    width: remaining.width, height: remaining.height - h
                )
            }
            i += row.count
        }
        return result
    }

    private static func worstRatio(_ row: [Double], side: Double) -> Double {
        guard let maxA = row.max(), let minA = row.min(), minA > 0, side > 0 else { return .infinity }
        let sum = row.reduce(0, +)
        let s2 = sum * sum
        let side2 = side * side
        return max(side2 * maxA / s2, s2 / (side2 * minA))
    }
}

// MARK: - 메인 뷰

struct LargeFilesView: View {
    @EnvironmentObject private var model: LargeFilesModel

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(
                title: "스페이스 렌즈",
                subtitle: "큰 파일을 한눈에 — 타일이 클수록 차지하는 공간이 큽니다",
                icon: "circle.hexagongrid.fill", iconColor: Theme.purple
            )
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 12)

            filterBar
            Divider().opacity(0.3)

            if model.scanning {
                VStack(spacing: 14) {
                    Spacer()
                    ProgressView()
                        .controlSize(.large)
                    Text("홈 폴더를 스캔하는 중… 파일이 많으면 시간이 걸립니다")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            } else if !model.scanned {
                emptyStartView
            } else if model.filtered.isEmpty {
                VStack(spacing: 10) {
                    Spacer()
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(Theme.green)
                    Text("조건에 맞는 파일이 없습니다")
                        .font(.headline)
                    Text("필터를 조정하거나 최소 크기를 낮춰 다시 스캔해보세요")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
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

    // MARK: 필터 바

    private var filterBar: some View {
        HStack(spacing: 8) {
            FilterMenu(
                icon: "slider.horizontal.3", tint: Theme.purple,
                options: [(50, "50 MB+"), (100, "100 MB+"), (500, "500 MB+"), (1000, "1 GB+")],
                selection: $model.minSizeMB
            )
            FilterMenu(
                icon: "square.grid.2x2", tint: Theme.purple,
                options: FileKind.allCases.map { ($0, $0.rawValue) },
                selection: $model.kindFilter
            )
            FilterMenu(
                icon: "clock", tint: Theme.purple,
                options: AccessFilter.allCases.map { ($0, $0.rawValue) },
                selection: $model.accessFilter
            )
            FilterMenu(
                icon: "arrow.up.arrow.down", tint: Theme.purple,
                options: SortOrder.allCases.map { ($0, $0.rawValue) },
                selection: $model.sortOrder
            )
            FilterToggle(title: "~/Library", tint: Theme.purple, isOn: $model.includeLibrary)

            Spacer()

            FilterSegment(
                icons: ["circle.hexagongrid.fill", "list.bullet"],
                tint: Theme.purple,
                selection: $model.viewMode
            )

            Button {
                model.scan()
            } label: {
                Label("스캔", systemImage: "magnifyingglass")
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.purple)
            .disabled(model.scanning)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
    }

    // MARK: 시작 전 화면

    private var emptyStartView: some View {
        ZStack {
            ParticleField()
            VStack(spacing: 16) {
                Spacer()
                Image(systemName: "circle.hexagongrid.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(
                        LinearGradient(colors: [Theme.purple, Theme.blue],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .symbolEffect(.pulse.byLayer, options: .repeating)
                Text("Mac에서 가장 큰 파일을 찾아보세요")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                Text("스캔 버튼을 누르면 홈 폴더의 큰 파일을 찾아\n크기에 비례하는 타일 지도로 보여드립니다. 공간을 가장 많이\n차지하는 파일을 한눈에 식별할 수 있어요.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                PulsingGlow(color: Theme.purple) {
                    ProminentScanButton(title: "스캔 시작", systemImage: "magnifyingglass") {
                        model.scan()
                    }
                }
                .padding(.top, 6)
                Spacer()
            }
        }
    }

    // MARK: 렌즈 (treemap)

    private var lensView: some View {
        VStack(spacing: 8) {
            summaryStrip
            GeometryReader { geo in
                let files = Array(model.filtered.prefix(60))
                let rects = Treemap.squarify(
                    files.map { Double($0.size) },
                    in: CGRect(origin: .zero, size: geo.size)
                )
                ZStack(alignment: .topLeading) {
                    ForEach(Array(zip(files, rects)), id: \.0.id) { file, rect in
                        TreemapTile(file: file, selected: file.selected) {
                            model.toggle(file.id)
                        }
                        .frame(width: max(rect.width - 3, 1), height: max(rect.height - 3, 1))
                        .offset(x: rect.minX + 1.5, y: rect.minY + 1.5)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 8)
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
                        Text(kind.rawValue).font(.caption).foregroundStyle(.secondary)
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
                        Text(file.displayPath)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
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
            Button {
                model.trashSelected()
            } label: {
                Label("선택 항목 휴지통으로 (\(Format.bytes(model.selectedSize)))", systemImage: "trash")
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.orange)
            .disabled(model.selectedFiles.isEmpty)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }
}

// MARK: - 타일

private struct TreemapTile: View {
    let file: LargeFile
    let selected: Bool
    let onTap: () -> Void
    @State private var hovering = false

    var body: some View {
        GeometryReader { geo in
            let showText = geo.size.width > 70 && geo.size.height > 34
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(file.kind.tint.opacity(selected ? 0.95 : hovering ? 0.75 : 0.55))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(
                                selected ? Color.white : Color.white.opacity(0.15),
                                lineWidth: selected ? 2 : 1
                            )
                    )
                if showText {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(file.url.lastPathComponent)
                            .font(.system(size: 11, weight: .semibold))
                            .lineLimit(1)
                        Text(Format.bytes(file.size))
                            .font(.system(size: 10, weight: .medium))
                            .opacity(0.85)
                    }
                    .foregroundStyle(.white)
                    .padding(6)
                }
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.white)
                        .padding(4)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                }
            }
        }
        .onTapGesture(perform: onTap)
        .onHover { hovering = $0 }
        .help("\(file.displayPath) — \(Format.bytes(file.size))")
        .animation(.easeOut(duration: 0.15), value: hovering)
        .animation(.easeOut(duration: 0.15), value: selected)
    }
}
