# DiaryBook — リリース前最終整理（2026-03-30）

このドキュメントは、現在の実装を基準に「次に何をやれば出せるか」を明確にするための実行メモです。  
参照済み: `project.yml` / `docs/structure.md` / `docs/dependency_mapping.md` / ソース一式。

## 1. 現在地サマリー

- アプリ本体・Share Extension を含めて **シミュレータ向けビルド成功**。
- コア機能（CRUD、添付、各種インポート、書籍プレビュー、PDF出力、StoreKit 2 課金導線）は実装済み。
- リリースに向けた主要な未完は、**外部設定（Bundle ID / App Group / App Store Connect）** と **最終QA**。

### 1.1 実機ビルド / Share Extension 受け渡し確認結果（2026-03-30）

#### 確認済み

- `project.yml` を更新し、署名・識別子を共通変数化
  - `CODE_SIGN_STYLE: Automatic`
  - `DIARY_BUNDLE_ID_PREFIX`
  - `DIARY_APP_GROUP_IDENTIFIER`
  - `DIARY_SHARE_URL_SCHEME`
- `DiaryApp` / `ShareExtension` 両 target に `Application Groups` capability 属性を付与（`xcodegen generate` 後の `project.pbxproj` 反映確認済み）
- 両 entitlements を `$(DIARY_APP_GROUP_IDENTIFIER)` 参照へ変更
- `Shared/ShareTransfer.swift` を Info.plist 読み取り方式に変更（App Group / URL scheme のハードコード除去）
- `ContentView` の `onOpenURL` 判定が `ShareTransferConfig.urlScheme` を参照することを確認
- ビルド確認:
  - `xcodebuild -project DiaryApp.xcodeproj -scheme DiaryApp -destination 'generic/platform=iOS Simulator' -derivedDataPath build/DerivedData-Sim build` 成功
  - `xcodebuild -project DiaryApp.xcodeproj -scheme DiaryApp -destination 'generic/platform=iOS' build CODE_SIGNING_ALLOWED=NO` 成功

#### 未確認

- Development Team 設定済み状態での実機インストールと起動
- 実機共有シートからの Text / URL / Image の 3 経路での end-to-end 受け渡し
- Share Extension 保存後に本体アプリへ戻り、`DiaryEntry` と添付画像が作成されることの実機目視

#### 手動確認が必要

- `xcodebuild -project DiaryApp.xcodeproj -scheme DiaryApp -destination 'generic/platform=iOS' build` は以下で失敗:
  - `Signing for "DiaryApp" requires a development team`
  - `Signing for "ShareExtension" requires a development team`
- この環境では `security find-identity -v -p codesigning` が `0 valid identities found` のため、Apple ID / Team / 証明書のローカル設定が未完了

#### 実機確認の最短手順（Xcode）

1. `DiaryApp.xcodeproj` を開く。
2. `DiaryApp` と `ShareExtension` の Signing & Capabilities で同一 Team を選択し、`Automatically manage signing` を ON にする。
3. 必要に応じて Build Settings の以下を実値へ変更する。
   - `DIARY_BUNDLE_ID_PREFIX`
   - `DIARY_SHARE_URL_SCHEME`
   - `DIARY_APP_GROUP_IDENTIFIER`（通常は `group.$(DIARY_BUNDLE_ID_PREFIX).diaryapp` のままで可）
4. Apple Developer portal で App ID（本体/Extension）に同一 App Group を紐付ける。
5. 実機で `DiaryApp` を1回起動後、共有シートで Text / URL / Image をそれぞれ送信し、日記生成と画像添付を確認する。

#### 問題が残る場合の再現手順と原因候補

- 再現手順:
  1. Team 未設定状態で `xcodebuild -project DiaryApp.xcodeproj -scheme DiaryApp -destination 'generic/platform=iOS' build`
  2. 署名エラーで停止
- 原因候補:
  - Development Team 未設定
  - ローカル証明書未作成（Apple Development identity 不在）
  - Apple Developer 側で App Group が本体/Extension の両 App ID に未割当
  - `DIARY_*` 変数の実値と Apple Developer 側 Identifier 不一致

