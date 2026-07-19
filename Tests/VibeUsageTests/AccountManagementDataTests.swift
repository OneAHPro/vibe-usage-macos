import Foundation
import Testing
@testable import VibeUsage

struct AccountManagementDataTests {
    @Test
    func tokenPageDecodesProductionPayloadAndFormatsSafely() throws {
        let data = Data(#"""
        {
          "page":1,"page_size":20,"total":1,
          "items":[{
            "id":9,"user_id":7,"key":"abcd**********wxyz","status":1,
            "name":"Codex","created_time":1720000000,"accessed_time":1720000100,
            "expired_time":-1,"remain_quota":1000000,"unlimited_quota":false,
            "model_limits_enabled":true,"model_limits":"gpt-5.6-sol,gpt-5.6-terra",
            "allow_ips":"127.0.0.1","used_quota":250000,"group":"pro",
            "cross_group_retry":true
          }]
        }
        """#.utf8)

        let page = try JSONDecoder().decode(TokenPage.self, from: data)
        let token = try #require(page.items.first)

        #expect(page.pageSize == 20)
        #expect(token.statusLabel == "已启用")
        #expect(token.quotaLabel(quotaPerUnit: 500_000) == "$2.00")
        #expect(token.expirationLabel == "永不过期")
        #expect(token.maskedKey == "abcd**********wxyz")
        #expect(!token.maskedKey.contains("sk-"))
    }

    @Test
    func unlimitedTokenAndTerminalStatusesHaveClearLabels() {
        let token = TokenRecord(
            id: 1,
            userID: 7,
            maskedKey: "ab****yz",
            status: 3,
            name: "过期令牌",
            createdTime: 0,
            accessedTime: 0,
            expiredTime: 1,
            remainQuota: 0,
            unlimitedQuota: true,
            modelLimitsEnabled: false,
            modelLimits: "",
            allowIPs: nil,
            usedQuota: 0,
            group: "",
            crossGroupRetry: false
        )

        #expect(token.statusLabel == "已过期")
        #expect(token.quotaLabel(quotaPerUnit: 500_000) == "无限额度")
    }

    @Test
    func topUpInfoAndHistoryDecodeProductionSnakeCase() throws {
        let infoData = Data(#"""
        {
          "enable_online_topup":true,"enable_stripe_topup":true,
          "enable_creem_topup":false,"enable_waffo_topup":true,
          "enable_waffo_pancake_topup":false,
          "waffo_pay_methods":[{"name":"Card","icon":"/pay-card.png","payMethodType":"CREDITCARD","payMethodName":""}],
          "creem_products":"[]",
          "pay_methods":[{"name":"支付宝","type":"alipay","color":"blue"}],
          "min_topup":10,"stripe_min_topup":5,"waffo_min_topup":8,
          "waffo_pancake_min_topup":12,"amount_options":[10,20,50],
          "discount":{"20":0.95}
        }
        """#.utf8)
        let recordData = Data(#"""
        {
          "id":88,"user_id":7,"amount":5000000,"money":9.5,
          "trade_no":"order-88","payment_method":"alipay","payment_provider":"epay",
          "create_time":1720000000,"complete_time":1720000030,"status":"success"
        }
        """#.utf8)

        let info = try JSONDecoder().decode(TopUpInfo.self, from: infoData)
        let topUp = try JSONDecoder().decode(TopUpRecord.self, from: recordData)

        #expect(info.amountOptions == [10, 20, 50])
        #expect(info.paymentMethods.first?.name == "支付宝")
        #expect(info.waffoPaymentMethods.first?.payMethodType == "CREDITCARD")
        #expect(info.discount[20] == 0.95)
        #expect(topUp.statusLabel == "成功")
        #expect(topUp.tradeNumber == "order-88")
    }

    @Test
    func topUpStatusLabelsCoverServerStates() {
        #expect(TopUpRecord.statusLabel(for: "pending") == "待支付")
        #expect(TopUpRecord.statusLabel(for: "success") == "成功")
        #expect(TopUpRecord.statusLabel(for: "failed") == "失败")
        #expect(TopUpRecord.statusLabel(for: "expired") == "已过期")
    }

    @Test
    func subscriptionPlansAndCurrentSubscriptionDecodeProductionPayloads() throws {
        let planJSON = #"{"id":3,"title":"Pro","subtitle":"高并发模型权益","price_amount":29.9,"currency":"USD","duration_unit":"month","duration_value":1,"custom_seconds":0,"enabled":true,"sort_order":10,"stripe_price_id":"price_123","creem_product_id":"prod_123","max_purchase_per_user":2,"upgrade_group":"pro","total_amount":100000000,"quota_reset_period":"monthly","quota_reset_custom_seconds":0,"created_at":1720000000,"updated_at":1720000100}"#
        let plans = try JSONDecoder().decode(
            [SubscriptionPlanItem].self,
            from: Data("[{\"plan\":\(planJSON)}]".utf8)
        )
        let current = try JSONDecoder().decode(
            SubscriptionSelf.self,
            from: Data(#"{"billing_preference":"subscription_first","subscriptions":[{"subscription":{"id":9,"user_id":7,"plan_id":3,"amount_total":100000000,"amount_used":25000000,"start_time":1720000000,"end_time":1751536000,"status":"active","source":"order","last_reset_time":1720000000,"next_reset_time":1722592000,"upgrade_group":"pro","prev_user_group":"","created_at":1720000000,"updated_at":1720000100},"plan":\#(planJSON)}],"all_subscriptions":[]}"#.utf8)
        )

        let plan = try #require(plans.first?.plan)
        let subscription = try #require(current.subscriptions.first)

        #expect(plan.durationLabel == "1 个月")
        #expect(plan.resetLabel == "每月")
        #expect(plan.quotaLabel(quotaPerUnit: 500_000) == "$200.00")
        #expect(plan.priceLabel == "$29.90")
        #expect(current.billingPreference == .subscriptionFirst)
        #expect(subscription.remainingAmount == 75_000_000)
        #expect(subscription.usageFraction == 0.25)
        #expect(subscription.subscription.statusLabel == "生效中")
    }

    @Test
    func subscriptionFormattingHandlesUnlimitedAndCustomDurations() {
        let plan = SubscriptionPlan(
            id: 4,
            title: "Flexible",
            subtitle: "",
            priceAmount: 0,
            currency: "USD",
            durationUnit: "custom",
            durationValue: 1,
            customSeconds: 172_800,
            enabled: true,
            sortOrder: 0,
            stripePriceID: "",
            creemProductID: "",
            maxPurchasePerUser: 0,
            upgradeGroup: "",
            totalAmount: 0,
            quotaResetPeriod: "custom",
            quotaResetCustomSeconds: 3_600,
            createdAt: 0,
            updatedAt: 0
        )

        #expect(plan.durationLabel == "2 天")
        #expect(plan.resetLabel == "每 1 小时")
        #expect(plan.quotaLabel(quotaPerUnit: 500_000) == "不限额度")
        #expect(BillingPreference.walletOnly.label == "仅用钱包")
    }

    @Test
    func tokenQuotaConversionRejectsNonFiniteAndOverflowingInput() {
        #expect(TokenQuotaInput.quota(dollars: "10", quotaPerUnit: 500_000, unlimited: false) == 5_000_000)
        #expect(TokenQuotaInput.quota(dollars: "1e999", quotaPerUnit: 500_000, unlimited: false) == nil)
        #expect(TokenQuotaInput.quota(dollars: "-1", quotaPerUnit: 500_000, unlimited: false) == nil)
        #expect(TokenQuotaInput.quota(dollars: "999999999999999999999", quotaPerUnit: 500_000, unlimited: false) == nil)
        #expect(TokenQuotaInput.quota(dollars: "", quotaPerUnit: 500_000, unlimited: true) == 0)
    }
}
