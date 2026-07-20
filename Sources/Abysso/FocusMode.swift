import SwiftUI

// MARK: - 집중(부스트) 모드
//
// Abysso 차별화 기능. 관리자 암호 없이 사용자 권한만으로
// 메모리 압박(purgeMemory)을 유도해 비활성 RAM을 즉시 회수한다 —
// 버튼을 누르는 순간 암호 창 없이 곧바로 자원이 확보된다.
// (예전의 mdutil(Spotlight 색인 중지)은 관리자 권한이 필요해 완전히 제거함)
//
// purgeMemory는 DEBUG 안전모드(DevMode.shouldRunCommand)의 통제를 받으므로
// 드라이런/샌드박스 모드에서는 실제 실행 대신 로그만 남고 릴리스 무결성이 유지된다.

@MainActor
final class FocusMode: ObservableObject {
    static let shared = FocusMode()
    private init() {}

    @Published var active = false
    @Published var working = false
    /// 사용자에게 보여줄 결과 메시지 (이미 현지화된 문자열)
    @Published var message: String?
    /// 활성화 순간 강조색 플래시 트리거
    @Published var flash = false

    func toggle() {
        guard !working else { return }
        if active { deactivate() } else { activate() }
    }

    /// 집중 모드 켜기 — 메모리 압박으로 비활성 RAM 즉시 회수 (암호 불필요)
    func activate() {
        guard !working else { return }
        working = true
        message = nil
        Task {
            let before = SystemProbe.usedMemory()
            let ok = await SystemActions.focusBoost()
            let after = SystemProbe.usedMemory()
            withAnimation(.easeInOut(duration: 0.3)) {
                working = false
                if ok {
                    active = true
                    let freed = before > after ? Int64(before - after) : 0
                    message = freed > 0
                        ? String(format: NSLocalizedString("시스템 자원을 최대로 확보했습니다 — %@ 확보", comment: ""), Format.bytes(freed))
                        : NSLocalizedString("시스템 자원을 최대로 확보했습니다", comment: "")
                    triggerFlash()
                } else {
                    message = NSLocalizedString("집중 모드를 시작하지 못했습니다", comment: "")
                }
            }
            clearMessageLater()
        }
    }

    /// 집중 모드 끄기 — 되돌릴 시스템 변경이 없으므로 상태만 해제한다.
    func deactivate() {
        guard !working else { return }
        withAnimation(.easeInOut(duration: 0.3)) {
            active = false
            message = NSLocalizedString("집중 모드를 해제했습니다", comment: "")
        }
        clearMessageLater()
    }

    /// 강조색 플래시를 잠시 켰다가 부드럽게 끈다.
    private func triggerFlash() {
        flash = true
        Task {
            try? await Task.sleep(for: .seconds(1.0))
            withAnimation(.easeOut(duration: 0.6)) { flash = false }
        }
    }

    private func clearMessageLater() {
        Task {
            try? await Task.sleep(for: .seconds(5))
            withAnimation { message = nil }
        }
    }
}

// MARK: - 집중 모드용 시스템 명령
//
// SystemActions(열거형)에 부스트 전용 동작을 확장으로 덧붙인다.
// 관리자 권한(runShellAsAdmin)은 일절 사용하지 않는다 — 암호 창이 뜨지 않는다.

extension SystemActions {
    /// 집중 모드 켜기: 사용자 권한 메모리 압박으로 비활성 RAM을 즉시 회수.
    static func focusBoost() async -> Bool {
        await purgeMemory()
    }
}
