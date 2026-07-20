import Foundation

enum Format {
    static func bytes(_ n: Int64) -> String {
        // ByteCountFormatter는 0을 "Zero KB"로 표기하므로 직접 처리
        guard n > 0 else { return "0 KB" }
        return ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
    }

    /// Double 입력용 안전 변환 — NaN/무한대/Int64 범위 초과 값(네트워크 카운터 역행 등)에서
    /// Int64(Double) 런타임 트랩이 나지 않도록 잘라낸다.
    static func bytes(_ value: Double) -> String {
        guard value.isFinite, value > 0 else { return bytes(Int64(0)) }
        return bytes(Int64(min(value, 9.2e18)))  // Int64.max 바로 아래로 클램프
    }

    /// 전송 속도(네트워크·디스크 I/O) 포맷 — ByteCountFormatter는 로케일에 따라
    /// "바이트"처럼 단위를 현지화하므로 쓰지 않고, 언어 설정과 무관하게
    /// IT 표준 표기(B/s, KB/s, MB/s, GB/s)로 통일해 출력한다.
    static func speed(_ bytesPerSec: Double) -> String {
        guard bytesPerSec.isFinite, bytesPerSec >= 1 else { return "0 KB/s" }
        let units = ["B/s", "KB/s", "MB/s", "GB/s", "TB/s"]
        var value = min(bytesPerSec, 9.2e18)
        var i = 0
        while value >= 1000, i < units.count - 1 {
            value /= 1000
            i += 1
        }
        // 세 자리 이상·B/s 단위·정수로 떨어지는 값은 소수점 없이, 그 외에는 한 자리
        let rounded = (value * 10).rounded() / 10
        let number = (value >= 100 || i == 0 || rounded == rounded.rounded())
            ? String(format: "%.0f", locale: .current, rounded)
            : String(format: "%.1f", locale: .current, rounded)
        return "\(number) \(units[i])"
    }

    /// 크기를 알 수 없는 항목(0 이하)은 별도 문구로
    static let unknownSize = "용량 확인 불가"
}

enum DiskUtil {
    /// 디렉터리 전체 크기. 심볼릭 링크는 해석하고, 열거가 막히면 du로 폴백.
    static func directorySize(_ url: URL) -> Int64 {
        let resolved = url.resolvingSymlinksInPath()
        let keys: [URLResourceKey] = [
            .isRegularFileKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey, .fileSizeKey,
        ]
        var total: Int64 = 0
        if let enumerator = FileManager.default.enumerator(
            at: resolved,
            includingPropertiesForKeys: keys,
            options: [],
            errorHandler: { _, _ in true }
        ) {
            for case let fileURL as URL in enumerator {
                guard let values = try? fileURL.resourceValues(forKeys: Set(keys)),
                      values.isRegularFile == true else { continue }
                total += Int64(
                    values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0
                )
            }
        }
        // 권한/SIP 등으로 열거가 통째로 막힌 경우 du로 재시도
        if total == 0 {
            total = duSize(resolved)
        }
        return total
    }

    /// du -sk 폴백 (1KB 블록 단위)
    static func duSize(_ url: URL) -> Int64 {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/du")
        task.arguments = ["-sk", url.path]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        guard (try? task.run()) != nil else { return 0 }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard let output = String(data: data, encoding: .utf8),
              let kb = Int64(output.split(separator: "\t").first ?? "") else { return 0 }
        return kb * 1024
    }

    static func itemSize(_ url: URL) -> Int64 {
        let resolved = url.resolvingSymlinksInPath()
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: resolved.path, isDirectory: &isDir) else { return 0 }
        if isDir.boolValue { return directorySize(resolved) }
        let values = try? resolved.resourceValues(forKeys: [
            .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey,
        ])
        return Int64(
            values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? values?.fileSize ?? 0
        )
    }

    /// 휴지통으로 이동. 성공하면 true.
    @discardableResult
    static func trash(_ url: URL) -> Bool {
        #if DEBUG
        // 안전/샌드박스 모드에서는 실제 이동을 차단(로그만)하고 성공으로 처리해 로직 끝단까지 도달시킨다.
        if !DevMode.shouldPerformDelete(url) { return true }
        #endif
        return (try? FileManager.default.trashItem(at: url, resultingItemURL: nil)) != nil
    }
}

struct TimeEstimator {
    let startTime: Date
    
    init(startTime: Date = Date()) {
        self.startTime = startTime
    }
    
    func remainingTimeText(progress: Double) -> String? {
        guard progress > 0 && progress < 1.0 else { return nil }
        let elapsed = Date().timeIntervalSince(startTime)
        if elapsed < 0.5 { return NSLocalizedString("계산 중...", comment: "") }
        
        let totalEstimated = elapsed / progress
        let remaining = totalEstimated - elapsed
        
        if remaining < 1 {
            return NSLocalizedString("곧 완료됨", comment: "")
        } else if remaining < 60 {
            return String(format: NSLocalizedString("약 %d초 남음", comment: ""), Int(remaining))
        } else {
            let mins = Int(remaining) / 60
            let secs = Int(remaining) % 60
            return String(format: NSLocalizedString("약 %d분 %d초 남음", comment: ""), mins, secs)
        }
    }
}
