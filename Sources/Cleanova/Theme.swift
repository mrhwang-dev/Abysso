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

extension View {
    func card(padding: CGFloat = 16) -> some View {
        modifier(CardStyle(padding: padding))
    }
}

// MARK: - 링 게이지 (실시간 애니메이션)

struct RingGauge: View {
    let value: Double        // 0...1
    let label: String
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
    let title: String
    let systemImage: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .padding(.horizontal, 28)
                .padding(.vertical, 12)
                .background(Theme.accentGradient, in: Capsule())
                .foregroundStyle(.white)
                .shadow(color: Theme.blue.opacity(hovering ? 0.55 : 0.3), radius: hovering ? 14 : 8, y: 4)
                .scaleEffect(hovering ? 1.04 : 1.0)
        }
        .buttonStyle(.plain)
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
        ZStack {
            // screen 블렌딩 + 낮은 투명도로 배경에 자연스럽게 녹아드는 빛
            Capsule()
                .fill(color)
                .blur(radius: 34)
                .scaleEffect(x: pulse ? 1.35 : 0.95, y: pulse ? 1.9 : 1.1)
                .opacity(pulse ? 0.05 : 0.16)
                .blendMode(.screen)
            content()
        }
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
                        Label(label, systemImage: "checkmark")
                    } else {
                        Text(label)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint)
                Text(currentLabel)
                    .font(.system(size: 12.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.primary)
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
                Text(title)
                    .font(.system(size: 12.5, weight: .medium, design: .rounded))
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

// MARK: - 섹션 헤더

struct PageHeader: View {
    let title: String
    let subtitle: String
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
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}
