<p align="center">
  <img src="app-icon.png" width="128" height="128" alt="ClipNest アイコン">
</p>

<h1 align="center">ClipNest</h1>

<p align="center">
  <strong>スニペット機能を備えた軽量な macOS メニューバークリップボードマネージャー</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-13.0%2B-blue?logo=apple&logoColor=white" alt="macOS 13.0+">
  <img src="https://img.shields.io/badge/Swift-5.9-orange?logo=swift&logoColor=white" alt="Swift 5.9">
  <img src="https://img.shields.io/badge/License-MIT-green" alt="MIT License">
</p>

<p align="center">
  <a href="README.md">English</a>
</p>

---

## 機能

- **クリップボード履歴** — 履歴サイズを設定可能 (10〜100件) で、クリップボードを自動追跡
- **スニペット** — よく使うテキストをフォルダで整理してすばやくアクセス
- **グローバルホットキー** — どこからでも ClipNest を呼び出し (デフォルト: `Cmd+Shift+V`)
- **自動ペースト** — 項目を選択するとコピーされ、アクティブなアプリにペースト
- **ログイン時に起動** — ログイン時の自動起動をオプションで設定可能
- **プライバシー重視** — すべてのデータは `~/Library/Application Support/ClipNest/` にローカル保存

## スクリーンショット

> *準備中*

## 動作環境

| 要件 | バージョン |
|---|---|
| macOS | 13.0 (Ventura) 以降 |
| Swift | 5.9 以上 |
| 権限 | アクセシビリティ (初回起動時にプロンプト表示) |

## ビルドとインストール

**ソースからビルド:**

```bash
swift build -c release
bash scripts/build-app.sh
```

プロジェクトルートに `ClipNest.app` が生成されます。

**インストール:**

```bash
cp -r ClipNest.app /Applications/
open /Applications/ClipNest.app
```

## 使い方

1. ClipNest はメニューバーにクリップのアイコンとして表示されます。
2. アイコンをクリックするか、グローバルホットキーでメニューを開きます。
3. **履歴** サブメニューに最近のクリップボード項目が表示されます。
4. トップレベルの項目がスニペットです。クリックでペーストされます。
5. **スニペットを編集...** でスニペットをフォルダに整理できます。
6. **設定...** でホットキー、履歴サイズ、ログイン時の起動を設定できます。

## ライセンス

[MIT](LICENSE)
