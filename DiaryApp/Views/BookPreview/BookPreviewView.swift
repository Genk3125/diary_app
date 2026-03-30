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
        let pageInsets = UIEdgeInsets(top: 52, left: 44, bottom: 56, right: 44)
        let contentWidth = pageWidth - pageInsets.left - pageInsets.right

        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight))
        let data = renderer.pdfData { ctx in
            var y: CGFloat = pageInsets.top
            var pageNumber = 0

            let dateFormatter = DateFormatter()
            dateFormatter.locale = Locale(identifier: "ja_JP")
            dateFormatter.dateStyle = .long
            let generatedFormatter = DateFormatter()
            generatedFormatter.locale = Locale(identifier: "ja_JP")
            generatedFormatter.dateFormat = "yyyy年M月d日"

            let bodyParagraph = NSMutableParagraphStyle()
            bodyParagraph.lineSpacing = 3
            bodyParagraph.lineBreakMode = .byWordWrapping
            let centeredParagraph = NSMutableParagraphStyle()
            centeredParagraph.alignment = .center
            centeredParagraph.lineSpacing = 4
            let warningParagraph = NSMutableParagraphStyle()
            warningParagraph.lineSpacing = 2.5
            warningParagraph.lineBreakMode = .byWordWrapping

            let coverTitleAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 31, weight: .bold),
                .foregroundColor: UIColor.label,
                .paragraphStyle: centeredParagraph
            ]
            let coverSubtitleAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 16, weight: .regular),
                .foregroundColor: UIColor.secondaryLabel,
                .paragraphStyle: centeredParagraph
            ]
            let coverMetaAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12, weight: .medium),
                .foregroundColor: UIColor.secondaryLabel,
                .paragraphStyle: centeredParagraph
            ]
            let runningHeaderAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 10, weight: .medium),
                .foregroundColor: UIColor.secondaryLabel
            ]
            let sectionAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 13, weight: .semibold),
                .foregroundColor: UIColor.white
            ]
            let dateAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 11, weight: .regular),
                .foregroundColor: UIColor.secondaryLabel
            ]
            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 15, weight: .bold),
                .foregroundColor: UIColor.label
            ]
            let bodyAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12, weight: .regular),
                .foregroundColor: UIColor.label,
                .paragraphStyle: bodyParagraph
            ]
            let sourceAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 10, weight: .regular),
                .foregroundColor: UIColor.secondaryLabel
            ]
            let warningTextAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 10, weight: .semibold),
                .foregroundColor: UIColor.systemOrange,
                .paragraphStyle: warningParagraph
            ]
            let mediaLabelAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 10, weight: .semibold),
                .foregroundColor: UIColor.secondaryLabel
            ]
            let mediaSymbolAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12, weight: .semibold),
                .foregroundColor: UIColor.secondaryLabel
            ]

            func measuredHeight(
                _ text: String,
                width: CGFloat,
                attributes: [NSAttributedString.Key: Any]
            ) -> CGFloat {
                ceil((text as NSString).boundingRect(
                    with: CGSize(width: width, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: attributes,
                    context: nil
                ).height)
            }

            func remainingHeight() -> CGFloat {
                pageHeight - pageInsets.bottom - y
            }

            func drawRunningHeader() {
                (bookTitle as NSString).draw(
                    at: CGPoint(x: pageInsets.left, y: y),
                    withAttributes: runningHeaderAttrs
                )
                ("p.\(pageNumber)" as NSString).draw(
                    at: CGPoint(x: pageWidth - pageInsets.right - 26, y: y),
                    withAttributes: runningHeaderAttrs
                )
                y += 14
                UIColor.separator.setStroke()
                let divider = UIBezierPath()
                divider.move(to: CGPoint(x: pageInsets.left, y: y))
                divider.addLine(to: CGPoint(x: pageWidth - pageInsets.right, y: y))
                divider.lineWidth = 0.5
                divider.stroke()
                y += 10
            }

            func beginPage(withRunningHeader: Bool) {
                ctx.beginPage()
                pageNumber += 1
                y = pageInsets.top
                if withRunningHeader {
                    drawRunningHeader()
                }
            }

            func drawMediaPlaceholder(in rect: CGRect, symbol: String, dashed: Bool) {
                let rounded = UIBezierPath(roundedRect: rect, cornerRadius: 6)
                if dashed {
                    UIColor.secondaryLabel.setStroke()
                    rounded.setLineDash([4, 3], count: 2, phase: 0)
                    rounded.lineWidth = 1
                    rounded.stroke()
                } else {
                    UIColor.secondarySystemFill.setFill()
                    rounded.fill()
                    UIColor.separator.setStroke()
                    rounded.lineWidth = 0.6
                    rounded.stroke()
                }

                let symbolSize = (symbol as NSString).size(withAttributes: mediaSymbolAttrs)
                let symbolPoint = CGPoint(
                    x: rect.midX - symbolSize.width / 2,
                    y: rect.midY - symbolSize.height / 2
                )
                (symbol as NSString).draw(at: symbolPoint, withAttributes: mediaSymbolAttrs)
            }

            func drawImageThumbnail(_ image: UIImage, in rect: CGRect) {
                let imageSize = image.size
                guard imageSize.width > 0, imageSize.height > 0 else {
                    drawMediaPlaceholder(in: rect, symbol: "写", dashed: false)
                    return
                }

                let scale = max(rect.width / imageSize.width, rect.height / imageSize.height)
                let drawSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
                let drawRect = CGRect(
                    x: rect.midX - drawSize.width / 2,
                    y: rect.midY - drawSize.height / 2,
                    width: drawSize.width,
                    height: drawSize.height
                )

                ctx.cgContext.saveGState()
                UIBezierPath(roundedRect: rect, cornerRadius: 6).addClip()
                image.draw(in: drawRect)
                ctx.cgContext.restoreGState()

                UIColor.separator.setStroke()
                let border = UIBezierPath(roundedRect: rect, cornerRadius: 6)
                border.lineWidth = 0.5
                border.stroke()
            }

            beginPage(withRunningHeader: false)

            let coverCardRect = CGRect(
                x: pageInsets.left,
                y: pageInsets.top + 78,
                width: contentWidth,
                height: min(390, pageHeight - pageInsets.top - pageInsets.bottom - 180)
            )
            UIColor.systemGray6.setFill()
            UIBezierPath(roundedRect: coverCardRect, cornerRadius: 18).fill()

            let accentRect = CGRect(
                x: coverCardRect.minX + 24,
                y: coverCardRect.minY + 24,
                width: coverCardRect.width - 48,
                height: 8
            )
            UIColor.systemTeal.withAlphaComponent(0.85).setFill()
            UIBezierPath(roundedRect: accentRect, cornerRadius: 4).fill()

            let subtitle = config.subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
            var coverTextY = coverCardRect.minY + 56
            let coverTitleHeight = measuredHeight(bookTitle, width: coverCardRect.width - 56, attributes: coverTitleAttrs)
            bookTitle.draw(
                with: CGRect(
                    x: coverCardRect.minX + 28,
                    y: coverTextY,
                    width: coverCardRect.width - 56,
                    height: coverTitleHeight
                ),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: coverTitleAttrs,
                context: nil
            )
            coverTextY += coverTitleHeight + 14

            if !subtitle.isEmpty {
                let subtitleHeight = measuredHeight(subtitle, width: coverCardRect.width - 56, attributes: coverSubtitleAttrs)
                subtitle.draw(
                    with: CGRect(
                        x: coverCardRect.minX + 28,
                        y: coverTextY,
                        width: coverCardRect.width - 56,
                        height: subtitleHeight
                    ),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: coverSubtitleAttrs,
                    context: nil
                )
                coverTextY += subtitleHeight + 18
            }

            let coverMetaLines = [
                "並び順: \(config.sortOrder.displayName)",
                "グループ: \(config.grouping.displayName)",
                "写真 \(effectivePhotoLimit)枚 / 動画 \(effectiveVideoLimit)本",
                config.includeSourceApp ? "ソース表記: あり" : "ソース表記: なし"
            ]
            for line in coverMetaLines {
                let lineHeight = measuredHeight(line, width: coverCardRect.width - 56, attributes: coverMetaAttrs)
                line.draw(
                    with: CGRect(
                        x: coverCardRect.minX + 28,
                        y: coverTextY,
                        width: coverCardRect.width - 56,
                        height: lineHeight
                    ),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: coverMetaAttrs,
                    context: nil
                )
                coverTextY += lineHeight + 6
            }

            let generatedText = "生成日: \(generatedFormatter.string(from: Date()))"
            (generatedText as NSString).draw(
                at: CGPoint(x: pageInsets.left, y: coverCardRect.maxY + 24),
                withAttributes: coverMetaAttrs
            )

            beginPage(withRunningHeader: true)

            for group in groups {
                if !group.key.isEmpty {
                    let sectionHeight: CGFloat = 28
                    if remainingHeight() < sectionHeight + 12 && y > pageInsets.top + 10 {
                        beginPage(withRunningHeader: true)
                    }

                    let sectionRect = CGRect(x: pageInsets.left, y: y, width: contentWidth, height: sectionHeight)
                    UIColor.systemTeal.withAlphaComponent(0.9).setFill()
                    UIBezierPath(roundedRect: sectionRect, cornerRadius: 8).fill()
                    (group.key as NSString).draw(
                        at: CGPoint(x: sectionRect.minX + 12, y: sectionRect.minY + 6),
                        withAttributes: sectionAttrs
                    )
                    y += sectionHeight + 10
                }

                for entry in group.entries {
                    let entryTitle = entry.title.trimmingCharacters(in: .whitespacesAndNewlines)
                    let bodyStr = entry.body
                    let dateStr = dateFormatter.string(from: entry.date)
                    let sourceText = config.includeSourceApp ? "出典: \(bookSourceLabel(for: entry.sourceApp))" : nil
                    let photoCount = min(entry.photos.count, effectivePhotoLimit)
                    let videoCount = min(entry.videos.count, effectiveVideoLimit)
                    let warningLines = [
                        entry.photos.count > effectivePhotoLimit ? "写真は\(effectivePhotoLimit)枚まで掲載" : nil,
                        entry.videos.count > effectiveVideoLimit ? "動画QRは\(effectiveVideoLimit)本まで掲載" : nil
                    ].compactMap { $0 }

                    let cardInset: CGFloat = 14
                    let cardWidth = contentWidth
                    let innerWidth = cardWidth - (cardInset * 2)
                    let mediaColumns = 3
                    let mediaGap: CGFloat = 8
                    let mediaThumb = floor((innerWidth - (CGFloat(mediaColumns - 1) * mediaGap)) / CGFloat(mediaColumns))

                    let dateHeight = measuredHeight(dateStr, width: innerWidth, attributes: dateAttrs)
                    let titleHeight = entryTitle.isEmpty ? 0 : measuredHeight(entryTitle, width: innerWidth, attributes: titleAttrs)
                    let bodyHeight = bodyStr.isEmpty ? 0 : measuredHeight(bodyStr, width: innerWidth, attributes: bodyAttrs)
                    let sourceHeight = sourceText == nil ? 0 : measuredHeight(sourceText!, width: innerWidth, attributes: sourceAttrs)

                    let warningText = warningLines.map { "• \($0)" }.joined(separator: "\n")
                    let warningTextHeight = warningLines.isEmpty ? 0 : measuredHeight(warningText, width: innerWidth - 16, attributes: warningTextAttrs)
                    let warningBoxHeight = warningLines.isEmpty ? 0 : warningTextHeight + 12

                    let photoRows = photoCount > 0 ? Int(ceil(Double(photoCount) / Double(mediaColumns))) : 0
                    let photoLabelHeight: CGFloat = photoCount > 0 ? measuredHeight("写真", width: innerWidth, attributes: mediaLabelAttrs) + 4 : 0
                    let photoGridHeight: CGFloat = photoRows > 0
                        ? (CGFloat(photoRows) * mediaThumb) + (CGFloat(max(photoRows - 1, 0)) * mediaGap)
                        : 0
                    let videoRows = videoCount > 0 ? Int(ceil(Double(videoCount) / Double(mediaColumns))) : 0
                    let videoLabelHeight: CGFloat = videoCount > 0 ? measuredHeight("動画QR", width: innerWidth, attributes: mediaLabelAttrs) + 4 : 0
                    let videoGridHeight: CGFloat = videoRows > 0
                        ? (CGFloat(videoRows) * mediaThumb) + (CGFloat(max(videoRows - 1, 0)) * mediaGap)
                        : 0

                    var cardContentHeight = dateHeight
                    if titleHeight > 0 { cardContentHeight += 6 + titleHeight }
                    if bodyHeight > 0 { cardContentHeight += 8 + bodyHeight }
                    if sourceHeight > 0 { cardContentHeight += 8 + sourceHeight }
                    if warningBoxHeight > 0 { cardContentHeight += 8 + warningBoxHeight }
                    if photoGridHeight > 0 { cardContentHeight += 10 + photoLabelHeight + photoGridHeight }
                    if videoGridHeight > 0 { cardContentHeight += 10 + videoLabelHeight + videoGridHeight }

                    let cardHeight = (cardInset * 2) + cardContentHeight
                    if remainingHeight() < cardHeight + 12 && y > pageInsets.top + 10 {
                        beginPage(withRunningHeader: true)
                    }

                    let cardRect = CGRect(x: pageInsets.left, y: y, width: cardWidth, height: cardHeight)
                    UIColor.secondarySystemBackground.setFill()
                    UIBezierPath(roundedRect: cardRect, cornerRadius: 10).fill()
                    UIColor.separator.setStroke()
                    let cardBorder = UIBezierPath(roundedRect: cardRect, cornerRadius: 10)
                    cardBorder.lineWidth = 0.7
                    cardBorder.stroke()

                    var cursorY = cardRect.minY + cardInset
                    (dateStr as NSString).draw(
                        at: CGPoint(x: cardRect.minX + cardInset, y: cursorY),
                        withAttributes: dateAttrs
                    )
                    cursorY += dateHeight

                    if !entryTitle.isEmpty {
                        entryTitle.draw(
                            with: CGRect(x: cardRect.minX + cardInset, y: cursorY + 6, width: innerWidth, height: titleHeight),
                            options: [.usesLineFragmentOrigin, .usesFontLeading],
                            attributes: titleAttrs,
                            context: nil
                        )
                        cursorY += 6 + titleHeight
                    }

                    if !bodyStr.isEmpty {
                        bodyStr.draw(
                            with: CGRect(x: cardRect.minX + cardInset, y: cursorY + 8, width: innerWidth, height: bodyHeight),
                            options: [.usesLineFragmentOrigin, .usesFontLeading],
                            attributes: bodyAttrs,
                            context: nil
                        )
                        cursorY += 8 + bodyHeight
                    }

                    if let sourceText {
                        (sourceText as NSString).draw(
                            at: CGPoint(x: cardRect.minX + cardInset, y: cursorY + 8),
                            withAttributes: sourceAttrs
                        )
                        cursorY += 8 + sourceHeight
                    }

                    if !warningLines.isEmpty {
                        let warningRect = CGRect(
                            x: cardRect.minX + cardInset,
                            y: cursorY + 8,
                            width: innerWidth,
                            height: warningBoxHeight
                        )
                        UIColor.systemOrange.withAlphaComponent(0.12).setFill()
                        UIBezierPath(roundedRect: warningRect, cornerRadius: 6).fill()

                        warningText.draw(
                            with: warningRect.insetBy(dx: 8, dy: 6),
                            options: [.usesLineFragmentOrigin, .usesFontLeading],
                            attributes: warningTextAttrs,
                            context: nil
                        )
                        cursorY += 8 + warningBoxHeight
                    }

                    if photoCount > 0 {
                        ("写真" as NSString).draw(
                            at: CGPoint(x: cardRect.minX + cardInset, y: cursorY + 10),
                            withAttributes: mediaLabelAttrs
                        )
                        cursorY += 10 + photoLabelHeight

                        for (idx, photo) in entry.photos.prefix(photoCount).enumerated() {
                            let row = idx / mediaColumns
                            let column = idx % mediaColumns
                            let rect = CGRect(
                                x: cardRect.minX + cardInset + CGFloat(column) * (mediaThumb + mediaGap),
                                y: cursorY + CGFloat(row) * (mediaThumb + mediaGap),
                                width: mediaThumb,
                                height: mediaThumb
                            )
                            if let data = store.loadImageData(filename: photo.filename),
                               let image = UIImage(data: data) {
                                drawImageThumbnail(image, in: rect)
                            } else {
                                drawMediaPlaceholder(in: rect, symbol: "写", dashed: false)
                            }
                        }
                        cursorY += photoGridHeight
                    }

                    if videoCount > 0 {
                        ("動画QR" as NSString).draw(
                            at: CGPoint(x: cardRect.minX + cardInset, y: cursorY + 10),
                            withAttributes: mediaLabelAttrs
                        )
                        cursorY += 10 + videoLabelHeight

                        for idx in 0..<videoCount {
                            let row = idx / mediaColumns
                            let column = idx % mediaColumns
                            let rect = CGRect(
                                x: cardRect.minX + cardInset + CGFloat(column) * (mediaThumb + mediaGap),
                                y: cursorY + CGFloat(row) * (mediaThumb + mediaGap),
                                width: mediaThumb,
                                height: mediaThumb
                            )
                            drawMediaPlaceholder(in: rect, symbol: "QR", dashed: true)
                        }
                        cursorY += videoGridHeight
                    }

                    y += cardHeight + 12
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
    private var warningMessages: [String] {
        [
            photosExceedLimit ? "写真は最大\(maxPhotosInPrint)枚まで反映" : nil,
            videosExceedLimit ? "動画QRは最大\(maxVideosInPrint)本まで反映" : nil
        ].compactMap { $0 }
    }
    private var sourceLabel: String? {
        guard includeSourceApp else { return nil }
        return "出典: \(bookSourceLabel(for: entry.sourceApp))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(entry.date, style: .date)
                .font(.caption)
                .foregroundStyle(.secondary)

            if !entry.title.isEmpty {
                Text(entry.title)
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)
            }

            if !entry.body.isEmpty {
                Text(entry.body)
                    .font(.callout)
                    .lineSpacing(2)
                    .lineLimit(8)
            }

            if let sourceLabel {
                Text(sourceLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if !warningMessages.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(warningMessages, id: \.self) { warning in
                        Text("• \(warning)")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.orange.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            if !printPhotos.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("写真")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        ForEach(printPhotos) { _ in
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.secondary.opacity(0.16))
                                .frame(width: 44, height: 44)
                                .overlay(Image(systemName: "photo").font(.caption).foregroundStyle(.secondary))
                        }
                    }

                    if photosExceedLimit {
                        Text("+\(entry.photos.count - maxPhotosInPrint)枚を省略")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
            }

            if !printVideos.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("動画QR")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        ForEach(printVideos) { _ in
                            ZStack {
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(style: StrokeStyle(lineWidth: 1, dash: [3]))
                                    .frame(width: 44, height: 44)
                                    .foregroundStyle(.secondary)
                                Image(systemName: "qrcode")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    if videosExceedLimit {
                        Text("+\(entry.videos.count - maxVideosInPrint)本を省略")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.vertical, 2)
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
