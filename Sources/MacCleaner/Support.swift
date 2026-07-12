import Foundation

enum Format {
    static func bytes(_ n: Int64) -> String {
        // ByteCountFormatter는 0을 "Zero KB"로 표기하므로 직접 처리
        guard n > 0 else { return "0 KB" }
        return ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
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
        (try? FileManager.default.trashItem(at: url, resultingItemURL: nil)) != nil
    }
}
