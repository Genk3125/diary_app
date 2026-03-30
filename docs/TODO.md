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
| 書籍レイアウト設定の編集・保存（タイトル / 並び順 / グループ / 反映数） | `PlanView` / `DiaryStore` / `BookPreviewView` |
| QR コード生成・表示（CoreImage） | `QRCodeView` → `DiaryDetailView` |
| StoreKit 2 課金ゲート | `PurchaseManager` → `DiaryStore` → `PlanView` |
| Share Extension（テキスト / URL / 画像 → App Group queue → 本体取り込み） | `ShareViewController` / `ShareTransfer.swift` / `ContentView` / `DiaryStore` |

### ⚠️ 実装済みだが設定が必要なもの（コードは書いた、外部設定が未）

| 機能 | 何が足りないか |
|---|---|
| StoreKit 2 本番購入 | App Store Connect で Product ID 登録が必要（後述） |

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

### ✅ B. Share Extension 受け取りフロー

**対応内容：**
1. Share Extension でテキスト / URL / 画像を `SharePayload` に正規化し、App Group queue に保存
2. `diarybook://import` で本体アプリを起動
3. 本体アプリは起動時と URL 受信時に queue を読み、`ImportManager` で `DiaryEntry` に変換して `DiaryStore.importEntries()` に流す
4. 画像は App Group の一時領域から本体アプリの `Documents/media/` へ移動して `PhotoAttachment` 化

**関連ファイル：**
- `Shared/ShareTransfer.swift`
- `ShareExtension/ShareViewController.swift`
- `DiaryApp/Views/ContentView.swift`
- `DiaryApp/Storage/DiaryStore.swift`
- `DiaryApp/Import/ImportManager.swift`

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
| 書籍 PDF のレイアウト強化 | 現状の PDF は基本レイアウトのみ。表紙デザイン、余白、フォントなどの調整余地がある | `BookPreviewView.swift` / `BookLayoutConfig.swift` |
| 検索・フィルター | 日付・キーワードで絞り込み。`DiaryListView` に検索バー追加 | `DiaryListView.swift` |
| iPad 対応 | `project.yml` の `TARGETED_DEVICE_FAMILY: "1"` → `"1,2"` + レイアウト調整 | `project.yml` |
| iCloud Backup 除外 | `Documents/media/` は大容量になるため `.isExcludedFromBackupKey` を設定 | `DiaryStore.setupDirectories()` |

---

## 6. 技術的負債

| 項目 | 影響 | 対処 |
|---|---|---|
| `@Published entries` の全画面再描画 | エントリ数が多いと重くなる | `id` ベースの差分更新に変更 |
| 孤立メディアファイル | エントリ削除時に漏れた場合ストレージが増え続ける | 起動時に `diary_entries.json` と `media/` を突合して孤立ファイルを削除 |
| `BookLayoutConfig` の高度設定不足 | タイトル・並び順・反映数は編集できるが、ページサイズやフォントなどは未対応 | `BookLayoutConfig.swift` / `PlanView.swift` / `BookPreviewView.swift` |
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
| Share Extension の受け取り処理 | `ShareViewController.swift` / `ShareTransfer.swift` / `ContentView.swift` |
| 書籍化レイアウト | `BookPreviewView.swift` / `BookLayoutConfig.swift` |
| データモデル変更 | `DiaryEntry.swift` / `MediaAttachment.swift`（Codable なので移行注意） |

---

## 9. 最近のエラーと対処メモ

### 9-1. PlanView の `Section` で型推論が崩れる

**症状:**
- `PlanView.swift` の `Section("書籍化設定") { ... }` で SwiftUI のオーバーロード解決に失敗
- 代表的なエラー:
  - `missing argument label 'content:' in call`
  - `cannot convert value of type 'String' to expected argument type '() -> Content'`
  - `generic parameter 'Content' could not be inferred`

**原因:**
- `PlanView` の構成次第で `Section("...") { ... }` の省略形だと型解決が不安定になることがあった

**対処:**
- 文字列ヘッダの省略形を避け、明示形に統一する

```swift
Section {
    ...
} header: {
    Text("書籍化設定")
} footer: {
    ...
}
```

**補足:**
- `maxPhotosPerEntry` / `maxVideosPerEntry` の Picker は、保存済み override が現在の plan 上限を超えていても UI が壊れないよう、表示値だけ正規化する Binding にしてある

### 9-2. Share Extension は queue 保存失敗時に本体を起動しない

**症状:**
- App Group queue への保存に失敗しても `diarybook://import` で本体アプリを起動してしまう経路があった
- その結果、共有データは取り込まれないのにアプリだけ開く
- 画像共有時は stage 済みファイルが残る可能性があった

**対処:**
- queue 保存が失敗した場合は本体アプリを起動しない
- stage 済み画像を削除してから Extension を終了する

### 9-3. `share_extension` を UI 表示ラベルへ変換する

**症状:**
- `sourceApp = "share_extension"` を追加したあと、一覧画面と書籍化プレビューのラベル変換が未更新だった
- UI 上で内部値の `share_extension` がそのまま見えていた

**対処:**
- `share_extension` を正式な入力元として扱い、一覧表示・書籍化表示・関連ドキュメントの表記をそろえる

### 9-4. 署名エラー

**症状:**
- `Signing for "DiaryApp" requires a development team.`
- `Signing for "ShareExtension" requires a development team.`

**原因:**
- `DiaryApp` / `ShareExtension` の Signing 設定に Development Team が未設定

**対処:**
- Xcode の `Signing & Capabilities` で Development Team を設定する
- 純粋なコンパイル確認だけなら署名を無効化してビルドする

```bash
xcodebuild -project DiaryApp.xcodeproj -scheme DiaryApp -configuration Debug \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
```

### 9-5. Share Extension 側で共有型が見つからない一時エラー

**症状:**
- `cannot find 'ShareQueueStore' in scope`
- `cannot find type 'ShareItem' in scope`

**発生箇所:**
- `ShareExtension/ShareViewController.swift`

**原因候補:**
- `Shared/ShareTransfer.swift` を `ShareExtension` ターゲットが正しく参照できていない

**対処:**
- `Shared/ShareTransfer.swift` が `DiaryApp` と `ShareExtension` の両ターゲットに含まれていることを確認する
- `project.yml` の `sources` に `Shared` が含まれている状態を維持する
- ターゲット設定が怪しい場合は `xcodegen generate` で `DiaryApp.xcodeproj` を再生成する

**今回の確定原因:**
- `project.yml` には `Shared` が含まれていたが、生成済みの `DiaryApp.xcodeproj` が古く、`ShareTransfer.swift` が `ShareExtension` ターゲットに入っていなかった

**今回の解決:**
- `xcodegen generate` を実行して `.xcodeproj` を再生成
- 再生成後、`ShareTransfer.swift in Sources` が `DiaryApp` / `ShareExtension` の両方に入ったことを確認
- その後の署名無効ビルドでコンパイル成功を確認

### 9-6. ビルド確認メモ

- Share 対応の検証を通すため、`PlanView` の `Section` 初期化もあわせて修正が必要だった
- `xcodegen generate` 後、一時 build directory を使った `xcodebuild` で `DiaryApp` target のビルド成功を確認済み
- 検索・絞り込み追加自体に起因するコンパイルエラーは確認されていない
