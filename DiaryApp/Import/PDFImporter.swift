// PDFImporter.swift
// PDFKit でテキストを抽出し DiaryEntry を生成する。
// ページ単位ではなく、PDF 全体を 1 エントリとして取り込む（タイトル = ファイル名）。
// テキストが空のページは無視する。

import Foundation
import PDFKit

struct PDFImporter {

    static func importEntries(from url: URL) throws -> [DiaryEntry] {
        guard let doc = PDFDocument(url: url) else {
            throw ImportError.fileReadFailed("PDFを開けませんでした: \(url.lastPathComponent)")
        }

        var pages: [String] = []
        for i in 0 ..< doc.pageCount {
            if let page = doc.page(at: i),
               let text = page.string,
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                pages.append(text)
            }
        }

        guard !pages.isEmpty else {
            throw ImportError.parsingFailed("PDFにテキストが含まれていません（スキャン画像PDFは非対応）")
        }

        let body = pages.enumerated()
            .map { i, text in "【p.\(i + 1)】\n\(text)" }
            .joined(separator: "\n\n")

        let title = url.deletingPathExtension().lastPathComponent
        let entry = DiaryEntry(
            date: Date(),
            title: title,
            body: body,
            sourceApp: ImportSource.pdf.rawValue,
            metadata: [
                "filename": url.lastPathComponent,
                "pageCount": "\(doc.pageCount)"
            ]
        )
        return [entry]
    }
}
