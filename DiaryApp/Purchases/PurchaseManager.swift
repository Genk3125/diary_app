// PurchaseManager.swift
// StoreKit 2 ラッパー。DiaryStore が所有し、isProActive の変化を Combine で通知する。
// ローカルテスト: Xcode > Edit Scheme > Run > Options > StoreKit Configuration → Products.storekit を選択。
// 本番: App Store Connect で com.yourapp.diaryapp.pro.monthly を登録後、そのままの Product ID で動く。

import Foundation
import StoreKit

enum StoreError: LocalizedError {
    case failedVerification
    case purchasePending
    case userCancelled
    case productNotAvailable
    case unknownPurchaseResult
    case restoreFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .failedVerification: return "購入の検証に失敗しました"
        case .purchasePending:    return "購入が保留中です（保護者承認などをご確認ください）"
        case .userCancelled:      return nil
        case .productNotAvailable: return "購入商品を取得できませんでした。しばらくしてから再試行してください。"
        case .unknownPurchaseResult: return "購入処理の結果を判定できませんでした。時間をおいて再試行してください。"
        case .restoreFailed(let underlying):
            return "購入の復元に失敗しました。通信状態をご確認のうえ再試行してください。（\(underlying.localizedDescription)）"
        }
    }
}

@MainActor
final class PurchaseManager: ObservableObject {
    static let proMonthlyID = "com.yourapp.diaryapp.pro.monthly"

    @Published private(set) var isProActive = false
    @Published private(set) var isLoading = false
    @Published private(set) var proProduct: Product?
    @Published private(set) var productLoadError: String?

    private var updateListenerTask: Task<Void, Never>?

    init() {
        updateListenerTask = Task { await listenForTransactions() }
        Task {
            await loadProducts()
            await updateEntitlements()
        }
    }

    deinit {
        updateListenerTask?.cancel()
    }

    // MARK: - Public actions

    func refreshProducts() async {
        await loadProducts()
    }

    func purchase() async throws {
        if proProduct == nil {
            await loadProducts()
        }
        guard let product = proProduct else {
            throw StoreError.productNotAvailable
        }
        isLoading = true
        defer { isLoading = false }

        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await updateEntitlements()
            await transaction.finish()
        case .pending:
            throw StoreError.purchasePending
        case .userCancelled:
            throw StoreError.userCancelled
        @unknown default:
            throw StoreError.unknownPurchaseResult
        }
    }

    func restore() async throws {
        isLoading = true
        defer { isLoading = false }
        do {
            try await AppStore.sync()
            await updateEntitlements()
        } catch {
            throw StoreError.restoreFailed(underlying: error)
        }
    }

    // MARK: - Private

    private func loadProducts() async {
        productLoadError = nil
        do {
            let products = try await Product.products(for: [Self.proMonthlyID])
            proProduct = products.first(where: { $0.id == Self.proMonthlyID })
            if proProduct == nil {
                productLoadError = "購入商品が見つかりませんでした。設定をご確認ください。"
            }
        } catch {
            proProduct = nil
            productLoadError = "商品情報を取得できませんでした。通信状態をご確認のうえ再試行してください。"
            print("[PurchaseManager] Product fetch failed: \(error)")
        }
    }

    private func updateEntitlements() async {
        var active = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let tx) = result,
               tx.productID == Self.proMonthlyID,
               tx.revocationDate == nil {
                let isNotExpired = tx.expirationDate.map { $0 > Date() } ?? true
                guard isNotExpired else { continue }
                active = true
            }
        }
        isProActive = active
    }

    private func listenForTransactions() async {
        for await result in Transaction.updates {
            if case .verified(let tx) = result {
                await updateEntitlements()
                await tx.finish()
            } else if case .unverified(_, let error) = result {
                print("[PurchaseManager] Unverified transaction update: \(error)")
            }
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified: throw StoreError.failedVerification
        case .verified(let value): return value
        }
    }
}
