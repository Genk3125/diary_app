# DiaryBook — モジュール依存関係マップ（現行実装）

変更時の影響範囲を素早く把握するための依存マップです。

## 1. 依存グラフ（矢印 = 依存方向）

```text
DiaryApp.swift
  └─ ContentView
      ├─ DiaryListView
      │   └─ DiaryDetailView
      │       └─ DiaryEditorView
      ├─ ImportView
      ├─ BookPreviewView
      └─ PlanView

All Views
  └─ @EnvironmentObject DiaryStore
      ├─ PurchaseManager
      ├─ ImportManager
      │   ├─ JSONImporter
      │   ├─ CSVImporter
      │   ├─ ZIPImporter
      │   │   ├─ JSONImporter
      │   │   └─ CSVImporter
      │   ├─ PDFImporter
      │   └─ TextImporter
      └─ Models
          ├─ DiaryEntry
          ├─ PhotoAttachment
          ├─ VideoAttachment
          ├─ UserPlan
          └─ BookLayoutConfig

ShareViewController (ShareExtension)
  └─ Shared/ShareTransfer.swift (ShareQueueStore)
      └─ ContentView.onOpenURL/.task
          └─ DiaryStore.importQueuedSharedEntriesIfNeeded()
```

## 2. レイヤー別責務

| レイヤー | ファイル | 責務 |
|---|---|---|
| Entry point | `DiaryApp/DiaryApp.swift` | アプリ起動 |
| Root view | `DiaryApp/Views/ContentView.swift` | TabView、`DiaryStore` 注入、共有URL受信 |
| Layout helper | `DiaryApp/Views/AdaptiveLayout.swift` | iPad/横幅向けの `regularWidthContent` 制約 |
| Diary UI | `DiaryApp/Views/DiaryList/DiaryListView.swift` | 一覧、検索、絞り込み、遷移 |
| Diary UI | `DiaryApp/Views/DiaryDetail/DiaryDetailView.swift` | 詳細表示、動画再生、編集/削除 |
| Diary UI | `DiaryApp/Views/DiaryEditor/DiaryEditorView.swift` | 作成/編集、写真動画添付、上限判定 |
| Import UI | `DiaryApp/Views/Import/ImportView.swift` | ファイル/テキスト取り込みUI |
| Book UI | `DiaryApp/Views/BookPreview/BookPreviewView.swift` | プレビュー、PDF生成/共有 |
| Plan UI | `DiaryApp/Views/Settings/PlanView.swift` | プラン表示、購入、復元、書籍設定編集 |
| Storage | `DiaryApp/Storage/DiaryStore.swift` | JSON保存、メディア保存、設定保存、共有キュー取り込み、バックアップ除外、孤立メディア掃除 |
| Purchase | `DiaryApp/Purchases/PurchaseManager.swift` | StoreKit 2 商品取得・購入・復元・購読状態更新 |
| Import routing | `DiaryApp/Import/ImportManager.swift` | 拡張子/入力種別に応じた importer 振り分け |
| Import impl | `DiaryApp/Import/*.swift` | JSON/CSV/ZIP/PDF/Text のパース |
| Shared transfer | `Shared/ShareTransfer.swift` | App Group queue と共有画像ステージング |
| Share extension | `ShareExtension/ShareViewController.swift` | 共有データ正規化、queue保存、本体起動 |

## 3. 変更時の差し込みポイント

| やりたいこと | 変更箇所 |
|---|---|
| 新しい取込形式を追加 | `ImportManager.swift` にcase追加 + `Import/XxxImporter.swift` 追加 |
| Share受け取り項目を増やす | `ShareViewController.swift`, `ShareTransfer.swift`, `ImportManager.importSharePayloads` |
| プラン上限を変更 | `Models/UserPlan.swift`, 必要に応じて `PlanView.swift` |
| 書籍レイアウト項目を増やす | `Models/BookLayoutConfig.swift`, `PlanView.swift`, `BookPreviewView.swift`, `DiaryStore.saveConfig/loadConfig` |
| 動画アップロード実装 | `DiaryStore.saveVideoFile` 後段 + `VideoAttachment` 更新 |
| クラウド同期へ移行 | `DiaryStore.loadEntries/saveEntries/deleteEntry/importEntries` の保存層差し替え |

## 4. 主要データフロー

### 4.1 日記作成・更新

```text
DiaryEditorView
  -> DiaryStore.addEntry / updateEntry
  -> diary_entries.json 保存
  -> @Published entries 更新
  -> DiaryListView / BookPreviewView 再描画
```

### 4.2 ファイル/テキスト取り込み

```text
ImportView
  -> ImportManager.importFile / importText
  -> 各Importerで [DiaryEntry]
  -> DiaryStore.importEntries
  -> diary_entries.json 保存
```

### 4.3 Share Extension 取り込み

```text
ShareViewController
  -> ShareQueueStore.append
  -> diarybook://import
  -> ContentView.onOpenURL or .task
  -> DiaryStore.importQueuedSharedEntriesIfNeeded
  -> ImportManager.importSharePayloads
  -> DiaryStore.importEntries
```

### 4.4 書籍化とPDF

```text
DiaryStore.entries + BookLayoutConfig
  -> BookPreviewView（並び替え・グルーピング・上限適用）
  -> exportPDF()（A4描画）
  -> ShareSheet
```
