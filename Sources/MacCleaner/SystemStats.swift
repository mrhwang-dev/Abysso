import AppKit
import Foundation
import IOKit
import IOKit.ps

// MARK: - 스냅샷 구조체

struct SystemSnapshot {
    var cpuUsage: Double = 0                 // 0...1
    var memUsed: UInt64 = 0
    var memTotal: UInt64 = 1
    var diskUsed: Int64 = 0
    var diskTotal: Int64 = 1
    var diskFree: Int64 = 0
    var trashSize: Int64 = 0
    var netDownPerSec: Double = 0            // bytes/s
    var netUpPerSec: Double = 0
    var batteryPercent: Int? = nil
    var batteryCharging = false
    var thermalState: ProcessInfo.ThermalState = .nominal
    var diskReadPerSec: Double = 0           // bytes/s
    var diskWritePerSec: Double = 0

    var memFraction: Double { Double(memUsed) / Double(memTotal) }
    var diskFraction: Double { Double(diskUsed) / Double(diskTotal) }
}

struct MachineInfo {
    var osName = ""
    var osVersion = ""
    var modelID = ""
    var chip = ""
    var hostName = ""
}

// MARK: - 저수준 수집 함수

enum SystemProbe {
    static func sysctlString(_ name: String) -> String {
        var size = 0
        sysctlbyname(name, nil, &size, nil, 0)
        guard size > 0 else { return "" }
        var buf = [CChar](repeating: 0, count: size)
        sysctlbyname(name, &buf, &size, nil, 0)
        return String(cString: buf)
    }

    static func machineInfo() -> MachineInfo {
        var info = MachineInfo()
        let v = ProcessInfo.processInfo.operatingSystemVersion
        let names: [Int: String] = [
            13: "Ventura", 14: "Sonoma", 15: "Sequoia", 26: "Tahoe",
        ]
        let name = names[v.majorVersion].map { "macOS \($0)" } ?? "macOS"
        info.osName = name
        info.osVersion = "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
        info.modelID = sysctlString("hw.model")
        info.chip = sysctlString("machdep.cpu.brand_string")
        info.hostName = Host.current().localizedName ?? ""
        return info
    }

