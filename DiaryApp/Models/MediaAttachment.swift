// MediaAttachment.swift
// Photo and video attachment models.
// Files are stored locally by filename under DiaryStore's media directory.
// Cloud hosting is a future extension point via hostedAssetID / remoteURL.

import Foundation

struct PhotoAttachment: Codable, Identifiable, Equatable {
    var id: UUID
    /// Filename relative to DiaryStore's media directory (e.g. "abc123.jpg")
    var filename: String
    var caption: String
    var sortOrder: Int

    init(id: UUID = UUID(), filename: String, caption: String = "", sortOrder: Int = 0) {
        self.id = id
        self.filename = filename
        self.caption = caption
        self.sortOrder = sortOrder
    }
}

struct VideoAttachment: Codable, Identifiable, Equatable {
    var id: UUID
    /// Local filename relative to DiaryStore's media directory. nil until uploaded to cloud.
    var filename: String?
    /// Future: cloud asset ID after upload
    var hostedAssetID: String?
    /// Future: hosted URL used for QR code generation
    var remoteURL: String?
    var caption: String
    var sortOrder: Int
    /// Thumbnail filename relative to media directory
    var thumbnailFilename: String?

    init(
        id: UUID = UUID(),
        filename: String? = nil,
        hostedAssetID: String? = nil,
        remoteURL: String? = nil,
        caption: String = "",
        sortOrder: Int = 0,
        thumbnailFilename: String? = nil
    ) {
        self.id = id
        self.filename = filename
        self.hostedAssetID = hostedAssetID
        self.remoteURL = remoteURL
        self.caption = caption
        self.sortOrder = sortOrder
        self.thumbnailFilename = thumbnailFilename
    }

    /// The URL target to encode as QR code in printed book.
    /// TODO: Replace placeholder URL with real CDN URL after cloud upload.
    var qrCodeTarget: String? {
        if let url = remoteURL { return url }
        if let assetID = hostedAssetID { return "https://diary.app/v/\(assetID)" }
        return nil
    }
}
