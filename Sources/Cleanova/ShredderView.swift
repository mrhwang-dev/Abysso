import SwiftUI
import Security
import UniformTypeIdentifiers

// MARK: - 모델

struct ShredItem: Identifiable {
    enum Status { case pending, shredding, done, failed }

    let id = UUID()
    let url: URL
    let size: Int64
    var status: Status = .pending

    var displayPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return url.path.replacingOccurrences(of: home, with: "~")
    }
}

@MainActor
final class ShredderModel: ObservableObject {
    @Published var items: [ShredItem] = []
    @Published var shredding = false
    @Published var progress: Double = 0
    @Published var finishedMessage: String?

    func add(urls: [URL]) {
        finishedMessage = nil
        for url in urls where !items.contains(where: { $0.url == url }) {
            items.append(ShredItem(url: url, size: DiskUtil.itemSize(url)))
        }
    }

    func remove(_ id: UUID) {
        items.removeAll { $0.id == id }
    }

    func shredAll() {
        guard !shredding else { return }
        shredding = true
        progress = 0
        let targets = items
        Task.detached(priority: .userInitiated) {
            var doneCount = 0
            for item in targets {
                await MainActor.run {
                    if let i = self.items.firstIndex(where: { $0.id == item.id }) {
                        self.items[i].status = .shredding
                    }
                }
                let ok = Self.shred(item.url)
                doneCount += 1
                let fraction = Double(doneCount) / Double(targets.count)
                await MainActor.run {
                    if let i = self.items.firstIndex(where: { $0.id == item.id }) {
                        self.items[i].status = ok ? .done : .failed
                    }
                    self.progress = fraction
                }
            }
            await MainActor.run {
                self.shredding = false
                let failed = self.items.filter { $0.status == .failed }.count
                let freed = self.items.filter { $0.status == .done }.reduce(0) { $0 + $1.size }
                self.finishedMessage = failed == 0
                    ? "\(targets.count)개 항목(\(Format.bytes(freed)))을 복구 불가능하게 파쇄했습니다."
                    : "\(targets.count - failed)개 파쇄 완료, \(failed)개 실패 (권한 또는 사용 중)"
                self.items.removeAll { $0.status == .done }
            }
        }
    }

    /// 파일/폴더 파쇄: 랜덤 2회 + 0 채우기 1회 덮어쓰기 후 삭제 (DoD 5220.22-M 3-pass)
    nonisolated static func shred(_ url: URL) -> Bool {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return false }

        if isDir.boolValue {
            // 폴더: 내부 파일 전부 파쇄 후 폴더 제거
            var allOK = true
            if let enumerator = fm.enumerator(
                at: url, includingPropertiesForKeys: [.isRegularFileKey],
                options: [], errorHandler: { _, _ in true }
            ) {
                for case let fileURL as URL in enumerator {
                    let isFile = (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]))?
                        .isRegularFile ?? false
                    if isFile, !overwriteFile(fileURL) { allOK = false }
                }
            }
            do { try fm.removeItem(at: url) } catch { return false }
            return allOK
        } else {
            guard overwriteFile(url) else { return false }
            do { try fm.removeItem(at: url) } catch { return false }
            return true
        }
    }

    nonisolated private static func overwriteFile(_ url: URL) -> Bool {
        guard let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int64,
              size > 0 else {
            return FileManager.default.isDeletableFile(atPath: url.path)
        }
        guard let handle = FileHandle(forWritingAtPath: url.path) else { return false }
        defer { try? handle.close() }

        let chunkSize = 1 << 20  // 1MB
        for pass in 0..<3 {
            do {
                try handle.seek(toOffset: 0)
                var remaining = size
                while remaining > 0 {
                    let n = Int(min(Int64(chunkSize), remaining))
                    var data = Data(count: n)
                    if pass < 2 {
                        // 랜덤 패스
                        let result = data.withUnsafeMutableBytes {
                            SecRandomCopyBytes(kSecRandomDefault, n, $0.baseAddress!)
                        }
                        guard result == errSecSuccess else { return false }
                    }
                    // pass 2는 0으로 채움 (Data(count:)는 이미 0)
                    try handle.write(contentsOf: data)
                    remaining -= Int64(n)
                }
                try handle.synchronize()
            } catch {
                return false
            }
        }
        return true
    }
}

