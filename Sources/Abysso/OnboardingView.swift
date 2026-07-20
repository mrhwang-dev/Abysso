import SwiftUI

/// 최초 실행 시 표시되는 온보딩. 환영 → EULA 동의 → 전체 디스크 접근 권한 안내 순.
/// 완료하면 UserDefaults의 onboardingCompleted 플래그가 저장되어 다시 뜨지 않는다.
struct OnboardingView: View {
    @Binding var isPresented: Bool
    @AppStorage("onboardingCompleted") private var completed = false
    @AppStorage("fdaPromptSuppressed") private var fdaSuppressed = false

    enum Step { case welcome, eula, permission }
    @State private var step: Step = .welcome
    @State private var agreedEULA = false
    @State private var fdaGranted = false

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
            Divider().opacity(0.4)
            footer
        }
        .frame(width: 560, height: 560)
        .background(Theme.background)
        .preferredColorScheme(.dark)
    }

    // MARK: 단계별 콘텐츠

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome: welcomeStep
        case .eula: eulaStep
        case .permission: permissionStep
        }
    }

    private var welcomeStep: some View {
        VStack(spacing: 20) {
            Spacer()
            AnimatedAppIcon()
            VStack(spacing: 8) {
                Text("Abysso에 오신 것을 환영합니다")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                Text("Welcome to Abysso")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Text("Mac을 가볍고 깨끗하게 유지하는 올인원 관리 도구입니다.\n캐시 정리부터 대용량 파일 정리, 개인정보 보호까지\n한곳에서 관리하세요.")
                .multilineTextAlignment(.center)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineSpacing(3)
            Spacer()
        }
        .padding(40)
    }

    private var eulaStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            stepHeader(icon: "doc.text.fill", tint: Theme.blue,
                       title: "이용 약관", subtitle: "계속하려면 아래 내용에 동의해 주세요")

            ScrollView {
                Text(Self.eulaText)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            }
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
            .frame(maxHeight: .infinity)

            Toggle(isOn: $agreedEULA) {
                Text("위 이용 약관 및 면책 조항을 읽고 이에 동의합니다.")
                    .font(.callout)
            }
            .toggleStyle(.checkbox)
            .tint(Theme.teal)
        }
        .padding(28)
    }

    private var permissionStep: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: fdaGranted ? "checkmark.shield.fill" : "lock.shield.fill")
                .font(.system(size: 52))
                .foregroundStyle(fdaGranted ? Theme.green.gradient : Theme.blue.gradient)
            Text(fdaGranted ? "권한이 확인되었습니다!" : "전체 디스크 접근 권한")
                .font(.system(size: 20, weight: .bold, design: .rounded))
            if fdaGranted {
                Text("모든 캐시와 로그를 빠짐없이 스캔할 수 있습니다.\n이제 Abysso를 시작할 준비가 끝났습니다.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            } else {
                Text("권한이 없으면 숨겨진 캐시·시스템 로그·일부 앱 데이터를 스캔할 수\n없어 정리 가능한 공간이 실제보다 적게 표시됩니다. 지금 허용하는 것을\n권장하지만, 나중에 환경설정에서 설정할 수도 있습니다.")
                    .multilineTextAlignment(.center)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)

                VStack(alignment: .leading, spacing: 10) {
                    permStep(1, "‘시스템 설정 열기’를 누릅니다")
                    permStep(2, "목록에서 Abysso 스위치를 켭니다")
                    permStep(3, "스위치를 켜면 자동으로 인식됩니다")
                }
                .padding(14)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))

                HStack(spacing: 10) {
                    Button {
                        Permissions.openFullDiskAccessSettings()
                    } label: {
                        Label("시스템 설정 열기", systemImage: "gear")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.blue)
                    Button("권한 다시 확인") {
                        withAnimation { fdaGranted = Permissions.hasFullDiskAccess() }
                    }
                }
            }
            Spacer()
        }
        .padding(32)
        .onAppear { fdaGranted = Permissions.hasFullDiskAccess() }
        .task {
            // 시스템 설정에서 스위치를 켜면 자동 감지해 성공 화면으로 전환
            while !fdaGranted, !Task.isCancelled {
                if Permissions.hasFullDiskAccess() {
                    withAnimation { fdaGranted = true }
                    break
                }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    // MARK: 하단 네비게이션

    private var footer: some View {
        HStack {
            // 진행 표시 점
            HStack(spacing: 6) {
                ForEach([Step.welcome, .eula, .permission], id: \.self) { s in
                    Circle()
                        .fill(s == step ? Theme.teal : Color.white.opacity(0.2))
                        .frame(width: 7, height: 7)
                }
            }
            Spacer()
            if step != .welcome {
                Button("이전") { back() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
            Button(LocalizedStringKey(primaryTitle)) { advance() }
                .buttonStyle(.borderedProminent)
                .tint(Theme.teal)
                .controlSize(.large)
                .disabled(step == .eula && !agreedEULA)
        }
        .padding(20)
    }

    private var primaryTitle: String {
        switch step {
        case .welcome: return "시작하기"
        case .eula: return "동의하고 계속"
        case .permission: return fdaGranted ? "Abysso 시작" : "나중에 설정하고 시작"
        }
    }

    private func advance() {
        switch step {
        case .welcome: withAnimation { step = .eula }
        case .eula: withAnimation { step = .permission }
        case .permission:
            completed = true
            fdaSuppressed = true  // 온보딩에서 이미 FDA를 안내했으므로 중복 프롬프트 방지
            isPresented = false
        }
    }

    private func back() {
        switch step {
        case .welcome: break
        case .eula: withAnimation { step = .welcome }
        case .permission: withAnimation { step = .eula }
        }
    }

    // MARK: 보조 뷰

    private func stepHeader(icon: String, tint: Color, title: LocalizedStringKey, subtitle: LocalizedStringKey) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 11))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 19, weight: .bold, design: .rounded))
                Text(subtitle).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func permStep(_ n: Int, _ text: LocalizedStringKey) -> some View {
        HStack(spacing: 10) {
            Text("\(n)")
                .font(.caption.bold())
                .frame(width: 20, height: 20)
                .background(Theme.blue.opacity(0.25), in: Circle())
            Text(text).font(.callout)
        }
    }

    // MARK: EULA 본문

    static var eulaText: String { NSLocalizedString("eula.body", comment: "EULA full text") }
}

// MARK: - 애니메이션 앱 아이콘 (심해 블루 + 스파클)

struct AnimatedAppIcon: View {
    @State private var glow = false
    @State private var sparkle = false

    var body: some View {
        ZStack {
            // 발광 배경
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hex: 0x0E2148), Color(hex: 0x1668B8), Color(hex: 0x2DD4BF),
                        ],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                .frame(width: 120, height: 120)
                .shadow(color: Theme.teal.opacity(glow ? 0.6 : 0.25),
                        radius: glow ? 30 : 14)
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                )

            Image(systemName: "sparkles")
                .font(.system(size: 54, weight: .medium))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                .scaleEffect(sparkle ? 1.08 : 0.96)
                .opacity(sparkle ? 1 : 0.85)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                glow = true
            }
            withAnimation(.easeInOut(duration: 1.3).repeatForever(autoreverses: true)) {
                sparkle = true
            }
        }
    }
}
