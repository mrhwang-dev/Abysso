import AppKit
import SwiftUI

/// 모든 탭을 자동으로 순회하며 창을 캡처해 한 장의 그리드 이미지로 합친다.
enum ScreenshotExporter {
    enum Result {
        case success(URL)
        case noPermission
        case failed
    }

    /// setSelection으로 각 탭을 표시시키고, 잠깐 렌더링을 기다린 뒤 창을 캡처.
    @MainActor
    static func captureAllTabs(setSelection: @escaping (SidebarItem) -> Void) async -> Result {
        guard let window = mainWindow() else { return .failed }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        let windowID = CGWindowID(window.windowNumber)

        var shots: [(String, NSImage)] = []
        let tmp = FileManager.default.temporaryDirectory

        for (index, item) in SidebarItem.allCases.enumerated() {
            setSelection(item)
            // 탭 전환 애니메이션 + 초기 렌더가 끝나도록 대기
            try? await Task.sleep(for: .milliseconds(index == 0 ? 500 : 650))

            let path = tmp.appendingPathComponent("mc_tab_\(index).png")
            try? FileManager.default.removeItem(at: path)
            let ok = await captureWindow(windowID, to: path)
            if ok, let img = NSImage(contentsOf: path) {
                shots.append((item.rawValue, img))
            } else if index == 0 {
                // 첫 캡처부터 실패하면 대개 화면 기록 권한 문제
                return .noPermission
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

    // MARK: 창 찾기 / 캡처

    @MainActor
    private static func mainWindow() -> NSWindow? {
        // 가장 큰 titled 창을 메인 창으로 간주 (환경설정 창 등 제외)
        NSApp.windows
            .filter { $0.isVisible && $0.styleMask.contains(.titled) && $0.contentView != nil }
            .max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
    }

    private static func captureWindow(_ id: CGWindowID, to url: URL) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                // -x: 소리 없음, -o: 창 그림자 제외, -l: 특정 창 ID
                p.arguments = ["-x", "-o", "-l", String(id), url.path]
                do {
                    try p.run()
                    p.waitUntilExit()
                } catch {
                    continuation.resume(returning: false)
                    return
                }
                let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int ?? 0
                let ok = p.terminationStatus == 0
                    && FileManager.default.fileExists(atPath: url.path)
                    && size > 0
                continuation.resume(returning: ok)
            }
        }
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

            // 라벨
            (shot.0 as NSString).draw(
                in: labelRect.insetBy(dx: 4, dy: 4), withAttributes: labelAttrs
            )
            // 이미지 (셀에 맞춰 축소)
            shot.1.draw(in: imgRect, from: .zero, operation: .copy, fraction: 1)
            // 이미지 테두리
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

    static func openScreenRecordingSettings() {
        NSWorkspace.shared.open(URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        )!)
    }
}

private extension NSImage {
    func pngData() -> Data? {
        guard let tiff = tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
