import SwiftUI

struct SubscriptionPurchaseSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var store: WalletManagementStore
    let client: (any AccountManagementClient)?
    let plan: SubscriptionPlan
    let topUpInfo: TopUpInfo?
    let quotaPerUnit: Double

    @State private var selectedPaymentID = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 19))
                    .foregroundStyle(AppTheme.costAccent)
                    .frame(width: 38, height: 38)
                    .background(AppTheme.costAccent.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                VStack(alignment: .leading, spacing: 3) {
                    Text("购买订阅套餐")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(AppTheme.primaryText)
                    Text(plan.title)
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.secondaryText)
                }
                Spacer()
                Button("取消") { dismiss() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }

            VStack(spacing: 0) {
                detailRow("应付金额", plan.priceLabel, accent: true)
                Divider()
                detailRow("有效期", plan.durationLabel)
                Divider()
                detailRow("总额度", plan.quotaLabel(quotaPerUnit: quotaPerUnit))
                if plan.resetLabel != "不重置" {
                    Divider()
                    detailRow("额度重置", plan.resetLabel)
                }
                if plan.maxPurchasePerUser > 0 {
                    Divider()
                    detailRow("购买限制", "已购 \(purchaseCount) / \(plan.maxPurchasePerUser)")
                }
            }
            .background(AppTheme.subtleSurface)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(AppTheme.separator, lineWidth: 1))

            VStack(alignment: .leading, spacing: 8) {
                Text("选择支付方式")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppTheme.secondaryText)

                if paymentOptions.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "creditcard.trianglebadge.exclamationmark")
                        Text("当前套餐暂无可用支付方式")
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.tertiaryText)
                    .frame(maxWidth: .infinity, minHeight: 58)
                } else {
                    Picker("选择支付方式", selection: $selectedPaymentID) {
                        ForEach(paymentOptions) { option in
                            Text(option.name).tag(option.id)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                }
            }

            if let message = store.errorMessage {
                AccountErrorBanner(message: message)
            }

            HStack {
                Text("支付成功后返回软件并刷新订阅状态")
                    .font(.system(size: 9))
                    .foregroundStyle(AppTheme.tertiaryText)
                Spacer()
                Button("前往支付", systemImage: "arrow.up.right") { beginCheckout() }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.isMutating || selectedRequest == nil || purchaseLimitReached)
            }
        }
        .padding(22)
        .frame(width: 500)
        .background(AppTheme.surface)
        .task {
            if selectedPaymentID.isEmpty { selectedPaymentID = paymentOptions.first?.id ?? "" }
        }
    }

    private func detailRow(_ label: String, _ value: String, accent: Bool = false) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(AppTheme.secondaryText)
            Spacer()
            Text(value)
                .font(.system(size: accent ? 15 : 11, weight: accent ? .semibold : .regular, design: .monospaced))
                .foregroundStyle(accent ? AppTheme.costAccent : AppTheme.primaryText)
        }
        .font(.system(size: 11))
        .padding(.horizontal, 13)
        .frame(height: 42)
    }

    private var paymentOptions: [SubscriptionPaymentOption] {
        guard let topUpInfo else { return [] }
        let externalProviderTypes: Set<String> = ["stripe", "creem", "waffo", "waffo_pancake"]
        var result: [SubscriptionPaymentOption] = []
        if topUpInfo.enableStripeTopUp, !plan.stripePriceID.isEmpty {
            result.append(SubscriptionPaymentOption(id: "stripe", name: "Stripe"))
        }
        if topUpInfo.enableCreemTopUp, !plan.creemProductID.isEmpty {
            result.append(SubscriptionPaymentOption(id: "creem", name: "Creem"))
        }
        if topUpInfo.enableOnlineTopUp {
            result += topUpInfo.paymentMethods
                .filter { !externalProviderTypes.contains($0.type) }
                .map { SubscriptionPaymentOption(id: "epay:\($0.type)", name: $0.name) }
        }
        return result
    }

    private var selectedRequest: SubscriptionPaymentRequest? {
        guard plan.id > 0 else { return nil }
        if selectedPaymentID == "stripe" { return .stripe(planID: plan.id) }
        if selectedPaymentID == "creem" { return .creem(planID: plan.id) }
        if selectedPaymentID.hasPrefix("epay:") {
            return .epay(
                planID: plan.id,
                paymentMethod: String(selectedPaymentID.dropFirst("epay:".count))
            )
        }
        return nil
    }

    private var purchaseCount: Int { store.purchaseCount(for: plan.id) }

    private var purchaseLimitReached: Bool {
        plan.maxPurchasePerUser > 0 && purchaseCount >= plan.maxPurchasePerUser
    }

    private func beginCheckout() {
        guard let client, let request = selectedRequest else { return }
        Task {
            guard let checkout = await store.createSubscriptionCheckout(request, client: client) else { return }
            do {
                try ExternalPaymentLauncher().launch(checkout)
                dismiss()
            } catch {
                store.errorMessage = error.localizedDescription
            }
        }
    }
}

private struct SubscriptionPaymentOption: Identifiable {
    let id: String
    let name: String
}
