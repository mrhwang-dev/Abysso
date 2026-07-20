#if DEBUG
import SwiftUI

// ============================================================================
//  개발/테스트 전용 안전 장치 — 이 파일 전체가 #if DEBUG로 감싸져 있어
//  `swift build -c release`(DMG 빌드)에서는 컴파일에서 완전히 제외된다.
//  따라서 배포 시 별도 코드 수정 없이 아래 기능들이 자동으로 사라진다.
//
//  1) Dry-Run 모드: 실제 삭제/시스템 명령을 전부 차단하고 [DRY-RUN] 로그만 남긴다.
//  2) 샌드박스 모드: 스캐너가 /tmp/AbyssoTestSandbox 도 함께 추적하고,
//     실제 삭제는 이 폴더 내부로만 제한한다(외부 파일 보호).
//  3) 더미 정크 데이터 생성기 + 인앱 디버그 로그 뷰 + 개발자 환경설정 탭.
// ============================================================================

struct DevLogEntry: Identifiable {
    let id = UUID()
    let time = Date()
    let text: String   // "🗑️ 삭제 예정 파일: …" 형태 (아이콘 포함)
}

final class DevMode: ObservableObject {
    static let shared = DevMode()

    private enum Key {
        static let dryRun = "dev.dryRun"
        static let sandbox = "dev.sandboxScan"
    }

    /// 안전 모드: 실제 삭제/명령을 전부 차단하고 로그만 남긴다.
    @Published var isDryRun: Bool {
        didSet { UserDefaults.standard.set(isDryRun, forKey: Key.dryRun) }
    }
    /// 샌드박스 스캔: 스캐너가 /tmp/AbyssoTestSandbox 를 함께 추적하고,
    /// 실제 삭제는 샌드박스 내부로만 제한한다.
    @Published var isSandboxScan: Bool {
        didSet { UserDefaults.standard.set(isSandboxScan, forKey: Key.sandbox) }
    }
    @Published private(set) var logs: [DevLogEntry] = []

    static let sandboxRoot = "/tmp/AbyssoTestSandbox"
    /// /tmp 는 /private/tmp 심볼릭 링크이므로 내부/외부 판정을 위해 실제 경로로 해석해 둔다.
    static let resolvedSandboxRoot = URL(fileURLWithPath: sandboxRoot).resolvingSymlinksInPath().path

    private init() {
        isDryRun = UserDefaults.standard.bool(forKey: Key.dryRun)
        isSandboxScan = UserDefaults.standard.bool(forKey: Key.sandbox)
    }

    // MARK: 스레드 안전 정적 읽기 (백그라운드 nonisolated 함수용)

    static var dryRunEnabled: Bool { UserDefaults.standard.bool(forKey: Key.dryRun) }
    static var sandboxScanEnabled: Bool { UserDefaults.standard.bool(forKey: Key.sandbox) }

    static func isInsideSandbox(_ url: URL) -> Bool {
        url.resolvingSymlinksInPath().path.hasPrefix(resolvedSandboxRoot)
    }

    // MARK: 로깅 (어떤 스레드에서든 호출 가능)

    static func log(_ tag: String, _ icon: String, _ text: String) {
        let display = "\(icon) \(text)"
        print("[\(tag)] \(display)")   // Xcode 콘솔 출력
        let entry = DevLogEntry(text: display)
        DispatchQueue.main.async {
            shared.logs.append(entry)
            if shared.logs.count > 800 {
                shared.logs.removeFirst(shared.logs.count - 800)
            }
        }
    }

    func clearLogs() { logs.removeAll() }

    // MARK: 삭제/명령 게이트 (choke point 공통 진입점)

