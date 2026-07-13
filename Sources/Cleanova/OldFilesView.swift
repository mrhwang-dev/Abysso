import SwiftUI

// MARK: - 모델

enum AgeFilter: String, CaseIterable, Identifiable {
    case any = "전체 기간"
    case month1 = "1개월 이상"
    case month6 = "6개월 이상"
    case year1 = "1년 이상"

    var id: String { rawValue }

    var cutoff: Date? {
        let cal = Calendar.current
        switch self {
        case .any: return nil
        case .month1: return cal.date(byAdding: .month, value: -1, to: .now)
        case .month6: return cal.date(byAdding: .month, value: -6, to: .now)
        case .year1: return cal.date(byAdding: .year, value: -1, to: .now)
        }
    }
}

enum OldSort: String, CaseIterable, Identifiable {
    case size = "크기순"
    case oldest = "오래된 순"
    var id: String { rawValue }
}

@MainActor
final class OldFilesModel: ObservableObject {
    @Published var allFiles: [LargeFile] = []
    @Published var scanning = false
    @Published var scanned = false
    @Published var kindFilter: FileKind = .all
    @Published var ageFilter: AgeFilter = .any
    @Published var sort: OldSort = .size
    @Published var lastCleaned: Int64?

    var filtered: [LargeFile] {
        var files = allFiles
        if kindFilter != .all {
            files = files.filter { $0.kind == kindFilter }
        }
        if let cutoff = ageFilter.cutoff {
            files = files.filter { ($0.lastAccess ?? .distantPast) < cutoff }
        }
        switch sort {
        case .size: files.sort { $0.size > $1.size }
        case .oldest: files.sort { ($0.lastAccess ?? .distantPast) < ($1.lastAccess ?? .distantPast) }
        }
        return files
    }

    var filteredSize: Int64 { filtered.reduce(0) { $0 + $1.size } }
    var selectedFiles: [LargeFile] { allFiles.filter(\.selected) }
    var selectedSize: Int64 { selectedFiles.reduce(0) { $0 + $1.size } }

    func scan() {
        scanning = true
        scanned = true
        lastCleaned = nil
        Task.detached(priority: .userInitiated) {
            // 50MB+ 파일, Library 제외
            let result = LargeFilesModel.findLargeFiles(minBytes: 50_000_000, skipLibrary: true)
            await MainActor.run {
                withAnimation {
                    self.allFiles = result
                    self.scanning = false
                }
            }
        }
    }

    func trashSelected() {
        var freed: Int64 = 0
        for file in selectedFiles where DiskUtil.trash(file.url) { freed += file.size }
        lastCleaned = freed
        allFiles.removeAll(where: \.selected)
    }

    func toggle(_ id: UUID) {
        guard let i = allFiles.firstIndex(where: { $0.id == id }) else { return }
        allFiles[i].selected.toggle()
    }
}

// MARK: - 뷰

struct OldFilesView: View {
    @EnvironmentObject private var model: OldFilesModel

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(
                title: "오래된 대용량 파일",
                subtitle: "50MB 이상이면서 오랫동안 열지 않은 파일을 찾아 정리합니다",
                icon: "clock.badge.exclamationmark.fill", iconColor: Theme.orange
            )
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 12)

            filterBar
            Divider().opacity(0.3)

            if model.scanning {
                VStack(spacing: 14) {
                    Spacer()
                    ProgressView().controlSize(.large)
                    Text("홈 폴더에서 대용량 파일을 찾는 중…")
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
                    Text("필터를 넓혀 다시 확인해보세요")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            } else {
                fileList
            }

            Divider().opacity(0.3)
            bottomBar
        }
        .background(Theme.background)
    }

    private var filterBar: some View {
        HStack(spacing: 8) {
            FilterMenu(
                icon: "square.grid.2x2", tint: Theme.orange,
                options: FileKind.allCases.map { ($0, $0.rawValue) },
                selection: $model.kindFilter
            )
            FilterMenu(
                icon: "clock", tint: Theme.orange,
                options: AgeFilter.allCases.map { ($0, $0.rawValue) },
                selection: $model.ageFilter
            )
            FilterMenu(
                icon: "arrow.up.arrow.down", tint: Theme.orange,
                options: OldSort.allCases.map { ($0, $0.rawValue) },
                selection: $model.sort
            )
            Spacer()
            Button {
                model.scan()
            } label: {
                Label("스캔", systemImage: "magnifyingglass")
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.orange)
            .disabled(model.scanning)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
    }

    private var emptyStartView: some View {
        ZStack {
            ParticleField()
            VStack(spacing: 16) {
                Spacer()
                Image(systemName: "clock.badge.exclamationmark.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(Theme.orange.gradient)
                Text("잊고 있던 큰 파일을 찾아보세요")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                Text("한동안 열지 않은 50MB 이상의 파일을 목록으로 보여드립니다.\n종류와 마지막으로 연 날짜로 걸러 필요 없는 것만 골라 지우세요.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                PulsingGlow(color: Theme.orange) {
                    ProminentScanButton(title: "스캔 시작", systemImage: "magnifyingglass") {
                        model.scan()
                    }
                }
                .padding(.top, 6)
                Spacer()
            }
        }
    }

    private var fileList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(model.filtered.count)개 파일 · \(Format.bytes(model.filteredSize))")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 10)

            List(model.filtered) { file in
                let binding = Binding(
                    get: { file.selected },
                    set: { _ in model.toggle(file.id) }
                )
                HStack(spacing: 10) {
                    Toggle(isOn: binding) { EmptyView() }
                        .toggleStyle(.checkbox)
                        .labelsHidden()
                    Image(nsImage: NSWorkspace.shared.icon(forFile: file.url.path))
                        .resizable().frame(width: 24, height: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(file.url.lastPathComponent)
                        Text(file.displayPath)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(Format.bytes(file.size))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        if let access = file.lastAccess {
                            Text("최근 사용: " + access.formatted(.relative(presentation: .named)))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([file.url])
                    } label: {
                        Image(systemName: "magnifyingglass.circle")
                    }
                    .buttonStyle(.plain)
                    .help("Finder에서 보기")
                }
            }
            .scrollContentBackground(.hidden)
        }
    }

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
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }
}
