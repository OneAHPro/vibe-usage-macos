import SwiftUI

struct WalletManagementView: View {
    @Environment(AppState.self) private var appState
    @Bindable var store: WalletManagementStore
    let client: (any AccountManagementClient)?
    let quotaPerUnit: Double

    @State private var selectedPaymentID = ""
    @State private var selectedCreemProductID = ""
    @State private var amountText = "20"

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 12) {
                if let errorMessage = store.errorMessage {
                    AccountErrorBanner(message: errorMessage)
                }
                if let checkoutMessage = store.checkoutMessage {
                    HStack(spacing: 7) {
                        Image(systemName: "info.circle.fill")
                            .foregroundStyle(AppTheme.costAccent)
                        Text(checkoutMessage)
                            .font(.system(size: 11))
                            .foregroundStyle(AppTheme.secondaryText)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .background(AppTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(AppTheme.separator, lineWidth: 1))
                }

                summaryCards
                rechargeCard
                historyCard

                AccountPagination(
                    page: store.page,
                    pageCount: store.pageCount,
                    total: store.total,
                    disabled: store.isLoading || store.isMutating,
                    onPrevious: { changePage(store.page - 1) },
                    onNext: { changePage(store.page + 1) }
                )
                .padding(.horizontal, 4)
            }
            .padding(20)
        }
        .background(AppTheme.subtleSurface)
        .task {
            guard let client else { return }
            await store.loadIfNeeded(client: client)
            selectDefaultPaymentIfNeeded()
        }
        .onChange(of: store.requiresAuthentication) { _, required in
            if required { appState.handleAccountAuthenticationFailure() }
        }
        .onChange(of: amountText) { _, _ in store.clearPaymentEstimate() }
        .onChange(of: selectedPaymentID) { _, _ in store.clearPaymentEstimate() }
        .onChange(of: selectedCreemProductID) { _, _ in store.clearPaymentEstimate() }
    }

    private var summaryCards: some View {
        HStack(spacing: 8) {
            AccountSummaryCard(
                title: "当前余额",
                value: quotaCost(store.user?.quota),
                accent: true
            )
            AccountSummaryCard(
                title: "历史消耗",
                value: quotaCost(store.user?.usedQuota),
                accent: true
            )
            AccountSummaryCard(
                title: "请求次数",
                value: Formatters.formatExactNumber(store.user?.requestCount ?? 0)
            )
        }
    }

    private var rechargeCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("在线充值")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppTheme.primaryText)
                    Text("支付将在默认浏览器中安全完成")
                        .font(.system(size: 10))
                        .foregroundStyle(AppTheme.tertiaryText)
                }
                Spacer()
                Button("刷新", systemImage: "arrow.clockwise") { refresh() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }

            if paymentOptions.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "creditcard.trianglebadge.exclamationmark")
                    Text("当前未启用在线充值")
                }
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.tertiaryText)
                .frame(maxWidth: .infinity, minHeight: 74)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .bottom, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("支付方式")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(AppTheme.secondaryText)
                        Picker("支付方式", selection: $selectedPaymentID) {
                            ForEach(paymentOptions) { option in
                                Text(option.name).tag(option.id)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 180)
                    }

                        if selectedPaymentID == "creem" {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("选择产品")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(AppTheme.secondaryText)
                                Picker("选择产品", selection: $selectedCreemProductID) {
                                    ForEach(store.topUpInfo?.creemProducts ?? []) { product in
                                        Text("\(product.name) · \(Formatters.formatExactNumber(Int(product.quota))) 额度 · \(Formatters.formatMoney(product.price, currency: product.currency))")
                                            .tag(product.productID)
                                    }
                                }
                                .labelsHidden()
                                .frame(width: 260)
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("充值金额")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(AppTheme.secondaryText)
                                TextField("金额", text: $amountText)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 130)
                                    .onSubmit { calculatePaymentAmount() }
                            }

                            if let presets = store.topUpInfo?.amountOptions, !presets.isEmpty {
                                HStack(spacing: 6) {
                                    ForEach(presets.prefix(5), id: \.self) { amount in
                                        Button(String(amount)) { amountText = String(amount) }
                                            .buttonStyle(.bordered)
                                            .controlSize(.small)
                                    }
                                }
                            }
                        }

                        Spacer()
                    }

                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("预计支付金额")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(AppTheme.secondaryText)
                            Text(expectedPaymentLabel)
                                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                                .foregroundStyle(expectedPaymentAmount == nil ? AppTheme.tertiaryText : AppTheme.costAccent)
                        }

                    Spacer()
                        if selectedPaymentID != "creem" {
                            Button("计算实付", systemImage: "equal.circle") { calculatePaymentAmount() }
                                .buttonStyle(.bordered)
                                .disabled(store.isMutating || paymentRequest == nil)
                        }
                    Button("前往支付", systemImage: "arrow.up.right") { beginCheckout() }
                        .buttonStyle(.borderedProminent)
                            .disabled(store.isMutating || paymentRequest == nil || expectedPaymentAmount == nil)
                    }
                }
            }
        }
        .padding(16)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(AppTheme.separator, lineWidth: 1))
    }

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("充值记录")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppTheme.primaryText)
                .padding(16)

            Divider()

            ScrollView(.horizontal, showsIndicators: false) {
                VStack(spacing: 0) {
                    historyHeader
                    Divider()
                    if store.records.isEmpty && !store.isLoading {
                        Text("暂无充值记录")
                            .font(.system(size: 12))
                            .foregroundStyle(AppTheme.tertiaryText)
                            .frame(maxWidth: .infinity)
                            .frame(height: 110)
                    } else {
                        ForEach(store.records) { record in
                            historyRow(record)
                            Divider()
                        }
                    }
                }
                .frame(minWidth: 900)
            }
        }
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(AppTheme.separator, lineWidth: 1))
        .overlay {
            if store.isLoading {
                ProgressView().controlSize(.small)
            }
        }
    }

    private var historyHeader: some View {
        historyColumns(
            order: Text("订单号"),
            method: Text("支付方式"),
            quota: Text("充值额度"),
            money: Text("支付金额"),
            status: Text("状态"),
            date: Text("创建时间")
        )
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(AppTheme.secondaryText)
        .frame(height: 38)
    }

    private func historyRow(_ record: TopUpRecord) -> some View {
        historyColumns(
            order: Text(record.tradeNumber).font(.system(size: 10, design: .monospaced)).lineLimit(1),
            method: Text(record.paymentProvider.isEmpty ? record.paymentMethod : record.paymentProvider),
            quota: Text(Formatters.formatExactNumber(Int(record.amount)))
                .font(.system(size: 10, design: .monospaced)),
            money: Text(Formatters.formatCost(record.money))
                .font(.system(size: 10, design: .monospaced)),
            status: AccountStatusLabel(text: record.statusLabel, color: statusColor(record.status)),
            date: Text(Formatters.formatUnixDateTime(record.createTime)).font(.system(size: 10, design: .monospaced))
        )
        .font(.system(size: 11))
        .foregroundStyle(AppTheme.secondaryText)
        .frame(height: 46)
    }

    private func historyColumns<Order: View, Method: View, Quota: View, Money: View, Status: View, DateView: View>(
        order: Order,
        method: Method,
        quota: Quota,
        money: Money,
        status: Status,
        date: DateView
    ) -> some View {
        HStack(spacing: 14) {
            order.frame(width: 220, alignment: .leading)
            method.frame(width: 110, alignment: .leading)
            quota.frame(width: 110, alignment: .trailing)
            money.frame(width: 100, alignment: .trailing)
            status.frame(width: 90, alignment: .leading)
            date.frame(width: 150, alignment: .leading)
        }
        .padding(.horizontal, 16)
    }

    private var paymentOptions: [WalletPaymentOption] {
        guard let info = store.topUpInfo else { return [] }
        let externalProviderTypes: Set<String> = ["stripe", "creem", "waffo", "waffo_pancake"]
        var result = (info.enableOnlineTopUp ? info.paymentMethods : [])
            .filter { !externalProviderTypes.contains($0.type) }
            .map {
            WalletPaymentOption(id: "epay:\($0.type)", name: $0.name)
            }
        if info.enableStripeTopUp {
            result.append(WalletPaymentOption(id: "stripe", name: "Stripe"))
        }
        if info.enableCreemTopUp, !info.creemProducts.isEmpty {
            result.append(WalletPaymentOption(id: "creem", name: "Creem"))
        }
        if info.enableWaffoTopUp {
            result.append(WalletPaymentOption(id: "waffo", name: "Waffo"))
        }
        return result
    }

    private var paymentRequest: PaymentRequest? {
        let id = selectedPaymentID.isEmpty ? paymentOptions.first?.id ?? "" : selectedPaymentID
        if id == "creem", let product = selectedCreemProduct {
            return .creem(productID: product.productID)
        }
        let amount = Int64(amountText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        guard amount > 0 else { return nil }
        if id.hasPrefix("epay:") {
            return .epay(amount: amount, paymentMethod: String(id.dropFirst("epay:".count)))
        }
        if id == "stripe" { return .stripe(amount: amount) }
        if id == "waffo" { return .waffo(amount: amount, payMethodIndex: nil) }
        return nil
    }

    private var selectedCreemProduct: CreemProduct? {
        let products = store.topUpInfo?.creemProducts ?? []
        return products.first(where: { $0.productID == selectedCreemProductID })
    }

    private var expectedPaymentAmount: Double? {
        guard let request = paymentRequest else { return nil }
        if case .creem = request {
            return selectedCreemProduct?.price
        }
        guard store.estimatedPaymentRequest == request else { return nil }
        return store.estimatedPaymentAmount
    }

    private var expectedPaymentLabel: String {
        guard let amount = expectedPaymentAmount else { return "请先计算" }
        if let product = selectedCreemProduct, selectedPaymentID == "creem" {
            return Formatters.formatMoney(product.price, currency: product.currency)
        }
        return Formatters.formatCost(amount)
    }

    private func selectDefaultPaymentIfNeeded() {
        if selectedPaymentID.isEmpty {
            selectedPaymentID = paymentOptions.first?.id ?? ""
        }
        if selectedCreemProductID.isEmpty {
            selectedCreemProductID = store.topUpInfo?.creemProducts.first?.productID ?? ""
        }
    }

    private func calculatePaymentAmount() {
        guard let client, let request = paymentRequest else { return }
        if case .creem = request, let price = selectedCreemProduct?.price {
            store.setLocalPaymentEstimate(price, for: request)
            return
        }
        Task { await store.estimatePayment(request, client: client) }
    }

    private func beginCheckout() {
        guard let client, let request = paymentRequest else { return }
        Task {
            if case .creem = request, let price = selectedCreemProduct?.price {
                store.setLocalPaymentEstimate(price, for: request)
            }
            guard let checkout = await store.createCheckout(request, client: client) else { return }
            do {
                try ExternalPaymentLauncher().launch(checkout)
            } catch {
                store.errorMessage = error.localizedDescription
            }
        }
    }

    private func refresh() {
        guard let client else { return }
        Task {
            await store.refresh(client: client)
            selectDefaultPaymentIfNeeded()
        }
    }

    private func changePage(_ page: Int) {
        guard let client else { return }
        Task { await store.goToPage(page, client: client) }
    }

    private func quotaCost(_ quota: Int?) -> String {
        Formatters.formatCost(Double(quota ?? 0) / max(quotaPerUnit, 1))
    }

    private func statusColor(_ status: String) -> Color {
        switch status.lowercased() {
        case "success": AppTheme.costAccent
        case "pending": .orange
        case "failed", "expired": .red
        default: .gray
        }
    }
}

private struct WalletPaymentOption: Identifiable {
    let id: String
    let name: String
}
