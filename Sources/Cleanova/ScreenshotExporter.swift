import AppKit
import SwiftUI

/// 모든 탭을 자동으로 순회하며 창을 캡처해 한 장의 그리드 이미지로 합친다.
///
/// 자기 앱의 창을 직접 렌더링(AppKit `cacheDisplay`)하므로 시스템 화면 기록 권한이
/// 전혀 필요 없다. List·라이브 데이터·아이콘 등 실제 화면에 그려진 내용을 그대로 담는다.
enum ScreenshotExporter {
    enum Result {
        case success(URL)
        case failed
    }

    /// setSelection으로 각 탭을 표시시키고, 렌더링을 기다린 뒤 창 내용을 캡처.
    @MainActor
    static func captureAllTabs(setSelection: @escaping (SidebarItem) -> Void) async -> Result {
        guard let window = mainWindow() else { return .failed }

        var shots: [(String, NSImage)] = []
        for (index, item) in SidebarItem.allCases.enumerated() {
            setSelection(item)
            // 탭 전환 애니메이션 + 초기 렌더가 끝나도록 대기
            try? await Task.sleep(for: .milliseconds(index == 0 ? 450 : 550))
            if let img = captureWindowContent(window) {
                shots.append((item.rawValue, img))
            }
        }

        guard !shots.isEmpty else { return .failed }
        guard let montage = makeGrid(shots) else { return .failed }

        let out = desktopURL()
        guard let data = montage.pngData() else { return .failed }
        do {
            try data.write(to: out)
            return .success(out)
        } catch {
            return .failed
        }
    }

    // MARK: 창 찾기 / 캡처 (권한 불필요)

    @MainActor
    private static func mainWindow() -> NSWindow? {
        // 가장 큰 titled 창을 메인 창으로 간주 (환경설정 창 등 제외)
        NSApp.windows
            .filter { $0.isVisible && $0.styleMask.contains(.titled) && $0.contentView != nil }
            .max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
    }

    /// 창의 contentView를 자체 렌더링해 비트맵으로. 화면 기록 권한이 필요 없다.
    @MainActor
    static func captureWindowContent(_ window: NSWindow) -> NSImage? {
        guard let view = window.contentView else { return nil }
        let bounds = view.bounds
        guard bounds.width > 0, bounds.height > 0,
              let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        rep.size = bounds.size
        view.cacheDisplay(in: bounds, to: rep)
        let image = NSImage(size: bounds.size)
        image.addRepresentation(rep)
        return image
    }

    // MARK: 그리드 합성

    private static func makeGrid(_ shots: [(String, NSImage)]) -> NSImage? {
        let cols = 3
        let rows = Int(ceil(Double(shots.count) / Double(cols)))
        let cellW: CGFloat = 460
        let pad: CGFloat = 16
        let labelH: CGFloat = 30

        // 첫 이미지 비율로 셀 높이 결정
        guard let first = shots.first?.1, first.size.width > 0 else { return nil }
        let ratio = first.size.height / first.size.width
        let cellH = cellW * ratio

        let totalW = CGFloat(cols) * cellW + CGFloat(cols + 1) * pad
        let totalH = CGFloat(rows) * (cellH + labelH) + CGFloat(rows + 1) * pad

        let canvas = NSImage(size: NSSize(width: totalW, height: totalH))
        canvas.lockFocus()

        // 배경 (테마 심해 블루)
        NSColor(calibratedRed: 0.04, green: 0.06, blue: 0.10, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: totalW, height: totalH).fill()

        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]

        for (i, shot) in shots.enumerated() {
            let col = i % cols
            let row = i / cols
            let x = pad + CGFloat(col) * (cellW + pad)
            // NSImage 좌표계는 좌하단 원점 → 위에서부터 채우도록 y 뒤집기
            let yTop = totalH - (pad + CGFloat(row) * (cellH + labelH + pad))
            let labelRect = NSRect(x: x, y: yTop - labelH, width: cellW, height: labelH)
            let imgRect = NSRect(x: x, y: yTop - labelH - cellH, width: cellW, height: cellH)

            (shot.0 as NSString).draw(
                in: labelRect.insetBy(dx: 4, dy: 4), withAttributes: labelAttrs
            )
            shot.1.draw(in: imgRect, from: .zero, operation: .copy, fraction: 1)
            NSColor.white.withAlphaComponent(0.12).setStroke()
            let border = NSBezierPath(rect: imgRect)
            border.lineWidth = 1
            border.stroke()
        }

        canvas.unlockFocus()
        return canvas
    }

    private static func desktopURL() -> URL {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyyMMdd-HHmm"
        let name = "Cleanova-탭모음-\(fmt.string(from: .now)).png"
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
        return desktop.appendingPathComponent(name)
    }
}

private extension NSImage {
    func pngData() -> Data? {
        guard let tiff = tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
