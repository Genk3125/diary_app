// DiaryApp.swift
// App entry point. DiaryStore is created once in ContentView via @StateObject
// and injected via environmentObject — no global singletons needed.

import SwiftUI

@main
struct DiaryApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
