// SettingsView.swift
// アプリ設定のルート画面。プラン・書籍化設定などへのナビゲーション起点。

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: DiaryStore

    var body: some View {
        NavigationStack {
            List {
                Section("サブスクリプション") {
                    NavigationLink(destination: PlanView()) {
                        HStack {
                            Label("プラン", systemImage: "crown")
                            Spacer()
                            Text(store.currentPlan.displayName)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .regularWidthContent(maxWidth: 860)
            .navigationTitle("設定")
        }
    }
}
