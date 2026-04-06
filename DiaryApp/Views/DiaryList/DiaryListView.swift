// DiaryListView.swift
// Shows all entries sorted by date (newest first).
// Each row links to DiaryDetailView.
// Swipe-to-delete removes the entry and its associated media files.

import SwiftUI

struct DiaryListView: View {
    @EnvironmentObject var store: DiaryStore
    @State private var showingEditor = false
    @State private var searchText = ""
    @State private var selectedSourceApp: String?
    @State private var sortOrder: DiaryListSortOrder = .newestFirst
    @State private var attachmentsOnly = false

    private var sourceOptions: [String] {
        Array(
            Set(
                store.entries
                    .map(\.sourceApp)
                    .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            )
        )
            .sorted { DiarySourcePresentation.label(for: $0) < DiarySourcePresentation.label(for: $1) }
    }

    private var searchTokens: [String] {
        searchText
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .map(DiarySearchNormalizer.normalize)
    }

    private var filteredAndSortedEntries: [DiaryEntry] {
        let tokens = searchTokens

        return store.entries
            .filter { entry in
                tokens.isEmpty || entry.matchesSearchTokens(tokens)
            }
            .filter { entry in
                selectedSourceApp == nil || entry.sourceApp == selectedSourceApp
            }
            .filter { entry in
                !attachmentsOnly || entry.hasAttachments
            }
            .sorted(by: sortOrder.comparator)
    }

    private var hasActiveFilters: Bool {
        selectedSourceApp != nil || attachmentsOnly
    }

    private var hasCustomPresentation: Bool {
        hasActiveFilters || sortOrder != .newestFirst
    }

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var resultSummaryText: String {
        var parts: [String] = []

        if !trimmedSearchText.isEmpty {
            parts.append("検索: 「\(trimmedSearchText)」")
        }
        if let selectedSourceApp {
            parts.append("ソース: \(DiarySourcePresentation.label(for: selectedSourceApp))")
        }
        if attachmentsOnly {
            parts.append("添付ありのみ")
        }
        if sortOrder != .newestFirst {
            parts.append("並び順: \(sortOrder.title)")
        }

        return parts.joined(separator: " / ")
    }

    private var noResultsDescription: String {
        if !trimmedSearchText.isEmpty && hasActiveFilters {
            return "検索語または絞り込み条件を変更して、もう一度お試しください"
        }
        if !trimmedSearchText.isEmpty {
            return "検索語を変更して、もう一度お試しください"
        }
        if hasActiveFilters {
            return "絞り込み条件を変更して、もう一度お試しください"
        }
        return "条件に一致する日記がありません。もう一度お試しください"
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
                } else if filteredAndSortedEntries.isEmpty {
                    ContentUnavailableView {
                        Label("該当する日記がありません", systemImage: "magnifyingglass")
                    } description: {
                        Text(noResultsDescription)
                    } actions: {
                        if !trimmedSearchText.isEmpty || hasCustomPresentation {
                            Button("検索・絞り込みをリセット") {
                                resetSearchAndFilters()
                            }
                        }
                    }
                } else {
                    List {
                        Section {
                            ForEach(filteredAndSortedEntries) { entry in
                                NavigationLink(destination: DiaryDetailView(entryID: entry.id)) {
                                    DiaryRowView(entry: entry)
                                }
                            }
                            .onDelete(perform: deleteEntries)
                        } header: {
                            if !resultSummaryText.isEmpty {
                                Text(resultSummaryText)
                            }
                        }
                    }
                }
            }
            .regularWidthContent(maxWidth: 860)
            .navigationTitle("日記")
            .searchable(text: $searchText, prompt: "タイトル・本文・ソースで検索")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if !store.entries.isEmpty {
                        filterMenu
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showingEditor = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingEditor) {
                DiaryEditorView(existingEntry: nil)
                    .environmentObject(store)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    private func deleteEntries(at offsets: IndexSet) {
        offsets.map { filteredAndSortedEntries[$0] }.forEach { store.deleteEntry($0) }
    }

    private func resetSearchAndFilters() {
        searchText = ""
        selectedSourceApp = nil
        sortOrder = .newestFirst
        attachmentsOnly = false
    }

    private var filterMenu: some View {
        Menu {
            Section("並び順") {
                Button {
                    sortOrder = .newestFirst
                } label: {
                    menuSelectionLabel("新しい順", isSelected: sortOrder == .newestFirst)
                }

                Button {
                    sortOrder = .oldestFirst
                } label: {
                    menuSelectionLabel("古い順", isSelected: sortOrder == .oldestFirst)
                }
            }

            Section("ソース") {
                Button {
                    selectedSourceApp = nil
                } label: {
                    menuSelectionLabel("すべて", isSelected: selectedSourceApp == nil)
                }

                ForEach(sourceOptions, id: \.self) { sourceApp in
                    Button {
                        selectedSourceApp = sourceApp
                    } label: {
                        menuSelectionLabel(
                            DiarySourcePresentation.label(for: sourceApp),
                            isSelected: selectedSourceApp == sourceApp
                        )
                    }
                }
            }

            Section("添付") {
                Button {
                    attachmentsOnly.toggle()
                } label: {
                    menuSelectionLabel("添付ありのみ", isSelected: attachmentsOnly)
                }
            }

            if hasCustomPresentation {
                Section {
                    Button("絞り込みをリセット") {
                        resetSearchAndFilters()
                    }
                }
            }
        } label: {
            Image(systemName: hasCustomPresentation ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
        .accessibilityLabel("並び替えと絞り込み")
    }

    @ViewBuilder
    private func menuSelectionLabel(_ title: String, isSelected: Bool) -> some View {
        if isSelected {
            Label(title, systemImage: "checkmark")
        } else {
            Text(title)
        }
    }
}

// MARK: - Row

struct DiaryRowView: View {
    let entry: DiaryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                HStack(spacing: 6) {
                    Text(entry.date.formatted(date: .long, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(entry.sourceDisplayName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12))
                        .clipShape(Capsule())
                }
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

// MARK: - List helpers

private enum DiaryListSortOrder: String {
    case newestFirst
    case oldestFirst

    var title: String {
        switch self {
        case .newestFirst:
            return "新しい順"
        case .oldestFirst:
            return "古い順"
        }
    }

    var comparator: (DiaryEntry, DiaryEntry) -> Bool {
        switch self {
        case .newestFirst:
            return { $0.date > $1.date }
        case .oldestFirst:
            return { $0.date < $1.date }
        }
    }
}

private enum DiarySourcePresentation {
    static func label(for sourceApp: String) -> String {
        switch sourceApp {
        case "manual":
            return "手動入力"
        case "json_import":
            return "JSON取込"
        case "csv_import":
            return "CSV取込"
        case "zip_import":
            return "ZIP取込"
        case "text_paste":
            return "テキスト取込"
        case "pdf_import":
            return "PDF取込"
        case "share_extension":
            return "共有シート"
        default:
            return sourceApp
        }
    }
}

private enum DiarySearchNormalizer {
    static func normalize(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension DiaryEntry {
    var hasAttachments: Bool {
        !photos.isEmpty || !videos.isEmpty
    }

    var sourceDisplayName: String {
        DiarySourcePresentation.label(for: sourceApp)
    }

    func matchesSearchTokens(_ tokens: [String]) -> Bool {
        let searchIndex = searchableText
        return tokens.allSatisfy { searchIndex.contains($0) }
    }

    private var searchableText: String {
        [title, body, sourceApp, sourceDisplayName]
        .map(DiarySearchNormalizer.normalize)
        .joined(separator: "\n")
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
