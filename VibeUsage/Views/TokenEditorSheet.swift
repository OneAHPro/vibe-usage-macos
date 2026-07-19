import SwiftUI

struct TokenEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let token: TokenRecord?
    let quotaPerUnit: Double
    let onSave: (TokenMutation) async -> Bool

    @State private var name: String
    @State private var unlimitedQuota: Bool
    @State private var quotaText: String
    @State private var hasExpiration: Bool
    @State private var expirationDate: Date
    @State private var modelLimitsEnabled: Bool
    @State private var modelLimits: String
    @State private var allowIPs: String
    @State private var group: String
    @State private var crossGroupRetry: Bool
    @State private var isSaving = false

    init(
        token: TokenRecord?,
        quotaPerUnit: Double,
        onSave: @escaping (TokenMutation) async -> Bool
    ) {
        self.token = token
        self.quotaPerUnit = quotaPerUnit
        self.onSave = onSave
        _name = State(initialValue: token?.name ?? "")
        _unlimitedQuota = State(initialValue: token?.unlimitedQuota ?? false)
        let quota = Double(token?.remainQuota ?? 0) / max(quotaPerUnit, 1)
        _quotaText = State(initialValue: token == nil ? "10" : String(format: "%.2f", quota))
        let epoch = token?.expiredTime ?? -1
        _hasExpiration = State(initialValue: epoch >= 0)
        _expirationDate = State(initialValue: epoch >= 0
            ? Date(timeIntervalSince1970: TimeInterval(epoch))
            : Date().addingTimeInterval(30 * 86_400))
        _modelLimitsEnabled = State(initialValue: token?.modelLimitsEnabled ?? false)
        _modelLimits = State(initialValue: token?.modelLimits ?? "")
        _allowIPs = State(initialValue: token?.allowIPs ?? "")
        _group = State(initialValue: token?.group ?? "")
        _crossGroupRetry = State(initialValue: token?.crossGroupRetry ?? false)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(token == nil ? "新建令牌" : "编辑令牌")
                    .font(.system(size: 17, weight: .bold))
                Spacer()
                Button("取消") { dismiss() }
                    .buttonStyle(.borderless)
            }
            .padding(20)

            Divider()

            Form {
                TextField("名称", text: $name)

                Toggle("无限额度", isOn: $unlimitedQuota)
                if !unlimitedQuota {
                    TextField("剩余额度（美金）", text: $quotaText)
                }

                Toggle("设置到期时间", isOn: $hasExpiration)
                if hasExpiration {
                    DatePicker(
                        "到期时间",
                        selection: $expirationDate,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                }

                Toggle("限制可用模型", isOn: $modelLimitsEnabled)
                if modelLimitsEnabled {
                    TextField("模型，使用英文逗号分隔", text: $modelLimits)
                }

                TextField("分组（留空使用默认分组）", text: $group)
                Toggle("跨分组重试", isOn: $crossGroupRetry)

                VStack(alignment: .leading, spacing: 6) {
                    Text("IP 白名单（每行一个）")
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.secondaryText)
                    TextEditor(text: $allowIPs)
                        .font(.system(size: 11, design: .monospaced))
                        .frame(height: 72)
                        .overlay {
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(AppTheme.separator, lineWidth: 1)
                        }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button(token == nil ? "创建" : "保存") {
                    Task {
                        guard let mutation else { return }
                        isSaving = true
                        defer { isSaving = false }
                        if await onSave(mutation) {
                            dismiss()
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    isSaving ||
                    name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                    mutation == nil
                )
            }
            .padding(20)
        }
        .frame(width: 520, height: 610)
    }

    private var mutation: TokenMutation? {
        guard let quota = TokenQuotaInput.quota(
            dollars: quotaText,
            quotaPerUnit: quotaPerUnit,
            unlimited: unlimitedQuota
        ) else { return nil }
        return TokenMutation(
            id: token?.id,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            expiredTime: hasExpiration ? Int64(expirationDate.timeIntervalSince1970) : -1,
            remainQuota: quota,
            unlimitedQuota: unlimitedQuota,
            modelLimitsEnabled: modelLimitsEnabled,
            modelLimits: modelLimits.trimmingCharacters(in: .whitespacesAndNewlines),
            allowIPs: allowIPs.trimmingCharacters(in: .whitespacesAndNewlines),
            group: group.trimmingCharacters(in: .whitespacesAndNewlines),
            crossGroupRetry: crossGroupRetry,
            status: token?.status
        )
    }
}
