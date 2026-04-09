# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## プロジェクト概要

ClipNest — macOS メニューバー常駐のクリップボードマネージャー + スニペット管理アプリ。

- **言語:** Swift 5.9
- **フレームワーク:** AppKit (SwiftUI はスニペットエディタ・設定画面のみ)
- **最小対応:** macOS 13.0 (Ventura)
- **ビルド:** Swift Package Manager (`Package.swift`)、Xcode プロジェクトも併存
- **リンク:** Carbon framework (グローバルホットキー用)
- **外部依存なし** (純正フレームワークのみ)
- **テストなし** (現状)

## ビルド・実行

```bash
# デバッグビルド
swift build

# デバッグビルドを実行
open .build/debug/ClipNest

# リリース (.app バンドル生成 → プロジェクトルートに ClipNest.app)
bash scripts/build-app.sh

# /Applications にインストール
cp -r ClipNest.app /Applications/
```

## アーキテクチャ

- **AppDelegate** がアプリ全体を統括: メニューバーアイコン、グローバルホットキー登録、イベントハンドリング
- **PopupPanel** は NSPanel サブクラス。NSTableView ベースで `Row` enum によりセクション (header/folder/snippet/historyItem/separator) を管理
- **DataStore** が履歴・スニペットの永続化を担当。JSON ファイルは `~/Library/Application Support/ClipNest/`
- **ClipboardMonitor** は 0.5s タイマーで NSPasteboard を監視、コピー元アプリ情報 (sourceAppName/sourceAppBundleID) も記録
- **ClipboardItem** は後方互換デコード対応 (sourceApp 系フィールドは Optional + decodeIfPresent)
- **HotkeyManager** は Carbon API (`RegisterEventHotKey`) 経由でグローバルホットキーを登録
- **SettingsView / SnippetEditorView** は SwiftUI。設定系画面のみ SwiftUI を使用

## コーディング規約

- UI は AppKit 中心 (NSPanel, NSTableView)。SwiftUI は設定系画面のみ
- Accessibility 権限が必要 (初回起動時にプロンプト表示)
- データはすべてローカル保存 (`~/Library/Application Support/ClipNest/`)
