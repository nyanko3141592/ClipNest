# ClipNest

macOS メニューバー常駐のクリップボードマネージャー + スニペット管理アプリ。

## Tech Stack

- **言語:** Swift 5.9
- **フレームワーク:** AppKit (SwiftUI はスニペットエディタ・設定画面のみ)
- **最小対応:** macOS 13.0 (Ventura)
- **ビルド:** Swift Package Manager (`Package.swift`)、Xcode プロジェクトも併存
- **リンク:** Carbon framework (グローバルホットキー用)

## プロジェクト構造

```
ClipNest/
├── App/           AppDelegate (メニューバー・ホットキー・イベント管理), ClipNestApp (エントリポイント)
├── Models/        ClipboardItem (履歴アイテム), SnippetFolder (スニペット・フォルダ)
├── Services/      ClipboardMonitor (ペーストボード監視), DataStore (永続化・JSON), HotkeyManager (Carbon ホットキー)
├── Views/         PopupPanel (カスタム NSPanel), SettingsView (SwiftUI), SnippetEditorView (SwiftUI)
├── Assets.xcassets/
└── Info.plist
scripts/
└── build-app.sh   リリースビルド → .app バンドル生成
```

## ビルド

```bash
# デバッグ
swift build

# リリース (.app バンドル生成)
bash scripts/build-app.sh
```

## アーキテクチャメモ

- **PopupPanel** は NSPanel サブクラス。NSTableView ベースで Row enum でセクション (header/folder/snippet/historyItem/separator) を管理
- **DataStore** が履歴・スニペットの永続化を担当。JSON ファイルは `~/Library/Application Support/ClipNest/`
- **ClipboardMonitor** は 0.5s タイマーで NSPasteboard を監視、コピー元アプリ情報 (sourceAppName/sourceAppBundleID) も記録
- **ClipboardItem** は後方互換デコード対応 (sourceApp 系フィールドは Optional + decodeIfPresent)
- グローバルホットキーは Carbon API (`RegisterEventHotKey`) 経由

## コーディング規約

- UI は AppKit 中心 (NSPanel, NSTableView)。SwiftUI は設定系画面のみ
- テストなし (現状)
- 外部依存なし (純正フレームワークのみ)
