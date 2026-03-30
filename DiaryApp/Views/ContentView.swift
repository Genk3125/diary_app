// ContentView.swift
// Root tab container. Injects DiaryStore into the environment once here;
// all child views receive it via @EnvironmentObject.

import SwiftUI

struct ContentView: View {
    @StateObject private var store = DiaryStore()

    var body: some View {
        TabView {
            DiaryListView()
                .tabItem { Label("日記", systemImage: "book.fill") }

            ImportView()
                .tabItem { Label("インポート", systemImage: "square.and.arrow.down") }

            BookPreviewView()
                .tabItem { Label("書籍化", systemImage: "book.closed.fill") }

            PlanView()
                .tabItem { Label("プラン", systemImage: "crown") }
        }
        .environmentObject(store)
    }
}
