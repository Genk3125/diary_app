// ImportManager.swift
// Routes incoming files to the correct importer.
// Adding a new format = add a case here + a new XxxImporter.swift.

import Foundation
import UniformTypeIdentifiers

// MARK: - Import source identifiers

enum ImportSource: String {
    case json    = "json_import"
    case csv     = "csv_import"
    case zip     = "zip_import"
    case text    = "text_paste"
    case pdf     = "pdf_import"
    case share   = "share_extension"
}

// MARK: - Errors

enum ImportError: LocalizedError {
    case invalidFormat(String)
    case unsupportedType(String)
    case parsingFailed(String)
    case fileReadFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidFormat(let m):   return "フォーマットエラー: \(m)"
        case .unsupportedType(let m): return "未対応のファイル形式: \(m)"
        case .parsingFailed(let m):   return "パース失敗: \(m)"
        case .fileReadFailed(let m):  return "ファイル読み込み失敗: \(m)"
        }
    }
}

// MARK: - Manager

struct ImportManager {
    /// Route a file URL to the appropriate importer.
    static func importFile(at url: URL) throws -> [DiaryEntry] {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "json":
            return try JSONImporter.importEntries(from: url)
        case "csv":
            return try CSVImporter.importEntries(from: url)
        case "zip":
            return try ZIPImporter.importEntries(from: url)
        case "pdf":
            return try PDFImporter.importEntries(from: url)
        default:
            throw ImportError.unsupportedType(".\(ext)")
        }
    }

    /// Parse pasted plain text into one or more entries.
    static func importText(_ text: String) throws -> [DiaryEntry] {
        return try TextImporter.importEntries(from: text)
    }

    /// Convert queued share payloads into DiaryEntry values.
    static func importSharePayloads(
        _ payloads: [SharePayload],
        imageImporter: (_ stagedFilename: String, _ sortOrder: Int) -> PhotoAttachment?
    ) -> [DiaryEntry] {
        payloads.compactMap { payload in
            importSharePayload(payload, imageImporter: imageImporter)
        }
    }

    private static func importSharePayload(
        _ payload: SharePayload,
        imageImporter: (_ stagedFilename: String, _ sortOrder: Int) -> PhotoAttachment?
    ) -> DiaryEntry? {
        var bodyParts: [String] = []
        var photos: [PhotoAttachment] = []
        var kinds: Set<String> = []
        var textCount = 0
        var urlCount = 0

        for item in payload.items {
            kinds.insert(item.kind.rawValue)

            switch item.kind {
            case .text:
                guard let text = trimmed(item.text), !text.isEmpty else { continue }
                bodyParts.append(text)
                textCount += 1

            case .url:
                guard let urlString = trimmed(item.text), !urlString.isEmpty else { continue }
                bodyParts.append(urlString)
                urlCount += 1

            case .image:
                guard let stagedFilename = item.imageFilename else { continue }
                let sortOrder = photos.count
                if let photo = imageImporter(stagedFilename, sortOrder) {
                    photos.append(photo)
                }
            }
        }

        let body = bodyParts
            .joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !body.isEmpty || !photos.isEmpty else { return nil }

        var metadata: [String: String] = [
            "sharedPayloadID": payload.id.uuidString
        ]
        if !kinds.isEmpty {
            metadata["sharedItemKinds"] = kinds.sorted().joined(separator: ",")
        }
        if textCount > 0 {
            metadata["sharedTextCount"] = String(textCount)
        }
        if urlCount > 0 {
            metadata["sharedURLCount"] = String(urlCount)
        }
        if !photos.isEmpty {
            metadata["sharedImageCount"] = String(photos.count)
        }

        return DiaryEntry(
            id: UUID(),
            date: payload.date,
            title: titleForSharedEntry(body: body, photoCount: photos.count),
            body: body,
            photos: photos,
            videos: [],
            sourceApp: ImportSource.share.rawValue,
            metadata: metadata
        )
    }

    private static func titleForSharedEntry(body: String, photoCount: Int) -> String {
        let firstLine = body
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })

        if let firstLine, !firstLine.isEmpty {
            return firstLine.count > 60 ? String(firstLine.prefix(60)) + "…" : firstLine
        }

        return photoCount == 1 ? "共有された画像" : "共有された画像 \(photoCount)枚"
    }

    private static func trimmed(_ text: String?) -> String? {
        text?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
