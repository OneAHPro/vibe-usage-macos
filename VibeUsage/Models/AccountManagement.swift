import Foundation

struct TokenRecord: Codable, Identifiable, Equatable, Sendable {
    let id: Int
    let userID: Int
    let maskedKey: String
    let status: Int
    let name: String
    let createdTime: Int64
    let accessedTime: Int64
    let expiredTime: Int64
    let remainQuota: Int
    let unlimitedQuota: Bool
    let modelLimitsEnabled: Bool
    let modelLimits: String
    let allowIPs: String?
    let usedQuota: Int
    let group: String
    let crossGroupRetry: Bool

    enum CodingKeys: String, CodingKey {
        case id, status, name, group
        case userID = "user_id"
        case maskedKey = "key"
        case createdTime = "created_time"
        case accessedTime = "accessed_time"
        case expiredTime = "expired_time"
        case remainQuota = "remain_quota"
        case unlimitedQuota = "unlimited_quota"
        case modelLimitsEnabled = "model_limits_enabled"
        case modelLimits = "model_limits"
        case allowIPs = "allow_ips"
        case usedQuota = "used_quota"
        case crossGroupRetry = "cross_group_retry"
    }

    var statusLabel: String {
        switch status {
        case 1: "已启用"
        case 2: "已禁用"
        case 3: "已过期"
        case 4: "额度已用尽"
        default: "未知"
        }
    }

    var expirationLabel: String {
        guard expiredTime >= 0 else { return "永不过期" }
        return Formatters.formatUnixDate(expiredTime)
    }

    func quotaLabel(quotaPerUnit: Double) -> String {
        guard !unlimitedQuota else { return "无限额度" }
        guard quotaPerUnit > 0 else { return "$0.00" }
        return Formatters.formatCost(Double(remainQuota) / quotaPerUnit)
    }
}

struct TokenPage: Decodable, Equatable, Sendable {
    let page: Int
    let pageSize: Int
    let total: Int
    let items: [TokenRecord]

    enum CodingKeys: String, CodingKey {
        case page, total, items
        case pageSize = "page_size"
    }
}

struct TokenMutation: Encodable, Equatable, Sendable {
    var id: Int?
    var name: String
    var expiredTime: Int64
    var remainQuota: Int
    var unlimitedQuota: Bool
    var modelLimitsEnabled: Bool
    var modelLimits: String
    var allowIPs: String?
    var group: String
    var crossGroupRetry: Bool
    var status: Int?

    enum CodingKeys: String, CodingKey {
        case id, name, status, group
        case expiredTime = "expired_time"
        case remainQuota = "remain_quota"
        case unlimitedQuota = "unlimited_quota"
        case modelLimitsEnabled = "model_limits_enabled"
        case modelLimits = "model_limits"
        case allowIPs = "allow_ips"
        case crossGroupRetry = "cross_group_retry"
    }
}

struct PaymentMethod: Decodable, Identifiable, Equatable, Sendable {
    let name: String
    let type: String
    let color: String?
    let minimumTopUp: Int?

    var id: String { type }

    enum CodingKeys: String, CodingKey {
        case name, type, color
        case minimumTopUp = "min_topup"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        type = try container.decode(String.self, forKey: .type)
        color = try container.decodeIfPresent(String.self, forKey: .color)
        if let number = try? container.decodeIfPresent(Int.self, forKey: .minimumTopUp) {
            minimumTopUp = number
        } else if let string = try? container.decodeIfPresent(String.self, forKey: .minimumTopUp) {
            minimumTopUp = Int(string)
        } else {
            minimumTopUp = nil
        }
    }
}

struct WaffoPaymentMethod: Decodable, Identifiable, Equatable, Sendable {
    let name: String
    let icon: String
    let payMethodType: String
    let payMethodName: String

    var id: String { "\(payMethodType):\(payMethodName)" }
}

struct CreemProduct: Decodable, Identifiable, Equatable, Sendable {
    let productID: String
    let name: String
    let price: Double
    let currency: String
    let quota: Int64

    var id: String { productID }

    enum CodingKeys: String, CodingKey {
        case name, price, currency, quota
        case productID = "productId"
    }
}

struct TopUpInfo: Decodable, Equatable, Sendable {
    let enableOnlineTopUp: Bool
    let enableStripeTopUp: Bool
    let enableCreemTopUp: Bool
    let enableWaffoTopUp: Bool
    let enableWaffoPancakeTopUp: Bool
    let waffoPaymentMethods: [WaffoPaymentMethod]
    let creemProducts: [CreemProduct]
    let paymentMethods: [PaymentMethod]
    let minimumTopUp: Int
    let stripeMinimumTopUp: Int
    let waffoMinimumTopUp: Int
    let waffoPancakeMinimumTopUp: Int
    let amountOptions: [Int]
    let discount: [Int: Double]

