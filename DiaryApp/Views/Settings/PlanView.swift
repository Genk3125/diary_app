// PlanView.swift
// プラン管理 UI。DiaryStore 経由で PurchaseManager を呼び出す。
// ローカルテスト時は Xcode Scheme > StoreKit Configuration に Products.storekit を指定すること。

import SwiftUI
import StoreKit

struct PlanView: View {
    @EnvironmentObject var store: DiaryStore
    @State private var errorMessage: String?
    @State private var showError = false

    private var pm: PurchaseManager { store.purchaseManager }

    var body: some View {
        NavigationStack {
            List {
                currentPlanSection
                bookLayoutSection
                featuresSection
                if !store.currentPlan.isPro {
                    purchaseSection
                }
                restoreSection
            }
            .navigationTitle("プラン")
            .alert("エラー", isPresented: $showError) {
                Button("OK") {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    // MARK: - Sections

    private var currentPlanSection: some View {
        Section {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("現在のプラン")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(store.currentPlan.displayName)
                        .font(.title2.bold())
                }
                Spacer()
                planBadge
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var planBadge: some View {
        if store.currentPlan.isPro {
            Text("PRO")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.accentColor)
                .clipShape(Capsule())
        } else {
            Text("FREE")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.15))
                .clipShape(Capsule())
        }
    }

    private var featuresSection: some View {
        Section("機能比較") {
            featureRow("写真添付",       free: "1枚/エントリ", pro: "3枚/エントリ")
            featureRow("動画添付",       free: "1本/エントリ", pro: "3本/エントリ")
            featureRow("PDF インポート", free: "○",            pro: "○")
            featureRow("QR コード生成",  free: "○",            pro: "○")
            featureRow("書籍化プレビュー",free: "○",            pro: "○")
        }
    }

    private var bookLayoutSection: some View {
        Section(
            content: {
                TextField("タイトル", text: configBinding(\.title))
                TextField("サブタイトル", text: configBinding(\.subtitle))

                Picker("並び順", selection: configBinding(\.sortOrder)) {
                    ForEach(BookLayoutConfig.SortOrder.allCases, id: \.self) { sortOrder in
                        Text(sortOrder.displayName).tag(sortOrder)
                    }
                }

                Picker("グループ", selection: configBinding(\.grouping)) {
                    ForEach(BookLayoutConfig.GroupingStyle.allCases, id: \.self) { grouping in
                        Text(grouping.displayName).tag(grouping)
                    }
                }

                Toggle("ソースアプリを掲載", isOn: configBinding(\.includeSourceApp))

                Picker("写真の反映数", selection: photoLimitBinding) {
                    Text("プラン既定（\(store.currentPlan.maxPhotosInPrint)枚）").tag(Optional<Int>.none)
                    ForEach(0...store.currentPlan.maxPhotosInPrint, id: \.self) { count in
                        Text("\(count)枚").tag(Optional<Int>.some(count))
                    }
                }

                Picker("動画の反映数", selection: videoLimitBinding) {
                    Text("プラン既定（\(store.currentPlan.maxVideosInPrint)本）").tag(Optional<Int>.none)
                    ForEach(0...store.currentPlan.maxVideosInPrint, id: \.self) { count in
                        Text("\(count)本").tag(Optional<Int>.some(count))
                    }
                }
            },
            header: {
                Text("書籍化設定")
            },
            footer: {
                Text("設定は書籍化プレビューとPDF出力に保存反映されます。未設定では現在の\(store.currentPlan.displayName)プラン上限を使い、明示設定してもプラン上限は超えません。")
            }
        )
    }

    private func featureRow(_ name: String, free: String, pro: String) -> some View {
        HStack {
            Text(name)
            Spacer()
            HStack(spacing: 24) {
                Text(free)
                    .foregroundStyle(store.currentPlan.isPro ? .secondary : .primary)
                    .frame(width: 80, alignment: .center)
                Text(pro)
                    .foregroundStyle(store.currentPlan.isPro ? .primary : .secondary)
                    .frame(width: 80, alignment: .center)
            }
            .font(.caption)
        }
    }

    @ViewBuilder
    private var purchaseSection: some View {
        Section {
            Button {
                Task { await doPurchase() }
            } label: {
                HStack {
                    if pm.isLoading {
                        ProgressView()
                    } else {
                        Text(pm.proProduct.map { "Proにアップグレード \($0.displayPrice)/月" }
                             ?? "Proにアップグレード")
                            .bold()
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .disabled(pm.isLoading)
        } footer: {
            Text("App Storeのサブスクリプション規約が適用されます。購入後はキャンセルするまで毎月自動更新されます。")
        }
    }

    private var restoreSection: some View {
        Section {
            Button("購入を復元") {
                Task { await pm.restore() }
            }
            .disabled(pm.isLoading)
        }
    }

    // MARK: - Actions

    private func doPurchase() async {
        do {
            try await pm.purchase()
        } catch StoreError.userCancelled {
            // no-op
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func configBinding<Value>(_ keyPath: WritableKeyPath<BookLayoutConfig, Value>) -> Binding<Value> {
        Binding(
            get: { store.bookLayoutConfig[keyPath: keyPath] },
            set: { store.setBookLayoutConfig(keyPath, to: $0) }
        )
    }

    private var photoLimitBinding: Binding<Int?> {
        Binding(
            get: {
                normalizedLimit(
                    store.bookLayoutConfig.maxPhotosPerEntry,
                    maxAllowed: store.currentPlan.maxPhotosInPrint
                )
            },
            set: { store.setBookLayoutConfig(\.maxPhotosPerEntry, to: $0) }
        )
    }

    private var videoLimitBinding: Binding<Int?> {
        Binding(
            get: {
                normalizedLimit(
                    store.bookLayoutConfig.maxVideosPerEntry,
                    maxAllowed: store.currentPlan.maxVideosInPrint
                )
            },
            set: { store.setBookLayoutConfig(\.maxVideosPerEntry, to: $0) }
        )
    }

    private func normalizedLimit(_ value: Int?, maxAllowed: Int) -> Int? {
        guard let value else { return nil }
        return max(0, min(value, maxAllowed))
    }
}
