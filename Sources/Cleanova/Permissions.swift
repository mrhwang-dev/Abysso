import SwiftUI

enum Permissions {
    /// TCC 보호 경로를 실제로 열어봐서 전체 디스크 접근 권한 확인
    static func hasFullDiskAccess() -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let probes = [
            home.appendingPathComponent("Library/Safari/CloudTabs.db"),
            home.appendingPathComponent("Library/Safari/Bookmarks.plist"),
        ]
        for url in probes where FileManager.default.fileExists(atPath: url.path) {
            if let handle = FileHandle(forReadingAtPath: url.path) {
                try? handle.close()
                return true
            }
            return false
        }
        // 파일이 없으면 폴더 열람으로 판정
        let safariDir = home.appendingPathComponent("Library/Safari")
        return (try? FileManager.default.contentsOfDirectory(atPath: safariDir.path)) != nil
    }

    static func openFullDiskAccessSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
        NSWorkspace.shared.open(url)
    }
}

// MARK: - FDA 안내 모달

struct FullDiskAccessSheet: View {
    @Binding var isPresented: Bool
    @AppStorage("fdaPromptSuppressed") private var suppressed = false
    @State private var granted = false

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: granted ? "checkmark.shield.fill" : "lock.shield.fill")
                .font(.system(size: 46))
                .foregroundStyle(granted ? Theme.green.gradient : Theme.blue.gradient)
                .padding(.top, 6)

            Text(granted ? "권한이 확인되었습니다!" : "전체 디스크 접근 권한이 필요합니다")
                .font(.system(size: 19, weight: .bold, design: .rounded))

            if granted {
                Text("이제 모든 캐시와 로그를 빠짐없이 스캔할 수 있습니다.")
                    .foregroundStyle(.secondary)
                Button("시작하기") { isPresented = false }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.teal)
                    .controlSize(.large)
            } else {
                Text("권한이 없으면 숨겨진 캐시·시스템 로그·일부 앱 데이터를 스캔할 수\n없어 정리 가능한 공간이 실제보다 적게 표시됩니다.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 10) {
                    step(1, "아래 버튼으로 시스템 설정을 엽니다")
                    step(2, "목록에서 Cleanova 스위치를 켭니다")
                    step(3, "안내에 따라 앱을 다시 실행합니다")
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))

                HStack(spacing: 10) {
                    Button {
                        Permissions.openFullDiskAccessSettings()
                    } label: {
                        Label("시스템 설정 열기", systemImage: "gear")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.blue)
                    .controlSize(.large)

                    Button("권한 다시 확인") {
                        granted = Permissions.hasFullDiskAccess()
                    }
                    .controlSize(.large)
                }

                HStack {
                    Toggle("다시 표시하지 않음", isOn: $suppressed)
                        .toggleStyle(.checkbox)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("나중에") { isPresented = false }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 2)
            }
        }
        .padding(24)
        .frame(width: 440)
        .background(Theme.bgTop)
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(spacing: 10) {
            Text("\(n)")
                .font(.caption.bold())
                .frame(width: 20, height: 20)
                .background(Theme.blue.opacity(0.25), in: Circle())
            Text(text)
                .font(.callout)
        }
    }
}