## 2. 実装ステータス（コード根拠付き）

### 2.1 完了済み

| 項目 | 実装箇所 |
|---|---|
| 日記 CRUD（作成・編集・削除・一覧・詳細） | `DiaryApp/Views/DiaryList/DiaryListView.swift`, `DiaryApp/Views/DiaryDetail/DiaryDetailView.swift`, `DiaryApp/Views/DiaryEditor/DiaryEditorView.swift`, `DiaryApp/Storage/DiaryStore.swift` |
| 一覧検索・絞り込み（タイトル/本文/source、sourceフィルタ、添付ありのみ、並び順、空状態） | `DiaryApp/Views/DiaryList/DiaryListView.swift` |
| 写真添付（プラン上限） | `DiaryApp/Views/DiaryEditor/DiaryEditorView.swift`, `DiaryApp/Models/UserPlan.swift` |
| 動画添付・再生（AVKit） | `DiaryApp/Views/DiaryEditor/DiaryEditorView.swift`, `DiaryApp/Views/DiaryDetail/DiaryDetailView.swift`, `DiaryApp/Storage/DiaryStore.swift` |
| JSON / CSV / ZIP / PDF / テキスト取り込み | `DiaryApp/Import/ImportManager.swift` + 各 Importer |
| Share Extension（テキスト / URL / 画像）→ App Group queue → 本体取り込み | `ShareExtension/ShareViewController.swift`, `Shared/ShareTransfer.swift`, `DiaryApp/Views/ContentView.swift`, `DiaryApp/Storage/DiaryStore.swift` |
| 書籍化プレビュー（並び順・グループ・反映上限） | `DiaryApp/Views/BookPreview/BookPreviewView.swift`, `DiaryApp/Models/BookLayoutConfig.swift`, `DiaryApp/Views/Settings/PlanView.swift` |
| PDF出力（A4描画 + 共有シート） | `DiaryApp/Views/BookPreview/BookPreviewView.swift` |
| 書籍PDFレイアウト改善（表紙/見出し/余白/画像配置/出典/警告） | `DiaryApp/Views/BookPreview/BookPreviewView.swift` |
| StoreKit 2 課金導線（商品取得・購入・復元・状態反映） | `DiaryApp/Purchases/PurchaseManager.swift`, `DiaryApp/Views/Settings/PlanView.swift`, `DiaryApp/Storage/DiaryStore.swift` |
| QRコード生成（動画URL/AssetID向け） | `DiaryApp/Views/DiaryDetail/QRCodeView.swift`, `DiaryApp/Models/MediaAttachment.swift` |
| iPad 対応（ターゲット追加 + 主要画面の横幅/Sheet調整） | `project.yml`, `DiaryApp/Views/AdaptiveLayout.swift`, `DiaryApp/Views/ContentView.swift`, `DiaryApp/Views/DiaryList/DiaryListView.swift`, `DiaryApp/Views/DiaryDetail/DiaryDetailView.swift`, `DiaryApp/Views/DiaryEditor/DiaryEditorView.swift`, `DiaryApp/Views/Import/ImportView.swift`, `DiaryApp/Views/BookPreview/BookPreviewView.swift`, `DiaryApp/Views/Settings/PlanView.swift` |
| `media/` のiCloudバックアップ除外・孤立ファイル整理 | `DiaryApp/Storage/DiaryStore.swift`（`applyBackupExclusion` / `cleanupOrphanedMediaFilesIfSafe`） |

### 2.2 未完（実装タスク）