// MARK: - 뷰

struct ShredderView: View {
    @EnvironmentObject private var model: ShredderModel
    @State private var importing = false
    @State private var confirming = false
    @State private var dropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(
                title: "파쇄기",
                subtitle: "보안 삭제 (3회 덮어쓰기)로 파일을 복구할 수 없게 지웁니다",
                icon: "flame.fill", iconColor: Theme.red
            )
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 12)

            if model.items.isEmpty {
                dropZone
            } else {
                itemList
            }

            Divider().opacity(0.3)
            bottomBar
        }
        .background(Theme.background)
        .fileImporter(
            isPresented: $importing,
            allowedContentTypes: [.item, .folder],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result { model.add(urls: urls) }
        }
        .confirmationDialog(
            "\(model.items.count)개 항목을 영구 파쇄할까요?",
            isPresented: $confirming
        ) {
            Button("영구 파쇄 (복구 불가)", role: .destructive) { model.shredAll() }
        } message: {
            Text("휴지통을 거치지 않고 즉시 덮어쓴 후 삭제합니다. 되돌릴 수 없습니다.")
        }
    }

    private var dropZone: some View {
        ZStack {
            ParticleField()
            VStack(spacing: 16) {
                Spacer()
                Image(systemName: "flame.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(
                        LinearGradient(colors: [Theme.red, Theme.orange],
                                       startPoint: .top, endPoint: .bottom)
                    )
                    .symbolEffect(.pulse, options: .repeating)
                Text("민감한 파일을 흔적 없이 지우세요")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                Text("파일이나 폴더를 여기로 드래그하거나 아래 버튼으로 선택하세요.\n랜덤 데이터로 여러 번 덮어쓴 뒤 삭제하므로 복구 도구로도 되살릴 수 없습니다.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                PulsingGlow(color: Theme.red) {
                    ProminentScanButton(title: "파일 선택", systemImage: "plus.circle") {
                        importing = true
                    }
                }
                .padding(.top, 6)
                Text("참고: 최신 Mac(SSD) 환경에서는 시스템 최적화 기능으로 인해 완벽한 파쇄가 제한될 수 있습니다.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 10)
                Spacer()
            }
            .padding(.horizontal, 40)

            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(
                    dropTargeted ? Theme.red : Color.white.opacity(0.10),
                    style: StrokeStyle(lineWidth: 2, dash: [8, 6])
                )
                .padding(24)
                .allowsHitTesting(false)
        }
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            handleDrop(providers)
        }
    }

    private var itemList: some View {
        VStack(spacing: 0) {
            if model.shredding {
                ProgressView(value: model.progress)
                    .tint(Theme.red)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 8)
            }
            List {
                ForEach(model.items) { item in
                    HStack {
                        statusIcon(item.status)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.url.lastPathComponent)
                            Text(item.displayPath)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        Text(Format.bytes(item.size))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        if !model.shredding {
                            Button {
                                model.remove(item.id)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.tertiary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            handleDrop(providers)
        }
    }

    private func statusIcon(_ status: ShredItem.Status) -> some View {
        Group {
            switch status {
            case .pending:
                Image(systemName: "doc.fill").foregroundStyle(.secondary)
            case .shredding:
                ProgressView().controlSize(.small)
            case .done:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.green)
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.red)
            }
        }
        .frame(width: 20)
    }

    private var bottomBar: some View {
        HStack {
            if let msg = model.finishedMessage {
                Label(msg, systemImage: "checkmark.seal.fill")
                    .foregroundStyle(Theme.green)
                    .font(.callout)
            } else if !model.items.isEmpty {
                Text("\(model.items.count)개 항목 · \(Format.bytes(model.items.reduce(0) { $0 + $1.size }))")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
            Spacer()
            if !model.items.isEmpty {
                Button {
                    importing = true
                } label: {
                    Label("추가", systemImage: "plus")
                }
                .disabled(model.shredding)
                Button(role: .destructive) {
                    confirming = true
                } label: {
                    Label("영구 파쇄", systemImage: "flame")
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.red)
                .disabled(model.shredding || model.items.isEmpty)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                if let data = data as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil) {
                    Task { @MainActor in model.add(urls: [url]) }
                }
            }
        }
        return !providers.isEmpty
    }
}
