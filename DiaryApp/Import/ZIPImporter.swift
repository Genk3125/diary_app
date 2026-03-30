// ZIPImporter.swift
// ZIP を展開して内部の JSON/CSV を再帰的にインポートする。
// ZipFoundation (SPM) が必要 — project.yml で有効化済み。

import Foundation
import ZIPFoundation

struct ZIPImporter {

    static func importEntries(from url: URL) throws -> [DiaryEntry] {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try FileManager.default.unzipItem(at: url, to: tempDir)
        return try scanDirectory(tempDir)
    }

    // MARK: - Directory scanner

    static func scanDirectory(_ directory: URL) throws -> [DiaryEntry] {
        var entries: [DiaryEntry] = []
        let fm = FileManager.default

        guard let contents = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        ) else { return entries }

        for fileURL in contents {
            let isDir = (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDir {
                entries += (try? scanDirectory(fileURL)) ?? []
                continue
            }
            switch fileURL.pathExtension.lowercased() {
            case "json":
                entries += (try? JSONImporter.importEntries(from: fileURL)) ?? []
            case "csv":
                entries += (try? CSVImporter.importEntries(from: fileURL)) ?? []
            default:
                break
            }
        }
        return entries
    }
}
