import SwiftUI

// MARK: - 색상 팔레트 (다크 모드 최적화)

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

enum Theme {
    // 심해 블루 배경 계열
    static let bgTop = Color(hex: 0x101828)
    static let bgBottom = Color(hex: 0x0A0F1A)
    static let card = Color(hex: 0x1A2438)
    static let cardHighlight = Color(hex: 0x223052)

    // 포인트 색상
    static let teal = Color(hex: 0x2DD4BF)
    static let blue = Color(hex: 0x4C8DFF)
    static let orange = Color(hex: 0xFF9F43)
    static let red = Color(hex: 0xFF5C5C)
    static let green = Color(hex: 0x34D399)
    static let purple = Color(hex: 0xA78BFA)
    static let yellow = Color(hex: 0xFACC15)

    static var background: LinearGradient {
        LinearGradient(colors: [bgTop, bgBottom], startPoint: .top, endPoint: .bottom)
    }

    static var accentGradient: LinearGradient {
        LinearGradient(colors: [blue, teal], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// 대시보드(메인 화면) 전용 배경 — 상단에 보라 글로우가 감도는 깊은 그라디언트.
    /// 정보 위주의 다른 탭(짙은 네이비)과 달리 첫 화면에 생기를 준다.
    static var heroBackground: LinearGradient {
        LinearGradient(
            colors: [Color(hex: 0x2E2266), Color(hex: 0x1A163A), bgBottom],
            startPoint: .top, endPoint: .bottom
        )
    }

    /// heroBackground 위에 방사형 보라·청록 글로우를 얹어 깊이감을 준 배경 뷰.
    static var heroBackgroundView: some View {
        heroBackground
            .overlay(alignment: .top) {
                RadialGradient(
                    colors: [purple.opacity(0.35), .clear],
                    center: .center, startRadius: 0, endRadius: 520
                )
                .frame(height: 520)
                .offset(y: -120)
                .blendMode(.screen)
            }
            .overlay(alignment: .topTrailing) {
                RadialGradient(
                    colors: [teal.opacity(0.16), .clear],
                    center: .center, startRadius: 0, endRadius: 360
                )
                .frame(width: 460, height: 460)
                .offset(x: 120, y: -80)
                .blendMode(.screen)
            }
            .ignoresSafeArea()
    }

    /// 사용률(0~1)에 따른 상태 색: 녹색 → 황색 → 적색
    static func statusColor(_ fraction: Double) -> Color {
        if fraction > 0.85 { return red }
        if fraction > 0.70 { return orange }
        return green
    }
}

// MARK: - 카드 스타일

struct CardStyle: ViewModifier {
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Theme.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                    )
            )
            .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
    }
}

/// 최신 macOS 스타일의 반투명(글래스) 카드 — 배경이 살짝 비쳐 보이는 재질.
/// 대시보드처럼 정보 밀도가 높은 화면에서 카드 간 깊이감을 만든다.
struct GlassCardStyle: ViewModifier {
    var padding: CGFloat = 14
    var cornerRadius: CGFloat = 14

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
            .background(
                // 다크 배경 위에서 재질이 너무 밝아지지 않게 카드색을 옅게 깔아준다
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Theme.card.opacity(0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
    }
}

/// 색상 틴트가 살짝 감도는 광택 카드 — 히어로 카드와 톤을 맞춘 보조 정보 타일용.
struct TintedCardStyle: ViewModifier {
    var tint: Color
    var padding: CGFloat = 14
    var cornerRadius: CGFloat = 18

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(LinearGradient(
                            colors: [tint.opacity(0.20), tint.opacity(0.03)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ))
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(tint.opacity(0.28), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.22), radius: 10, y: 5)
    }
}

extension View {
    func card(padding: CGFloat = 16) -> some View {
        modifier(CardStyle(padding: padding))
    }

    func glassCard(padding: CGFloat = 14, cornerRadius: CGFloat = 14) -> some View {
        modifier(GlassCardStyle(padding: padding, cornerRadius: cornerRadius))
    }

    func tintedCard(_ tint: Color, padding: CGFloat = 14, cornerRadius: CGFloat = 18) -> some View {
        modifier(TintedCardStyle(tint: tint, padding: padding, cornerRadius: cornerRadius))
    }
}

// MARK: - 히어로 카드 (메인 화면용 대형 광택 카드)

