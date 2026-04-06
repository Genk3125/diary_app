// ContentView.swift
// Root tab container. Injects DiaryStore into the environment once here;
// all child views receive it via @EnvironmentObject.

import SwiftUI

struct ContentView: View {
    private enum Tab {
        case diary
        case `import`
        case book
        case settings
    }

    @StateObject private var store = DiaryStore()
    @State private var selectedTab: Tab = .diary

    var body: some View {
        TabView(selection: $selectedTab) {
            DiaryListView()
                .tag(Tab.diary)
                .tabItem { Label("日記", systemImage: "book.fill") }

            ImportView()
                .tag(Tab.import)
                .tabItem { Label("インポート", systemImage: "square.and.arrow.down") }

            BookPreviewView()
                .tag(Tab.book)
                .tabItem { Label("書籍化", systemImage: "book.closed.fill") }

            SettingsView()
                .tag(Tab.settings)
                .tabItem { Label("設定", systemImage: "gearshape") }
        }
        .tabViewStyle(.automatic)
        .environmentObject(store)
        .task {
            store.importQueuedSharedEntriesIfNeeded()
        }
        .onOpenURL { url in
            guard isShareImportURL(url) else { return }
            selectedTab = .diary
            store.importQueuedSharedEntriesIfNeeded()
        }
    }

    private func isShareImportURL(_ url: URL) -> Bool {
        guard url.scheme == ShareTransferConfig.urlScheme else { return false }
        return url.host == "import" || url.path == "/import"
    }
}