    enum CodingKeys: String, CodingKey {
        case enableOnlineTopUp = "enable_online_topup"
        case enableStripeTopUp = "enable_stripe_topup"
        case enableCreemTopUp = "enable_creem_topup"
        case enableWaffoTopUp = "enable_waffo_topup"
        case enableWaffoPancakeTopUp = "enable_waffo_pancake_topup"
        case waffoPaymentMethods = "waffo_pay_methods"
        case creemProducts = "creem_products"
        case paymentMethods = "pay_methods"
        case minimumTopUp = "min_topup"
        case stripeMinimumTopUp = "stripe_min_topup"
        case waffoMinimumTopUp = "waffo_min_topup"
        case waffoPancakeMinimumTopUp = "waffo_pancake_min_topup"
        case amountOptions = "amount_options"
        case discount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enableOnlineTopUp = try container.decodeIfPresent(Bool.self, forKey: .enableOnlineTopUp) ?? false
        enableStripeTopUp = try container.decodeIfPresent(Bool.self, forKey: .enableStripeTopUp) ?? false
        enableCreemTopUp = try container.decodeIfPresent(Bool.self, forKey: .enableCreemTopUp) ?? false
        enableWaffoTopUp = try container.decodeIfPresent(Bool.self, forKey: .enableWaffoTopUp) ?? false
        enableWaffoPancakeTopUp = try container.decodeIfPresent(Bool.self, forKey: .enableWaffoPancakeTopUp) ?? false
        waffoPaymentMethods = try container.decodeIfPresent([WaffoPaymentMethod].self, forKey: .waffoPaymentMethods) ?? []
        paymentMethods = try container.decodeIfPresent([PaymentMethod].self, forKey: .paymentMethods) ?? []
        minimumTopUp = try container.decodeIfPresent(Int.self, forKey: .minimumTopUp) ?? 0
        stripeMinimumTopUp = try container.decodeIfPresent(Int.self, forKey: .stripeMinimumTopUp) ?? 0
        waffoMinimumTopUp = try container.decodeIfPresent(Int.self, forKey: .waffoMinimumTopUp) ?? 0
        waffoPancakeMinimumTopUp = try container.decodeIfPresent(Int.self, forKey: .waffoPancakeMinimumTopUp) ?? 0
        amountOptions = try container.decodeIfPresent([Int].self, forKey: .amountOptions) ?? []
        discount = try container.decodeIfPresent([Int: Double].self, forKey: .discount) ?? [:]

        if let products = try? container.decode([CreemProduct].self, forKey: .creemProducts) {
            creemProducts = products
        } else if let encoded = try? container.decode(String.self, forKey: .creemProducts),
                  let data = encoded.data(using: .utf8),
                  let products = try? JSONDecoder().decode([CreemProduct].self, from: data) {
            creemProducts = products
        } else {
            creemProducts = []
        }
    }
}

struct TopUpRecord: Decodable, Identifiable, Equatable, Sendable {
    let id: Int
    let userID: Int
    let amount: Int64
    let money: Double
    let tradeNumber: String
    let paymentMethod: String
    let paymentProvider: String
    let createTime: Int64
    let completeTime: Int64
    let status: String

    enum CodingKeys: String, CodingKey {
        case id, amount, money, status
        case userID = "user_id"
        case tradeNumber = "trade_no"
        case paymentMethod = "payment_method"
        case paymentProvider = "payment_provider"
        case createTime = "create_time"
        case completeTime = "complete_time"
    }

    var statusLabel: String { Self.statusLabel(for: status) }

    static func statusLabel(for status: String) -> String {
        switch status.lowercased() {
        case "pending": "待支付"
        case "success": "成功"
        case "failed": "失败"
        case "expired": "已过期"
        default: "未知"
        }
    }
}

struct TopUpPage: Decodable, Equatable, Sendable {
    let page: Int
    let pageSize: Int
    let total: Int
    let items: [TopUpRecord]

    enum CodingKeys: String, CodingKey {
        case page, total, items
        case pageSize = "page_size"
    }
}

enum PaymentCheckout: Equatable, Sendable {
    case url(URL)
    case form(action: URL, fields: [String: String])
}

enum PaymentRequest: Equatable, Sendable {
    case epay(amount: Int64, paymentMethod: String)
    case stripe(amount: Int64)
    case creem(productID: String)
    case waffo(amount: Int64, payMethodIndex: Int?)
}

enum TokenQuotaInput {
    static func quota(dollars: String, quotaPerUnit: Double, unlimited: Bool) -> Int? {
        if unlimited { return 0 }
        guard quotaPerUnit.isFinite,
              quotaPerUnit > 0,
              let value = Double(dollars.trimmingCharacters(in: .whitespacesAndNewlines)),
              value.isFinite,
              value >= 0
        else { return nil }

        let quota = value * quotaPerUnit
        let rounded = quota.rounded()
        guard rounded.isFinite, rounded >= 0, rounded < Double(Int.max) else { return nil }
        return Int(rounded)
    }
}
