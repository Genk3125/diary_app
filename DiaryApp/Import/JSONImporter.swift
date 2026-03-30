// JSONImporter.swift
// Accepts JSON that is either:
//   1. A [DiaryEntry] array matching the internal model exactly
//   2. A DiaryEntry object
//   3. A generic [[String:Any]] / [String:Any] — mapped via best-effort key matching
// This makes it easy to ingest exports from other apps without a dedicated parser.

import Foundation

struct JSONImporter {

    static func importEntries(from url: URL) throws -> [DiaryEntry] {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ImportError.fileReadFailed(error.localizedDescription)
        }
        return try importEntries(from: data)
    }

    static func importEntries(from data: Data, source: ImportSource = .json) throws -> [DiaryEntry] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // 1. Try native [DiaryEntry]
        if let entries = try? decoder.decode([DiaryEntry].self, from: data) {
            return entries.map { tagged($0, source: source) }
        }

        // 2. Try native DiaryEntry
        if let entry = try? decoder.decode(DiaryEntry.self, from: data) {
            return [tagged(entry, source: source)]
        }

        // 3. Try generic JSON array
        if let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            let entries = jsonArray.compactMap { mapGeneric($0, source: source) }
            if !entries.isEmpty { return entries }
        }

        // 4. Try generic JSON object
        if let jsonDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let entry = mapGeneric(jsonDict, source: source) {
            return [entry]
        }

        throw ImportError.parsingFailed("JSON を DiaryEntry に変換できませんでした")
    }

    // MARK: - Private helpers

    private static func tagged(_ entry: DiaryEntry, source: ImportSource) -> DiaryEntry {
        var e = entry
        e.sourceApp = source.rawValue
        return e
    }

    /// Maps a generic JSON dictionary to DiaryEntry using common field name variants.
    private static func mapGeneric(_ dict: [String: Any], source: ImportSource) -> DiaryEntry? {
        let body  = dict["body"] as? String
            ?? dict["text"] as? String
            ?? dict["content"] as? String
            ?? dict["本文"] as? String
            ?? ""
        let title = dict["title"] as? String ?? dict["タイトル"] as? String ?? ""

        var date = Date()
        let dateStr = dict["date"] as? String
            ?? dict["created_at"] as? String
            ?? dict["timestamp"] as? String
            ?? dict["日付"] as? String
        if let ds = dateStr { date = parseDate(ds) ?? Date() }

        // Collect non-standard fields as metadata
        let knownKeys: Set<String> = [
            "id", "date", "title", "body", "text", "content",
            "created_at", "updated_at", "timestamp",
            "photos", "videos", "sourceApp", "metadata",
            "タイトル", "本文", "日付",
        ]
        var metadata: [String: String] = [:]
        for (k, v) in dict where !knownKeys.contains(k) {
            metadata[k] = "\(v)"
        }

        return DiaryEntry(
            id: UUID(),
            date: date,
            title: title,
            body: body,
            photos: [],
            videos: [],
            sourceApp: source.rawValue,
            metadata: metadata
        )
    }

    private static func parseDate(_ string: String) -> Date? {
        let formats = [
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd",
            "yyyy/MM/dd",
        ]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in formats {
            formatter.dateFormat = format
            if let d = formatter.date(from: string) { return d }
        }
        return nil
    }
}
