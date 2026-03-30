# DiaryBook — プロジェクト全体文脈 & 残作業

> **エージェント向け引き継ぎ文書。**
> このファイルを読めば、何を作っているか・今どこまで動いているか・次に何をすべきかがわかる。
> コードの詳細は `docs/structure.md`、モジュール依存は `docs/dependency_mapping.md` を参照。

---

## 1. 何を作っているか

**DiaryBook** は iOS 向けの日記アプリ。主な特徴：

- 日記を書いて写真・動画を添付し、**「書籍」として PDF 化・印刷**できる
- 動画は印刷できないため、**QR コードに変換**して紙の本に埋め込む設計
- 他アプリのデータ（JSON / CSV / ZIP / PDF / テキスト）を**インポート**して日記に変換できる
- Free / Pro の**サブスクリプションプラン**で添付枚数に差をつける

**開発方針（重要）：**
- 認証・DBなどのバックエンド設計は意図的に後回し。デバッグが複雑になるため。
- 「動くことを最優先」。過剰な抽象化禁止。
- `@MainActor DiaryStore` を `@EnvironmentObject` として全 View に流す。単一 SourceOfTruth。

---

## 2. 技術スタック

| 項目 | 内容 |
|---|---|
| 言語 | Swift 5.9 / SwiftUI |
| 最小 iOS | 17.0 |
| プロジェクト管理 | xcodegen (`brew install xcodegen && xcodegen generate`) |
| 外部ライブラリ | ZipFoundation 0.9.20（SPM） |
| 課金 | StoreKit 2 |
| 永続化（現状） | `Documents/diary_entries.json`（JSON、ISO 8601） |
| 永続化（将来） | CloudKit or Supabase（未着手） |
| メディア保存 | `Documents/media/<UUID>.<ext>` |

---

## 3. 現在の実装状況

### ✅ 動いているもの

| 機能 | 実装場所 |
|---|---|
| 日記 CRUD・一覧・詳細・編集 | `DiaryListView` / `DiaryDetailView` / `DiaryEditorView` |
| 写真添付（PhotosPicker、プラン上限付き） | `DiaryEditorView` |
| 動画添付・再生（AVKit） | `DiaryEditorView` / `VideoPlayerSheet` |
| JSON / CSV / テキスト インポート | `ImportManager` → 各 Importer |
| ZIP インポート（ZipFoundation で展開） | `ZIPImporter` |
| PDF インポート（PDFKit テキスト抽出） | `PDFImporter` |
| 書籍化プレビュー（月・年グループ） | `BookPreviewView` |
| PDF 書き出し（UIGraphicsPDFRenderer） | `BookPreviewView` |
| QR コード生成・表示（CoreImage） | `QRCodeView` → `DiaryDetailView` |
| StoreKit 2 課金ゲート | `PurchaseManager` → `DiaryStore` → `PlanView` |
| Share Extension（UI） | `ShareViewController` |

### ⚠️ 実装済みだが設定が必要なもの（コードは書いた、外部設定が未）

| 機能 | 何が足りないか |
|---|---|
| StoreKit 2 本番購入 | App Store Connect で Product ID 登録が必要（後述） |
| Share Extension データ転送 | App Group capability の設定が必要（後述） |

---

## 4. 次にやること（優先順）

### 🔴 A. StoreKit 2 本番設定

**背景：** `PurchaseManager.swift` と `Products.storekit`（ローカルテスト用定義）は実装済み。
Product ID `com.yourapp.diaryapp.pro.monthly` はコード内で使用済み。
この ID を App Store Connect で登録すれば、実機・TestFlight で課金が動く。

**手順：**
1. App Store Connect でアプリを登録（Bundle ID: `com.yourapp.diaryapp`）
2. 「サブスクリプション」→ 新規グループ作成: `group.diarybook.subscription`
3. サブスクリプション商品を追加:
   - Product ID: `com.yourapp.diaryapp.pro.monthly`
   - 期間: 月次
   - 価格: 任意（¥600 など）
