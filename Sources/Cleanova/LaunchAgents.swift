import Foundation

struct LaunchAgentInfo: Identifiable {
    let url: URL
    let label: String        // plist의 Label (launchctl 식별자)
    let displayName: String  // 사람이 읽기 쉬운 이름
    var enabled: Bool

    var id: String { label }
}

@MainActor
final class LaunchAgentManager: ObservableObject {
    @Published var agents: [LaunchAgentInfo] = []
    @Published var busy: Set<String> = []
    @Published var loaded = false

    func load() {
        Task.detached(priority: .userInitiated) {
            let list = Self.scan()
            await MainActor.run {
                self.agents = list
                self.loaded = true
            }
        }
    }

    func setEnabled(_ agent: LaunchAgentInfo, _ enable: Bool) {
        busy.insert(agent.label)
        // UI 즉시 반영 (실패 시 재스캔으로 복원됨)
        if let i = agents.firstIndex(where: { $0.label == agent.label }) {
            agents[i].enabled = enable
        }
        Task.detached(priority: .userInitiated) {
            let uid = getuid()
            let target = "gui/\(uid)/\(agent.label)"
            if enable {
                _ = Self.run("/bin/launchctl", ["enable", target])
                _ = Self.run("/bin/launchctl", ["bootstrap", "gui/\(uid)", agent.url.path])
            } else {
                _ = Self.run("/bin/launchctl", ["bootout", target])
                _ = Self.run("/bin/launchctl", ["disable", target])
            }
            let list = Self.scan()
            await MainActor.run {
                self.agents = list
                self.busy.remove(agent.label)
            }
        }
    }

    // MARK: 스캔

    nonisolated static func scan() -> [LaunchAgentInfo] {
        let fm = FileManager.default
        let dir = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents")
        guard let files = try? fm.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil
        ) else { return [] }

        let disabled = disabledLabels()
        var result: [LaunchAgentInfo] = []
        for url in files where url.pathExtension == "plist" {
            var dict: [String: Any]?
            if let data = try? Data(contentsOf: url) {
                dict = (try? PropertyListSerialization.propertyList(
                    from: data, format: nil
                )) as? [String: Any]
            }
            let label = (dict?["Label"] as? String) ?? url.deletingPathExtension().lastPathComponent
            result.append(LaunchAgentInfo(
                url: url,
                label: label,
                displayName: friendlyName(label: label, plist: dict),
                enabled: !disabled.contains(label)
            ))
        }
        return result.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    /// launchctl print-disabled 출력에서 비활성화된 라벨 추출
    nonisolated static func disabledLabels() -> Set<String> {
        let output = run("/bin/launchctl", ["print-disabled", "gui/\(getuid())"]).output
        var labels = Set<String>()
        let pattern = try! NSRegularExpression(pattern: #""([^"]+)"\s*=>\s*(disabled|true)"#)
        for line in output.split(separator: "\n") {
            let s = String(line)
            let range = NSRange(s.startIndex..., in: s)
            if let match = pattern.firstMatch(in: s, range: range),
               let labelRange = Range(match.range(at: 1), in: s) {
                labels.insert(String(s[labelRange]))
            }
        }
        return labels
    }

    // MARK: 이름 가공

    /// "com.google.GoogleUpdater.wake" → "Google Updater"
    nonisolated static func friendlyName(label: String, plist: [String: Any]?) -> String {
        // 1) 실행 경로에 .app이 있으면 앱 이름 사용 (가장 정확)
        var programPaths: [String] = []
        if let program = plist?["Program"] as? String { programPaths.append(program) }
        if let args = plist?["ProgramArguments"] as? [String], let first = args.first {
            programPaths.append(first)
        }
        for path in programPaths {
            for component in path.split(separator: "/") where component.hasSuffix(".app") {
                return String(component.dropLast(4))
            }
        }

        // 2) 라벨 휴리스틱: TLD 접두어와 일반 접미어 토큰 제거 후 카멜케이스 분리
        var tokens = label.split(separator: ".").map(String.init)
        let tlds: Set<String> = ["com", "org", "net", "io", "us", "co", "app", "de", "jp", "kr", "se"]
        if tokens.count > 1, tlds.contains(tokens[0].lowercased()) {
            tokens.removeFirst()
        }
        let generic: Set<String> = [
            "wake", "agent", "helper", "daemon", "service", "login",
            "launcher", "autostart", "startup", "keepalive", "monitor", "plist",
        ]
        while tokens.count > 1, generic.contains(tokens.last!.lowercased()) {
            tokens.removeLast()
        }
        guard let core = tokens.last else { return label }
        let spaced = splitCamelCase(core)
        // 회사명이 제품명과 다르면 함께 표기 (예: pqrs → Karabiner)
        return spaced
    }

    /// "GoogleUpdater" → "Google Updater", "riotclient" → "Riotclient"
    nonisolated static func splitCamelCase(_ s: String) -> String {
        var out = ""
        var prev: Character?
        for ch in s {
            if let p = prev,
               ch.isUppercase,
               (p.isLowercase || p.isNumber) {
                out.append(" ")
            }
            out.append(ch)
            prev = ch
        }
        // 첫 글자 대문자화
        return out.prefix(1).uppercased() + out.dropFirst()
    }

    // MARK: 프로세스 실행

    @discardableResult
    nonisolated static func run(_ path: String, _ args: [String]) -> (status: Int32, output: String) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = args
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do {
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            return (task.terminationStatus, String(data: data, encoding: .utf8) ?? "")
        } catch {
            return (-1, "")
        }
    }
}
