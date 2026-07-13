import SwiftUI

// MARK: - 모델

struct BrewPackage: Identifiable {
    let name: String
    let current: String
    let latest: String
    var id: String { name }
}

@MainActor
final class UpdaterModel: ObservableObject {
    @Published var brewPackages: [BrewPackage] = []
    @Published var osUpdates: [String] = []
    @Published var scanningBrew = false
    @Published var scanningOS = false
    @Published var scanned = false
    @Published var brewMissing = false
    @Published var upgrading: Set<String> = []
    @Published var message: String?

    nonisolated static var brewPath: String? {
        for path in ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
        where FileManager.default.fileExists(atPath: path) {
            return path
        }
        return nil
    }

    func scan() {
        scanned = true
        message = nil
        scanBrew()
        scanOS()
    }

    private func scanBrew() {
        guard let brew = Self.brewPath else {
            brewMissing = true
            return
        }
        scanningBrew = true
        Task.detached(priority: .userInitiated) {
            let output = LaunchAgentManager.run(brew, ["outdated", "--verbose"]).output
            var packages: [BrewPackage] = []
            // 형식: "wget (1.21.3) < 1.24.5"
            for line in output.split(separator: "\n") {
                let parts = line.split(separator: "<", maxSplits: 1)
                guard parts.count == 2 else { continue }
                let left = parts[0].trimmingCharacters(in: .whitespaces)
                let latest = parts[1].trimmingCharacters(in: .whitespaces)
                guard let parenIndex = left.firstIndex(of: "(") else { continue }
                let name = String(left[..<parenIndex]).trimmingCharacters(in: .whitespaces)
                let current = left[left.index(after: parenIndex)...]
                    .trimmingCharacters(in: CharacterSet(charactersIn: ") "))
                packages.append(BrewPackage(name: name, current: current, latest: latest))
            }
            let result = packages
            await MainActor.run {
                self.brewPackages = result
                self.scanningBrew = false
            }
        }
    }

    private func scanOS() {
        scanningOS = true
        Task.detached(priority: .userInitiated) {
            let output = LaunchAgentManager.run(
                "/usr/sbin/softwareupdate", ["-l"]
            ).output
            var updates: [String] = []
            for line in output.split(separator: "\n") {
                let s = line.trimmingCharacters(in: .whitespaces)
                if s.hasPrefix("* Label:") {
                    updates.append(s.replacingOccurrences(of: "* Label:", with: "")
                        .trimmingCharacters(in: .whitespaces))
                }
            }
            let result = updates
            await MainActor.run {
                self.osUpdates = result
                self.scanningOS = false
            }
        }
    }

    func upgrade(_ package: BrewPackage) {
        guard let brew = Self.brewPath else { return }
        upgrading.insert(package.name)
        Task.detached(priority: .userInitiated) {
            let result = LaunchAgentManager.run(brew, ["upgrade", package.name])
            await MainActor.run {
                self.upgrading.remove(package.name)
                if result.status == 0 {
                    self.brewPackages.removeAll { $0.name == package.name }
                    self.message = "\(package.name) 업그레이드 완료"
                } else {
                    self.message = "\(package.name) 업그레이드 실패 — 터미널에서 brew upgrade \(package.name) 를 실행해보세요"
                }
            }
        }
    }

    func upgradeAll() {
        for package in brewPackages { upgrade(package) }
    }
}

// MARK: - 뷰

struct UpdaterView: View {
    @EnvironmentObject private var model: UpdaterModel

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(
                title: "업데이트 관리",
                subtitle: "Homebrew 패키지와 macOS 시스템 업데이트를 한곳에서 확인합니다",
                icon: "arrow.triangle.2.circlepath", iconColor: Theme.green
            )
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 12)

            if !model.scanned {
                emptyStartView
            } else {
                resultView
            }
        }
        .background(Theme.background)
    }

    private var emptyStartView: some View {
        ZStack {
            ParticleField()
            VStack(spacing: 16) {
                Spacer()
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 56))
                    .foregroundStyle(Theme.green.gradient)
                Text("모든 것을 최신 상태로")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                Text("macOS 시스템 업데이트와 터미널로 설치한 도구(Homebrew)의\n새 버전을 확인합니다. macOS 확인은 수십 초 걸릴 수 있어요.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                PulsingGlow(color: Theme.green) {
                    ProminentScanButton(title: "업데이트 확인", systemImage: "arrow.triangle.2.circlepath") {
                        model.scan()
                    }
                }
                .padding(.top, 6)
                Spacer()
            }
        }
    }

    private var resultView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let msg = model.message {
                    Label(msg, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Theme.green)
                }

                // macOS 업데이트
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("macOS 시스템 업데이트", systemImage: "apple.logo")
                            .font(.headline)
                            .foregroundStyle(Theme.blue)
                        Spacer()
                        if model.scanningOS {
                            ProgressView().controlSize(.small)
                            Text("Apple 서버 조회 중…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if !model.scanningOS {
                        if model.osUpdates.isEmpty {
                            Label("macOS가 최신 상태입니다", systemImage: "checkmark.seal.fill")
                                .foregroundStyle(Theme.green)
                        } else {
                            ForEach(model.osUpdates, id: \.self) { update in
                                HStack {
                                    Image(systemName: "arrow.down.circle.fill")
                                        .foregroundStyle(Theme.orange)
                                    Text(update)
                                    Spacer()
                                }
                            }
                            Button {
                                NSWorkspace.shared.open(URL(
                                    string: "x-apple.systempreferences:com.apple.Software-Update-Settings.extension"
                                )!)
                            } label: {
                                Label("시스템 설정에서 업데이트", systemImage: "gear")
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Theme.blue)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()

                // Homebrew
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("터미널 및 외부 패키지 (Homebrew)", systemImage: "shippingbox.fill")
                            .font(.headline)
                            .foregroundStyle(Theme.orange)
                        Spacer()
                        if model.scanningBrew {
                            ProgressView().controlSize(.small)
                        } else if !model.brewPackages.isEmpty {
                            Button("모두 업그레이드") { model.upgradeAll() }
                                .buttonStyle(.borderedProminent)
                                .tint(Theme.orange)
                                .controlSize(.small)
                                .disabled(!model.upgrading.isEmpty)
                        }
                    }
                    if model.brewMissing {
                        Text("터미널 패키지 관리자(Homebrew)가 설치되어 있지 않아 확인을 건너뜁니다")
                            .foregroundStyle(.secondary)
                    } else if !model.scanningBrew {
                        if model.brewPackages.isEmpty {
                            Label("모든 패키지가 최신 상태입니다", systemImage: "checkmark.seal.fill")
                                .foregroundStyle(Theme.green)
                        } else {
                            ForEach(model.brewPackages) { package in
                                HStack {
                                    Text(package.name)
                                        .font(.system(.body, design: .monospaced))
                                    Spacer()
                                    Text("\(package.current) → \(package.latest)")
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                        .monospacedDigit()
                                    if model.upgrading.contains(package.name) {
                                        ProgressView().controlSize(.small)
                                    } else {
                                        Button("업그레이드") { model.upgrade(package) }
                                            .buttonStyle(.bordered)
                                            .controlSize(.small)
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()

                HStack {
                    Spacer()
                    Button {
                        model.scan()
                    } label: {
                        Label("다시 확인", systemImage: "arrow.clockwise")
                    }
                    .disabled(model.scanningBrew || model.scanningOS)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
    }
}
