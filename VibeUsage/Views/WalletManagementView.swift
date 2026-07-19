import SwiftUI

struct WalletManagementView: View {
    var body: some View {
        AccountPagePlaceholder(
            icon: "wallet.pass",
            title: "钱包数据准备中",
            message: "余额与充值记录将在这里显示"
        )
    }
}

struct AccountPagePlaceholder: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(AppTheme.tertiaryText)
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppTheme.secondaryText)
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.tertiaryText)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 300)
            .background(AppTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .stroke(AppTheme.separator, lineWidth: 1)
            }
            .padding(20)
        }
        .background(AppTheme.subtleSurface)
    }
}
