// ShareViewController.swift
// Share Extension entry point. Normalizes shared text / URL / image items,
// writes them into the shared App Group queue, then opens DiaryBook.

import UIKit
import SwiftUI
import UniformTypeIdentifiers

@objc(ShareViewController)
final class ShareViewController: UIViewController {
    private let queueStore = ShareQueueStore()

    override func viewDidLoad() {
        super.viewDidLoad()

        let ctx = extensionContext
        let host = UIHostingController(
            rootView: ShareRootView(
                extensionContext: ctx,
                onSave: { [weak self] items in self?.save(items: items) },
                onCancel: { [weak self] items in self?.cancel(items: items) }
            )
        )
        addChild(host)
        view.addSubview(host.view)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.didMove(toParent: self)
    }

    private func save(items: [ShareItem]) {
        do {
            try queueStore.append(SharePayload(items: items, date: Date()))
        } catch {
            print("[ShareExtension] Failed to enqueue shared items: \(error)")
            cleanupPreparedImages(in: items)
            extensionContext?.completeRequest(returningItems: nil)
            return
        }

        extensionContext?.open(ShareTransferConfig.importURL) { [weak self] _ in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
    }

    private func cancel(items: [ShareItem]) {
        cleanupPreparedImages(in: items)
        extensionContext?.completeRequest(returningItems: nil)
    }

    private func cleanupPreparedImages(in items: [ShareItem]) {
        for item in items where item.kind == .image {
            guard let filename = item.imageFilename else { continue }
            try? queueStore.removeStagedImage(named: filename)
        }
    }
}

private struct ShareRootView: View {
    let extensionContext: NSExtensionContext?
    let onSave: ([ShareItem]) -> Void
    let onCancel: ([ShareItem]) -> Void

    @State private var resolvedItems: [ShareItem] = []
    @State private var isLoading = true

    private let queueStore = ShareQueueStore()

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("読み込み中…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    previewList
                }
            }
            .navigationTitle("DiaryBook に保存")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { onCancel(resolvedItems) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { onSave(resolvedItems) }
                        .bold()
                        .disabled(resolvedItems.isEmpty)
                }
            }
        }
        .task { await resolveItems() }
    }

    private var previewList: some View {
        List {
            if resolvedItems.isEmpty {
                Text("取り込めるコンテンツがありません")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(resolvedItems) { item in
                    HStack(spacing: 12) {
                        Image(systemName: iconName(for: item))
                            .foregroundStyle(Color.accentColor)
                        Text(previewText(for: item))
                            .lineLimit(2)
                            .font(.subheadline)
                    }
                }
            }
        }
    }

    private func iconName(for item: ShareItem) -> String {
        switch item.kind {
        case .text:  return "text.alignleft"
        case .url:   return "link"
        case .image: return "photo"
        }
    }

    private func previewText(for item: ShareItem) -> String {
        switch item.kind {
        case .text, .url:
            return item.text ?? ""
        case .image:
            return "画像"
        }
    }

    @MainActor
    private func resolveItems() async {
        guard let context = extensionContext else {
            isLoading = false
            return
        }

        var found: [ShareItem] = []
        for inputItem in context.inputItems as? [NSExtensionItem] ?? [] {
            for attachment in inputItem.attachments ?? [] {
                if attachment.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    if let url = urlValue(from: try? await attachment.loadItem(forTypeIdentifier: UTType.url.identifier)) {
                        found.append(ShareItem(kind: .url, text: url.absoluteString))
                    }
                } else if attachment.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    if let text = stringValue(from: try? await attachment.loadItem(forTypeIdentifier: UTType.plainText.identifier)) {
                        found.append(ShareItem(kind: .text, text: text))
                    }
                } else if attachment.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    if let item = await resolveImageItem(from: attachment) {
                        found.append(item)
                    }
                }
            }
        }
        resolvedItems = found
        isLoading = false
    }

    private func resolveImageItem(from attachment: NSItemProvider) async -> ShareItem? {
        let loadedItem = try? await attachment.loadItem(forTypeIdentifier: UTType.image.identifier)

        if let url = urlValue(from: loadedItem) {
            let fileExtension = preferredImageExtension(for: attachment) ?? url.pathExtension
            if let filename = try? queueStore.copyImageToStaging(from: url, preferredExtension: fileExtension) {
                return ShareItem(kind: .image, imageFilename: filename)
            }
        }

        if let data = loadedItem as? Data {
            let fileExtension = preferredImageExtension(for: attachment)
            if let filename = try? queueStore.writeStagedImageData(data, preferredExtension: fileExtension) {
                return ShareItem(kind: .image, imageFilename: filename)
            }
        }

        if let image = loadedItem as? UIImage,
           let data = image.jpegData(compressionQuality: 0.92),
           let filename = try? queueStore.writeStagedImageData(data, preferredExtension: "jpg") {
            return ShareItem(kind: .image, imageFilename: filename)
        }

        return nil
    }

    private func urlValue(from value: NSSecureCoding?) -> URL? {
        if let url = value as? URL { return url }
        if let nsURL = value as? NSURL { return nsURL as URL }
        return nil
    }

    private func stringValue(from value: NSSecureCoding?) -> String? {
        if let text = value as? String { return text }
        if let nsString = value as? NSString { return nsString as String }
        return nil
    }

    private func preferredImageExtension(for attachment: NSItemProvider) -> String? {
        attachment.registeredTypeIdentifiers
            .compactMap { UTType($0) }
            .first(where: { $0.conforms(to: .image) })?
            .preferredFilenameExtension
    }
}
