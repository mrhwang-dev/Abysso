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
                Text("Cleanova에 오신 것을 환영합니다")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                Text("Welcome to Cleanova")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Text("Mac을 가볍고 깨끗하게 유지하는 올인원 관리 도구입니다.\n캐시 정리부터 대용량 파일 정리, 개인정보 보호, 악성 프로그램\n스캔까지 한곳에서 관리하세요.")
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
                Text("모든 캐시와 로그를 빠짐없이 스캔할 수 있습니다.\n이제 Cleanova를 시작할 준비가 끝났습니다.")
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
                    permStep(2, "목록에서 Cleanova 스위치를 켭니다")
                    permStep(3, "‘권한 다시 확인’을 눌러 반영합니다")
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
            Button(primaryTitle) { advance() }
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
        case .permission: return fdaGranted ? "Cleanova 시작" : "나중에 설정하고 시작"
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

    private func stepHeader(icon: String, tint: Color, title: String, subtitle: String) -> some View {
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

    private func permStep(_ n: Int, _ text: String) -> some View {
        HStack(spacing: 10) {
            Text("\(n)")
                .font(.caption.bold())
                .frame(width: 20, height: 20)
                .background(Theme.blue.opacity(0.25), in: Circle())
            Text(text).font(.callout)
        }
    }

    // MARK: EULA 본문

    static let eulaText = """
    Cleanova 최종 사용자 이용 약관 (EULA)

    1. 개요
    Cleanova(이하 "본 소프트웨어")는 macOS 시스템의 저장 공간 정리 및 관리를 돕는 개인용 유틸리티입니다. 본 약관에 동의함으로써 귀하는 아래 조건에 따라 본 소프트웨어를 사용하는 데 동의합니다.

    2. 데이터 삭제에 관한 책임
    본 소프트웨어는 캐시, 로그, 대용량 파일, 애플리케이션 및 관련 파일을 삭제하는 기능을 제공합니다. 파쇄기 및 휴지통 비우기 기능을 제외한 대부분의 삭제는 휴지통을 거치므로 복구가 가능합니다. 다만 '파쇄기(보안 삭제)' 기능으로 삭제한 파일은 복구할 수 없습니다. 귀하는 삭제할 항목을 직접 확인할 책임이 있으며, 삭제로 인해 발생하는 데이터 손실에 대해 개발자는 책임지지 않습니다.

    3. 시스템 변경
    본 소프트웨어는 로그인 항목, 시작 프로그램, 자동 실행 항목의 활성/비활성을 변경하고, 유지보수 작업(메모리 정리, DNS 캐시 초기화, Spotlight 재색인)을 실행할 수 있습니다. 이러한 작업은 시스템 동작에 영향을 줄 수 있습니다.

    4. 악성 프로그램 스캔의 한계
    본 소프트웨어의 악성 프로그램 스캔은 알려진 패턴 기반의 기초적인 검사이며, 전문 백신 소프트웨어를 대체하지 않습니다. 모든 위협을 탐지한다고 보장하지 않습니다.

    5. 보증의 부인
    본 소프트웨어는 "있는 그대로(as-is)" 제공되며, 명시적이든 묵시적이든 어떠한 종류의 보증도 하지 않습니다. 본 소프트웨어 사용으로 발생하는 모든 위험은 귀하가 부담합니다.

    6. 책임의 제한
    개발자는 본 소프트웨어의 사용 또는 사용 불능으로 인해 발생하는 직간접적, 부수적, 결과적 손해에 대해 어떠한 경우에도 책임지지 않습니다.

    본 약관에 동의하지 않으시면 본 소프트웨어를 사용하실 수 없습니다.
    """
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