    /// 실제 삭제를 수행해도 되는지 판단한다.
    /// - Returns: true면 호출측이 실제 삭제 진행, false면 건너뛰고 성공 처리(로그만 남김).
    static func shouldPerformDelete(_ url: URL) -> Bool {
        if dryRunEnabled {
            log("DRY-RUN", "🗑️", "삭제 예정 파일: \(url.path)")
            return false
        }
        if sandboxScanEnabled {
            if isInsideSandbox(url) {
                log("SANDBOX", "🧹", "샌드박스 파일 실제 삭제: \(url.path)")
                return true   // 샌드박스 내부만 물리적으로 삭제
            }
            log("SANDBOX", "🛡️", "샌드박스 외부 보호 — 실제 삭제 차단: \(url.path)")
            return false
        }
        return true   // 일반 모드
    }

    /// 시스템 명령을 실제로 실행해도 되는지 판단한다. 테스트 모드에서는 전부 차단.
    /// - Returns: true면 실제 실행, false면 건너뛰고 성공 처리(로그만 남김).
    static func shouldRunCommand(_ description: String) -> Bool {
        if dryRunEnabled {
            log("DRY-RUN", "⚙️", "실행 예정 시스템 명령: \(description)")
            return false
        }
        if sandboxScanEnabled {
            log("SANDBOX", "⚙️", "테스트 모드 — 시스템 명령 차단: \(description)")
            return false
        }
        return true
    }

    // MARK: 테스트용 더미 정크 데이터 생성기

    /// /tmp/AbyssoTestSandbox 를 초기화하고 가짜 캐시·로그·대용량·앱 찌꺼기를 생성한다.
    @discardableResult
    static func generateSandbox() -> String {
        let fm = FileManager.default
        let root = URL(fileURLWithPath: sandboxRoot)
        try? fm.removeItem(at: root)   // 재생성 시 초기화 (기존 DMG 정리 로직과 동일 취지)

        let cachesDir = root.appendingPathComponent("Caches/com.fake.browser")
        let logsDir = root.appendingPathComponent("Logs")
        let leftoverDir = root.appendingPathComponent("Application Support/com.fake.deadapp")
        let leftoverCache = root.appendingPathComponent("Caches/com.fake.deadapp")
        for dir in [cachesDir, logsDir, leftoverDir, leftoverCache] {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        // 1) 가짜 시스템 캐시 및 로그 (수십 MB)
        writeDummyFile(cachesDir.appendingPathComponent("cache_blob.bin"), megabytes: 22)
        writeDummyFile(cachesDir.appendingPathComponent("thumbnails.cache"), megabytes: 14)
        writeDummyFile(logsDir.appendingPathComponent("diagnostic.log"), megabytes: 8)
        writeDummyFile(logsDir.appendingPathComponent("crash_20260101.log"), megabytes: 3)

        // 2) 가짜 대용량 파일 3개 (모두 50MB 이상)
        writeDummyFile(root.appendingPathComponent("big_video.mp4"), megabytes: 60)
        writeDummyFile(root.appendingPathComponent("archive_backup.zip"), megabytes: 80)
        writeDummyFile(root.appendingPathComponent("disk_image.dmg"), megabytes: 120)

        // 3) 가짜 '응용 프로그램 찌꺼기' 구조
        writeDummyFile(leftoverDir.appendingPathComponent("Data.blob"), megabytes: 12)
        writeDummyFile(leftoverDir.appendingPathComponent("settings.plist"), megabytes: 1)
        writeDummyFile(leftoverCache.appendingPathComponent("orphan.cache"), megabytes: 6)

        log("SANDBOX", "🧪", "더미 데이터 생성 완료: \(sandboxRoot)")
        return sandboxRoot
    }

    static func removeSandbox() {
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: sandboxRoot))
        log("SANDBOX", "🧼", "샌드박스 폴더 정리 완료: \(sandboxRoot)")
    }

    static var sandboxExists: Bool {
        FileManager.default.fileExists(atPath: sandboxRoot)
    }

    static var sandboxSize: Int64 {
        sandboxExists ? DiskUtil.directorySize(URL(fileURLWithPath: sandboxRoot)) : 0
    }

    /// 압축/스파스 최적화로 할당 크기가 0이 되지 않도록 0이 아닌 패턴으로 실제 바이트를 쓴다.
    private static func writeDummyFile(_ url: URL, megabytes: Int) {
        let fm = FileManager.default
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        fm.createFile(atPath: url.path, contents: nil)
        guard let handle = FileHandle(forWritingAtPath: url.path) else { return }
        defer { try? handle.close() }
        let chunk = Data(repeating: 0xAB, count: 1 << 20)   // 1MB
        for _ in 0..<megabytes {
            try? handle.write(contentsOf: chunk)
        }
    }
}

