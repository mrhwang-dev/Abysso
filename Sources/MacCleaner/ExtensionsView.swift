import SwiftUI

// MARK: - 모델

enum ExtKind: String, CaseIterable {
    case safari = "Safari 확장 프로그램"
    case spotlight = "Spotlight 플러그인"
    case prefPane = "환경설정 패널"

    var icon: String {
        switch self {
        case .safari: return "safari.fill"
        case .spotlight: return "magnifyingglass.circle.fill"
        case .prefPane: return "slider.horizontal.3"
        }
    }

    var tint: Color {
        switch self {
        case .safari: return Theme.blue
        case .spotlight: return Theme.purple
        case .prefPane: return Theme.orange
        }
    }
}

struct ExtensionItem: Identifiable {
    let id = UUID()
    let kind: ExtKind
    let name: String
    let identifier: String   // pluginkit 식별자 또는 경로
    let path: String
    var enabled: Bool?       // nil = 토글 불가 (파일 기반)
}

@MainActor
final class ExtensionsModel: ObservableObject {
    @Published var items: [ExtensionItem] = []
    @Published var scanning = false
    @Published var scanned = false
    @Published var busy: Set<UUID> = []
    @Published var message: String?

    func scan() {
        scanning = true
        scanned = true
        message = nil
        Task.detached(priority: .userInitiated) {
            var found: [ExtensionItem] = []
            found += Self.safariExtensions()
            found += Self.fileBundles(
                kind: .spotlight,
                dirs: ["Library/Spotlight", "/Library/Spotlight"],
                ext: "mdimporter"
            )
            found += Self.fileBundles(
                kind: .prefPane,
                dirs: ["Library/PreferencePanes", "/Library/PreferencePanes"],
                ext: "prefPane"
            )
            let result = found
            await MainActor.run {
                withAnimation {
                    self.items = result
                    self.scanning = false
                }
            }
        }
    }

    /// pluginkit으로 Safari 웹 확장 열거 (+: 활성, -: 비활성)
    nonisolated static func safariExtensions() -> [ExtensionItem] {
        var items: [ExtensionItem] = []
        let protocols = ["com.apple.Safari.web-extension", "com.apple.Safari.extension"]
        let pattern = try! NSRegularExpression(
            pattern: #"^\s*([+\-!?])?\s+([\w.\-]+)\(([^)]*)\)\s+(.+)$"#
        )
        var seen = Set<String>()
        for proto in protocols {
            let output = LaunchAgentManager.run(
                "/usr/bin/pluginkit", ["-mAv", "-p", proto]
            ).output
            for line in output.split(separator: "\n") {
                let s = String(line)
                let range = NSRange(s.startIndex..., in: s)
                guard let match = pattern.firstMatch(in: s, range: range),
                      let identRange = Range(match.range(at: 2), in: s),
                      let pathRange = Range(match.range(at: 4), in: s) else { continue }
                let ident = String(s[identRange])
                guard !seen.contains(ident) else { continue }
                seen.insert(ident)
                let path = String(s[pathRange]).trimmingCharacters(in: .whitespaces)
                var flag = "+"
                if let flagRange = Range(match.range(at: 1), in: s) {
                    flag = String(s[flagRange])
                }
                // 호스트 앱 이름 추출 (경로의 첫 .app)
                var name = ident
                for component in path.split(separator: "/") where component.hasSuffix(".app") {
                    name = String(component.dropLast(4))
                    break
                }
                items.append(ExtensionItem(
                    kind: .safari, name: name, identifier: ident,
                    path: path, enabled: flag != "-"
                ))
            }
        }
        return items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    nonisolated static func fileBundles(kind: ExtKind, dirs: [String], ext: String) -> [ExtensionItem] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        var items: [ExtensionItem] = []
        for dir in dirs {
            let base = dir.hasPrefix("/") ? URL(fileURLWithPath: dir) : home.appendingPathComponent(dir)
            guard let files = try? fm.contentsOfDirectory(
                at: base, includingPropertiesForKeys: nil
            ) else { continue }
            for url in files where url.pathExtension == ext {
                items.append(ExtensionItem(
                    kind: kind,
                    name: url.deletingPathExtension().lastPathComponent,
                    identifier: url.path,
                    path: url.path,
                    enabled: nil
                ))
            }
        }
        return items
    }

