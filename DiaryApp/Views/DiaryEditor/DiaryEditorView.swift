// DiaryEditorView.swift
// Handles both creation (existingEntry == nil) and editing.
// Plan limits are enforced before media is accepted.
// TODO: Wire up real StoreKit subscription gate instead of plan mock.

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

// MARK: - Video Transferable wrapper

/// Bridges PhotosPicker video items to a local file URL.
struct VideoFile: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString + ".mov")
            try FileManager.default.copyItem(at: received.file, to: dest)
            return VideoFile(url: dest)
        }
    }
}

// MARK: - Editor View

struct DiaryEditorView: View {
    @EnvironmentObject var store: DiaryStore
    @Environment(\.dismiss) private var dismiss

    let existingEntry: DiaryEntry?

    @State private var date: Date
    @State private var title: String
    @State private var bodyText: String
    @State private var photos: [PhotoAttachment]
    @State private var videos: [VideoAttachment]

    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var selectedVideoItems: [PhotosPickerItem] = []
    @State private var isLoadingMedia = false
    @State private var photoLimitAlert = false
    @State private var videoLimitAlert = false

    init(existingEntry: DiaryEntry?) {
        self.existingEntry = existingEntry
        _date   = State(initialValue: existingEntry?.date   ?? Date())
        _title  = State(initialValue: existingEntry?.title  ?? "")
        _bodyText = State(initialValue: existingEntry?.body   ?? "")
        _photos = State(initialValue: existingEntry?.photos ?? [])
        _videos = State(initialValue: existingEntry?.videos ?? [])
    }

    private var maxPhotos: Int { store.effectiveMaxPhotos() }
    private var maxVideos: Int { store.effectiveMaxVideos() }

