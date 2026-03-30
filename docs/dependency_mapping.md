# DiaryBook — モジュール依存関係マップ

> 変更時の影響範囲確認・新機能追加時の差し込み先判断に使ってください。

---

## 依存グラフ（矢印 = 依存方向）

```
DiaryApp.swift
    └── ContentView
            ├── DiaryListView
            │       ├── DiaryDetailView
            │       │       └── DiaryEditorView ─────────────────┐
            │       └── DiaryEditorView                          │
            ├── ImportView                                        │
            │       └── ImportManager                            │
            │               ├── JSONImporter                     │
            │               ├── CSVImporter                      │
            │               ├── ZIPImporter                      │
            │               │       ├── JSONImporter             │
            │               │       └── CSVImporter              │
            │               └── TextImporter                     │
            └── BookPreviewView                                   │
                                                                  │
All Views ──────────────────── @EnvironmentObject ──► DiaryStore ┘
                                                        │
                                                   Models/
                                                   DiaryEntry
                                                   PhotoAttachment
                                                   VideoAttachment
                                                   UserPlan
                                                   BookLayoutConfig
```

---

## レイヤー別責務

| レイヤー | ファイル | 責務 |
|---|---|---|
| **Entry point** | `DiaryApp.swift` | App, WindowGroup |
| **View / Root** | `ContentView.swift` | TabView, DiaryStore 生成 |
| **View / List** | `DiaryListView.swift` | 一覧表示、スワイプ削除 |
| **View / Detail** | `DiaryDetailView.swift` | 詳細表示（写真グリッド、動画QR枠） |
| **View / Editor** | `DiaryEditorView.swift` | 作成・編集、PhotosPicker、プラン上限チェック |
| **View / Import** | `ImportView.swift` | ファイル選択・テキスト貼り付け UI |
| **View / Book** | `BookPreviewView.swift` | 印刷プレビュー、グループ化、制限警告 |
| **Storage** | `DiaryStore.swift` | JSON 読み書き、メディアファイル管理、プラン参照 |
| **Import** | `ImportManager.swift` | 拡張子 → インポーター ルーティング |
| **Import** | `JSONImporter.swift` | JSON → `[DiaryEntry]` |
| **Import** | `CSVImporter.swift` | CSV → `[DiaryEntry]` |
| **Import** | `ZIPImporter.swift` | ZIP 展開（スタブ）→ JSON/CSV 再帰パース |
| **Import** | `TextImporter.swift` | テキスト → `[DiaryEntry]`（日付行で分割） |
| **Model** | `DiaryEntry.swift` | コアモデル（Codable） |
| **Model** | `MediaAttachment.swift` | `PhotoAttachment` / `VideoAttachment` |
| **Model** | `UserPlan.swift` | プラン enum、上限値定義 |
| **Model** | `BookLayoutConfig.swift` | 書籍レイアウト設定 |

---

## 拡張ポイント一覧

| 機能 | 差し込み場所 |
|---|---|
| 新しいインポート形式 | `ImportManager.swift` に case 追加 + `XxxImporter.swift` 追加 |
| ZIP 実装 | `ZIPImporter.swift` のスタブを ZipFoundation で置き換え |
| PDF インポート | `ImportManager.swift` の `.pdf` ケース + `PDFImporter.swift` |
| 共有シート受け取り | Share Extension target 追加 → `ImportManager.importFile(at:)` 呼び出し |
| StoreKit 課金 | `UserPlan` を StoreKit Product に紐付け、`DiaryStore.currentPlan` を更新 |
| CloudKit 同期 | `DiaryStore` の `saveEntries` / `loadEntries` を CloudKit 実装に差し替え |
| 動画クラウドアップロード | `VideoAttachment.hostedAssetID` / `remoteURL` を書き戻す処理を追加 |
| QR コード生成 | `VideoAttachment.qrCodeTarget` を `CoreImage.CIFilter.qrCodeGenerator` へ渡す |
| PDF 書き出し | `BookPreviewView` のレイアウトを `UIGraphicsPDFRenderer` でレンダリング |
| 印刷上限の個別設定 | `BookLayoutConfig.maxPhotosPerEntry` を非 nil にして `DiaryStore` 経由で渡す |

---

## 主要データフロー

### 日記作成
```
User input
  → DiaryEditorView（バリデーション・プラン上限チェック）
    → DiaryStore.addEntry()
      → diary_entries.json に書き込み
      → media/ にメディアファイルを書き込み
        → DiaryListView が @Published entries を受信して再描画
```

### インポート
```
ファイル / テキスト
  → ImportView
    → ImportManager.importFile(at:) or importText(_:)
      → XxxImporter → [DiaryEntry]（sourceApp 付き）
        → DiaryStore.importEntries()（重複 id はスキップ）
          → diary_entries.json に書き込み
```

### 書籍化プレビュー
```
DiaryStore.entries
  → BookPreviewView（ソート・グループ化）
    → BookEntryRow（プラン上限を適用して写真数・動画QR枠を描画）
      → TODO: PDFRenderer に渡して書き出し
```
