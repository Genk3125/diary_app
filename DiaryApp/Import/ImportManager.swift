// ImportManager.swift
// Routes incoming files to the correct importer.
// Adding a new format = add a case here + a new XxxImporter.swift.
// TODO: Add share extension handler that calls importFile(at:) directly.

import Foundation
import UniformTypeIdentifiers

// MARK: - Import source identifiers

enum ImportSource: String {
    case json    = "json_import"
    case csv     = "csv_import"
    case zip     = "zip_import"
    case text    = "text_paste"
    case pdf     = "pdf_import"
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
}