    var body: some View {
        NavigationStack {
            Form {
                basicInfoSection
                bodySection
                photosSection
                videosSection
                planSection
            }
            .navigationTitle(existingEntry == nil ? "新しい日記" : "日記を編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .fontWeight(.semibold)
                        .disabled(bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && title.isEmpty)
                }
            }
            .onChange(of: selectedPhotoItems) { _, items in
                guard !items.isEmpty else { return }
                Task { await loadPhotos(items) }
            }
            .onChange(of: selectedVideoItems) { _, items in
                guard !items.isEmpty else { return }
                Task { await loadVideos(items) }
            }
            .alert("写真の上限です", isPresented: $photoLimitAlert) {
                Button("OK") {}
            } message: {
                Text("現在の\(store.currentPlan.displayName)プランでは写真を\(maxPhotos)枚まで添付できます。")
            }
            .alert("動画の上限です", isPresented: $videoLimitAlert) {
                Button("OK") {}
            } message: {
                Text("現在の\(store.currentPlan.displayName)プランでは動画を\(maxVideos)本まで添付できます。")
            }
            .overlay {
                if isLoadingMedia {
                    ZStack {
                        Color.black.opacity(0.3).ignoresSafeArea()
                        ProgressView("メディアを読み込み中...")
                            .padding(20)
                            .background(.ultraThickMaterial)
                            .cornerRadius(12)
                    }
                }
            }
        }
    }

    // MARK: - Form sections

    private var basicInfoSection: some View {
        Section("基本情報") {
            DatePicker("日付", selection: $date, displayedComponents: .date)
            TextField("タイトル（任意）", text: $title)
        }
    }

    private var bodySection: some View {
        Section("本文") {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $bodyText)
                    .frame(minHeight: 160)
                if bodyText.isEmpty {
                    Text("今日の出来事を書きましょう…")
                        .foregroundStyle(.tertiary)
                        .padding(.top, 8)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    private var photosSection: some View {
        Section {
            ForEach(photos) { photo in
                PhotoEditorRow(photo: photo, store: store)
            }
            .onDelete { offsets in photos.remove(atOffsets: offsets) }
            .onMove  { from, to  in photos.move(fromOffsets: from, toOffset: to) }

            if photos.count < maxPhotos {
                PhotosPicker(
                    selection: $selectedPhotoItems,
                    maxSelectionCount: maxPhotos - photos.count,
                    matching: .images
                ) {
                    Label("写真を追加", systemImage: "plus.circle")
                }
            } else {
                Label("上限に達しました（\(maxPhotos)枚）", systemImage: "lock")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }
        } header: {
            Text("写真  \(photos.count) / \(maxPhotos)")
        }
    }

    private var videosSection: some View {
        Section {
            ForEach(videos) { video in
                VideoEditorRow(video: video)
            }
            .onDelete { offsets in videos.remove(atOffsets: offsets) }

            if videos.count < maxVideos {
                PhotosPicker(
                    selection: $selectedVideoItems,
                    maxSelectionCount: maxVideos - videos.count,
                    matching: .videos
                ) {
                    Label("動画を追加", systemImage: "plus.circle")
                }
            } else {
                Label("上限に達しました（\(maxVideos)本）", systemImage: "lock")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }
        } header: {
            Text("動画  \(videos.count) / \(maxVideos)")
        } footer: {
            Text("動画は印刷時にQRコードとして掲載されます")
        }
    }

    private var planSection: some View {
        Section {
            HStack {
                Text("現在のプラン")
                Spacer()
                Text(store.currentPlan.displayName)
                    .foregroundStyle(.secondary)
            }
            // TODO: Button("プランをアップグレード") { showPaywall() }
        }
    }

    // MARK: - Save

    private func save() {
        if var existing = existingEntry {
            existing.date   = date
            existing.title  = title
            existing.body   = bodyText
            existing.photos = photos
            existing.videos = videos
            store.updateEntry(existing)
        } else {
            store.addEntry(DiaryEntry(
                date: date,
                title: title,
                body: bodyText,
                photos: photos,
                videos: videos,
                sourceApp: "manual"
            ))
        }
        dismiss()
    }

    // MARK: - Media loading

    @MainActor
    private func loadPhotos(_ items: [PhotosPickerItem]) async {
        isLoadingMedia = true
        defer { isLoadingMedia = false; selectedPhotoItems = [] }

        for item in items {
            guard photos.count < maxPhotos else { photoLimitAlert = true; break }
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            let filename = "\(UUID().uuidString).jpg"
            store.saveImageData(data, filename: filename)
            photos.append(PhotoAttachment(filename: filename, sortOrder: photos.count))
        }
    }

    @MainActor
    private func loadVideos(_ items: [PhotosPickerItem]) async {
        isLoadingMedia = true
        defer { isLoadingMedia = false; selectedVideoItems = [] }

        for item in items {
            guard videos.count < maxVideos else { videoLimitAlert = true; break }
            guard let video = try? await item.loadTransferable(type: VideoFile.self) else { continue }
            if let filename = store.saveVideoFile(from: video.url) {
                videos.append(VideoAttachment(filename: filename, sortOrder: videos.count))
            }
            // Cleanup temp file
            try? FileManager.default.removeItem(at: video.url)
        }
    }
}

// MARK: - Row sub-views

private struct PhotoEditorRow: View {
    let photo: PhotoAttachment
    let store: DiaryStore

    var body: some View {
        HStack(spacing: 12) {
            if let data = store.loadImageData(filename: photo.filename),
               let ui = UIImage(data: data) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: 48, height: 48)
                    .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
            }
            Text(photo.caption.isEmpty ? "写真" : photo.caption)
                .font(.subheadline)
        }
    }
}

private struct VideoEditorRow: View {
    let video: VideoAttachment

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.secondary.opacity(0.2))
                .frame(width: 48, height: 48)
                .overlay(Image(systemName: "video.fill").foregroundStyle(.secondary))
            VStack(alignment: .leading, spacing: 2) {
                Text(video.caption.isEmpty ? "動画" : video.caption)
                    .font(.subheadline)
                Text("印刷時はQRコードになります")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