// ============================================================================
//  개발자 환경설정 탭 (SettingsView의 TabView에 #if DEBUG로 추가됨)
// ============================================================================

struct DeveloperSettingsView: View {
    @ObservedObject private var dev = DevMode.shared
    @State private var sandboxInfo = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    modeToggles
                    sandboxCard
                    logCard
                }
                .padding(20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.bgTop)
        .onAppear { refreshInfo() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "hammer.fill")
                .font(.system(size: 22))
                .foregroundStyle(Theme.orange)
            VStack(alignment: .leading, spacing: 1) {
                Text("개발자 테스트 도구")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                Text("DEBUG 빌드 전용 — 릴리스(DMG)에서는 자동 제외됩니다")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(20)
    }

    private var modeToggles: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $dev.isDryRun) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("안전 모드 (Dry-Run)").font(.callout.weight(.medium))
                    Text("실제 삭제·시스템 명령을 전부 차단하고 [DRY-RUN] 로그만 남깁니다")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch).tint(Theme.green)

            Divider().opacity(0.4)

            Toggle(isOn: $dev.isSandboxScan) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("테스트 샌드박스 스캔 포함").font(.callout.weight(.medium))
                    Text("스캐너가 /tmp/AbyssoTestSandbox 도 추적하고, 실제 삭제는 이 폴더 내부로만 제한합니다")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch).tint(Theme.orange)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var sandboxCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("테스트용 더미 정크 파일").font(.headline)
            Text(sandboxInfo.isEmpty ? "샌드박스가 아직 없습니다." : sandboxInfo)
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button {
                    DevMode.generateSandbox()
                    refreshInfo()
                } label: {
                    Label("더미 정크 파일 생성", systemImage: "testtube.2")
                }
                .buttonStyle(.borderedProminent).tint(Theme.purple)

                Button {
                    DevMode.removeSandbox()
                    refreshInfo()
                } label: {
                    Label("샌드박스 정리", systemImage: "trash")
                }
                .disabled(!DevMode.sandboxExists)

                Button {
                    NSWorkspace.shared.activateFileViewerSelecting(
                        [URL(fileURLWithPath: DevMode.sandboxRoot)]
                    )
                } label: {
                    Image(systemName: "folder")
                }
                .disabled(!DevMode.sandboxExists)
                .help("Finder에서 보기")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var logCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("디버그 로그").font(.headline)
                Spacer()
                Text("\(dev.logs.count)개")
                    .font(.caption).foregroundStyle(.secondary)
                Button("지우기") { dev.clearLogs() }
                    .controlSize(.small)
                    .disabled(dev.logs.isEmpty)
            }
            if dev.logs.isEmpty {
                Text("아직 기록이 없습니다. 안전/샌드박스 모드를 켠 뒤 스캔·삭제를 실행해 보세요.")
                    .font(.caption).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(dev.logs.reversed()) { entry in
                            Text(entry.text)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .frame(height: 160)
                .padding(8)
                .background(Theme.bgBottom, in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func refreshInfo() {
        if DevMode.sandboxExists {
            sandboxInfo = "경로: \(DevMode.sandboxRoot)\n현재 크기: \(Format.bytes(DevMode.sandboxSize))"
        } else {
            sandboxInfo = ""
        }
    }
}
#endif
