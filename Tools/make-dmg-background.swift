// DMG 마운트 창 배경 이미지 생성기 — packaging/dmg-background.png
//
// 앱 아이콘(좌, 120/150) → Applications 바로가기(우, 380/150) 방향의
// 드래그 앤 드롭 안내 화살표가 그려진 500x300pt(@2x 1000x600px) 배경을 만든다.
// 사용: swift Tools/make-dmg-background.swift
import AppKit

let logicalW = 500.0, logicalH = 300.0
let scale = 2.0  // 레티나 대응 @2x — rep.size로 DPI를 지정해 Finder가 500x300pt로 표시

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(logicalW * scale), pixelsHigh: Int(logicalH * scale),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
) else { fatalError("비트맵 생성 실패") }
rep.size = NSSize(width: logicalW, height: logicalH)

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
guard let ctx = NSGraphicsContext.current?.cgContext else { fatalError("컨텍스트 없음") }

// 배경: 앱 다크 테마와 어울리는 딥 네이비 그라디언트
let bgColors = [
    NSColor(calibratedRed: 0.05, green: 0.07, blue: 0.11, alpha: 1).cgColor,
    NSColor(calibratedRed: 0.10, green: 0.13, blue: 0.20, alpha: 1).cgColor,
] as CFArray
let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: bgColors, locations: [0, 1])!
ctx.drawLinearGradient(
    gradient,
    start: CGPoint(x: 0, y: logicalH), end: CGPoint(x: 0, y: 0), options: []
)

// 화살표 — Finder 아이콘 좌표 (120,150)·(380,150) 기준.
// 이미지 좌표는 하단 원점이므로 y = 300 - 150 = 150 (아이콘 중앙 높이와 동일).
let arrowY = 150.0
let startX = 195.0
let endX = 305.0
let stroke = NSColor(calibratedWhite: 1, alpha: 0.30)

let shaft = NSBezierPath()
shaft.lineWidth = 9
shaft.lineCapStyle = .round
shaft.move(to: NSPoint(x: startX, y: arrowY))
shaft.line(to: NSPoint(x: endX - 16, y: arrowY))
stroke.setStroke()
shaft.stroke()

let head = NSBezierPath()
head.lineWidth = 9
head.lineCapStyle = .round
head.lineJoinStyle = .round
head.move(to: NSPoint(x: endX - 24, y: arrowY + 15))
head.line(to: NSPoint(x: endX, y: arrowY))
head.line(to: NSPoint(x: endX - 24, y: arrowY - 15))
stroke.setStroke()
head.stroke()

// 하단 안내 문구
let caption = "Abysso를 Applications 폴더로 드래그해 설치하세요"
let attrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 13, weight: .medium),
    .foregroundColor: NSColor(calibratedWhite: 1, alpha: 0.5),
]
let textSize = (caption as NSString).size(withAttributes: attrs)
(caption as NSString).draw(
    at: NSPoint(x: (logicalW - textSize.width) / 2, y: 30), withAttributes: attrs
)

NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("PNG 인코딩 실패") }
let out = URL(fileURLWithPath: "packaging/dmg-background.png")
try! FileManager.default.createDirectory(atPath: "packaging", withIntermediateDirectories: true)
try! png.write(to: out)
print("생성 완료: \(out.path)")
