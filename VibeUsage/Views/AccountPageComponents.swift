import SwiftUI

struct AccountSummaryCard: View {
    let title: String
    let value: String
    var accent = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppTheme.secondaryText)
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .monospaced))
                .foregroundStyle(accent ? AppTheme.costAccent : AppTheme.primaryText)
                .lineLimit(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .stroke(AppTheme.separator, lineWidth: 1)
        }
    }
}

struct AccountErrorBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.secondaryText)
            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 34)
        .background(Color.red.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .stroke(Color.red.opacity(0.22), lineWidth: 1)
        }
    }
}

struct AccountPagination: View {
    let page: Int
    let pageCount: Int
    let total: Int
    let disabled: Bool
    let onPrevious: () -> Void
    let onNext: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text("共 \(total) 条")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(AppTheme.tertiaryText)
            Spacer()
            Button(action: onPrevious) {
                Image(systemName: "chevron.left")
            }
            .disabled(disabled || page <= 1)
            Text("\(page) / \(pageCount)")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(AppTheme.secondaryText)
                .frame(minWidth: 52)
            Button(action: onNext) {
                Image(systemName: "chevron.right")
            }
            .disabled(disabled || page >= pageCount)
        }
        .buttonStyle(.borderless)
    }
}

struct AccountStatusLabel: View {
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(AppTheme.secondaryText)
        }
    }
}
