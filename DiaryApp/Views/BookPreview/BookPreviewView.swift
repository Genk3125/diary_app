// BookPreviewView.swift
// Shows a simulated book layout: entries ordered and grouped as they would appear in print.
// Plan limits are applied here — excess photos show a warning, videos show QR placeholders.

import SwiftUI
import UIKit

struct BookPreviewView: View {
    @EnvironmentObject var store: DiaryStore

    @State private var pdfShareItem: PDFShareItem?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                groupingPicker
                    .padding([.horizontal, .top])
                    .padding(.bottom, 8)

                previewHeader
                    .padding(.horizontal)
                    .padding(.bottom, 8)

                if store.entries.isEmpty {
                    ContentUnavailableView(
                        "日記がありません",
                        systemImage: "book.closed",
                        description: Text("日記タブで作成またはインポートしてください")
                    )
                } else {
                    bookContent
                }
            }
            .navigationTitle("書籍化プレビュー")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Picker("並び順", selection: sortOrderBinding) {
                            ForEach(BookLayoutConfig.SortOrder.allCases, id: \.self) { sortOrder in
                                Text(sortOrder.displayName).tag(sortOrder)
                            }
                        }
                        Divider()
                        Button("PDFを書き出す", systemImage: "arrow.down.doc") {
                            exportPDF()
                        }
                        .disabled(store.entries.isEmpty)
                    } label: {
                        Image(systemName: "arrow.up.arrow.down.circle")
                    }
                }
            }
            .sheet(item: $pdfShareItem) { item in
                ShareSheet(activityItems: [item.url])
            }
        }
    }

    // MARK: - Grouping picker

    private var groupingPicker: some View {
        Picker("グループ", selection: groupingBinding) {
            ForEach(BookLayoutConfig.GroupingStyle.allCases, id: \.self) { grouping in
                Text(grouping.displayName).tag(grouping)
            }
        }
        .pickerStyle(.segmented)
    }

    private var previewHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(bookTitle)
                .font(.title3.bold())

            if !store.bookLayoutConfig.subtitle.isEmpty {
                Text(store.bookLayoutConfig.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text(limitSummaryText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Content

    @ViewBuilder
    private var bookContent: some View {
        switch store.bookLayoutConfig.grouping {
        case .none:
            List(sortedEntries) { entry in
                BookEntryRow(
                    entry: entry,
                    includeSourceApp: store.bookLayoutConfig.includeSourceApp,
                    maxPhotosInPrint: effectivePhotoLimit,
                    maxVideosInPrint: effectiveVideoLimit
                )
            }

        case .byMonth:
            List {
                ForEach(groupedEntries) { group in
                    Section(group.key) {
                        ForEach(group.entries) { entry in
                            BookEntryRow(
                                entry: entry,
                                includeSourceApp: store.bookLayoutConfig.includeSourceApp,
                                maxPhotosInPrint: effectivePhotoLimit,
                                maxVideosInPrint: effectiveVideoLimit
                            )
                        }
                    }
                }
            }

        case .byYear:
            List {
                ForEach(groupedEntries) { group in
                    Section(group.key) {
                        ForEach(group.entries) { entry in
                            BookEntryRow(
                                entry: entry,
                                includeSourceApp: store.bookLayoutConfig.includeSourceApp,
                                maxPhotosInPrint: effectivePhotoLimit,
                                maxVideosInPrint: effectiveVideoLimit
                            )
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private var sortedEntries: [DiaryEntry] {
        switch store.bookLayoutConfig.sortOrder {
        case .dateAscending:  return store.entries.sorted { $0.date < $1.date }
        case .dateDescending: return store.entries.sorted { $0.date > $1.date }
        }
    }

    private var groupedEntries: [EntryGroup] {
        switch store.bookLayoutConfig.grouping {
        case .none:
            return [EntryGroup(key: "", entries: sortedEntries)]
        case .byMonth:
            return grouped(sortedEntries, by: monthKey)
        case .byYear:
            return grouped(sortedEntries, by: yearKey)
        }
    }

    private var bookTitle: String {
        let trimmed = store.bookLayoutConfig.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "無題の書籍" : trimmed
    }

    private var effectivePhotoLimit: Int { store.effectiveBookMaxPhotos() }
    private var effectiveVideoLimit: Int { store.effectiveBookMaxVideos() }

    private var limitSummaryText: String {
        var segments = [
            "写真\(effectivePhotoLimit)枚まで",
            "動画\(effectiveVideoLimit)本まで"
        ]
        if store.bookLayoutConfig.includeSourceApp {
            segments.append("ソース表記あり")
        }
        return segments.joined(separator: " / ")
    }

    private var groupingBinding: Binding<BookLayoutConfig.GroupingStyle> {
        configBinding(\.grouping)
    }

    private var sortOrderBinding: Binding<BookLayoutConfig.SortOrder> {
        configBinding(\.sortOrder)
    }

    struct EntryGroup: Identifiable {
        let key: String
        var entries: [DiaryEntry]
        var id: String { key }
    }

    private func grouped(
        _ entries: [DiaryEntry],
        by keyFn: (Date) -> String
    ) -> [EntryGroup] {
        var groups: [EntryGroup] = []
        var groupIndexes: [String: Int] = [:]

        for entry in entries {
            let key = keyFn(entry.date)
            if let index = groupIndexes[key] {
                groups[index].entries.append(entry)
            } else {
                groupIndexes[key] = groups.count
                groups.append(EntryGroup(key: key, entries: [entry]))
            }
        }

        return groups
    }

    private func monthKey(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "yyyy年 M月"
        return f.string(from: date)
    }

    private func yearKey(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "yyyy年"
        return f.string(from: date)
    }

    // MARK: - PDF export

    private func exportPDF() {
        let groups = groupedEntries
        let config = store.bookLayoutConfig
        let pageWidth: CGFloat = 595.2   // A4 width in points
        let pageHeight: CGFloat = 841.8  // A4 height in points
        let margin: CGFloat = 48

        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight))
        let data = renderer.pdfData { ctx in
            var y: CGFloat = margin

            func newPage() {
                ctx.beginPage()
                y = margin
            }

            func remainingHeight() -> CGFloat { pageHeight - margin - y }

            newPage()

            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 14),
                .foregroundColor: UIColor.label
            ]
            let coverTitleAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 24),
                .foregroundColor: UIColor.label
            ]
            let subtitleAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 14),
                .foregroundColor: UIColor.secondaryLabel
            ]
            let metaAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 11),
                .foregroundColor: UIColor.secondaryLabel
            ]
            let dateAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 10),
                .foregroundColor: UIColor.secondaryLabel
            ]
            let bodyAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 11),
                .foregroundColor: UIColor.label
            ]
            let warningAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 10),
                .foregroundColor: UIColor.systemOrange
            ]
            let sectionAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 12),
                .foregroundColor: UIColor.secondaryLabel
            ]
            let contentWidth = pageWidth - margin * 2
            let dateFormatter = DateFormatter()
            dateFormatter.locale = Locale(identifier: "ja_JP")
            dateFormatter.dateStyle = .long

            func measuredHeight(_ text: String, attributes: [NSAttributedString.Key: Any]) -> CGFloat {
                ceil((text as NSString).boundingRect(
                    with: CGSize(width: contentWidth, height: .greatestFiniteMagnitude),
                    options: .usesLineFragmentOrigin,
                    attributes: attributes,
                    context: nil
                ).height)
            }

            func drawBookHeader() {
                let subtitle = config.subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
                let summary = "並び順: \(config.sortOrder.displayName) / グループ: \(config.grouping.displayName)"
                let limits = "写真 \(effectivePhotoLimit)枚 / 動画 \(effectiveVideoLimit)本"

                let coverTitleHeight = measuredHeight(bookTitle, attributes: coverTitleAttrs)
                bookTitle.draw(
                    with: CGRect(x: margin, y: y, width: contentWidth, height: coverTitleHeight),
                    options: .usesLineFragmentOrigin,
                    attributes: coverTitleAttrs,
                    context: nil
                )
                y += coverTitleHeight + 8

                if !subtitle.isEmpty {
                    let subtitleHeight = measuredHeight(subtitle, attributes: subtitleAttrs)
                    subtitle.draw(
                        with: CGRect(x: margin, y: y, width: contentWidth, height: subtitleHeight),
                        options: .usesLineFragmentOrigin,
                        attributes: subtitleAttrs,
                        context: nil
                    )
                    y += subtitleHeight + 8
                }

                (summary as NSString).draw(at: CGPoint(x: margin, y: y), withAttributes: metaAttrs)
                y += 16
                (limits as NSString).draw(at: CGPoint(x: margin, y: y), withAttributes: metaAttrs)
                y += 24

                UIColor.separator.setStroke()
                let divider = UIBezierPath()
                divider.move(to: CGPoint(x: margin, y: y))
                divider.addLine(to: CGPoint(x: pageWidth - margin, y: y))
                divider.lineWidth = 0.5
                divider.stroke()
                y += 20
            }

            drawBookHeader()

            for group in groups {
                if !group.key.isEmpty {
                    if remainingHeight() < 28 && y > margin + 10 {
                        newPage()
                    }

                    (group.key as NSString).draw(
                        at: CGPoint(x: margin, y: y),
                        withAttributes: sectionAttrs
                    )
                    y += 20
                }

                for entry in group.entries {
                    let entryTitle = entry.title.isEmpty ? "" : entry.title
                    let bodyStr = entry.body
                    let dateStr = dateFormatter.string(from: entry.date)
                    let sourceText = config.includeSourceApp ? "ソース: \(bookSourceLabel(for: entry.sourceApp))" : nil
                    let photoCount = min(entry.photos.count, effectivePhotoLimit)
                    let videoCount = min(entry.videos.count, effectiveVideoLimit)

                    let dateHeight: CGFloat = 14
                    let titleHeight: CGFloat = entryTitle.isEmpty ? 0 : measuredHeight(entryTitle, attributes: titleAttrs) + 4
                    let bodyHeight: CGFloat = bodyStr.isEmpty ? 0 : measuredHeight(bodyStr, attributes: bodyAttrs) + 4
                    let sourceHeight: CGFloat = sourceText == nil ? 0 : 14
                    let warningLines = [
                        entry.photos.count > effectivePhotoLimit ? "写真は\(effectivePhotoLimit)枚まで掲載" : nil,
                        entry.videos.count > effectiveVideoLimit ? "動画QRは\(effectiveVideoLimit)本まで掲載" : nil
                    ].compactMap { $0 }
                    let warningHeight: CGFloat = warningLines.isEmpty ? 0 : CGFloat(warningLines.count) * 12
                    let photoRowHeight: CGFloat = photoCount > 0 ? 60 : 0
                    let videoRowHeight: CGFloat = videoCount > 0 ? 60 : 0
                    let totalHeight = dateHeight + titleHeight + bodyHeight + sourceHeight + warningHeight + photoRowHeight + videoRowHeight + 24

                    if remainingHeight() < totalHeight && y > margin + 10 {
                        newPage()
                    }

                    (dateStr as NSString).draw(
                        at: CGPoint(x: margin, y: y),
                        withAttributes: dateAttrs
                    )
                    y += dateHeight

                    if !entryTitle.isEmpty {
                        entryTitle.draw(
                            with: CGRect(x: margin, y: y, width: contentWidth, height: titleHeight),
                            options: .usesLineFragmentOrigin,
                            attributes: titleAttrs,
                            context: nil
                        )
                        y += titleHeight
                    }

                    if !bodyStr.isEmpty {
                        bodyStr.draw(
                            with: CGRect(x: margin, y: y, width: contentWidth, height: bodyHeight),
                            options: .usesLineFragmentOrigin,
                            attributes: bodyAttrs,
                            context: nil
                        )
                        y += bodyHeight
                    }

                    if let sourceText {
                        (sourceText as NSString).draw(
                            at: CGPoint(x: margin, y: y),
                            withAttributes: metaAttrs
                        )
                        y += sourceHeight
                    }

                    for warning in warningLines {
                        (warning as NSString).draw(
                            at: CGPoint(x: margin, y: y),
                            withAttributes: warningAttrs
                        )
                        y += 12
                    }

                    if photoCount > 0 {
                        let thumbSize: CGFloat = 48
                        var x = margin
                        for photo in entry.photos.prefix(photoCount) {
                            if let data = store.loadImageData(filename: photo.filename),
                               let image = UIImage(data: data) {
                                image.draw(in: CGRect(x: x, y: y, width: thumbSize, height: thumbSize))
                            } else {
                                UIColor.secondarySystemFill.setFill()
                                UIBezierPath(
                                    roundedRect: CGRect(x: x, y: y, width: thumbSize, height: thumbSize),
                                    cornerRadius: 4
                                ).fill()
                            }
                            x += thumbSize + 8
                        }
                        y += photoRowHeight
                    }

                    if videoCount > 0 {
                        let thumbSize: CGFloat = 48
                        var x = margin
                        for _ in 0..<videoCount {
                            let rect = CGRect(x: x, y: y, width: thumbSize, height: thumbSize)
                            let box = UIBezierPath(roundedRect: rect, cornerRadius: 4)
                            UIColor.secondaryLabel.setStroke()
                            box.lineWidth = 1
                            box.stroke()
                            ("QR" as NSString).draw(
                                at: CGPoint(x: x + 13, y: y + 16),
                                withAttributes: metaAttrs
                            )
                            x += thumbSize + 8
                        }
                        y += videoRowHeight
                    }

                    UIColor.separator.setStroke()
                    let sep = UIBezierPath()
                    sep.move(to: CGPoint(x: margin, y: y + 8))
                    sep.addLine(to: CGPoint(x: pageWidth - margin, y: y + 8))
                    sep.lineWidth = 0.5
                    sep.stroke()
                    y += 20
                }
            }
        }

        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiaryBook_\(Int(Date().timeIntervalSince1970)).pdf")
        try? data.write(to: tmpURL)
        pdfShareItem = PDFShareItem(url: tmpURL)
    }

    private func configBinding<Value>(_ keyPath: WritableKeyPath<BookLayoutConfig, Value>) -> Binding<Value> {
        Binding(
            get: { store.bookLayoutConfig[keyPath: keyPath] },
            set: { store.setBookLayoutConfig(keyPath, to: $0) }
        )
    }
}

