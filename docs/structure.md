# DiaryBook — アーキテクチャ概要

> vibe coding エージェント向け早見表。初めてこのコードを触る人はここから読んでください。

---

## 1. MVP 要件まとめ

| カテゴリ | 実装状況 |
|---|---|
| 日記の作成・編集・削除・一覧 | ✅ 実装済 |
| 画像添付（プラン上限付き） | ✅ 実装済 |
| 動画添付（QRコード前提で保持） | ✅ 実装済 |
| 動画再生（AVPlayerViewController） | ✅ 実装済 |
| JSON インポート | ✅ 実装済 |
| CSV インポート | ✅ 実装済 |
| テキスト貼り付けインポート | ✅ 実装済 |
| ZIP インポート | ✅ 実装済（ZipFoundation 0.9.20） |
| PDF インポート | ✅ 実装済（PDFKit テキスト抽出） |
| 書籍化プレビュー（月・年グループ） | ✅ 実装済 |
| PDF 書き出し（A4・UIGraphicsPDFRenderer） | ✅ 実装済 |
| プラン管理 / StoreKit 2 課金ゲート | ✅ 実装済（App Store Connect 登録は別途） |
| QR コード生成（CoreImage） | ✅ 実装済 |
| Share Extension | ✅ 実装済（App Group capability は別途） |

---

## 2. 画面構成

```
TabView
├── 日記タブ (DiaryListView)
│   ├── NavigationLink → DiaryDetailView
│   │   └── Sheet → DiaryEditorView（編集）
│   └── Sheet → DiaryEditorView（新規作成）
├── インポートタブ (ImportView)
├── 書籍化タブ (BookPreviewView)
└── プランタブ (PlanView)           ← StoreKit 2 課金ゲート

Share Extension (ShareViewController) — 外部アプリから受け取りシート
```

---

## 3. ディレクトリ構成

```
diary_app/
├── project.yml                  # xcodegen 定義 (brew install xcodegen && xcodegen generate)
├── docs/
│   ├── structure.md             # このファイル
│   └── dependency_mapping.md   # モジュール依存関係
└── DiaryApp/
    ├── DiaryApp.swift           # @main エントリポイント
    ├── Info.plist               # 権限宣言（写真ライブラリ）
    ├── Models/
    │   ├── DiaryEntry.swift     # コアデータモデル（Codable）
    │   ├── MediaAttachment.swift # PhotoAttachment / VideoAttachment
    │   ├── UserPlan.swift       # Free / Pro プラン enum
    │   └── BookLayoutConfig.swift # 書籍レイアウト設定
    ├── Storage/
    │   └── DiaryStore.swift     # ObservableObject / JSON 永続化
    ├── Import/
    │   ├── ImportManager.swift  # ルーター
    │   ├── JSONImporter.swift
    │   ├── CSVImporter.swift
    │   ├── ZIPImporter.swift    # ZipFoundation 0.9.20 で展開
    │   ├── PDFImporter.swift    # PDFKit テキスト抽出
    │   └── TextImporter.swift
    ├── Purchases/
    │   └── PurchaseManager.swift  # StoreKit 2 / AnyCancellable で DiaryStore に購読状態を伝搬
    ├── Products.storekit          # ローカルテスト用商品定義
    └── Views/
        ├── ContentView.swift            # TabView ルート（4タブ）
        ├── DiaryList/
        │   └── DiaryListView.swift
        ├── DiaryDetail/
        │   ├── DiaryDetailView.swift
        │   └── QRCodeView.swift         # CoreImage QR コード生成
        ├── DiaryEditor/
        │   └── DiaryEditorView.swift    # PhotosPicker / VideoFile Transferable
        ├── Import/
        │   └── ImportView.swift
        └── Settings/
            └── PlanView.swift           # プラン表示・購入・復元 UI
        ├── BookPreview/
        │   └── BookPreviewView.swift
        ...（外部）
ShareExtension/
    └── ShareViewController.swift        # Share Extension (App Group 設定後に完全動作)
```

---

## 4. データモデル（内部共通形式）

```swift
DiaryEntry {
  id:        UUID
  date:      Date
  title:     String
  body:      String
  photos:    [PhotoAttachment]   // filename → Documents/media/*.jpg
  videos:    [VideoAttachment]   // filename → Documents/media/*.mov / hostedAssetID
  sourceApp: String              // "manual" | "json_import" | "csv_import" ...
  metadata:  [String: String]    // 元データの追加フィールドを保持
  createdAt: Date
  updatedAt: Date
}
```

永続化先: `Documents/diary_entries.json`（ISO 8601 日付）
メディア:  `Documents/media/<UUID>.<ext>`

---

## 5. プラン制限の流れ

```
UserPlan.maxPhotosPerEntry
    ↓ DiaryStore.effectiveMaxPhotos()
    ↓ DiaryEditorView（入力制限）
    ↓ BookPreviewView（印刷反映枚数ウォーニング）
```

Free: 写真1・動画1 / Pro: 写真3・動画3
印刷時上限 = デジタル上限（`maxPhotosInPrint` / `maxVideosInPrint`）

---

## 6. Xcode プロジェクトのセットアップ

```bash
# xcodegen のインストール（初回のみ）
brew install xcodegen

# プロジェクト生成
cd diary_app
xcodegen generate

# Xcode で開く
open DiaryApp.xcodeproj
```

または Xcode で「New Project → iOS App」を作成し、`DiaryApp/` 以下の Swift ファイルをすべて追加してください。

---

## 7. 動画対応メモ

- 動画はローカルファイル（`Documents/media/*.mov`）または `hostedAssetID` / `remoteURL` として保持
- 印刷時は `VideoAttachment.qrCodeTarget` をQRコードにエンコードする想定
- TODO: 動画アップロード → `remoteURL` 書き戻し → `filename` を削除してストレージ節約

---

## 8. ZIP 対応の有効化手順

1. `project.yml` の `packages:` / `dependencies:` のコメントを外す
2. `xcodegen generate` を再実行
3. `ZIPImporter.swift` の `import ZIPFoundation` コメントを外す
4. `importEntries(from:)` の extraction ブロックのコメントを外す