/// CleanMyMac 스타일의 크고 화사한 카드 — 좌상단 라벨, 큰 수치, 우상단 광택 아이콘,
/// 카드별 색상 그라디언트 배경. 대시보드 첫인상을 살린다.
struct HeroCard<Content: View>: View {
    let tint: Color
    let icon: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
            .padding(18)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(LinearGradient(
                            colors: [tint.opacity(0.32), tint.opacity(0.06)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ))
                }
            )
            .overlay(alignment: .topTrailing) {
                // 3D 광택 아이콘 근사 — 뒤에 후광(글로우) 원 + 큰 심볼 + 밝은 그라디언트
                ZStack {
                    Circle()
                        .fill(tint.opacity(0.35))
                        .frame(width: 48, height: 48)
                        .blur(radius: 15)
                    Image(systemName: icon)
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(LinearGradient(
                            colors: [.white, tint],
                            startPoint: .top, endPoint: .bottom
                        ))
                        .shadow(color: tint.opacity(0.7), radius: 9, y: 3)
                }
                .padding(16)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.28), radius: 14, y: 8)
    }
}

// MARK: - 링 게이지 (실시간 애니메이션)

struct RingGauge: View {
    let value: Double        // 0...1
    let label: LocalizedStringKey
    var color: Color? = nil  // nil이면 상태 색 자동
    var size: CGFloat = 96
    var lineWidth: CGFloat = 10

    private var ringColor: Color { color ?? Theme.statusColor(value) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(value, 1)))
                .stroke(
                    AngularGradient(
                        colors: [ringColor.opacity(0.6), ringColor],
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(360 * value)
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.6), value: value)
            VStack(spacing: 2) {
                Text("\(Int(value * 100))%")
                    .font(.system(size: size * 0.22, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text(label)
                    .font(.system(size: size * 0.11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - 애니메이션 진행률 바

struct SmoothBar: View {
    let value: Double  // 0...1
    var color: Color? = nil
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08))
                Capsule()
                    .fill((color ?? Theme.statusColor(value)).gradient)
                    .frame(width: max(height, geo.size.width * min(value, 1)))
                    .animation(.easeInOut(duration: 0.5), value: value)
            }
        }
        .frame(height: height)
    }
}

// MARK: - 눈에 띄는 CTA 버튼

struct ProminentScanButton: View {
    let title: LocalizedStringKey
    let systemImage: String
    let action: () -> Void
    @State private var hovering = false
    // 체험 만료 시 스캔 시작 등 핵심 CTA를 잠근다 (탭을 눌러도 실행 대신 안내 모달).
    @ObservedObject private var license = LicenseManager.shared

    private var locked: Bool { license.isLocked }

    var body: some View {
        Button {
            if locked { license.presentLockPrompt() } else { action() }
        } label: {
            Label(title, systemImage: locked ? "lock.fill" : systemImage)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .padding(.horizontal, 28)
                .padding(.vertical, 12)
                .background(Theme.accentGradient, in: Capsule())
                .foregroundStyle(.white)
                .opacity(locked ? 0.5 : 1)
                .shadow(color: Theme.blue.opacity(hovering && !locked ? 0.55 : 0.3), radius: hovering && !locked ? 14 : 8, y: 4)
                .scaleEffect(hovering && !locked ? 1.04 : 1.0)
        }
        .buttonStyle(.plain)
        .help(locked ? "체험판이 만료되었습니다 — 라이선스를 활성화하세요" : "")
        .onHover { h in
            withAnimation(.spring(response: 0.3)) { hovering = h }
        }
    }
}

// MARK: - 맥동 글로우 (버튼 주변에 부드럽게 퍼지는 빛)

struct PulsingGlow<Content: View>: View {
    var color: Color = Theme.teal
    @ViewBuilder let content: () -> Content
    @State private var pulse = false

    var body: some View {
        // 글로우 캡슐은 background로 넣어 '콘텐츠(버튼) 크기'에만 맞추고
        // 세로로 늘어나 레이아웃 여백을 먹지 않도록 한다. (blur/scaleEffect는 렌더 전용)
        content()
            .background(
                // screen 블렌딩 + 낮은 투명도로 배경에 자연스럽게 녹아드는 빛
                Capsule()
                    .fill(color)
                    .blur(radius: 34)
                    .scaleEffect(x: pulse ? 1.35 : 0.95, y: pulse ? 1.9 : 1.1)
                    .opacity(pulse ? 0.05 : 0.16)
                    .blendMode(.screen)
            )
            .onAppear {
                withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
    }
}

// MARK: - 커스텀 필터 드롭다운 (다크 테마 캡슐형)

struct FilterMenu<T: Hashable>: View {
    let icon: String
    var tint: Color = Theme.teal
    let options: [(T, String)]
    @Binding var selection: T
    @State private var hovering = false

    private var currentLabel: String {
        options.first(where: { $0.0 == selection })?.1 ?? ""
    }

