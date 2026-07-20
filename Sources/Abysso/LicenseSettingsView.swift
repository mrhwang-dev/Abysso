import SwiftUI

// MARK: - 라이선스 환경설정 탭

struct LicenseSettingsView: View {
    @ObservedObject private var license = LicenseManager.shared

    @State private var email = ""
    @State private var key = ""
    @State private var errorText: String?
    @State private var justActivated = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                statusCard

                switch license.status {
                case .activated:
                    activatedInfo
                case .trial, .expired:
                    activationForm
                    purchaseRow
                }
            }
            .padding(20)
        }
        .background(Theme.bgTop)
    }

    // MARK: 현재 상태 카드

    private var statusCard: some View {
        HStack(spacing: 14) {
            Image(systemName: statusIcon)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(statusColor)
                .frame(width: 48, height: 48)
                .background(statusColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 3) {
                Text(statusTitle)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                Text(LocalizedStringKey(statusSubtitle))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var statusIcon: String {
        switch license.status {
        case .trial: return "clock.badge.checkmark"
        case .activated: return "checkmark.seal.fill"
        case .expired: return "lock.fill"
        }
    }

    private var statusColor: Color {
        switch license.status {
        case .trial: return Theme.blue
        case .activated: return Theme.green
        case .expired: return Theme.orange
        }
    }

    private var statusTitle: String {
        switch license.status {
        case .trial(let days):
            return String(format: NSLocalizedString("체험판 %d일 남음", comment: "trial days remaining"), days)
        case .activated:
            return NSLocalizedString("정품 인증 완료", comment: "license activated")
        case .expired:
            return NSLocalizedString("체험판이 만료되었습니다", comment: "trial expired")
        }
    }

    private var statusSubtitle: String {
        switch license.status {
        case .trial:
            return "모든 기능을 자유롭게 사용할 수 있습니다. 기간이 끝나기 전에 라이선스를 구매하세요."
        case .activated:
            return "Abysso의 모든 기능을 제한 없이 사용할 수 있습니다. 이용해 주셔서 감사합니다."
        case .expired:
            return "핵심 정리 기능이 잠겼습니다. 아래에서 라이선스를 활성화하면 즉시 잠금이 풀립니다."
        }
    }

    // MARK: 활성화 완료 정보

    private var activatedInfo: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "envelope.fill").foregroundStyle(Theme.green)
                Text(LocalizedStringKey(license.activatedEmail ?? "등록된 사용자"))
                    .font(.callout.weight(.medium))
                Spacer()
            }
            Text("이 Mac은 정품 인증되어 있습니다.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    // MARK: 라이선스 입력 폼

    private var activationForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("라이선스 활성화")
                .font(.headline)
            Text("구매 시 받은 이메일과 32자리 라이선스 키를 입력하세요.")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("이메일 주소", text: $email)
                .textFieldStyle(.roundedBorder)
                .disableAutocorrection(true)

            TextField("XXXXXXXX-XXXXXXXX-XXXXXXXX-XXXXXXXX", text: $key)
                .textFieldStyle(.roundedBorder)
                .font(.system(.callout, design: .monospaced))
                .disableAutocorrection(true)

            if let errorText {
                Label(errorText, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(Theme.red)
            } else if justActivated {
                Label("정품 인증되었습니다! 모든 기능이 활성화되었습니다.", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(Theme.green)
            }

            HStack {
                Spacer()
                Button("활성화") { attemptActivation() }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.green)
                    .disabled(email.isEmpty || key.isEmpty)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func attemptActivation() {
        justActivated = false
        if license.activate(email: email, key: key) {
            errorText = nil
            justActivated = true
            key = ""
        } else {
            let normalized = LicenseManager.normalizeKey(key)
            if !LicenseManager.isValidEmail(email.trimmingCharacters(in: .whitespaces)) {
                errorText = NSLocalizedString("이메일 주소 형식이 올바르지 않습니다.", comment: "")
            } else if !LicenseManager.isValidKey(normalized) {
                errorText = String(format: NSLocalizedString("라이선스 키는 32자리 영숫자여야 합니다 (현재 %d자).", comment: ""), normalized.count)
            } else {
                errorText = NSLocalizedString("활성화에 실패했습니다. 키를 다시 확인하세요.", comment: "")
            }
        }
    }

    // MARK: 구매 유도

    private var purchaseRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "cart.fill")
                .foregroundStyle(Theme.accentGradient)
            VStack(alignment: .leading, spacing: 1) {
                Text("아직 라이선스가 없으신가요?")
                    .font(.callout.weight(.medium))
                Text("Abysso 정식 버전을 구매하고 모든 기능을 계속 사용하세요.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button("Abysso 구매하기") { license.openPurchasePage() }
                .buttonStyle(.borderedProminent)
                .tint(Theme.blue)
                .fixedSize()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}
