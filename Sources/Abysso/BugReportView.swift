import SwiftUI

/// 인앱 피드백 시트 — 버그 제보와 기능 추가 요청을 한 창에서 받아 Sentry로 전송한다.
struct BugReportView: View {
    /// 제보 유형 — 버그 제보 / 기능 추가 요청
    enum ReportKind: String, CaseIterable, Identifiable {
        case bug
        case feature
        var id: String { rawValue }

        var title: LocalizedStringKey { self == .bug ? "버그 제보" : "기능 추가 요청" }
        var icon: String { self == .bug ? "ladybug.fill" : "lightbulb.fill" }
        var tint: Color { self == .bug ? Theme.red : Theme.yellow }
    }

    @Environment(\.dismiss) private var dismiss

    @State private var kind: ReportKind = .bug
    @State private var detail = ""
    @State private var email = ""
    @State private var sent = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 헤더 — 선택된 유형에 따라 아이콘·문구가 바뀐다
            HStack(spacing: 12) {
                Image(systemName: kind.icon)
                    .font(.system(size: 22))
                    .foregroundStyle(kind.tint)
                VStack(alignment: .leading, spacing: 1) {
                    Text(kind.title)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                    Text(kind == .bug
                         ? "발견한 문제를 알려주시면 개선에 큰 도움이 됩니다"
                         : "원하는 기능을 알려주시면 개발에 큰 도움이 됩니다")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(20)
            Divider()

            if sent {
                sentView
            } else {
                formView
            }
        }
        .frame(width: 460, height: 460)
        .background(Theme.bgTop)
        .preferredColorScheme(.dark)
        .animation(.easeInOut(duration: 0.15), value: kind)
    }

    // MARK: 입력 폼

    private var formView: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 유형 전환 — 버그 제보 ↔ 기능 추가 요청
            Picker("", selection: $kind) {
                ForEach(ReportKind.allCases) { k in
                    Text(k.title).tag(k)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Text(kind == .bug
                 ? "어떤 상황에서 어떤 문제가 발생했나요?"
                 : "어떤 기능이 필요하신가요?")
                .font(.callout.weight(.medium))
            // 상세 내용 에디터
            TextEditor(text: $detail)
                .font(.system(size: 13))
                .frame(minHeight: 140)
                .padding(6)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
                .overlay(alignment: .topLeading) {
                    if detail.isEmpty {
                        Text(kind == .bug
                             ? "예: 스마트 정리 스캔 후 앱이 멈췄습니다…"
                             : "예: 정리 예약(스케줄) 기능이 있으면 좋겠어요…")
                            .font(.system(size: 13))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 14)
                            .allowsHitTesting(false)
                    }
                }

            // 이메일 (선택)
            VStack(alignment: .leading, spacing: 4) {
                Text("회신받을 이메일 (선택)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("you@example.com", text: $email)
                    .textFieldStyle(.roundedBorder)
                    .disableAutocorrection(true)
            }

            HStack {
                Text("전송 시 진단을 위해 앱 버전·OS 정보가 함께 첨부됩니다")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("취소") { dismiss() }
                Button(kind == .bug ? "제보하기" : "요청하기") { submit() }
                    .buttonStyle(.borderedProminent)
                    .tint(kind.tint)
                    .disabled(detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.top, 2)
        }
        .padding(20)
    }

    // MARK: 전송 완료

    private var sentView: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(Theme.green)
            Text(kind == .bug ? "제보가 완료되었습니다" : "요청이 완료되었습니다")
                .font(.system(size: 17, weight: .bold, design: .rounded))
            Text("소중한 의견 감사합니다. 빠르게 확인하겠습니다.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func submit() {
        Telemetry.reportBug(message: detail, email: email, isFeatureRequest: kind == .feature)
        withAnimation { sent = true }
        // 가벼운 완료 알림 후 자동으로 닫힘
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            dismiss()
        }
    }
}
