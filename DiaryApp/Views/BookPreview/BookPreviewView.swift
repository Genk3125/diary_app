// BookPreviewView.swift
// Shows a simulated book layout: entries ordered and grouped as they would appear in print.
// Plan limits are applied here — excess photos show a warning, videos show QR placeholders.

import SwiftUI
import UIKit

struct BookPreviewView: View {
    @EnvironmentObject var store: DiaryStore

    @State private var grouping: BookLayoutConfig.GroupingStyle = .byMonth
    @State private var sortOrder: BookLayoutConfig.SortOrder   = .dateAscending
    @State private var pdfShareItem: PDFShareItem?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                groupingPicker
                    .padding([.horizontal, .top])
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
                        Picker("並び順", selection: $sortOrder) {
                            Text("日付昇順").tag(BookLayoutConfig.SortOrder.dateAscending)
                            Text("日付降順").tag(BookLayoutConfig.SortOrder.dateDescending)
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
        Picker("グループ", selection: $grouping) {
            Text("なし").tag(BookLayoutConfig.GroupingStyle.none)
            Text("月ごと").tag(BookLayoutConfig.GroupingStyle.byMonth)
            Text("年ごと").tag(BookLayoutConfig.GroupingStyle.byYear)
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Content

    @ViewBuilder
    private var bookContent: some View {
        let sorted = sortedEntries
        switch grouping {
        case .none:
            List(sorted) { entry in
                BookEntryRow(entry: entry, plan: store.currentPlan)
            }

        case .byMonth:
            List {
                ForEach(grouped(sorted, by: monthKey), id: \.key) { group in
                    Section(group.key) {
                        ForEach(group.entries) { entry in
                            BookEntryRow(entry: entry, plan: store.currentPlan)
                        }
                    }
                }
            }

        case .byYear:
            List {
                ForEach(grouped(sorted, by: yearKey), id: \.key) { group in
                    Section(group.key) {
                        ForEach(group.entries) { entry in
                            BookEntryRow(entry: entry, plan: store.currentPlan)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private var sortedEntries: [DiaryEntry] {
        switch sortOrder {
        case .dateAscending:  return store.entries.sorted { $0.date < $1.date }
        case .dateDescending: return store.entries.sorted { $0.date > $1.date }
        }
    }

    struct EntryGroup: Identifiable {
        let key: String
        let entries: [DiaryEntry]
        var id: String { key }
    }

    private func grouped(
        _ entries: [DiaryEntry],
        by keyFn: (Date) -> String
    ) -> [EntryGroup] {
        var dict: [String: [DiaryEntry]] = [:]
        for entry in entries {
            let key = keyFn(entry.date)
            dict[key, default: []].append(entry)
        }
        return dict.sorted { $0.key < $1.key }.map { EntryGroup(key: $0.key, entries: $0.value) }
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
        let entries = sortedEntries
        let plan = store.currentPlan
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
            let dateAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 10),
                .foregroundColor: UIColor.secondaryLabel
            ]
            let bodyAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 11),
                .foregroundColor: UIColor.label
            ]
            let contentWidth = pageWidth - margin * 2
            let dateFormatter = DateFormatter()
            dateFormatter.locale = Locale(identifier: "ja_JP")
            dateFormatter.dateStyle = .long

            for entry in entries {
                // Measure entry height
                let titleStr = entry.title.isEmpty ? "" : entry.title
                let bodyStr = entry.body
                let dateStr = dateFormatter.string(from: entry.date)

                let dateHeight: CGFloat = 14
                let titleHeight: CGFloat = titleStr.isEmpty ? 0 : ceil((titleStr as NSString).boundingRect(
                    with: CGSize(width: contentWidth, height: .greatestFiniteMagnitude),
                    options: .usesLineFragmentOrigin, attributes: titleAttrs, context: nil).height) + 4
                let bodyHeight: CGFloat = bodyStr.isEmpty ? 0 : ceil((bodyStr as NSString).boundingRect(
                    with: CGSize(width: contentWidth, height: .greatestFiniteMagnitude),
                    options: .usesLineFragmentOrigin, attributes: bodyAttrs, context: nil).height) + 4
                let photoCount = min(entry.photos.count, plan.maxPhotosInPrint)
                let photoRowHeight: CGFloat = photoCount > 0 ? 60 : 0
                let totalHeight = dateHeight + titleHeight + bodyHeight + photoRowHeight + 24

                if remainingHeight() < totalHeight && y > margin + 10 {
                    newPage()
                }

                // Draw date
                (dateStr as NSString).draw(
                    at: CGPoint(x: margin, y: y),
                    withAttributes: dateAttrs
                )
                y += dateHeight

                // Draw title
                if !titleStr.isEmpty {
                    titleStr.draw(
                        with: CGRect(x: margin, y: y, width: contentWidth, height: titleHeight),
                        options: .usesLineFragmentOrigin, attributes: titleAttrs, context: nil
                    )
                    y += titleHeight
                }

                // Draw body
                if !bodyStr.isEmpty {
                    bodyStr.draw(
                        with: CGRect(x: margin, y: y, width: contentWidth, height: bodyHeight),
                        options: .usesLineFragmentOrigin, attributes: bodyAttrs, context: nil
                    )
                    y += bodyHeight
                }

                // Draw photo thumbnails (loaded from store if available)
                if photoCount > 0 {
                    let thumbSize: CGFloat = 48
                    var x = margin
                    for photo in entry.photos.prefix(photoCount) {
                        if let data = store.loadImageData(filename: photo.filename),
                           let image = UIImage(data: data) {
                            image.draw(in: CGRect(x: x, y: y, width: thumbSize, height: thumbSize))
                        } else {
                            UIColor.secondarySystemFill.setFill()
                            UIBezierPath(roundedRect: CGRect(x: x, y: y, width: thumbSize, height: thumbSize), cornerRadius: 4).fill()
                        }
                        x += thumbSize + 8
                    }
                    y += photoRowHeight
                }

                // Separator
                UIColor.separator.setStroke()
                let sep = UIBezierPath()
                sep.move(to: CGPoint(x: margin, y: y + 8))
                sep.addLine(to: CGPoint(x: pageWidth - margin, y: y + 8))
                sep.lineWidth = 0.5
                sep.stroke()
                y += 20
            }
        }

        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiaryBook_\(Int(Date().timeIntervalSince1970)).pdf")
        try? data.write(to: tmpURL)
        pdfShareItem = PDFShareItem(url: tmpURL)
    }
}

// MARK: - Book entry row

struct BookEntryRow: View {
    let entry: DiaryEntry
    let plan: UserPlan

    private var printPhotos: [PhotoAttachment] { Array(entry.photos.prefix(plan.maxPhotosInPrint)) }
    private var printVideos: [VideoAttachment]  { Array(entry.videos.prefix(plan.maxVideosInPrint)) }
    private var photosExceedLimit: Bool { entry.photos.count > plan.maxPhotosInPrint }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {

            // Date + limit warnings
            HStack(alignment: .firstTextBaseline) {
                Text(entry.date, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if photosExceedLimit {
                    Text("写真: 最大\(plan.maxPhotosInPrint)枚まで反映")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }

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
                        Text("+\(entry.photos.count - plan.maxPhotosInPrint)枚省略")
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
                }
            }
        }
        .padding(.vertical, 4)
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
