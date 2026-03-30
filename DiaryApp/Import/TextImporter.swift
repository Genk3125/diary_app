// TextImporter.swift
// Parses plain text pasted by the user into one or more DiaryEntry objects.
//
// Splitting strategy:
//   1. If the text contains lines that start with a date (YYYY-MM-DD or YYYY/MM/DD),
//      each date line starts a new entry.
//   2. Otherwise the entire text becomes a single entry dated today.

import Foundation

struct TextImporter {

    static func importEntries(from text: String) throws -> [DiaryEntry] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ImportError.parsingFailed("テキストが空です")
        }

        let split = splitByDateHeaders(trimmed)
        if split.count > 1 { return split }

        // Single entry fallback
        return [DiaryEntry(
            id: UUID(),
            date: Date(),
            title: extractTitle(from: trimmed),
            body: trimmed,
            sourceApp: ImportSource.text.rawValue
        )]
    }

    // MARK: - Private

    private static func splitByDateHeaders(_ text: String) -> [DiaryEntry] {
        let lines = text.components(separatedBy: .newlines)
        var segments: [(date: Date, body: [String])] = []
        var current: (date: Date, body: [String])? = nil

        for line in lines {
            if let date = extractDate(from: line) {
                if let prev = current {
                    segments.append(prev)
                }
                // Strip the date prefix from the line before storing as body header
                let rest = String(line.dropFirst(10)).trimmingCharacters(in: .whitespaces)
                current = (date: date, body: rest.isEmpty ? [] : [rest])
            } else {
                current?.body.append(line)
            }
        }
        if let last = current { segments.append(last) }

        guard segments.count > 1 else { return [] }

        return segments.map { seg in
            let body = seg.body
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return DiaryEntry(
                id: UUID(),
                date: seg.date,
                title: extractTitle(from: body),
                body: body,
                sourceApp: ImportSource.text.rawValue
            )
        }
    }

    /// Attempts to parse a date from the first 10 characters of a line.
    private static func extractDate(from line: String) -> Date? {
        guard line.count >= 10 else { return nil }
        let prefix = String(line.prefix(10))
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in ["yyyy-MM-dd", "yyyy/MM/dd"] {
            formatter.dateFormat = format
            if let d = formatter.date(from: prefix) { return d }
        }
        return nil
    }

    /// Uses the first non-empty line as title, capped at 60 chars.
    private static func extractTitle(from text: String) -> String {
        let first = text
            .components(separatedBy: .newlines)
            .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? ""
        let t = first.trimmingCharacters(in: .whitespaces)
        return t.count > 60 ? String(t.prefix(60)) + "…" : t
    }
}
