// DiaryStore.swift
// Single source of truth for all diary data.
// Persists entries as JSON and media files under the app's Documents directory.

import Foundation
import SwiftUI
import Combine

@MainActor
final class DiaryStore: ObservableObject {
    @Published var entries: [DiaryEntry] = []
    @Published private(set) var currentPlan: UserPlan = .free
    @Published var bookLayoutConfig: BookLayoutConfig = BookLayoutConfig()

    let purchaseManager = PurchaseManager()
    private var planCancellable: AnyCancellable?

    // MARK: - File paths

    private let documentsURL: URL
    private let entriesFileURL: URL
    let mediaDirectoryURL: URL
    private let configFileURL: URL

    // MARK: - Init

    init() {
        documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        entriesFileURL = documentsURL.appendingPathComponent("diary_entries.json")
        mediaDirectoryURL = documentsURL.appendingPathComponent("media", isDirectory: true)
        configFileURL = documentsURL.appendingPathComponent("book_config.json")

        setupDirectories()
        loadEntries()
        loadConfig()

        // PurchaseManager の isProActive が変わったら currentPlan を同期する
        planCancellable = purchaseManager.$isProActive
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isPro in
                self?.currentPlan = isPro ? .pro : .free
            }
    }

    private func setupDirectories() {
        try? FileManager.default.createDirectory(at: mediaDirectoryURL, withIntermediateDirectories: true)
    }

    // MARK: - CRUD

    func addEntry(_ entry: DiaryEntry) {
        entries.append(entry)
        saveEntries()
    }

    func updateEntry(_ entry: DiaryEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        var updated = entry
        updated.updatedAt = Date()
        entries[index] = updated
        saveEntries()
    }

    func deleteEntry(_ entry: DiaryEntry) {
        entry.photos.forEach { deleteMediaFile(named: $0.filename) }
        entry.videos.forEach {
            if let fn = $0.filename { deleteMediaFile(named: fn) }
            if let fn = $0.thumbnailFilename { deleteMediaFile(named: fn) }
        }
        entries.removeAll { $0.id == entry.id }
        saveEntries()
    }

    // MARK: - Import

    func importEntries(_ newEntries: [DiaryEntry]) {
        let existingIDs = Set(entries.map { $0.id })
        let toAdd = newEntries.filter { !existingIDs.contains($0.id) }
        entries.append(contentsOf: toAdd)
        saveEntries()
    }

    func importQueuedSharedEntriesIfNeeded() {
        let queueStore = ShareQueueStore()

        do {
            let payloads = try queueStore.loadQueue()
            guard !payloads.isEmpty else { return }

            let importedEntries = ImportManager.importSharePayloads(payloads) { [mediaDirectoryURL] stagedFilename, sortOrder in
                let fileExtension = URL(fileURLWithPath: stagedFilename).pathExtension
                let filename = [
                    UUID().uuidString,
                    fileExtension.isEmpty ? "jpg" : fileExtension
                ].joined(separator: ".")
                let destinationURL = mediaDirectoryURL.appendingPathComponent(filename)

                do {
                    try queueStore.moveStagedImage(named: stagedFilename, to: destinationURL)
                    return PhotoAttachment(filename: filename, sortOrder: sortOrder)
                } catch {
                    print("[DiaryStore] Shared image import failed: \(error)")
                    try? queueStore.removeStagedImage(named: stagedFilename)
                    return nil
                }
            }

            if !importedEntries.isEmpty {
                importEntries(importedEntries)
            }

            try queueStore.clearQueue()
        } catch {
            print("[DiaryStore] Shared queue import failed: \(error)")
        }
    }

    // MARK: - Media: Photos

    func saveImageData(_ data: Data, filename: String) {
        let url = mediaDirectoryURL.appendingPathComponent(filename)
        try? data.write(to: url, options: .atomic)
    }

    func loadImageData(filename: String) -> Data? {
        let url = mediaDirectoryURL.appendingPathComponent(filename)
        return try? Data(contentsOf: url)
    }

    // MARK: - Media: Videos

    func saveVideoFile(from sourceURL: URL) -> String? {
        let filename = "\(UUID().uuidString).mov"
        let destURL = mediaDirectoryURL.appendingPathComponent(filename)
        do {
            try FileManager.default.copyItem(at: sourceURL, to: destURL)
            return filename
        } catch {
            print("[DiaryStore] Video save failed: \(error)")
            return nil
        }
    }

    func videoFileURL(filename: String) -> URL {
        return mediaDirectoryURL.appendingPathComponent(filename)
    }

    private func deleteMediaFile(named filename: String) {
        let url = mediaDirectoryURL.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Plan helpers

    func effectiveMaxPhotos() -> Int { currentPlan.maxPhotosPerEntry }
    func effectiveMaxVideos() -> Int { currentPlan.maxVideosPerEntry }

    func effectiveBookMaxPhotos() -> Int {
        let configured = bookLayoutConfig.maxPhotosPerEntry ?? currentPlan.maxPhotosInPrint
        return max(0, min(configured, currentPlan.maxPhotosInPrint))
    }

    func effectiveBookMaxVideos() -> Int {
        let configured = bookLayoutConfig.maxVideosPerEntry ?? currentPlan.maxVideosInPrint
        return max(0, min(configured, currentPlan.maxVideosInPrint))
    }

    func setBookLayoutConfig<Value>(_ keyPath: WritableKeyPath<BookLayoutConfig, Value>, to value: Value) {
        bookLayoutConfig[keyPath: keyPath] = value
        saveConfig()
    }

    // MARK: - Persistence: Entries

    private func loadEntries() {
        guard FileManager.default.fileExists(atPath: entriesFileURL.path) else { return }
        do {
            let data = try Data(contentsOf: entriesFileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            entries = try decoder.decode([DiaryEntry].self, from: data)
        } catch {
            print("[DiaryStore] Load entries failed: \(error)")
        }
    }

    private func saveEntries() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(entries)
            try data.write(to: entriesFileURL, options: .atomic)
        } catch {
            print("[DiaryStore] Save entries failed: \(error)")
        }
    }

    // MARK: - Persistence: Config

    private func loadConfig() {
        guard FileManager.default.fileExists(atPath: configFileURL.path) else { return }
        do {
            let data = try Data(contentsOf: configFileURL)
            bookLayoutConfig = try JSONDecoder().decode(BookLayoutConfig.self, from: data)
        } catch {
            print("[DiaryStore] Load config failed: \(error)")
        }
    }

    func saveConfig() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(bookLayoutConfig)
            try data.write(to: configFileURL, options: .atomic)
        } catch {
            print("[DiaryStore] Save config failed: \(error)")
        }
    }
}