    // CPU 틱 (누적값 — 델타로 사용률 계산)
    static func cpuTicks() -> (busy: UInt64, total: UInt64)? {
        var load = host_cpu_load_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size
        )
        let kr = withUnsafeMutablePointer(to: &load) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }
        let user = UInt64(load.cpu_ticks.0)
        let system = UInt64(load.cpu_ticks.1)
        let idle = UInt64(load.cpu_ticks.2)
        let nice = UInt64(load.cpu_ticks.3)
        let busy = user + system + nice
        return (busy, busy + idle)
    }

    static func usedMemory() -> UInt64 {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        let pageSize = UInt64(vm_kernel_page_size)
        let used = UInt64(stats.active_count) + UInt64(stats.wire_count)
            + UInt64(stats.compressor_page_count)
        return used * pageSize
    }

    // 네트워크 인터페이스 누적 바이트 (en* 인터페이스 합계)
    static func networkBytes() -> (down: UInt64, up: UInt64) {
        var addrs: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addrs) == 0, let first = addrs else { return (0, 0) }
        defer { freeifaddrs(addrs) }

        var down: UInt64 = 0, up: UInt64 = 0
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let ifa = cursor {
            let name = String(cString: ifa.pointee.ifa_name)
            if let addr = ifa.pointee.ifa_addr,
               addr.pointee.sa_family == UInt8(AF_LINK),
               name.hasPrefix("en"),
               let dataPtr = ifa.pointee.ifa_data {
                let data = dataPtr.assumingMemoryBound(to: if_data.self).pointee
                down += UInt64(data.ifi_ibytes)
                up += UInt64(data.ifi_obytes)
            }
            cursor = ifa.pointee.ifa_next
        }
        return (down, up)
    }

    static func battery() -> (percent: Int, charging: Bool)? {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }
        for source in sources {
            guard let info = IOPSGetPowerSourceDescription(snapshot, source)?
                .takeUnretainedValue() as? [String: Any],
                  let capacity = info["Current Capacity"] as? Int else { continue }
            let charging = (info["Is Charging"] as? Bool) ?? false
            return (capacity, charging)
        }
        return nil
    }

    // 디스크 I/O 누적 바이트 (IOBlockStorageDriver 통계 — 델타로 속도 계산)
    static func diskIOBytes() -> (read: UInt64, written: UInt64) {
        var iterator = io_iterator_t()
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("IOBlockStorageDriver"),
            &iterator
        ) == KERN_SUCCESS else { return (0, 0) }
        defer { IOObjectRelease(iterator) }

        var read: UInt64 = 0, written: UInt64 = 0
        var entry = IOIteratorNext(iterator)
        while entry != 0 {
            var props: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(entry, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let dict = props?.takeRetainedValue() as? [String: Any],
               let stats = dict["Statistics"] as? [String: Any] {
                read += (stats["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0
                written += (stats["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0
            }
            IOObjectRelease(entry)
            entry = IOIteratorNext(iterator)
        }
        return (read, written)
    }

    static func disk() -> (total: Int64, free: Int64) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        guard let values = try? home.resourceValues(forKeys: [
            .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey
        ]) else { return (1, 0) }
        return (Int64(values.volumeTotalCapacity ?? 1),
                values.volumeAvailableCapacityForImportantUsage ?? 0)
    }
}

// MARK: - 실시간 모니터 (2초 주기)

@MainActor
final class SystemMonitor: ObservableObject {
    @Published var snapshot = SystemSnapshot()
    @Published var machine = MachineInfo()

    private var timer: Timer?
    private var lastCPUTicks: (busy: UInt64, total: UInt64)?
    private var lastNet: (down: UInt64, up: UInt64)?
    private var lastNetTime: Date?
    private var lastDiskIO: (read: UInt64, written: UInt64)?
    private var tickCount = 0
    private var machineLoaded = false
    private var activeObserver: NSObjectProtocol?
    private var inactiveObserver: NSObjectProtocol?

    /// 기기 정보는 바뀌지 않으므로 최초 1회만 조회
    private func loadMachineIfNeeded() {
        guard !machineLoaded else { return }
        machine = SystemProbe.machineInfo()
        machineLoaded = true
    }

    func start() {
        guard activeObserver == nil else { return }  // 이미 관리 중이면 무시
        loadMachineIfNeeded()
        observeActivation()
        // 시작 시점에 앱이 활성이면 즉시 폴링, 아니면 대기
        if NSApp.isActive { resumePolling() }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        for obs in [activeObserver, inactiveObserver].compactMap({ $0 }) {
            NotificationCenter.default.removeObserver(obs)
        }
        activeObserver = nil
        inactiveObserver = nil
    }

    /// 앱이 백그라운드로 가면(다른 앱 사용 중) 폴링을 멈추고, 다시 앞으로 오면 재개.
    /// 사용자가 화면을 보고 있지 않을 때의 CPU/전력 낭비를 없앤다.
    private func observeActivation() {
        activeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.resumePolling() }
        }
        inactiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.pausePolling() }
        }
    }

    private func resumePolling() {
        guard timer == nil else { return }
        tick()
        let t = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        t.tolerance = 0.5  // 발화를 최대 0.5초까지 묶어 전력 절약
        timer = t
    }

    private func pausePolling() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        var snap = snapshot

        if let ticks = SystemProbe.cpuTicks() {
            if let last = lastCPUTicks, ticks.total > last.total {
                snap.cpuUsage = Double(ticks.busy - last.busy) / Double(ticks.total - last.total)
            }
            lastCPUTicks = ticks
        }

        snap.memUsed = SystemProbe.usedMemory()
        snap.memTotal = ProcessInfo.processInfo.physicalMemory

        let net = SystemProbe.networkBytes()
        let now = Date()
        let diskIO = SystemProbe.diskIOBytes()
        if let last = lastNet, let lastTime = lastNetTime {
            let dt = now.timeIntervalSince(lastTime)
            if dt > 0 {
                snap.netDownPerSec = Double(net.down &- last.down) / dt
                snap.netUpPerSec = Double(net.up &- last.up) / dt
                if let lastIO = lastDiskIO {
                    snap.diskReadPerSec = Double(diskIO.read &- lastIO.read) / dt
                    snap.diskWritePerSec = Double(diskIO.written &- lastIO.written) / dt
                }
            }
        }
        lastNet = net
        lastNetTime = now
        lastDiskIO = diskIO

        if let battery = SystemProbe.battery() {
            snap.batteryPercent = battery.percent
            snap.batteryCharging = battery.charging
        }
        snap.thermalState = ProcessInfo.processInfo.thermalState

        // 디스크/휴지통은 무거우므로 10초에 한 번만 (백그라운드)
        if tickCount % 5 == 0 {
            Task.detached(priority: .utility) {
                let disk = SystemProbe.disk()
                let trash = DiskUtil.directorySize(
                    FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
                )
                await MainActor.run {
                    self.snapshot.diskTotal = disk.total
                    self.snapshot.diskFree = disk.free
                    self.snapshot.diskUsed = disk.total - disk.free
                    self.snapshot.trashSize = trash
                }
            }
        }
        tickCount += 1
        snapshot = snap
    }
}

// MARK: - 시스템 동작 (메모리 정리 / 휴지통 비우기)

enum SystemActions {
    /// 관리자 권한으로 purge 실행 (비밀번호 프롬프트 표시됨)
    static func purgeMemory() async -> Bool {
        await runOSAScript("do shell script \"/usr/sbin/purge\" with administrator privileges")
    }

    /// Finder로 휴지통 비우기 (자동화 권한 프롬프트가 뜰 수 있음)
    static func emptyTrash() async -> Bool {
        if await runOSAScript("tell application \"Finder\" to empty trash") {
            return true
        }
        // Finder 자동화가 거부되면 직접 삭제
        let trash = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: trash, includingPropertiesForKeys: nil
        ) else { return false }
        var ok = true
        for item in items {
            do { try FileManager.default.removeItem(at: item) } catch { ok = false }
        }
        return ok
    }

    /// 임의의 셸 명령을 관리자 권한으로 실행 (암호 프롬프트 1회)
    static func runShellAsAdmin(_ command: String) async -> Bool {
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return await runOSAScript("do shell script \"\(escaped)\" with administrator privileges")
    }

    private static func runOSAScript(_ script: String) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                task.arguments = ["-e", script]
                task.standardError = Pipe()
                task.standardOutput = Pipe()
                do {
                    try task.run()
                    task.waitUntilExit()
                    continuation.resume(returning: task.terminationStatus == 0)
                } catch {
                    continuation.resume(returning: false)
                }
            }
        }
    }
}