| 優先 | 項目 | 現状 | 対応箇所 |
|---|---|---|---|
| P1 | 動画のクラウドアップロード | `VideoAttachment.remoteURL` / `hostedAssetID` は用意済みだが、アップロード処理なし | `DiaryApp/Storage/DiaryStore.swift`, `DiaryApp/Models/MediaAttachment.swift` |
| P1 | ZIP内画像の取り込み | ZIPはJSON/CSVのみ再帰取り込み | `DiaryApp/Import/ZIPImporter.swift` |
| P1 | PDF OCR | テキスト抽出のみ（スキャンPDF非対応） | `DiaryApp/Import/PDFImporter.swift` |
| P1 | 書籍化を任意タイミング起動に変更 | 現状は定期的に強制生成が走る挙動になっているが、ユーザーが明示的に「書籍を作る」操作をした時のみ生成する方式に変更する | `DiaryApp/Views/BookPreview/BookPreviewView.swift`, `DiaryApp/Models/BookLayoutConfig.swift` |
| P2 | iPad 実機 QA（未確認挙動の確認） | ターゲット追加と主要画面の崩れ対策は実装済み。実機で回転・マルチウィンドウ・共有シート表示を最終確認する | `DiaryApp/Views/ContentView.swift`, `DiaryApp/Views/DiaryList/DiaryListView.swift`, `DiaryApp/Views/DiaryDetail/DiaryDetailView.swift`, `DiaryApp/Views/DiaryEditor/DiaryEditorView.swift`, `DiaryApp/Views/Import/ImportView.swift`, `DiaryApp/Views/BookPreview/BookPreviewView.swift`, `DiaryApp/Views/Settings/PlanView.swift` |

### 2.3 外部設定待ち（コードはあるが環境設定が必要）

| 優先 | 項目 | 必要作業 | 関連箇所 |
|---|---|---|---|
| P0 | Bundle ID / App Group の実ID化 | `DIARY_BUNDLE_ID_PREFIX` と `DIARY_SHARE_URL_SCHEME` を実運用値に変更（`DIARY_APP_GROUP_IDENTIFIER` は既定で prefix から導出）。Apple Developer 側 Identifier と一致させる | `project.yml`, `DiaryApp/DiaryApp.entitlements`, `ShareExtension/ShareExtension.entitlements`, `DiaryApp/Info.plist`, `ShareExtension/Info.plist` |
| P0 | StoreKit本番商品設定 | App Store Connect で `com.yourapp.diaryapp.pro.monthly` を登録（または実IDに置換） | `DiaryApp/Purchases/PurchaseManager.swift`, `DiaryApp/Products.storekit` |
| P0 | Appアイコンアセット | `ASSETCATALOG_COMPILER_APPICON_NAME=AppIcon` 設定はあるが `.xcassets` がリポジトリに未配置 | Xcode Asset Catalog（新規追加） |

## 3. リリースまでの実行順（最短）

1. `project.yml` の `DIARY_BUNDLE_ID_PREFIX` / `DIARY_SHARE_URL_SCHEME` を実運用値へ変更（必要なら `DIARY_APP_GROUP_IDENTIFIER` を明示上書き）。
2. `xcodegen generate` を実行してプロジェクト再生成。
3. Apple Developer / App Store Connect 側で App ID, App Group, サブスクリプション商品を作成。
4. 実機で以下を通し確認: 新規作成、写真/動画添付、各種インポート、Share Extension 取り込み、PDF出力、購入/復元。
5. App icon / メタデータを埋め、Archive + TestFlight 配布。

## 4. リリース前最終チェックリスト

### 4.1 コード・ビルド

- [x] `xcodebuild` で `DiaryApp` スキームがビルド成功
- [x] Share Extension を含めてビルドされる
- [ ] 実運用 Bundle ID / App Group へ置換済み
- [ ] App icon (`AppIcon`) を配置済み

### 4.2 機能確認

- [ ] 日記 CRUD（本文なし/あり、編集、削除）
- [ ] 写真・動画添付の上限挙動（Free/Pro）
- [ ] JSON / CSV / ZIP / PDF / テキスト取り込み
- [ ] Share Extension からのテキスト・URL・画像取り込み
- [ ] 書籍プレビューの並び順・グループ・反映上限
- [ ] 書籍化が任意タイミング（ユーザー操作時のみ）で起動することの確認
- [ ] PDF出力と共有シート起動
- [ ] iPad 実機で回転（縦横）・マルチウィンドウ時の主要画面確認

