// DiaryListView.swift
// Shows all entries sorted by date (newest first).
// Each row links to DiaryDetailView.
// Swipe-to-delete removes the entry and its associated media files.

import SwiftUI

struct DiaryListView: View {
    @EnvironmentObject var store: DiaryStore
    @State private var showingEditor = false

    private var sortedEntries: [DiaryEntry] {
        store.entries.sorted { $0.date > $1.date }
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.entries.isEmpty {
                    ContentUnavailableView(
                        "日記がありません",
                        systemImage: "book",
                        description: Text("＋ から新規作成、またはインポートタブで取り込んでください")
                    )
                } else {
                    List {
                        ForEach(sortedEntries) { entry in
                            NavigationLink(destination: DiaryDetailView(entryID: entry.id)) {
                                DiaryRowView(entry: entry)
                            }
                        }
                        .onDelete(perform: deleteEntries)
                    }
                }
            }
            .navigationTitle("日記")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showingEditor = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingEditor) {
                DiaryEditorView(existingEntry: nil)
                    .environmentObject(store)
            }
        }
    }

    private func deleteEntries(at offsets: IndexSet) {
        offsets.map { sortedEntries[$0] }.forEach { store.deleteEntry($0) }
    }
}

// MARK: - Row

struct DiaryRowView: View {
    let entry: DiaryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(entry.date, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                MediaBadgeView(photoCount: entry.photos.count, videoCount: entry.videos.count)
            }

            if !entry.title.isEmpty {
                Text(entry.title)
                    .font(.headline)
                    .lineLimit(1)
            }

            Text(entry.body.isEmpty ? "（本文なし）" : entry.body)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Media badge

struct MediaBadgeView: View {
    let photoCount: Int
    let videoCount: Int

    var body: some View {
        HStack(spacing: 6) {
            if photoCount > 0 {
                Label("\(photoCount)", systemImage: "photo")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if videoCount > 0 {
                Label("\(videoCount)", systemImage: "video")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
