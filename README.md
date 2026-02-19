# 俺式 Arch Linux Niri エディション インストールスクリプト

Arch Linux の live 環境から実行する、対話型ワンショット・インストールスクリプトです。  
Wayland コンポジタ **[Niri](https://github.com/YaLTeR/niri)** を中心としたデスクトップ環境を自動構築します。

---

## 構成概要

| カテゴリ | 採用ソフトウェア |
|---|---|
| コンポジタ | Niri |
| バー | Waybar |
| ターミナル | foot |
| ランチャー | fuzzel |
| 通知 | mako |
| ロック画面 | swaylock |
| ファイルマネージャ | Thunar（アーカイバプラグイン同梱）|
| ログインマネージャ | greetd + tuigreet |
| ブラウザ | Firefox |
| オーディオ | PipeWire / WirePlumber |
| ネットワーク | NetworkManager + nm-applet |
| IME | fcitx5-mozc |
| 日本語フォント | IPAex / Source Han Sans・Serif JP |
| 英字フォント | JetBrainsMono Nerd Font |
| スワップ | zram（RAM の 50%・zstd 圧縮）|
| ブートローダ | GRUB（UEFI）|
| ファイルシステム | ext4 |

---

## 事前要件

- UEFI でブートした **Arch Linux インストールメディア**（USB 等）
- インターネット接続（`iwctl` で手動接続しておくこと）
- `git`（live 環境に入っていない場合は `pacman -Sy git` で導入）

---

## 使い方

```bash
# 1. iwctl でネットワークに接続しておく
# 2. リポジトリをクローン
git clone https://github.com/<your-username>/<repo-name>.git
cd <repo-name>

# 3. 実行権限を付与して起動
chmod +x install-niri.sh
./install-niri.sh
```

スクリプトを起動すると以下を順に確認・実行します。

1. **事前チェック** — UEFI・ネット疎通・root 権限
2. **対話入力** — ユーザー名 / ホスト名 / パスワード / インストール先ディスク
3. **ミラー最適化** — reflector で日本の高速ミラーを選定
4. **パーティション** — GPT、EFI 512 MB + root（残り全部）を自動作成・フォーマット
5. **pacstrap** — 5 並列ダウンロードで全パッケージを一括インストール
6. **chroot 設定** — タイムゾーク・ロケール・GRUB・ユーザー・各種 dotfiles を自動生成
7. **アンマウント** — 完了後に自動アンマウント

インストール完了後、メディアを取り外してリブートしてください。

---

## パーティション構成

```
/dev/sdX
├── /dev/sdX1   EFI System   512 MB   FAT32
└── /dev/sdX2   root         残り全部  ext4
```

> nvme・mmcblk デバイスにも対応しています（`p` 付きパーティション名を自動判別）。

---

## 初回起動後のチェックリスト

- [ ] tuigreet からログイン
- [ ] `fcitx5-configtool` を起動して Mozc を入力メソッドに追加
- [ ] nm-applet またはターミナルで `nmtui` を実行し Wi-Fi に接続
- [ ] 必要に応じて `xdg-user-dirs-update` を実行

---

## キーバインド（Niri デフォルト）

| キー | 動作 |
|---|---|
| `Mod + Return` | foot ターミナルを起動 |
| `Mod + D` | fuzzel ランチャーを開く |
| `Mod + Q` | フォーカスウィンドウを閉じる |
| `Mod + H/J/K/L` | フォーカス移動（vim 風）|
| `Mod + Shift + H/J/K/L` | ウィンドウ移動 |
| `Mod + 1〜5` | ワークスペース移動 |
| `Mod + Shift + 1〜5` | ウィンドウをワークスペースへ移動 |
| `Mod + F` | カラム最大化 |
| `Mod + Shift + F` | フルスクリーン |
| `Mod + Shift + L` | swaylock でロック |
| `Mod + Shift + E` | Niri 終了 |
| `Print` | スクリーンショット（選択範囲）|

> `Mod` キーは Super（Windows）キーです。

---

## カスタマイズ

スクリプト冒頭の定数ブロックでパッケージ構成を変更できます。

```bash
# 例：追加パッケージを増やす
EXTRA_PKGS="vim neovim htop btop fastfetch git xdg-user-dirs-gtk firefox reflector zram-generator <追加パッケージ>"
```

dotfiles は chroot スクリプト内のヒアドキュメントで管理されています。  
Niri 設定は `~/.config/niri/config.kdl`、Waybar 設定は `~/.config/waybar/` に生成されます。

---

## ライセンス

MIT
