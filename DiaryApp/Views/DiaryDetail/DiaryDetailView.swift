// DiaryDetailView.swift
// Full-content view for a single diary entry.
// Accepts an entry id and resolves live data from the store,
// so edits made in DiaryEditorView are reflected immediately on dismiss.

import SwiftUI
import AVKit

struct DiaryDetailView: View {
    @EnvironmentObject var store: DiaryStore
    let entryID: UUID

    @State private var showingEditor = false
    @State private var showingDeleteAlert = false
    @State private var playingVideoItem: IdentifiableURL?
    @Environment(\.dismiss) private var dismiss

    private var entry: DiaryEntry? {
        store.entries.first { $0.id == entryID }
    }

    var body: some View {
        Group {
            if let entry {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        headerSection(entry)
                        Divider()
                        bodySection(entry)
                        if !entry.photos.isEmpty { PhotosGridView(photos: entry.photos) }
                        if !entry.videos.isEmpty {
                            VideosListView(videos: entry.videos) { url in
                                playingVideoItem = IdentifiableURL(url: url)
                            }
                        }
                        if entry.sourceApp != "manual" || !entry.metadata.isEmpty {
                            MetadataView(entry: entry)
                        }
                    }
                    .regularWidthContent(maxWidth: 860)
                    .padding()
                }
                .navigationTitle(entry.title.isEmpty ? "日記" : entry.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { detailToolbar(entry) }
                .sheet(isPresented: $showingEditor) {
                    DiaryEditorView(existingEntry: entry)
                        .environmentObject(store)
                        .presentationDetents([.large])
                        .presentationDragIndicator(.visible)
                }
                .sheet(item: $playingVideoItem) { item in
                    VideoPlayerSheet(url: item.url)
                        .presentationDetents([.large])
                        .presentationDragIndicator(.visible)
                }
                .alert("この日記を削除しますか？", isPresented: $showingDeleteAlert) {
                    Button("削除", role: .destructive) {
                        store.deleteEntry(entry)
                        dismiss()
                    }
                    Button("キャンセル", role: .cancel) {}
                }
            } else {
                ContentUnavailableView("見つかりません", systemImage: "questionmark")
            }
        }
    }

    // MARK: - Sub-sections

    @ViewBuilder
    private func headerSection(_ entry: DiaryEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.date, style: .date)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if !entry.title.isEmpty {
                Text(entry.title)
                    .font(.title2.bold())
            }
        }
    }

    @ViewBuilder
    private func bodySection(_ entry: DiaryEntry) -> some View {
        Text(entry.body.isEmpty ? "（本文なし）" : entry.body)
            .font(.body)
            .textSelection(.enabled)
    }

    @ToolbarContentBuilder
    private func detailToolbar(_ entry: DiaryEntry) -> some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Menu {
                Button("編集", systemImage: "pencil") { showingEditor = true }
                Divider()
                Button("削除", systemImage: "trash", role: .destructive) {
                    showingDeleteAlert = true
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }
}

// MARK: - Photos grid

struct PhotosGridView: View {
    @EnvironmentObject var store: DiaryStore
    let photos: [PhotoAttachment]

    private let columns = [GridItem(.adaptive(minimum: 96))]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("写真 \(photos.count)枚", systemImage: "photo")
                .font(.headline)

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(photos) { photo in
                    Group {
                        if let data = store.loadImageData(filename: photo.filename),
                           let uiImage = UIImage(data: data) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFill()
                        } else {
                            Color.secondary.opacity(0.2)
                                .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
                        }
                    }
                    .frame(width: 96, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }
}

// MARK: - Videos list

struct VideosListView: View {
    @EnvironmentObject var store: DiaryStore
    let videos: [VideoAttachment]
    let onPlay: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("動画 \(videos.count)本", systemImage: "video")
                .font(.headline)

            ForEach(videos) { video in
                let localURL: URL? = video.filename.map { store.videoFileURL(filename: $0) }
                HStack(spacing: 12) {
                    if let url = localURL {
                        // ローカルファイルあり → 再生ボタン
                        Button { onPlay(url) } label: {
                            ZStack {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.accentColor.opacity(0.15))
                                    .frame(width: 44, height: 44)
                                Image(systemName: "play.fill")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        .buttonStyle(.plain)
                    } else if let target = video.qrCodeTarget {
                        // remoteURL / hostedAssetID あり → 実際の QR コードを表示
                        QRCodeView(content: target, size: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    } else {
                        // QR ターゲット未設定 → プレースホルダー
                        ZStack {
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(style: StrokeStyle(lineWidth: 1, dash: [4]))
                                .foregroundStyle(.secondary)
                                .frame(width: 44, height: 44)
                            Image(systemName: "qrcode")
                                .foregroundStyle(.secondary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(video.caption.isEmpty ? "動画" : video.caption)
                            .font(.subheadline)
                        Text(localURL != nil ? "タップして再生" :
                             video.qrCodeTarget != nil ? "QRコード（印刷時に掲載）" :
                             "印刷時はQRコードとして掲載されます")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(8)
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}

// MARK: - Video player sheet

private struct IdentifiableURL: Identifiable {
    let url: URL
    var id: URL { url }
}

struct VideoPlayerSheet: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VideoPlayer(player: AVPlayer(url: url))
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("動画再生")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("閉じる") { dismiss() }
                    }
                }
        }
    }
}

// MARK: - Metadata footer

struct MetadataView: View {
    let entry: DiaryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            Text("取込情報")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            infoRow(label: "ソース", value: entry.sourceApp)
            ForEach(entry.metadata.sorted(by: { $0.key < $1.key }), id: \.key) { kv in
                infoRow(label: kv.key, value: kv.value)
            }
        }
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 4) {
            Text("\(label):")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize()
            Text(value)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
