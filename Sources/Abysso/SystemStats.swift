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

    /// 기기 정보는 바뀌지 않으므로 최초 1회만 조회
    private func loadMachineIfNeeded() {
        guard !machineLoaded else { return }
        machine = SystemProbe.machineInfo()
        machineLoaded = true
    }

    /// 폴링 시작 (idempotent). 뷰가 화면에 보이고 앱이 활성일 때만 뷰가 호출한다.
    func start() {
        guard timer == nil else { return }
        loadMachineIfNeeded()
        tick()
        let t = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        t.tolerance = 0.5  // 발화를 최대 0.5초까지 묶어 전력 절약
        timer = t
    }

    /// 폴링 완전 정지 — 뷰가 사라지거나 앱이 백그라운드로 갈 때 호출.
    /// 타이머를 무효화하므로 백그라운드에서 CPU 점유율이 0%로 수렴한다.
    func stop() {
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
                // 카운터가 역행하면(절전 해제·인터페이스 리셋·VPN 등) 래핑 뺄셈이
                // UInt64.max 근처의 거대한 값이 되므로 그 틱은 0으로 처리한다.
                snap.netDownPerSec = net.down >= last.down ? Double(net.down - last.down) / dt : 0
                snap.netUpPerSec = net.up >= last.up ? Double(net.up - last.up) / dt : 0
                if let lastIO = lastDiskIO {
                    snap.diskReadPerSec = diskIO.read >= lastIO.read ? Double(diskIO.read - lastIO.read) / dt : 0
                    snap.diskWritePerSec = diskIO.written >= lastIO.written ? Double(diskIO.written - lastIO.written) / dt : 0
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
    /// 비관리자 메모리 확보 — 암호 프롬프트 없이 동작한다.
    /// 가용 RAM을 잠시 강제 할당(커밋)했다가 즉시 해제해 시스템이
    /// 비활성 메모리를 스스로 압축·회수하도록 유도한다 (App Store 계열 최적화 앱 방식).
    static func purgeMemory() async -> Bool {
        #if DEBUG
        if !DevMode.shouldRunCommand("메모리 압박으로 비활성 메모리 회수 (비관리자)") { return true }
        #endif
        return await Task.detached(priority: .userInitiated) {
            applyMemoryPressure()
        }.value
    }

    /// 64MB 단위로 할당·커밋을 반복하다가 시스템 여유가 1GB 아래로
    /// 내려가면 중단하고 전부 해제한다. 물리 RAM의 절반을 안전 상한으로 둔다.
    nonisolated private static func applyMemoryPressure() -> Bool {
        let chunkSize = 64 * 1024 * 1024
        let total = ProcessInfo.processInfo.physicalMemory
        let keepFree: UInt64 = 1 << 30       // 최소 1GB는 남겨 시스템 멈춤 방지
        let maxAllocate = total / 2          // 안전 상한: 물리 RAM의 절반
        var chunks: [UnsafeMutableRawPointer] = []
        var allocated: UInt64 = 0

        while allocated < maxAllocate {
            let used = SystemProbe.usedMemory()
            guard total > used, total - used > keepFree else { break }
            guard let p = malloc(chunkSize) else { break }
            memset(p, 0x5A, chunkSize)       // 실제 페이지 커밋을 강제해 압박 발생
            chunks.append(p)
            allocated += UInt64(chunkSize)
        }
        for p in chunks { free(p) }
        return true
    }

    /// Finder로 휴지통 비우기 (자동화 권한 프롬프트가 뜰 수 있음)
    static func emptyTrash() async -> Bool {
        #if DEBUG
        if !DevMode.shouldRunCommand("휴지통 비우기 (Finder empty trash)") { return true }
        #endif
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
        #if DEBUG
        if !DevMode.shouldRunCommand("관리자 셸: \(command)") { return true }
        #endif
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
