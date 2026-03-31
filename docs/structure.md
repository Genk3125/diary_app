# DiaryBook — アーキテクチャ概要（現行実装）

このファイルは、初見でコードを追うための最短ガイドです。

## 1. 実装範囲（MVP）

| カテゴリ | 状態 |
|---|---|
| 日記の作成・編集・削除・一覧・詳細 | ✅ 実装済み |
| 検索・絞り込み（タイトル/本文/source、添付あり、並び順） | ✅ 実装済み |
| 画像添付（プラン上限） | ✅ 実装済み |
| 動画添付・再生（AVPlayer） | ✅ 実装済み |
| JSON / CSV / ZIP / PDF / テキスト インポート | ✅ 実装済み |
| Share Extension（テキスト/URL/画像） | ✅ 実装済み |
| 書籍化プレビュー（月/年グループ、上限反映） | ✅ 実装済み |
| PDF書き出し（A4） | ✅ 実装済み |
| StoreKit 2 課金導線（購入・復元・反映） | ✅ 実装済み |
| `media/` バックアップ除外・孤立ファイル掃除 | ✅ 実装済み |
| 動画クラウドアップロード | ⏳ 未実装 |
| PDF OCR（スキャンPDF） | ⏳ 未実装 |

## 2. 画面構成

```text
TabView
├── 日記 (DiaryListView)
│   ├── Detail: DiaryDetailView
│   │   └── 編集Sheet: DiaryEditorView
│   └── 新規Sheet: DiaryEditorView
├── インポート (ImportView)
├── 書籍化 (BookPreviewView)
└── プラン (PlanView)

Share Extension
└── ShareViewController
    └── App Group queue に保存 → diarybook://import で本体起動
```

## 3. ディレクトリ構成

```text
diary_app/
├── project.yml
├── docs/
│   ├── TODO.md
│   ├── structure.md
│   └── dependency_mapping.md
├── Shared/
│   └── ShareTransfer.swift
├── ShareExtension/
│   ├── ShareViewController.swift
│   ├── Info.plist
│   └── ShareExtension.entitlements
└── DiaryApp/
    ├── DiaryApp.swift
    ├── Info.plist
    ├── DiaryApp.entitlements
    ├── Products.storekit
    ├── Models/
    │   ├── DiaryEntry.swift
    │   ├── MediaAttachment.swift
    │   ├── UserPlan.swift
    │   └── BookLayoutConfig.swift
    ├── Storage/
    │   └── DiaryStore.swift
    ├── Import/
    │   ├── ImportManager.swift
    │   ├── JSONImporter.swift
    │   ├── CSVImporter.swift
    │   ├── ZIPImporter.swift
    │   ├── PDFImporter.swift
    │   └── TextImporter.swift
    ├── Purchases/
    │   └── PurchaseManager.swift
    └── Views/
        ├── AdaptiveLayout.swift
        ├── ContentView.swift
        ├── DiaryList/DiaryListView.swift
        ├── DiaryDetail/{DiaryDetailView.swift, QRCodeView.swift}
        ├── DiaryEditor/DiaryEditorView.swift
        ├── Import/ImportView.swift
        ├── BookPreview/BookPreviewView.swift
        └── Settings/PlanView.swift
```












## 4. モデル要点

```swift
DiaryEntry {
  id: UUID
  date: Date
  title: String
  body: String
  photos: [PhotoAttachment]      // media/<uuid>.jpg
  videos: [VideoAttachment]      // media/<uuid>.mov / remoteURL
  sourceApp: String              // manual / json_import / ... / share_extension
  metadata: [String: String]
  createdAt: Date
  updatedAt: Date
}
```

永続化:
- エントリ: `Documents/diary_entries.json`（ISO 8601）
- 書籍設定: `Documents/book_config.json`
- メディア: `Documents/media/`
  - `DiaryStore` で `.isExcludedFromBackup` を付与
  - 起動時に孤立メディアをクリーンアップ

## 5. 主要フロー

### 5.1 日記作成・編集

`DiaryEditorView` → `DiaryStore.addEntry/updateEntry` → JSON保存 → 一覧再描画

### 5.2 インポート

`ImportView` → `ImportManager` → 各Importer → `[DiaryEntry]` → `DiaryStore.importEntries`

### 5.3 Share Extension

`ShareViewController` → `ShareQueueStore.append` → `diarybook://import` → `ContentView.onOpenURL/.task` → `DiaryStore.importQueuedSharedEntriesIfNeeded`

### 5.4 書籍化・PDF

`BookPreviewView` が `BookLayoutConfig` と `DiaryStore` を参照してプレビュー表示。  
`exportPDF()` で A4 PDF を生成し共有シートへ渡す。

## 6. セットアップ

```bash
cd /Users/kondogenki/diary_app
brew install xcodegen   # 未導入時のみ
xcodegen generate
open DiaryApp.xcodeproj
```

ローカル課金テスト:
- Xcode > Edit Scheme > Run > Options
- StoreKit Configuration に `DiaryApp/Products.storekit` を指定

## 7. 補足

- ZIPFoundation は `project.yml` の SPM 依存で有効化済み。
- バンドルID/App Group は `com.yourapp...` のプレースホルダ。リリース前に実IDへ差し替え必須。





このリポジトリの全体は `diary_app/` 配下にまとまっています。

`project.yml` は Xcodegen 用の設定ファイルです。

`docs/` はドキュメント置き場で、`TODO.md`、`structure.md`、`dependency_mapping.md` が入っています。

`Shared/` は共有コード置き場で、`ShareTransfer.swift` が入っています（Share Extension と本体の受け渡し用）。

`ShareExtension/` は Share Extension 本体で、`ShareViewController.swift` と `Info.plist`、`ShareExtension.entitlements` が入っています。

`DiaryApp/` はアプリ本体で、`DiaryApp.swift` と `Info.plist`、`DiaryApp.entitlements`、`Products.storekit` に加えて、主要ロジックやUIは次のサブフォルダに分かれています。

`DiaryApp/Models/` はデータモデル（例: `DiaryEntry`、`MediaAttachment`、`UserPlan`）です。

`DiaryApp/Storage/` は永続化（例: `DiaryStore.swift`）です。

`DiaryApp/Import/` はインポート処理（例: `ImportManager` と各Importer）です。

`DiaryApp/Purchases/` は課金まわり（例: `PurchaseManager.swift`）です。

`DiaryApp/Views/` は SwiftUI の画面群で、`ContentView`、日記一覧/詳細/編集、`ImportView`、`BookPreviewView`、`PlanView` などがここにあります。