    func setEnabled(_ item: ExtensionItem, _ enable: Bool) {
        guard item.kind == .safari else { return }
        busy.insert(item.id)
        Task.detached(priority: .userInitiated) {
            _ = LaunchAgentManager.run(
                "/usr/bin/pluginkit", ["-e", enable ? "use" : "ignore", "-i", item.identifier]
            )
            let safari = Self.safariExtensions()
            await MainActor.run {
                // Safari 항목만 갱신
                self.items.removeAll { $0.kind == .safari }
                self.items.insert(contentsOf: safari, at: 0)
                self.busy.remove(item.id)
            }
        }
    }

    func trash(_ item: ExtensionItem) {
        let url = URL(fileURLWithPath: item.path)
        if DiskUtil.trash(url) {
            items.removeAll { $0.id == item.id }
            message = "\(item.name) 을(를) 휴지통으로 옮겼습니다"
        } else {
            message = "\(item.name) 삭제 실패 — /Library 항목은 관리자 권한이 필요할 수 있습니다"
        }
    }
}

// MARK: - 뷰

struct ExtensionsView: View {
    @EnvironmentObject private var model: ExtensionsModel

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(
                title: "확장 프로그램",
                subtitle: "Safari 확장·Spotlight 플러그인·환경설정 패널을 한곳에서 관리합니다",
                icon: "puzzlepiece.extension.fill", iconColor: Theme.yellow
            )
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 12)

            if model.scanning {
                Spacer()
                ProgressView("확장 프로그램을 찾는 중…")
                Spacer()
            } else if !model.scanned {
                Spacer()
                ProgressView()
                Spacer()
            } else {
                resultList
            }
        }
        .background(Theme.background)
        .onAppear {
            if !model.scanned { model.scan() }
        }
    }

    private var resultList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let msg = model.message {
                    Label(msg, systemImage: "info.circle.fill")
                        .foregroundStyle(Theme.green)
                }
                ForEach(ExtKind.allCases, id: \.self) { kind in
                    let sectionItems = model.items.filter { $0.kind == kind }
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label(kind.rawValue, systemImage: kind.icon)
                                .font(.headline)
                                .foregroundStyle(kind.tint)
                            Spacer()
                            Text("\(sectionItems.count)개")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if sectionItems.isEmpty {
                            Text("항목 없음")
                                .font(.callout)
                                .foregroundStyle(.tertiary)
                        } else {
                            ForEach(sectionItems) { item in
                                row(item)
                            }
                        }
                        if kind == .safari && !sectionItems.isEmpty {
                            Text("Safari 설정에서 최종적으로 켜고 끌 수 있습니다.")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()
                }
                HStack {
                    Spacer()
                    Button {
                        model.scan()
                    } label: {
                        Label("다시 스캔", systemImage: "arrow.clockwise")
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
    }

    private func row(_ item: ExtensionItem) -> some View {
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: hostAppPath(item) ?? item.path))
                .resizable()
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name)
                    .font(.system(size: 13.5, weight: .medium))
                Text(item.kind == .safari ? item.identifier : displayPath(item.path))
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.path)])
            } label: {
                Image(systemName: "folder")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tertiary)
            .help("Finder에서 보기")

            if let enabled = item.enabled {
                Toggle("", isOn: Binding(
                    get: { enabled },
                    set: { model.setEnabled(item, $0) }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .disabled(model.busy.contains(item.id))
            } else {
                Button {
                    model.trash(item)
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.orange)
                .help("휴지통으로 이동")
            }
        }
        .padding(.vertical, 3)
    }

    private func hostAppPath(_ item: ExtensionItem) -> String? {
        guard item.kind == .safari else { return nil }
        guard let range = item.path.range(of: ".app") else { return nil }
        return String(item.path[..<range.upperBound])
    }

    private func displayPath(_ path: String) -> String {
        path.replacingOccurrences(
            of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~"
        )
    }
}