### 4.3 課金・配布設定

- [ ] App Store Connect のサブスクリプション作成
- [ ] 実機サンドボックスで購入/復元確認
- [ ] TestFlight で課金導線確認

## 5. ビルド確認ログ（今回）

- 実行日: 2026-03-30
- 実行コマンド:

```bash
xcodebuild -project DiaryApp.xcodeproj -scheme DiaryApp -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.1' \
  -derivedDataPath build/DerivedData-iPadSupport \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build

xcodebuild -project DiaryApp.xcodeproj -scheme DiaryApp -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M5),OS=26.1' \
  -derivedDataPath build/DerivedData-iPadSupport \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build

xcodebuild -project DiaryApp.xcodeproj -scheme DiaryApp -configuration Debug \
  -destination 'generic/platform=iOS Simulator' build
```

- 結果: 上記3コマンドすべて `** BUILD SUCCEEDED **`
- 追加確認:
  - `xcodegen generate` 後の署名なし iOS ビルドでも `** BUILD SUCCEEDED **`
  - iPad 対応に伴って出ていた `All interface orientations must be supported unless the app requires full screen.` 警告は、`UISupportedInterfaceOrientations` / `UISupportedInterfaceOrientations~ipad` を追加して解消
  - リポジトリ直下の `build/` は生成物のため `.gitignore` で除外
- 未確認挙動（iPad）:
  - 実機での `Form` 入力時キーボード挙動
  - Stage Manager / Split View 時の `TabView` と各 `NavigationStack` の表示密度
  - `ShareSheet` / 動画再生シートの実機表示サイズ（シミュレータ以外）

## 6. 書籍PDFレイアウト改善の反映整理（2026-03-30）

### 6.1 今回反映した設定（`BookLayoutConfig`）

| 設定 | 反映内容 |
|---|---|
| `title` | 表紙タイトル・本文ページのランニングヘッダに反映 |
| `subtitle` | 表紙サブタイトルに反映（空文字は非表示） |
| `sortOrder` | エントリ並び順に反映し、表紙メタにも表示 |
| `grouping` | PDFセクション分割と見出し帯に反映 |
| `maxPhotosPerEntry` | 掲載写真数上限に反映（プラン上限でクランプ） |
| `maxVideosPerEntry` | 掲載動画QR数上限に反映（プラン上限でクランプ） |
| `includeSourceApp` | 各エントリの出典表示ON/OFFと表紙メタに反映 |

### 6.2 レイアウト改善ポイント（PDF/プレビュー整合）

- PDFの表紙を独立ページ化し、タイトル/サブタイトル/設定メタを再配置
- セクション見出しを帯スタイルに変更して月/年区切りを明確化
- 本文をカードレイアウト化し、内側余白・行間・情報階層を整理
- 写真と動画QRをグリッド配置に変更し、複数添付時の崩れを抑制
- 出典表記と警告表記をプレビュー/PDFで統一（出典行 + 警告ボックス）

### 6.3 まだ未対応の高度設定

- ページサイズ切替（A4以外）
- フォントファミリ/文字サイズ/行間のユーザー設定
- 表紙テーマ（色・装飾・レイアウトプリセット）の切替
- 画像グリッド列数・サムネイルサイズのユーザー設定
- セクション見出し/警告スタイルの詳細カスタマイズ

### 6.4 補足

- 今回は既存設定の反映範囲拡大を優先し、`BookLayoutConfig` の項目追加は実施しなかった（互換性維持）。
- 写真/動画上限は `DiaryStore.effectiveBookMaxPhotos/MaxVideos` を継続利用し、`currentPlan` 上限との整合を維持。

## 7. ドキュメント同期ルール

- 実装済み項目は TODO に残さない。
- TODO に追加する項目は、必ず「対応箇所（ファイル）」を併記する。
- 仕様変更時は `docs/structure.md` と `docs/dependency_mapping.md` を同時更新する。