4. `project.yml` の `com.yourapp` を実際の Bundle ID prefix に変更 → `xcodegen generate`
5. **ローカルテスト時:** Xcode > Edit Scheme > Run > Options > StoreKit Configuration → `DiaryApp/Products.storekit` を選択

**関連ファイル：**
- `DiaryApp/Purchases/PurchaseManager.swift` — StoreKit 2 本体
- `DiaryApp/Products.storekit` — ローカルサンドボックス定義
- `DiaryApp/Storage/DiaryStore.swift` — `purchaseManager.$isProActive` を Combine で購読して `currentPlan` を更新
- `DiaryApp/Views/Settings/PlanView.swift` — 購入 UI

---

### 🔴 B. Share Extension — App Group 設定

**背景：** `ShareExtension/ShareViewController.swift` は UI まで実装済み。
ユーザーが他アプリでテキスト・URL・画像を共有すると「DiaryBook に保存」がシートに出る。
ただし、Extension → 本体アプリへのデータ転送部分がコメントアウト。
iOS の sandbox 制約で、App Group なしに Extension と本体アプリはファイルを共有できない。

**手順：**
1. Xcode > DiaryApp ターゲット > Signing & Capabilities > + Capability > **App Groups**
   - グループ ID: `group.com.yourapp.diaryapp`
2. 同様に ShareExtension ターゲットにも同じ App Group を追加
3. `ShareViewController.swift` のコメントを外す（2箇所）:
   ```swift
   // TODO: App Group capability を有効化後にコメントを外す
   if let container = FileManager.default
       .containerURL(forSecurityApplicationGroupIdentifier: groupID) { ... }
   ```
   ```swift
   // TODO: URL scheme 登録後にコメントを外す
   extensionContext?.open(URL(string: "diarybook://import")!, completionHandler: nil)
   ```
4. `DiaryApp.swift`（または `ContentView`）の `onOpenURL` で `diarybook://import` を受け取り、
   App Group キューファイルを読んで `store.importEntries()` を呼ぶ処理を追加

**関連ファイル：**
- `ShareExtension/ShareViewController.swift` — Extension 本体。`groupID = "group.com.yourapp.diaryapp"` が定義済み
- `DiaryApp/DiaryApp.swift` — URL scheme ハンドラ追加先
- `project.yml` — URL scheme `diarybook://` は登録済み

---

### 🟡 C. 認証・アカウント管理（意図的に後回し）

**背景：** 現状はデバイス内ローカル保存のみ。マルチデバイス同期・バックアップには Auth が必要だが、
早期に導入するとデバッグが複雑になるため、ローカル動作が安定してから着手する方針。

**選択肢（未決定）：**
- **Sign in with Apple** — App Store 審査で必須になる可能性あり（ソーシャルログインを実装する場合）
- **Supabase Auth** — メール / OAuth 対応、後述の DB と同一サービスで統一できる
- **Firebase Auth** — 実績多いが Google 依存

**着手時の影響範囲：**
- `DiaryStore` の init / save / load を認証済みユーザー ID ベースに変更
- メディアファイルの保存先もユーザー別に変更

---

### 🟡 D. データベース・クラウド同期（意図的に後回し）

**背景：** 現状は `Documents/diary_entries.json` に全エントリをまとめて書き込む。
エントリが増えると読み書き全件になる点と、マルチデバイス同期がない点が課題。

**選択肢（未決定）：**
- **CloudKit** — Apple IDだけで動く。Sign in with Apple と相性◎。ただし Android/Web 非対応
- **Supabase** — PostgreSQL ベース。RLS で行レベル認証。Auth と DB を統一できる

**着手時の変更点：**
```
DiaryStore.saveEntries()   → Supabase INSERT / CloudKit record save
DiaryStore.loadEntries()   → Supabase SELECT / CloudKit fetch
DiaryStore.deleteEntry()   → Supabase DELETE / CloudKit delete
DiaryStore.importEntries() → バルク upsert（conflict on id → skip）
```

---

### 🟡 E. 動画クラウドアップロード

**背景：** 動画はローカル `Documents/media/*.mov` に保存されている。
`VideoAttachment` には `hostedAssetID` / `remoteURL` フィールドがあり、
クラウドにアップロードされれば `qrCodeTarget` に URL が入り、QR コードが自動生成される（実装済み）。
アップロードさえ実装すれば QR コードが印刷物に反映される。

