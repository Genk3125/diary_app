// DiaryEntry.swift
// Core data model for a single diary entry.
// All import sources and manual entries are normalized into this struct.

import Foundation

struct DiaryEntry: Codable, Identifiable, Equatable {
    var id: UUID
    var date: Date
    var title: String
    var body: String
    var photos: [PhotoAttachment]
    var videos: [VideoAttachment]

    /// Source identifier: "manual", "json_import", "csv_import", "zip_import", "text_paste", "pdf_import"
    var sourceApp: String

    /// Flexible key-value store for source-specific metadata (e.g. original app fields)
    var metadata: [String: String]

    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        title: String = "",
        body: String = "",
        photos: [PhotoAttachment] = [],
        videos: [VideoAttachment] = [],
        sourceApp: String = "manual",
        metadata: [String: String] = [:],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.date = date
        self.title = title
        self.body = body
        self.photos = photos
        self.videos = videos
        self.sourceApp = sourceApp
        self.metadata = metadata
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
