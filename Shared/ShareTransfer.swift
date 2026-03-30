// ShareTransfer.swift
// Shared App Group queue definitions used by both the app target and Share Extension.

import Foundation

enum ShareTransferConfig {
    static let appGroupID = "group.com.yourapp.diaryapp"
    static let queueFilename = "share_queue.json"
    static let stagedImageDirectoryName = "share_media"
    static let importURL = URL(string: "diarybook://import")!
}

enum ShareTransferError: LocalizedError {
    case unavailableAppGroup(String)
    case missingStagedImage(String)

    var errorDescription: String? {
        switch self {
        case .unavailableAppGroup(let groupID):
            return "App Group コンテナを開けませんでした: \(groupID)"
        case .missingStagedImage(let filename):
            return "共有画像が見つかりませんでした: \(filename)"
        }
    }
}

struct ShareItem: Identifiable, Codable {
    var id = UUID()

    enum Kind: String, Codable {
        case text
        case url
        case image
    }

    var kind: Kind
    var text: String?
    var imageFilename: String?

    init(
        id: UUID = UUID(),
        kind: Kind,
        text: String? = nil,
        imageFilename: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.imageFilename = imageFilename
    }
}

struct SharePayload: Identifiable, Codable {
    var id: UUID
    var items: [ShareItem]
    var date: Date

    init(id: UUID = UUID(), items: [ShareItem], date: Date = Date()) {
        self.id = id
        self.items = items
        self.date = date
    }
}

struct ShareQueueStore {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func append(_ payload: SharePayload) throws {
        try ensureDirectories()
        var queue = try loadQueue()
        queue.append(payload)
        try saveQueue(queue)
    }

    func loadQueue() throws -> [SharePayload] {
        let url = try queueFileURL()
        guard fileManager.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        return try Self.decoder.decode([SharePayload].self, from: data)
    }

    func clearQueue() throws {
        let url = try queueFileURL()
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    func writeStagedImageData(_ data: Data, preferredExtension: String? = nil) throws -> String {
        try ensureDirectories()
        let filename = "\(UUID().uuidString).\(normalizedImageExtension(preferredExtension))"
        let url = try stagedImageURL(named: filename)
        try data.write(to: url, options: .atomic)
        return filename
    }

    func copyImageToStaging(from sourceURL: URL, preferredExtension: String? = nil) throws -> String {
        try ensureDirectories()
        let fileExtension = preferredExtension ?? sourceURL.pathExtension
        let filename = "\(UUID().uuidString).\(normalizedImageExtension(fileExtension))"
        let destinationURL = try stagedImageURL(named: filename)
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
        return filename
    }

    func moveStagedImage(named filename: String, to destinationURL: URL) throws {
        let sourceURL = try stagedImageURL(named: filename)
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw ShareTransferError.missingStagedImage(filename)
        }
        try fileManager.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.moveItem(at: sourceURL, to: destinationURL)
    }

    func removeStagedImage(named filename: String) throws {
        let url = try stagedImageURL(named: filename)
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    private func saveQueue(_ queue: [SharePayload]) throws {
        let data = try Self.encoder.encode(queue)
        try data.write(to: queueFileURL(), options: .atomic)
    }

    private func ensureDirectories() throws {
        try fileManager.createDirectory(
            at: stagedImageDirectoryURL(),
            withIntermediateDirectories: true
        )
    }

    private func containerURL() throws -> URL {
        guard let url = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: ShareTransferConfig.appGroupID
        ) else {
            throw ShareTransferError.unavailableAppGroup(ShareTransferConfig.appGroupID)
        }
        return url
    }

    private func queueFileURL() throws -> URL {
        try containerURL().appendingPathComponent(ShareTransferConfig.queueFilename)
    }

    private func stagedImageDirectoryURL() throws -> URL {
        try containerURL().appendingPathComponent(
            ShareTransferConfig.stagedImageDirectoryName,
            isDirectory: true
        )
    }

    private func stagedImageURL(named filename: String) throws -> URL {
        try stagedImageDirectoryURL().appendingPathComponent(filename)
    }

    private func normalizedImageExtension(_ rawExtension: String?) -> String {
        let trimmed = (rawExtension ?? "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()
        return trimmed.isEmpty ? "jpg" : trimmed
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