    var body: some View {
        Menu {
            ForEach(options, id: \.0) { value, label in
                Button {
                    selection = value
                } label: {
                    if value == selection {
                        Label(LocalizedStringKey(label), systemImage: "checkmark")
                    } else {
                        Text(LocalizedStringKey(label))
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint)
                Text(LocalizedStringKey(currentLabel))
                    .font(.system(size: 12.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(hovering ? Theme.cardHighlight : Theme.card, in: Capsule())
            .overlay(
                Capsule().strokeBorder(
                    hovering ? tint.opacity(0.45) : Color.white.opacity(0.10),
                    lineWidth: 1
                )
            )
        }
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

/// 캡슐형 체크 토글 (필터 바용)
struct FilterToggle: View {
    let title: String
    var tint: Color = Theme.teal
    @Binding var isOn: Bool
    @State private var hovering = false

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isOn ? tint : .secondary)
                Text(LocalizedStringKey(title))
                    .font(.system(size: 12.5, weight: .medium, design: .rounded))
                    // 가로 공간이 부족해도 세로로 줄바꿈되지 않도록 강제 (캡슐 찌그러짐 방지)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                isOn ? tint.opacity(0.15) : (hovering ? Theme.cardHighlight : Theme.card),
                in: Capsule()
            )
            .overlay(
                Capsule().strokeBorder(
                    isOn ? tint.opacity(0.5) : Color.white.opacity(0.10),
                    lineWidth: 1
                )
            )
        }
        .buttonStyle(.plain)
        // FilterMenu와 동일하게 고유 크기를 유지하고, 다른 필터에 밀려 압축되지 않도록 방어
        .fixedSize()
        .layoutPriority(1)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

/// 캡슐형 세그먼트 (아이콘 2~3개 전환용)
struct FilterSegment: View {
    let icons: [String]
    var tint: Color = Theme.teal
    @Binding var selection: Int

    var body: some View {
        HStack(spacing: 2) {
            ForEach(icons.indices, id: \.self) { i in
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { selection = i }
                } label: {
                    Image(systemName: icons[i])
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(selection == i ? Color.white : .secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            selection == i ? AnyShapeStyle(tint.gradient) : AnyShapeStyle(.clear),
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Theme.card, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
    }
}

// MARK: - 파티클 배경 (희미하게 떠오르는 입자)

struct ParticleField: View {
    private struct Particle {
        let x: Double        // 0...1 가로 위치
        let size: Double
        let speed: Double    // 초당 상승 포인트
        let phase: Double
        let opacity: Double
        let tint: Int        // 0: teal, 1: blue, 2: purple
    }

    private let particles: [Particle]

    init(count: Int = 36) {
        particles = (0..<count).map { _ in
            Particle(
                x: .random(in: 0...1),
                size: .random(in: 1.5...4),
                speed: .random(in: 6...22),
                phase: .random(in: 0...600),
                opacity: .random(in: 0.10...0.35),
                tint: .random(in: 0...2)
            )
        }
    }

    private static let tints: [Color] = [Theme.teal, Theme.blue, Theme.purple]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            Canvas { ctx, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                for p in particles {
                    let travel = (t * p.speed + p.phase)
                        .truncatingRemainder(dividingBy: Double(size.height) + 24)
                    let y = Double(size.height) + 12 - travel
                    let x = p.x * Double(size.width) + sin(t * 0.5 + p.phase) * 16
                    let twinkle = 0.65 + 0.35 * sin(t * 1.4 + p.phase)
                    ctx.opacity = p.opacity * twinkle
                    ctx.fill(
                        Ellipse().path(in: CGRect(x: x, y: y, width: p.size, height: p.size)),
                        with: .color(Self.tints[p.tint])
                    )
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - 레이더 스캔 애니메이션

struct ScanRadar: View {
    var color: Color = Theme.teal
    var icon: String = "magnifyingglass"
    var size: CGFloat = 150
    @State private var sweeping = false
    @State private var ripple = false

    var body: some View {
        ZStack {
            // 동심원 링
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .stroke(color.opacity(0.22 - Double(i) * 0.06), lineWidth: 1)
                    .frame(width: size * (0.45 + CGFloat(i) * 0.28))
            }
            // 바깥으로 퍼지는 파동
            Circle()
                .stroke(color.opacity(0.35), lineWidth: 1.5)
                .frame(width: size * 0.4)
                .scaleEffect(ripple ? 2.4 : 0.9)
                .opacity(ripple ? 0 : 0.7)
                .animation(.easeOut(duration: 1.6).repeatForever(autoreverses: false), value: ripple)
            // 회전하는 스윕
            Circle()
                .fill(
                    AngularGradient(
                        colors: [color.opacity(0), color.opacity(0), color.opacity(0.45)],
                        center: .center
                    )
                )
                .frame(width: size, height: size)
                .mask(Circle().frame(width: size, height: size))
                .rotationEffect(.degrees(sweeping ? 360 : 0))
                .animation(.linear(duration: 2.0).repeatForever(autoreverses: false), value: sweeping)
            // 스윕 끝의 빛나는 라인
            Rectangle()
                .fill(LinearGradient(colors: [color.opacity(0), color], startPoint: .leading, endPoint: .trailing))
                .frame(width: size / 2, height: 1.5)
                .offset(x: size / 4)
                .rotationEffect(.degrees(sweeping ? 360 : 0))
                .animation(.linear(duration: 2.0).repeatForever(autoreverses: false), value: sweeping)
            // 중앙 아이콘
            Image(systemName: icon)
                .font(.system(size: size * 0.17, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: size * 0.3, height: size * 0.3)
                .background(color.opacity(0.12), in: Circle())
        }
        .frame(width: size, height: size)
        .onAppear {
            sweeping = true
            ripple = true
        }
    }
}

// MARK: - 검사 경로 티커 (빠르게 스쳐 지나가는 경로 텍스트)

struct ScanPathTicker: View {
    let paths: [String]
    var color: Color = Theme.teal

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.12)) { context in
            let t = Int(context.date.timeIntervalSinceReferenceDate / 0.12)
            let path = paths.isEmpty ? "" : paths[t % paths.count]
            HStack(spacing: 6) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 10))
                    .foregroundStyle(color)
                Text(path)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .id(path)
                    .transition(.opacity)
            }
            .frame(maxWidth: 380)
        }
    }
}

// MARK: - 지연 안내 라벨 (스캔·작업이 길어질 때)

/// 스캔이나 작업이 길어지면 이유와 상태를 알려주는 공용 라벨.
/// 처음 몇 초는 아무것도 표시하지 않다가 showAfter초부터 "N초 경과"를,
/// reasonAfter초부터는 지연 사유 문구를 함께 보여준다. 뷰가 나타난 시점부터 잰다.
struct ScanDelayNotice: View {
    var reason: LocalizedStringKey = "파일 용량이 커서 분석이 지연되고 있습니다"
    var showAfter = 3
    var reasonAfter = 10
    @State private var start = Date()

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsed = Int(context.date.timeIntervalSince(start))
            VStack(spacing: 3) {
                if elapsed >= showAfter {
                    Text(String(format: NSLocalizedString("%lld초 경과", comment: ""), Int64(elapsed)))
                        .font(.callout)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
                }
                if elapsed >= reasonAfter {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: elapsed >= showAfter)
            .animation(.easeInOut(duration: 0.3), value: elapsed >= reasonAfter)
        }
        .onAppear { start = Date() }
    }
}

// MARK: - 스캔 전 빈 화면 (모든 탭 공통 레이아웃)
//
// 아이콘·제목·설명·CTA 버튼을 항상 동일한 위치(세로 정중앙)에 배치한다.
// 하단 참고 문구(footnote)는 가운데 블록을 밀어 올리지 않도록 별도로 바닥에 고정한다.
// 이렇게 모든 탭의 빈 화면이 같은 자리에 오도록 통일한다.

struct EmptyStatePane<ButtonContent: View>: View {
    let icon: String
    var iconStyle: AnyShapeStyle
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    var glow: Color = Theme.teal
    var footnote: LocalizedStringKey? = nil
    @ViewBuilder var button: () -> ButtonContent

    var body: some View {
        ZStack {
            ParticleField()

            VStack(spacing: 16) {
                Spacer()
                Image(systemName: icon)
                    .font(.system(size: 56))
                    .foregroundStyle(iconStyle)
                    .symbolEffect(.pulse.byLayer, options: .repeating)
                Text(title)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                Text(message)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                PulsingGlow(color: glow) { button() }
                    .padding(.top, 6)
                Spacer()
            }
            .padding(.horizontal, 40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let footnote {
                Text(footnote)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 44)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 40)
            }
        }
    }
}

// MARK: - 섹션 헤더

struct PageHeader: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let icon: String
    var iconColor: Color = Theme.teal

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(iconColor.gradient)
                .frame(width: 52, height: 52)
                .background(iconColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    // 제목은 한 줄 유지 — 좁아지면 줄바꿈 대신 살짝 축소
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    // 설명문은 최대 2줄까지만 자연스럽게 줄바꿈
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
        }
    }
}
