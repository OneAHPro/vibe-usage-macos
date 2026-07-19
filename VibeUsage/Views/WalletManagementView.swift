import SwiftUI

struct WalletManagementView: View {
    @Environment(AppState.self) private var appState
    @Bindable var store: WalletManagementStore
    let client: (any AccountManagementClient)?
    let quotaPerUnit: Double

    @State private var selectedSection = WalletSection.subscriptions
    @State private var selectedPaymentID = ""
    @State private var selectedCreemProductID = ""
    @State private var selectedPlan: SubscriptionPlan?
    @State private var amountText = "20"

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 12) {
                if let errorMessage = store.errorMessage {
                    AccountErrorBanner(message: errorMessage)
                }
                if let checkoutMessage = store.checkoutMessage {
                    checkoutBanner(checkoutMessage)
                }

                balanceCard
                sectionPicker

                switch selectedSection {
                case .subscriptions:
                    subscriptionContent
                case .recharge:
                    rechargeCard
                case .records:
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
            }
            .padding(20)
        }
        .background(AppTheme.subtleSurface)
        .task {
            guard let client else { return }
            await store.loadIfNeeded(client: client)
            selectDefaultPaymentIfNeeded()
        }
        .onChange(of: selectedSection) { _, section in
            guard section == .records, let client else { return }
            Task { await store.loadFundingRecordsIfNeeded(client: client) }
        }
        .onChange(of: store.requiresAuthentication) { _, required in
            if required { appState.handleAccountAuthenticationFailure() }
        }
        .onChange(of: amountText) { _, _ in store.clearPaymentEstimate() }
        .onChange(of: selectedPaymentID) { _, _ in store.clearPaymentEstimate() }
        .onChange(of: selectedCreemProductID) { _, _ in store.clearPaymentEstimate() }
        .sheet(item: $selectedPlan) { plan in
            SubscriptionPurchaseSheet(
                store: store,
                client: client,
                plan: plan,
                topUpInfo: store.topUpInfo,
                quotaPerUnit: quotaPerUnit
            )
        }
    }

    private func checkoutBanner(_ message: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(AppTheme.costAccent)
            Text(message)
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

    private var balanceCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "wallet.pass.fill")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(AppTheme.costAccent)
                .frame(width: 38, height: 38)
                .background(AppTheme.costAccent.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 4) {
                Text("当前余额")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppTheme.secondaryText)
                Text(quotaCost(store.user?.quota))
                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppTheme.costAccent)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(store.subscriptions.isEmpty ? "暂无生效订阅" : "\(store.subscriptions.count) 个订阅生效中")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(store.subscriptions.isEmpty ? AppTheme.tertiaryText : AppTheme.costAccent)
                Text("余额与套餐均以服务器数据为准")
                    .font(.system(size: 9))
                    .foregroundStyle(AppTheme.tertiaryText)
            }

            Button("刷新", systemImage: "arrow.clockwise") { refresh() }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(store.isLoading || store.isMutating)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 82)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(AppTheme.separator, lineWidth: 1))
    }

    private var sectionPicker: some View {
        Picker("钱包功能", selection: $selectedSection) {
            ForEach(WalletSection.allCases) { section in
                Text(section.rawValue).tag(section)
            }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 460)
    }

    private var subscriptionContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            currentSubscriptionsCard
            availablePlansCard
        }
    }

    private var currentSubscriptionsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("当前订阅")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppTheme.primaryText)
                    Text("套餐额度与钱包余额按选择的顺序抵扣")
                        .font(.system(size: 10))
                        .foregroundStyle(AppTheme.tertiaryText)
                }
                Spacer()
                Picker("计费顺序", selection: billingPreferenceBinding) {
                    ForEach(BillingPreference.allCases) { preference in
                        Text(preference.label).tag(preference)
                    }
                }
                .labelsHidden()
                .frame(width: 150)
                .disabled(store.isMutating || store.subscriptions.isEmpty)
            }
            .padding(16)

            Divider()

            if store.subscriptions.isEmpty && !store.isLoading {
                subscriptionEmptyState
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(store.subscriptions.enumerated()), id: \.element.id) { index, summary in
                        subscriptionRow(summary)
                        if index < store.subscriptions.count - 1 { Divider() }
                    }
                }
            }
        }
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(AppTheme.separator, lineWidth: 1))
        .overlay {
            if store.isLoading && !store.hasLoaded {
                ProgressView().controlSize(.small)
            }
        }
    }

    private var subscriptionEmptyState: some View {
        HStack(spacing: 10) {
            Image(systemName: "crown")
                .font(.system(size: 18))
                .foregroundStyle(AppTheme.tertiaryText)
            VStack(alignment: .leading, spacing: 3) {
                Text("暂无生效订阅")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppTheme.secondaryText)
                Text("可在下方选择适合的套餐")
                    .font(.system(size: 10))
                    .foregroundStyle(AppTheme.tertiaryText)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 76)
    }

    private func subscriptionRow(_ summary: SubscriptionSummary) -> some View {
        let total = summary.subscription.amountTotal
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(summary.plan?.title ?? "订阅套餐")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppTheme.primaryText)
                    if let subtitle = summary.plan?.subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 9))
                            .foregroundStyle(AppTheme.tertiaryText)
                            .lineLimit(1)
                    }
                }
                AccountStatusLabel(text: summary.subscription.statusLabel, color: AppTheme.costAccent)
                Spacer()
                Text("至 \(Formatters.formatUnixDate(summary.subscription.endTime))")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(AppTheme.secondaryText)
            }

            HStack(spacing: 16) {
                if total > 0 {
                    VStack(alignment: .leading, spacing: 5) {
                        ProgressView(value: summary.usageFraction)
                            .tint(AppTheme.costAccent)
                        Text("已用 \(quotaCost(summary.subscription.amountUsed)) · 剩余 \(quotaCost(summary.remainingAmount)) · 共 \(quotaCost(total))")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                } else {
                    Text("不限额度")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AppTheme.costAccent)
                }
                Spacer()
                if summary.subscription.nextResetTime > 0 {
                    Label(
                        "\(Formatters.formatUnixDateTime(summary.subscription.nextResetTime)) 重置",
                        systemImage: "arrow.triangle.2.circlepath"
                    )
                    .font(.system(size: 9))
                    .foregroundStyle(AppTheme.tertiaryText)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    private var availablePlansCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("可选套餐")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppTheme.primaryText)
                Text("购买将在默认浏览器中安全完成")
                    .font(.system(size: 10))
                    .foregroundStyle(AppTheme.tertiaryText)
            }

            if store.plans.isEmpty && !store.isLoading {
                Text("当前暂无可购买套餐")
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.tertiaryText)
                    .frame(maxWidth: .infinity, minHeight: 90)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 10)], spacing: 10) {
                    ForEach(store.plans) { plan in
                        planCard(plan)
                    }
                }
            }
        }
        .padding(16)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(AppTheme.separator, lineWidth: 1))
    }

    private func planCard(_ plan: SubscriptionPlan) -> some View {
        let purchased = store.purchaseCount(for: plan.id)
        let limitReached = plan.maxPurchasePerUser > 0 && purchased >= plan.maxPurchasePerUser
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(plan.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppTheme.primaryText)
                        .lineLimit(1)
                    if !plan.subtitle.isEmpty {
                        Text(plan.subtitle)
                            .font(.system(size: 9))
                            .foregroundStyle(AppTheme.tertiaryText)
                            .lineLimit(2)
                    }
                }
                Spacer()
                Text(plan.priceLabel)
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppTheme.costAccent)
            }

            VStack(alignment: .leading, spacing: 6) {
                planFeature("有效期", plan.durationLabel)
                planFeature("总额度", plan.quotaLabel(quotaPerUnit: quotaPerUnit))
                if plan.resetLabel != "不重置" { planFeature("额度重置", plan.resetLabel) }
                if plan.maxPurchasePerUser > 0 {
                    planFeature("购买限制", "\(purchased) / \(plan.maxPurchasePerUser)")
                }
            }

            Button(limitReached ? "已达购买上限" : "选择套餐", systemImage: "arrow.up.right") {
                selectedPlan = plan
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .disabled(limitReached || !hasSubscriptionPaymentOption(for: plan) || store.isMutating)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 188, alignment: .topLeading)
        .background(AppTheme.subtleSurface)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(AppTheme.separator, lineWidth: 1))
    }

    private func planFeature(_ label: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(AppTheme.tertiaryText).frame(width: 3, height: 3)
            Text("\(label)：\(value)")
                .font(.system(size: 9))
                .foregroundStyle(AppTheme.secondaryText)
        }
    }

    private var rechargeCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("在线充值")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppTheme.primaryText)
                Text("支付将在默认浏览器中安全完成")
                    .font(.system(size: 10))
                    .foregroundStyle(AppTheme.tertiaryText)
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
                                .frame(width: 300)
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
            if store.isLoading { ProgressView().controlSize(.small) }
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
            quota: Text(Formatters.formatExactNumber(Int(record.amount))).font(.system(size: 10, design: .monospaced)),
            money: Text(Formatters.formatCost(record.money)).font(.system(size: 10, design: .monospaced)),
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

    private var billingPreferenceBinding: Binding<BillingPreference> {
        Binding(
            get: { store.billingPreference },
            set: { preference in
                guard let client else { return }
                Task { await store.updateBillingPreference(preference, client: client) }
            }
        )
    }

    private var paymentOptions: [WalletPaymentOption] {
        guard let info = store.topUpInfo else { return [] }
        let externalProviderTypes: Set<String> = ["stripe", "creem", "waffo", "waffo_pancake"]
        var result = (info.enableOnlineTopUp ? info.paymentMethods : [])
            .filter { !externalProviderTypes.contains($0.type) }
            .map { WalletPaymentOption(id: "epay:\($0.type)", name: $0.name) }
        if info.enableStripeTopUp { result.append(WalletPaymentOption(id: "stripe", name: "Stripe")) }
        if info.enableCreemTopUp, !info.creemProducts.isEmpty {
            result.append(WalletPaymentOption(id: "creem", name: "Creem"))
        }
        if info.enableWaffoTopUp { result.append(WalletPaymentOption(id: "waffo", name: "Waffo")) }
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
        store.topUpInfo?.creemProducts.first(where: { $0.productID == selectedCreemProductID })
    }

    private var expectedPaymentAmount: Double? {
        guard let request = paymentRequest else { return nil }
        if case .creem = request { return selectedCreemProduct?.price }
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

    private func hasSubscriptionPaymentOption(for plan: SubscriptionPlan) -> Bool {
        guard let info = store.topUpInfo else { return false }
        let hasEpay = info.enableOnlineTopUp && !info.paymentMethods.isEmpty
        let hasStripe = info.enableStripeTopUp && !plan.stripePriceID.isEmpty
        let hasCreem = info.enableCreemTopUp && !plan.creemProductID.isEmpty
        return hasEpay || hasStripe || hasCreem
    }

    private func selectDefaultPaymentIfNeeded() {
        if selectedPaymentID.isEmpty { selectedPaymentID = paymentOptions.first?.id ?? "" }
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

    private func quotaCost(_ quota: Int64) -> String {
        Formatters.formatCost(Double(max(quota, 0)) / max(quotaPerUnit, 1))
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

private enum WalletSection: String, CaseIterable, Identifiable {
    case subscriptions = "订阅套餐"
    case recharge = "余额充值"
    case records = "资金记录"

    var id: String { rawValue }
}

private struct WalletPaymentOption: Identifiable {
    let id: String
    let name: String
}
