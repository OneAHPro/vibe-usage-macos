import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

struct PaymentQRCodePresentation: Identifiable {
    let id = UUID()
    let checkout: PaymentCheckout
    let title: String
    let paymentMethod: String
    let amount: String
}

enum PaymentQRCodeRenderer {
    static let context = CIContext(options: [.cacheIntermediates: false])

    static func pngData(for value: String, scale: CGFloat = 10) -> Data? {
        guard !value.isEmpty, let data = value.data(using: .utf8) else { return nil }

        let filter = CIFilter.qrCodeGenerator()
        filter.message = data
        filter.correctionLevel = "M"
        guard let outputImage = filter.outputImage else { return nil }

        let scaledImage = outputImage.transformed(
            by: CGAffineTransform(scaleX: scale, y: scale)
        )
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return context.pngRepresentation(
            of: scaledImage,
            format: .RGBA8,
            colorSpace: colorSpace
        )
    }
}

@MainActor
struct PaymentQRCodeSheet: View {
    @Environment(\.dismiss) private var dismiss

    let presentation: PaymentQRCodePresentation
    let onPaymentCompleted: @MainActor () async -> Void

    @State private var copied = false
    @State private var isRefreshing = false
    @State private var isRendering = true
    @State private var qrImage: NSImage?

    private let paymentURL: URL?

    init(
        presentation: PaymentQRCodePresentation,
        onPaymentCompleted: @escaping @MainActor () async -> Void
    ) {
        self.presentation = presentation
        self.onPaymentCompleted = onPaymentCompleted
        let paymentURL = presentation.checkout.qrCodeURL
        self.paymentURL = paymentURL
    }

    var body: some View {
        VStack(spacing: 18) {
            header

            VStack(spacing: 12) {
                qrCode
                Text(presentation.amount)
                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppTheme.costAccent)
                Text("请使用手机扫码完成支付")
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.secondaryText)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)

            Divider()

            HStack(spacing: 8) {
                Button("取消") { dismiss() }
                    .buttonStyle(.bordered)

                Spacer()

                Button(copied ? "已复制" : "复制支付链接", systemImage: copied ? "checkmark" : "doc.on.doc") {
                    copyPaymentLink()
                }
                .buttonStyle(.bordered)
                .disabled(paymentURL == nil)

                Button("完成支付并刷新", systemImage: "arrow.clockwise") {
                    completePayment()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isRefreshing)
            }
        }
        .padding(22)
        .frame(width: 430)
        .background(AppTheme.surface)
        .task(id: paymentURL) {
            await renderQRCode()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "qrcode")
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(AppTheme.costAccent)
                .frame(width: 38, height: 38)
                .background(AppTheme.costAccent.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 3) {
                Text(presentation.title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(AppTheme.primaryText)
                Text(presentation.paymentMethod)
                    .font(.system(size: 10))
                    .foregroundStyle(AppTheme.tertiaryText)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var qrCode: some View {
        if let qrImage {
            Image(nsImage: qrImage)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(width: 236, height: 236)
                .padding(14)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(AppTheme.separator, lineWidth: 1)
                )
                .accessibilityLabel("支付二维码")
        } else if isRendering {
            VStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text("正在生成支付二维码")
                    .font(.system(size: 10))
            }
            .foregroundStyle(AppTheme.tertiaryText)
            .frame(width: 264, height: 264)
            .background(AppTheme.subtleSurface)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        } else {
            VStack(spacing: 9) {
                Image(systemName: "qrcode.viewfinder")
                    .font(.system(size: 34))
                Text("无法生成支付二维码")
                    .font(.system(size: 12, weight: .medium))
                Text("请取消后重新创建支付订单")
                    .font(.system(size: 10))
            }
            .foregroundStyle(AppTheme.tertiaryText)
            .frame(width: 264, height: 264)
            .background(AppTheme.subtleSurface)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private func copyPaymentLink() {
        guard let paymentURL else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(paymentURL.absoluteString, forType: .string)
        copied = true
    }

    private func renderQRCode() async {
        guard let paymentURL else {
            isRendering = false
            return
        }
        let value = paymentURL.absoluteString
        let data = await Task.detached(priority: .userInitiated) {
            PaymentQRCodeRenderer.pngData(for: value)
        }.value
        guard !Task.isCancelled else { return }
        qrImage = data.flatMap(NSImage.init(data:))
        isRendering = false
    }

    private func completePayment() {
        guard !isRefreshing else { return }
        isRefreshing = true
        Task {
            await onPaymentCompleted()
            isRefreshing = false
            dismiss()
        }
    }
}
