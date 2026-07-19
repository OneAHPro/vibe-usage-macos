import AppKit
import SwiftUI

struct TokenManagementView: View {
    @Environment(AppState.self) private var appState
    @Bindable var store: TokenManagementStore
    let client: (any AccountManagementClient)?
    let quotaPerUnit: Double

    @State private var editingToken: TokenRecord?
    @State private var showsEditor = false
    @State private var pendingDeletion: TokenRecord?
    @State private var copyMessage: String?

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 12) {
                if let errorMessage = store.errorMessage {
                    AccountErrorBanner(message: errorMessage)
                }
                if let copyMessage {
                    HStack(spacing: 7) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(AppTheme.costAccent)
                        Text(copyMessage)
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

                HStack(spacing: 8) {
                    AccountSummaryCard(title: "令牌总数", value: Formatters.formatExactNumber(store.total))
                    AccountSummaryCard(title: "当前页已启用", value: Formatters.formatExactNumber(store.enabledCount))
                    AccountSummaryCard(
                        title: "当前页有限额度",
                        value: Formatters.formatCost(Double(store.finiteQuotaTotal) / max(quotaPerUnit, 1)),
                        accent: true
                    )
                }

                toolbar
                tokenTable

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
        }
        .onChange(of: store.requiresAuthentication) { _, required in
            if required { appState.handleAccountAuthenticationFailure() }
        }
        .sheet(isPresented: $showsEditor) {
            TokenEditorSheet(token: editingToken, quotaPerUnit: quotaPerUnit) { mutation in
                guard let client else { return false }
                if mutation.id == nil {
                    return await store.create(mutation, client: client)
                }
                return await store.update(mutation, client: client)
            }
        }
        .confirmationDialog(
            "确定删除令牌“\(pendingDeletion?.name ?? "")”吗？",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除令牌", role: .destructive) {
                guard let token = pendingDeletion, let client else { return }
                Task {
                    _ = await store.delete(id: token.id, client: client)
                    pendingDeletion = nil
                }
            }
            Button("取消", role: .cancel) { pendingDeletion = nil }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            TextField("按名称搜索", text: $store.searchText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 220)
                .onSubmit { submitSearch() }
            TextField("按令牌片段搜索", text: $store.tokenSearchText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 220)
                .onSubmit { submitSearch() }
            Button("搜索", systemImage: "magnifyingglass") { submitSearch() }
                .buttonStyle(.bordered)
            Spacer()
            Button("刷新", systemImage: "arrow.clockwise") { refresh() }
                .buttonStyle(.bordered)
            Button("新建令牌", systemImage: "plus") {
                editingToken = nil
                showsEditor = true
            }
            .buttonStyle(.borderedProminent)
        }
        .controlSize(.small)
        .disabled(store.isLoading || store.isMutating || client == nil)
    }

    private var tokenTable: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(spacing: 0) {
                tokenHeader
                Divider()
                if store.tokens.isEmpty && !store.isLoading {
                    Text("暂无令牌")
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.tertiaryText)
                        .frame(maxWidth: .infinity)
                        .frame(height: 120)
                } else {
                    ForEach(store.tokens) { token in
                        tokenRow(token)
                        Divider()
                    }
                }
            }
            .frame(minWidth: 990)
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

    private var tokenHeader: some View {
        tokenColumns(
            name: Text("名称"),
            key: Text("脱敏密钥"),
            status: Text("状态"),
            quota: Text("已用 / 剩余"),
            models: Text("模型限制"),
            expiry: Text("到期时间"),
            actions: Text("操作")
        )
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(AppTheme.secondaryText)
        .frame(height: 38)
    }

    private func tokenRow(_ token: TokenRecord) -> some View {
        tokenColumns(
            name: Text(token.name).lineLimit(1),
            key: Text(token.maskedKey).font(.system(size: 10, design: .monospaced)).lineLimit(1),
            status: AccountStatusLabel(text: token.statusLabel, color: token.status == 1 ? AppTheme.costAccent : .gray),
            quota: Text("\(Formatters.formatCost(Double(token.usedQuota) / max(quotaPerUnit, 1))) / \(token.quotaLabel(quotaPerUnit: quotaPerUnit))")
                .font(.system(size: 10, design: .monospaced)),
            models: Text(token.modelLimitsEnabled ? token.modelLimits : "全部").lineLimit(1),
            expiry: Text(token.expirationLabel).font(.system(size: 10, design: .monospaced)),
            actions: HStack(spacing: 9) {
                Button { copyToken(token) } label: { Image(systemName: "doc.on.doc") }
                    .help("复制完整密钥")
                Button {
                    editingToken = token
                    showsEditor = true
                } label: { Image(systemName: "pencil") }
                    .help("编辑")
                Button { toggle(token) } label: {
                    Image(systemName: token.status == 1 ? "pause.circle" : "play.circle")
                }
                .help(token.status == 1 ? "禁用" : "启用")
                Button { pendingDeletion = token } label: { Image(systemName: "trash") }
                    .help("删除")
            }
            .buttonStyle(.borderless)
            .disabled(store.isMutating)
        )
        .font(.system(size: 11))
        .foregroundStyle(AppTheme.secondaryText)
        .frame(height: 46)
    }

    private func tokenColumns<Name: View, Key: View, Status: View, Quota: View, Models: View, Expiry: View, Actions: View>(
        name: Name,
        key: Key,
        status: Status,
        quota: Quota,
        models: Models,
        expiry: Expiry,
        actions: Actions
    ) -> some View {
        HStack(spacing: 14) {
            name.frame(width: 120, alignment: .leading)
            key.frame(width: 170, alignment: .leading)
            status.frame(width: 84, alignment: .leading)
            quota.frame(width: 170, alignment: .leading)
            models.frame(width: 150, alignment: .leading)
            expiry.frame(width: 100, alignment: .leading)
            actions.frame(width: 120, alignment: .trailing)
        }
        .padding(.horizontal, 16)
    }

    private func submitSearch() {
        guard let client else { return }
        Task { await store.submitSearch(client: client) }
    }

    private func refresh() {
        guard let client else { return }
        Task { await store.refresh(client: client) }
    }

    private func changePage(_ page: Int) {
        guard let client else { return }
        Task { await store.goToPage(page, client: client) }
    }

    private func toggle(_ token: TokenRecord) {
        guard let client else { return }
        Task { _ = await store.setEnabled(token.status != 1, id: token.id, client: client) }
    }

    private func copyToken(_ token: TokenRecord) {
        guard let client else { return }
        Task {
            await store.revealTokenKey(id: token.id, client: client) { key in
                let canonicalKey = key.hasPrefix("sk-") ? key : "sk-\(key)"
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(canonicalKey, forType: .string)
                copyMessage = "“\(token.name)”的密钥已复制"
            }
        }
    }
}