**実装場所：** `DiaryStore.saveVideoFile()` の後にアップロード処理を追加し、
成功したら `VideoAttachment.remoteURL` を書き戻して `DiaryStore.updateEntry()` を呼ぶ。

---

## 5. 品質・UX の残作業

| 項目 | 概要 | 関連ファイル |
|---|---|---|
| ZIP 内画像の添付 | 現状 JSON/CSV のみ抽出。画像も読んで `PhotoAttachment` に変換する | `ZIPImporter.scanDirectory()` |
| PDF OCR 対応 | スキャン画像 PDF はテキスト抽出不可。Vision で OCR を追加 | `PDFImporter.swift` |
| 書籍化 → 実 PDF 出力 | `BookPreviewView` はプレビューのみ。`UIGraphicsPDFRenderer` で実際に PDF を生成する処理が未実装 | `BookPreviewView.swift` |
| ImportView の文言更新 | Share Extension 完成後に「今後の予定」セクションを「対応済み」に変更 | `ImportView.swift` |
| 検索・フィルター | 日付・キーワードで絞り込み。`DiaryListView` に検索バー追加 | `DiaryListView.swift` |
| iPad 対応 | `project.yml` の `TARGETED_DEVICE_FAMILY: "1"` → `"1,2"` + レイアウト調整 | `project.yml` |
| iCloud Backup 除外 | `Documents/media/` は大容量になるため `.isExcludedFromBackupKey` を設定 | `DiaryStore.setupDirectories()` |

---

## 6. 技術的負債

| 項目 | 影響 | 対処 |
|---|---|---|
| `@Published entries` の全画面再描画 | エントリ数が多いと重くなる | `id` ベースの差分更新に変更 |
| 孤立メディアファイル | エントリ削除時に漏れた場合ストレージが増え続ける | 起動時に `diary_entries.json` と `media/` を突合して孤立ファイルを削除 |
| `BookLayoutConfig` 設定 UI なし | DiaryStore が持っているが、ユーザーが変更する画面がない | `PlanView` に設定セクション追加 or 専用 `SettingsView` を作成 |
| `DiaryStore.currentPlan` は `private(set)` | テスト・デバッグ時に外部から plan を変えられない | デバッグ用の `setplan(_:)` メソッドを `#if DEBUG` で追加 |

---

## 7. セットアップ手順（新しい環境での再現）

```bash
# 1. リポジトリ取得後
cd /Users/kondogenki/diary_app

# 2. xcodegen インストール（初回のみ）
brew install xcodegen

# 3. プロジェクト生成
xcodegen generate

# 4. Xcode で開く（SPM パッケージは Xcode が自動解決する）
open DiaryApp.xcodeproj

# 5. ビルド対象を iPhone Simulator（iOS 17+）に設定してビルド
# ⚠️ xcodebuild CLI は SPM パッケージを -target 指定だと解決できないため、Xcode GUI からビルド推奨
```

**StoreKit ローカルテスト有効化（ローカルで課金フローを試す場合）：**
Xcode > Product > Scheme > Edit Scheme > Run > Options タブ
→ StoreKit Configuration: `DiaryApp/Products.storekit` を選択

---

## 8. ファイル早引き（どこを触ればよいか）

| やりたいこと | 触るファイル |
|---|---|
| 日記の保存・読み込みロジック変更 | `DiaryStore.swift` |
| プラン上限の変更 | `UserPlan.swift` |
| 新しいインポート形式を追加 | `ImportManager.swift` に case 追加 + `XxxImporter.swift` 新規作成 |
| 課金・プラン購入フロー | `PurchaseManager.swift` / `PlanView.swift` |
| QR コードの見た目変更 | `QRCodeView.swift` |
| Share Extension の受け取り処理 | `ShareViewController.swift` |
| 書籍化レイアウト | `BookPreviewView.swift` / `BookLayoutConfig.swift` |
| データモデル変更 | `DiaryEntry.swift` / `MediaAttachment.swift`（Codable なので移行注意） |
