// ShareViewController.swift
// Share Extension エントリポイント。テキスト・URL・画像を受け取り、
// App Group コンテナに書き出して DiaryBook 本体へ渡す。
//
// ⚠️ 事前設定が必要（TODO.md 参照）:
//   1. DiaryApp と ShareExtension 両ターゲットに App Groups capability を追加
//      (group.com.yourapp.diaryapp)
//   2. DiaryApp に URL scheme "diarybook" を登録済み（project.yml で設定済み）
//   3. ShareExtension の entitlements に com.apple.security.application-groups を追加

import UIKit
import SwiftUI
import UniformTypeIdentifiers

@objc(ShareViewController)
final class ShareViewController: UIViewController {

    private let groupID = "group.com.yourapp.diaryapp"

    override func viewDidLoad() {
        super.viewDidLoad()

        let ctx = extensionContext
        let host = UIHostingController(
            rootView: ShareRootView(
                extensionContext: ctx,
                onSave: { [weak self] items in self?.save(items: items) },
                onCancel: { [weak self] in
                    self?.extensionContext?.completeRequest(returningItems: nil)
                }
            )
        )
        addChild(host)
        view.addSubview(host.view)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.didMove(toParent: self)
    }

    private func save(items: [ShareItem]) {
        // TODO: App Group capability を有効化後にコメントを外す
        // if let container = FileManager.default
        //     .containerURL(forSecurityApplicationGroupIdentifier: groupID) {
        //     let payload = SharePayload(items: items, date: Date())
        //     let url = container.appendingPathComponent("share_queue.json")
        //     let existing = (try? JSONDecoder().decode([SharePayload].self, from: Data(contentsOf: url))) ?? []
        //     try? JSONEncoder().encode(existing + [payload]).write(to: url, options: .atomic)
        // }

        // TODO: URL scheme 登録後にコメントを外す
        // extensionContext?.open(URL(string: "diarybook://import")!, completionHandler: nil)

        extensionContext?.completeRequest(returningItems: nil)
    }
}

// MARK: - Data types

struct ShareItem: Identifiable, Codable {
    var id = UUID()
    enum Kind: String, Codable { case text, url, image }
    var kind: Kind
    var text: String?
    var imageFilename: String?
}

struct SharePayload: Codable {
    var items: [ShareItem]
    var date: Date
}

// MARK: - SwiftUI View

private struct ShareRootView: View {
    let extensionContext: NSExtensionContext?
    let onSave: ([ShareItem]) -> Void
    let onCancel: () -> Void

    @State private var resolvedItems: [ShareItem] = []
    @State private var isLoading = true

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
                    Button("キャンセル") { onCancel() }
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
        case .text, .url: return item.text ?? ""
        case .image:      return "画像"
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
                    if let url = try? await attachment.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL {
                        found.append(ShareItem(kind: .url, text: url.absoluteString))
                    }
                } else if attachment.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    if let text = try? await attachment.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String {
                        found.append(ShareItem(kind: .text, text: text))
                    }
                } else if attachment.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    found.append(ShareItem(kind: .image))
                }
            }
        }
        resolvedItems = found
        isLoading = false
    }
}
