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

    var errorDescription: String? {
        switch self {
        case .failedVerification: return "購入の検証に失敗しました"
        case .purchasePending:    return "購入が保留中です（保護者承認などをご確認ください）"
        case .userCancelled:      return nil
        }
    }
}

@MainActor
final class PurchaseManager: ObservableObject {
    static let proMonthlyID = "com.yourapp.diaryapp.pro.monthly"

    @Published private(set) var isProActive = false
    @Published private(set) var isLoading = false
    @Published private(set) var proProduct: Product?

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

    func purchase() async throws {
        guard let product = proProduct else { return }
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
            break
        }
    }

    func restore() async {
        isLoading = true
        defer { isLoading = false }
        try? await AppStore.sync()
        await updateEntitlements()
    }

    // MARK: - Private

    private func loadProducts() async {
        do {
            let products = try await Product.products(for: [Self.proMonthlyID])
            proProduct = products.first
        } catch {
            print("[PurchaseManager] Product fetch failed: \(error)")
        }
    }

    private func updateEntitlements() async {
        var active = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let tx) = result,
               tx.productID == Self.proMonthlyID,
               tx.revocationDate == nil {
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
