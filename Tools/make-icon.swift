// 앱 아이콘 생성 스크립트: swift Tools/make-icon.swift
// Big Sur+ 스타일: 그라데이션 + 비네트 + 글래스 하이라이트 + 림 라이트,
// 심볼에는 그라데이션 틴트와 드롭 섀도로 입체감을 부여
import AppKit

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    // macOS 아이콘 그리드: 전체의 약 82%를 차지하는 라운드 사각형
    let inset = size * 0.09
    let rect = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let radius = rect.width * 0.225
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    let center = NSPoint(x: rect.midX, y: rect.midY)

    NSGraphicsContext.current?.saveGraphicsState()
    path.addClip()

    // 1) 베이스 그라데이션 (심해 네이비 → 블루 → 청록)
    NSGradient(colors: [
        NSColor(calibratedRed: 0.05, green: 0.11, blue: 0.28, alpha: 1),
        NSColor(calibratedRed: 0.09, green: 0.42, blue: 0.74, alpha: 1),
        NSColor(calibratedRed: 0.17, green: 0.82, blue: 0.74, alpha: 1),
    ])!.draw(in: rect, angle: 60)

    // 2) 비네트 — 가장자리를 어둡게 해 깊이감
    NSGradient(
        starting: NSColor.black.withAlphaComponent(0),
        ending: NSColor.black.withAlphaComponent(0.30)
    )!.draw(
        fromCenter: center, radius: rect.width * 0.32,
        toCenter: center, radius: rect.width * 0.78,
        options: [.drawsAfterEndingLocation]
    )

    // 3) 상단 글래스 하이라이트 — 위쪽을 덮는 타원형 광택
    if let ctx = NSGraphicsContext.current {
        ctx.saveGraphicsState()
        let glass = NSBezierPath(ovalIn: NSRect(
            x: rect.minX - rect.width * 0.18,
            y: rect.midY - rect.height * 0.02,
            width: rect.width * 1.36,
            height: rect.height * 0.78
        ))
        glass.addClip()
        NSGradient(
            starting: NSColor.white.withAlphaComponent(0.26),
            ending: NSColor.white.withAlphaComponent(0.0)
        )!.draw(in: glass.bounds, angle: -90)
        ctx.restoreGraphicsState()
    }

    // 4) 하단 내부 그림자 — 바닥 쪽 미세한 어둠
    NSGradient(
        starting: NSColor.black.withAlphaComponent(0.22),
        ending: NSColor.black.withAlphaComponent(0.0)
    )!.draw(
        in: NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height * 0.22),
        angle: 90
    )

    // 5) 림 라이트 — 안쪽 테두리의 은은한 빛
    let rim = NSBezierPath(
        roundedRect: rect.insetBy(dx: size * 0.006, dy: size * 0.006),
        xRadius: radius - size * 0.006, yRadius: radius - size * 0.006
    )
    rim.lineWidth = size * 0.008
    NSColor.white.withAlphaComponent(0.22).setStroke()
    rim.stroke()

    NSGraphicsContext.current?.restoreGraphicsState()

    // 6) 스파클 심볼 — 그라데이션 틴트 + 드롭 섀도
    let config = NSImage.SymbolConfiguration(pointSize: size * 0.42, weight: .medium)
    if let symbol = NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {

        // 수직 그라데이션 틴트 (위: 흰색 → 아래: 옅은 하늘색)
        let tinted = NSImage(size: symbol.size)
        tinted.lockFocus()
        NSGradient(
            starting: NSColor.white,
            ending: NSColor(calibratedRed: 0.78, green: 0.90, blue: 1.0, alpha: 1)
        )!.draw(in: NSRect(origin: .zero, size: symbol.size), angle: -90)
        symbol.draw(at: .zero, from: .zero, operation: .destinationIn, fraction: 1)
        tinted.unlockFocus()

        let origin = NSPoint(
            x: rect.midX - symbol.size.width / 2,
            y: rect.midY - symbol.size.height / 2
        )

        if let ctx = NSGraphicsContext.current {
            // 드롭 섀도 (아래로 살짝, 부드럽게 번짐)
            ctx.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.45)
            shadow.shadowOffset = NSSize(width: 0, height: -size * 0.018)
            shadow.shadowBlurRadius = size * 0.03
            shadow.set()
            tinted.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1)
            ctx.restoreGraphicsState()

            // 상단 엠보싱 하이라이트 (위로 미세하게 어긋난 밝은 사본)
            tinted.draw(
                at: NSPoint(x: origin.x, y: origin.y + size * 0.004),
                from: .zero, operation: .sourceOver, fraction: 0.28
            )
        }
    }

    image.unlockFocus()
    return image
}

func writePNG(_ image: NSImage, to url: URL, pixels: Int) {
    let target = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    target.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: target)
    image.draw(
        in: NSRect(x: 0, y: 0, width: pixels, height: pixels),
        from: .zero, operation: .copy, fraction: 1
    )
    NSGraphicsContext.restoreGraphicsState()
    let png = target.representation(using: .png, properties: [:])!
    try! png.write(to: url)
}

let fm = FileManager.default
let projectDir = URL(fileURLWithPath: CommandLine.arguments[0])
    .deletingLastPathComponent()  // Tools/
    .deletingLastPathComponent()  // 프로젝트 루트
let iconset = projectDir.appendingPathComponent("AppIcon.iconset")
try? fm.removeItem(at: iconset)
try! fm.createDirectory(at: iconset, withIntermediateDirectories: true)

let master = drawIcon(size: 1024)
let sizes: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, px) in sizes {
    writePNG(master, to: iconset.appendingPathComponent("\(name).png"), pixels: px)
}

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", projectDir.appendingPathComponent("AppIcon.icns").path]
try! task.run()
task.waitUntilExit()
try? fm.removeItem(at: iconset)
print(task.terminationStatus == 0 ? "AppIcon.icns 생성 완료" : "iconutil 실패")
