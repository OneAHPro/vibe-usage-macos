import SwiftUI

struct ActivityCenterView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "gift")
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(AppTheme.tertiaryText)

            Text("暂无活动")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppTheme.secondaryText)

            Text("新活动上线后会在这里显示")
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.tertiaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .stroke(AppTheme.separator, lineWidth: 1)
        }
        .padding(20)
        .background(AppTheme.subtleSurface)
    }
}
