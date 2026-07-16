import SwiftUI

/// Main dashboard content hosted inside the standard application window.
struct PopoverView: View {
    @Environment(AppState.self) private var appState
    @State private var username = ""
    @State private var password = ""
    @State private var twoFactorCode = ""

    var body: some View {
        Group {
            if appState.isCheckingSession {
                checkingSessionView
            } else if !appState.isConfigured {
                loginView
            } else {
                DashboardShellView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.subtleSurface)
    }

    private var checkingSessionView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.regular)
            Text("正在连接 new 系统…")
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.secondaryText)
        }
    }

    private var loginView: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 36)

            VStack(alignment: .leading, spacing: 22) {
                brand

                VStack(alignment: .leading, spacing: 5) {
                    Text(appState.requiresTwoFactor ? "输入验证码" : "登录 new 系统")
                        .font(.system(size: 23, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppTheme.primaryText)

                    Text(appState.requiresTwoFactor ? "请输入身份验证器中显示的 6 位验证码。" : "登录后显示你在 new 系统中的使用数据。")
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.secondaryText)
                }

                if appState.requiresTwoFactor {
                    twoFactorForm
                } else {
                    passwordForm
                }

                HStack(spacing: 6) {
                    Image(systemName: "lock.fill")
                    Text("安全连接到 api.anhepro.com")
                }
                .font(.system(size: 10))
                .foregroundStyle(AppTheme.tertiaryText)
            }
            .padding(28)
            .frame(maxWidth: 410)
            .background(AppTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppTheme.separator, lineWidth: 1))

            Spacer(minLength: 36)
        }
        .padding(.horizontal, 24)
    }

    private var brand: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 5)
                    .stroke(AppTheme.primaryText, lineWidth: 1.5)
                Text("V")
                    .font(.system(size: 14, weight: .black, design: .monospaced))
                    .foregroundStyle(AppTheme.primaryText)
            }
            .frame(width: 28, height: 28)

            Text("Vibe Usage")
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .foregroundStyle(AppTheme.primaryText)

            if AppConfig.isDev {
                Text("DEBUG")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.orange)
            }
        }
    }

    private var passwordForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("用户名或邮箱")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppTheme.secondaryText)
                TextField("请输入用户名或邮箱", text: $username)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.username)
                    .onSubmit(submitPasswordLogin)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("密码")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppTheme.secondaryText)
                SecureField("请输入密码", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.password)
                    .onSubmit(submitPasswordLogin)
            }

            authenticationError

            Button(action: submitPasswordLogin) {
                loginButtonLabel("登录")
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.primaryText)
            .foregroundStyle(AppTheme.windowBackground)
            .disabled(username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.isEmpty || appState.isAuthenticating)
        }
    }

    private var twoFactorForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("6 位验证码")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppTheme.secondaryText)
                TextField("000000", text: $twoFactorCode)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .onChange(of: twoFactorCode) { _, value in
                        twoFactorCode = String(value.filter(\.isNumber).prefix(6))
                    }
                    .onSubmit(submitTwoFactor)
            }

            authenticationError

            Button(action: submitTwoFactor) {
                loginButtonLabel("验证并进入")
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.primaryText)
            .foregroundStyle(AppTheme.windowBackground)
            .disabled(twoFactorCode.count != 6 || appState.isAuthenticating)

            Button("返回登录") {
                twoFactorCode = ""
                appState.cancelTwoFactor()
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(AppTheme.secondaryText)
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private var authenticationError: some View {
        if let error = appState.authenticationError {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "exclamationmark.circle.fill")
                Text(error)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.system(size: 11))
            .foregroundStyle(.red)
        }
    }

    private func loginButtonLabel(_ title: String) -> some View {
        HStack(spacing: 7) {
            if appState.isAuthenticating {
                ProgressView()
                    .controlSize(.small)
            }
            Text(title)
                .font(.system(size: 12, weight: .semibold))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 30)
    }

    private func submitPasswordLogin() {
        guard !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !password.isEmpty,
              !appState.isAuthenticating
        else { return }
        Task {
            await appState.login(
                username: username.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password
            )
            if appState.requiresTwoFactor || appState.isConfigured {
                password = ""
            }
        }
    }

    private func submitTwoFactor() {
        guard twoFactorCode.count == 6, !appState.isAuthenticating else { return }
        Task {
            await appState.verifyTwoFactor(code: twoFactorCode)
            if appState.isConfigured {
                twoFactorCode = ""
            }
        }
    }
}
