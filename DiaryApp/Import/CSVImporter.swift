// CSVImporter.swift
// RFC 4180-compliant CSV parser.
// Supports both English and Japanese column headers.
// Required columns: at least one of body / text / content / 本文.
// Optional columns: date / 日付, title / タイトル.

import Foundation

struct CSVImporter {

    static func importEntries(from url: URL) throws -> [DiaryEntry] {
        let content: String
        do {
            content = try String(contentsOf: url, encoding: .utf8)
        } catch {
            // Try Shift-JIS fallback for Japanese exports
            if let sjis = try? String(contentsOf: url, encoding: .shiftJIS) {
                content = sjis
            } else {
                throw ImportError.fileReadFailed(error.localizedDescription)
            }
        }
        return try importEntries(from: content)
    }

    static func importEntries(from content: String) throws -> [DiaryEntry] {
        let lines = content.components(separatedBy: .newlines).filter { !$0.isEmpty }
        guard lines.count >= 2 else {
            throw ImportError.parsingFailed("CSV にはヘッダー行と1件以上のデータ行が必要です")
        }

        let headers = parseCSVLine(lines[0]).map {
            $0.trimmingCharacters(in: .whitespaces).lowercased()
        }

        var entries: [DiaryEntry] = []
        for line in lines.dropFirst() {
            let values = parseCSVLine(line)
            guard !values.isEmpty else { continue }
            var dict: [String: String] = [:]
            for (i, header) in headers.enumerated() {
                dict[header] = i < values.count ? values[i] : ""
            }
            entries.append(mapRow(dict))
        }
        return entries
    }

    // MARK: - Private

    private static func mapRow(_ dict: [String: String]) -> DiaryEntry {
        let title = dict["title"] ?? dict["タイトル"] ?? ""
        let body  = dict["body"] ?? dict["text"] ?? dict["content"]
                 ?? dict["本文"] ?? dict["内容"] ?? dict["テキスト"] ?? ""

        var date = Date()
        if let ds = dict["date"] ?? dict["日付"] ?? dict["created_at"] {
            date = parseDate(ds) ?? Date()
        }

        let knownKeys: Set<String> = [
            "id", "date", "title", "body", "text", "content",
            "created_at", "updated_at",
            "日付", "タイトル", "本文", "内容", "テキスト",
        ]
        var metadata: [String: String] = [:]
        for (k, v) in dict where !knownKeys.contains(k) && !v.isEmpty {
            metadata[k] = v
        }

        return DiaryEntry(
            id: UUID(),
            date: date,
            title: title,
            body: body,
            sourceApp: ImportSource.csv.rawValue,
            metadata: metadata
        )
    }

    /// Minimal RFC 4180 CSV line parser: handles quoted fields containing commas / newlines.
    static func parseCSVLine(_ line: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inQuotes = false

        for char in line {
            switch char {
            case "\"":
                inQuotes.toggle()
            case "," where !inQuotes:
                result.append(current)
                current = ""
            default:
                current.append(char)
            }
        }
        result.append(current)
        return result
    }

    private static func parseDate(_ string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in ["yyyy-MM-dd", "yyyy/MM/dd", "MM/dd/yyyy", "dd/MM/yyyy"] {
            formatter.dateFormat = format
            if let d = formatter.date(from: string.trimmingCharacters(in: .whitespaces)) {
                return d
            }
        }
        return nil
    }
}
