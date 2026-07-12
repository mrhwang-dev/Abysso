import AppKit

struct RunningProc: Identifiable {
    let pid: Int32
    let name: String
    let cpu: Double        // %
    let memBytes: Int64
    let bundleID: String?
    var id: Int32 { pid }

    var icon: NSImage {
        if let app = NSRunningApplication(processIdentifier: pid), let img = app.icon {
            return img
        }
        return NSWorkspace.shared.icon(for: .unixExecutable)
    }
}

enum ProcessMonitor {
    /// ps로 CPU/메모리 상위 프로세스 수집
    static func topProcesses(limit: Int = 12) -> [RunningProc] {
        // ps -Aceo pid,%cpu,rss,comm : 명령 이름(comm)은 앱 이름에 가깝게 나옴
        let result = LaunchAgentManager.run(
            "/bin/ps", ["-Aceo", "pid=,%cpu=,rss=,comm="]
        )
        guard result.status == 0 else { return [] }

        // pid → bundleID 매핑 (GUI 앱만)
        var bundleByPID: [Int32: String] = [:]
        var nameByPID: [Int32: String] = [:]
        for app in NSWorkspace.shared.runningApplications {
            bundleByPID[app.processIdentifier] = app.bundleIdentifier
            if let name = app.localizedName { nameByPID[app.processIdentifier] = name }
        }

        var procs: [RunningProc] = []
        for line in result.output.split(separator: "\n") {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 4,
                  let pid = Int32(parts[0]),
                  let cpu = Double(parts[1]),
                  let rssKB = Int64(parts[2]) else { continue }
            let comm = parts[4...].joined(separator: " ")
            let name = nameByPID[pid] ?? String(comm)
            procs.append(RunningProc(
                pid: pid, name: name, cpu: cpu,
                memBytes: rssKB * 1024, bundleID: bundleByPID[pid]
            ))
        }
        return procs
    }

    static func topByCPU(limit: Int = 8) -> [RunningProc] {
        Array(topProcesses().filter { $0.pid != getpid() }
            .sorted { $0.cpu > $1.cpu }.prefix(limit))
    }

    static func topByMemory(limit: Int = 8) -> [RunningProc] {
        Array(topProcesses().filter { $0.pid != getpid() }
            .sorted { $0.memBytes > $1.memBytes }.prefix(limit))
    }

    /// 실행 중인 일반 GUI 앱 (강제 종료 대상). unresponsive 플래그는 best-effort.
    static func guiApps() -> [(app: NSRunningApplication, unresponsive: Bool)] {
        NSWorkspace.shared.runningApplications
            .filter {
                $0.activationPolicy == .regular
                    && $0.processIdentifier != getpid()
                    && !$0.isTerminated
            }
            .map { ($0, Responsiveness.isUnresponsive(pid: $0.processIdentifier)) }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 }  // 응답 없는 앱 먼저
                return (lhs.0.localizedName ?? "") .localizedCaseInsensitiveCompare(rhs.0.localizedName ?? "") == .orderedAscending
            }
    }

    @discardableResult
    static func quit(pid: Int32, force: Bool) -> Bool {
        if let app = NSRunningApplication(processIdentifier: pid) {
            return force ? app.forceTerminate() : app.terminate()
        }
        return kill(pid, force ? SIGKILL : SIGTERM) == 0
    }
}

/// 앱 응답 여부 검사 — 비공개 CoreGraphics 심볼을 dlsym으로 안전하게 조회.
/// 심볼이 없거나 조회에 실패하면 "응답함"으로 간주(false)해 오탐과 크래시를 방지한다.
enum Responsiveness {
    private typealias CIDFn = @convention(c) () -> Int32
    private typealias UnresponsiveFn = @convention(c) (Int32, pid_t) -> Bool

    private static let handle = dlopen(nil, RTLD_NOW)
    private static let cid: Int32? = {
        guard let sym = dlsym(handle, "CGSMainConnectionID") else { return nil }
        return unsafeBitCast(sym, to: CIDFn.self)()
    }()
    // pid를 직접 받는 변형이 있으면 사용 (없으면 감지 비활성화)
    private static let fn: UnresponsiveFn? = {
        guard let sym = dlsym(handle, "CGSEventIsAppUnresponsiveForPID") else { return nil }
        return unsafeBitCast(sym, to: UnresponsiveFn.self)
    }()

    static func isUnresponsive(pid: pid_t) -> Bool {
        guard let cid, let fn else { return false }
        return fn(cid, pid)
    }
}
