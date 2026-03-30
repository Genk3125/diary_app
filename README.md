# diary_app

DiaryBook の iOS アプリ本体と Share Extension を含むリポジトリです。

## 前提

- Xcode 15+
- Homebrew
- xcodegen

## セットアップ

```bash
cd /Users/kondogenki/diary_app
brew install xcodegen   # 未導入時のみ
xcodegen generate
open DiaryApp.xcodeproj
```

## CLI ビルド確認

```bash
xcodebuild -project DiaryApp.xcodeproj -scheme DiaryApp -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' build
```

## StoreKit ローカルテスト

- Xcode > Edit Scheme > Run > Options
- StoreKit Configuration に `DiaryApp/Products.storekit` を設定

## ドキュメント

- 現状と残タスク: `docs/TODO.md`
- 構造概要: `docs/structure.md`
- 依存マップ: `docs/dependency_mapping.md`
