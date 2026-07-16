import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    let embedded: Bool

    @State private var autoStartEnabled = false
    @State private var showingLogoutConfirmation = false

    init(embedded: Bool = false) {
        self.embedded = embedded
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("账号") {
                    Text(appState.accountUsername ?? "—")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(AppTheme.secondaryText)
                }

                LabeledContent("服务器") {
                    Text("api.anhepro.com")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(AppTheme.secondaryText)
                }

                LabeledContent("状态") {
                    HStack(spacing: 5) {
                        statusIcon
                        Text(statusText)
                    }
                    .font(.caption)
                }

                if let lastSync = appState.lastSyncTime {
                    LabeledContent("上次更新") {
                        Text(Formatters.formatRelativeTime(lastSync))
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                }

                Button("立即更新数据") {
                    Task { await appState.triggerSync() }
                }
                .disabled(appState.syncStatus == .syncing)
            } header: {
                Text("new 系统")
            } footer: {
                Text("客户端直接读取当前账号在 new 系统中的使用记录，不扫描本地 AI 工具日志。")
                    .font(.caption)
            }

            Section {
                Toggle("菜单栏显示费用", isOn: Binding(
                    get: { appState.showCostInMenuBar },
                    set: { appState.showCostInMenuBar = $0 }
                ))
                .tint(.green)

                Toggle("菜单栏显示 Token", isOn: Binding(
                    get: { appState.showTokensInMenuBar },
                    set: { appState.showTokensInMenuBar = $0 }
                ))
                .tint(.green)
            } header: {
                Text("菜单栏")
            } footer: {
                Text("在菜单栏图标旁显示当前时间范围的费用和 Token 用量。")
                    .font(.caption)
            }

            Section {
                Toggle("开机自启动", isOn: $autoStartEnabled)
                    .tint(.green)
                    .onChange(of: autoStartEnabled) { _, newValue in
                        setAutoStart(newValue)
                    }
            } header: {
                Text("通用")
            }

            Section {
                LabeledContent("版本") {
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? AppConfig.version)
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                }
            } header: {
                Text("关于")
            }

            Section {
                Button("退出当前账号", role: .destructive) {
                    showingLogoutConfirmation = true
                }
                .confirmationDialog("确定退出当前账号吗？", isPresented: $showingLogoutConfirmation) {
                    Button("退出登录", role: .destructive) {
                        Task { await appState.logout() }
                    }
                    Button("取消", role: .cancel) {}
                } message: {
                    Text("退出后需要重新输入 new 系统账号和密码。")
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
        .background(AppTheme.subtleSurface)
        .frame(width: embedded ? nil : 420, height: embedded ? nil : 460)
        .frame(maxWidth: embedded ? 760 : nil, maxHeight: embedded ? .infinity : nil)
        .padding(embedded ? 20 : 0)
        .onAppear {
            autoStartEnabled = SMAppService.mainApp.status == .enabled
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch appState.syncStatus {
        case .idle, .success:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .syncing:
            ProgressView()
                .controlSize(.small)
        case .error:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
        }
    }

    private var statusText: String {
        switch appState.syncStatus {
        case .idle: "已连接"
        case .syncing: "更新中…"
        case .success: "更新成功"
        case .error(let message): message
        }
    }

    private func setAutoStart(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("Failed to set auto-start: \(error)")
        }
    }
}
