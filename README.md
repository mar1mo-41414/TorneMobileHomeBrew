# torne mobile HomeBrew エディション

Sony のサポート終了後も、公式ファームウェアの nasne をスマートフォンから操作し続けるための、非公式・個人開発のクライアントアプリです。iOS / Android の両対応を目指します。

## 現状

計画フェーズが完了し、フェーズ 0 (API 実機検証) を進行中です。計画の詳細は [docs/plan.md](docs/plan.md) を参照してください。

## v1 の範囲

- nasne の発見・登録
- 本体・HDD・チューナー等の情報取得
- 録画予約の一覧・作成・更新・削除
- 録画タイトル一覧の表示

録画の再生は DTCP-IP の資格情報が必須となるため v1 では未実装とし、アプリ内にその旨を通知します。

## 技術方式

- Flutter (iOS / Android 単一コードベース)
- アプリ識別子: com.markun.tmhb
- 対応 OS: iOS 15.0 以降 / Android 10 (API 29) 以降

## ライセンス

MIT License