// MARK: - Book entry row

struct BookEntryRow: View {
    let entry: DiaryEntry
    let includeSourceApp: Bool
    let maxPhotosInPrint: Int
    let maxVideosInPrint: Int

    private var printPhotos: [PhotoAttachment] { Array(entry.photos.prefix(maxPhotosInPrint)) }
    private var printVideos: [VideoAttachment]  { Array(entry.videos.prefix(maxVideosInPrint)) }
    private var photosExceedLimit: Bool { entry.photos.count > maxPhotosInPrint }
    private var videosExceedLimit: Bool { entry.videos.count > maxVideosInPrint }
    private var sourceLabel: String? {
        guard includeSourceApp else { return nil }
        return "ソース: \(bookSourceLabel(for: entry.sourceApp))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(entry.date, style: .date)
                .font(.caption)
                .foregroundStyle(.secondary)

            // Title
            if !entry.title.isEmpty {
                Text(entry.title)
                    .font(.subheadline.bold())
            }

            // Body preview
            if !entry.body.isEmpty {
                Text(entry.body)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
            }

            if let sourceLabel {
                Text(sourceLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if photosExceedLimit {
                Text("写真: 最大\(maxPhotosInPrint)枚まで反映")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }

            if videosExceedLimit {
                Text("動画QR: 最大\(maxVideosInPrint)本まで反映")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }

            // Photo thumbnails (capped to print limit)
            if !printPhotos.isEmpty {
                HStack(spacing: 6) {
                    ForEach(printPhotos) { _ in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.secondary.opacity(0.15))
                            .frame(width: 36, height: 36)
                            .overlay(Image(systemName: "photo").font(.caption2).foregroundStyle(.secondary))
                    }
                    if photosExceedLimit {
                        Text("+\(entry.photos.count - maxPhotosInPrint)枚省略")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
            }

            // QR placeholders for videos
            if !printVideos.isEmpty {
                HStack(spacing: 6) {
                    ForEach(printVideos) { _ in
                        ZStack {
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(style: StrokeStyle(lineWidth: 1, dash: [3]))
                                .frame(width: 36, height: 36)
                                .foregroundStyle(.secondary)
                            Image(systemName: "qrcode")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text("QRコード（動画）")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if videosExceedLimit {
                        Text("+\(entry.videos.count - maxVideosInPrint)本省略")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private func bookSourceLabel(for sourceApp: String) -> String {
    switch sourceApp {
    case "manual":
        return "手動入力"
    case "json_import":
        return "JSONインポート"
    case "csv_import":
        return "CSVインポート"
    case "zip_import":
        return "ZIPインポート"
    case "text_paste":
        return "テキスト取り込み"
    case "pdf_import":
        return "PDFインポート"
    case "share_extension":
        return "共有シート"
    default:
        return sourceApp
    }
}

// MARK: - PDF share helpers

private struct PDFShareItem: Identifiable {
    let url: URL
    var id: URL { url }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
