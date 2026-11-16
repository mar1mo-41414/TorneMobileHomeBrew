# torne mobile HomeBrew エディション 計画書 — 操作系 v1 の範囲・技術方式・フェーズ

> **移管について (2026-11-16)**: 本書は、もともと SonyNasne-DTCP リポジトリの docs/42 として作成された計画書を、本プロジェクトのリポジトリへ移管したものである。以後の計画の正本は本書とする。文中の引用 ([21](https://github.com/mar1mo-41414/SonyNasne-DTCP/blob/main/docs/21_torne_mobile_ipa_static_analysis.md)・[32](https://github.com/mar1mo-41414/SonyNasne-DTCP/blob/main/docs/32_pydtcpip_survey.md)・[37](https://github.com/mar1mo-41414/SonyNasne-DTCP/blob/main/docs/37_pydtcpip_live_verification.md)・[41](https://github.com/mar1mo-41414/SonyNasne-DTCP/blob/main/docs/41_torne_vita_fagdec_eboot_analysis.md)) は SonyNasne-DTCP リポジトリの各文書を指す。

**位置づけ**: torne mobile の後継となる自作スマホクライアント (正式名称は「torne mobile HomeBrew エディション」、2026-11-16 本人決定、§9) の**計画書**。実装はまだ行わない。本書は計画と、その根拠となる既存の到達点 ([21](https://github.com/mar1mo-41414/SonyNasne-DTCP/blob/main/docs/21_torne_mobile_ipa_static_analysis.md)・[32](https://github.com/mar1mo-41414/SonyNasne-DTCP/blob/main/docs/32_pydtcpip_survey.md)・[37](https://github.com/mar1mo-41414/SonyNasne-DTCP/blob/main/docs/37_pydtcpip_live_verification.md)・[41](https://github.com/mar1mo-41414/SonyNasne-DTCP/blob/main/docs/41_torne_vita_fagdec_eboot_analysis.md)) の対応づけ、および本人決定事項の記録である。

**前提となる本人決定 (2026-11-16)**:

- 目標成果物は **iOS 用 IPA と Android 用 APK の両方**。
- v1 の範囲は **nasne の操作系の最小範囲** (公式 FW の nasne に対して)。発見・登録、情報取得、録画予約、録画一覧 (リストアップ)。再生は未実装としてアプリ内に通知する。詳細は §1.2 と §9 の項目 5。
- **DTCP-IP の鍵が必須な部分 (録画再生・視聴の実体転送) は、資格情報ペアが現時点で得られていないため v1 の範囲外**。ただし将来ペアが得られた場合に再生エンジンを差し込めるよう、境界 (インタフェース) だけを計画に含める。
- リモート視聴 (Telepathy) も v1 の範囲外。在宅利用が第一目標。
- 開発体制: 本人はコードを書かない。実装はエージェント側が担い、検証は本人の実機 (公式 FW の nasne、スマートフォン等) で行う。
- 技術方式は **Flutter** で決定。識別子は **com.markun.tmhb** (iOS / Android 共通)。リポジトリは新規作成し、本書は作成時にそちらへ移管する。配布は **GitHub** で IPA / APK の両方、ライセンスは **MIT**。
- 実装順序は **iOS 先行** (§6 のフェーズ 2・3 の入れ替え済み)。**iPad 対応を v1 に含める**。対応 OS 下限は **iOS 15.0 / Android 10 (API 29)** (§9.1 の調査結果に基づく)。

**現在の到達点 (材料)**: nasne WebAPI は iOS 版 ([21](https://github.com/mar1mo-41414/SonyNasne-DTCP/blob/main/docs/21_torne_mobile_ipa_static_analysis.md)、62 件) と Vita 版 ([41](https://github.com/mar1mo-41414/SonyNasne-DTCP/blob/main/docs/41_torne_vita_fagdec_eboot_analysis.md)、定義テーブル全読) の両方から全読済み。DLNA DMS のメタデータは資格情報なしで取得できることを実機で確認済み ([37](https://github.com/mar1mo-41414/SonyNasne-DTCP/blob/main/docs/37_pydtcpip_live_verification.md))。DTCP-IP のプロトコル実装は pydtcpip が公開済み ([32](https://github.com/mar1mo-41414/SonyNasne-DTCP/blob/main/docs/32_pydtcpip_survey.md))。

---

## 1. 目的と範囲

### 1.1 目的

Sony のサポート終了後も、公式 FW の nasne を手元のスマートフォンから操作し続けられる状態を保つこと。第一段階 (v1) は「操作するクライアント」の完成を指し、再生は将来段階 (§8) に分離する。本人の整理 (2026-11-16): 「DTCP-IP の鍵が必須な部分はまだ不可能だけど、操作するだけなら可能」。

### 1.2 v1 でやること

公式 FW の nasne (同一 LAN 内) に対して、次の操作を iOS / Android の両アプリから行えるようにする。範囲は 2026-11-16 の本人決定で「最低限」に確定した (§9 の項目 5)。

1. **発見と登録** (通信の前提): LAN 内の nasne の発見 (SSDP)、手動登録 (アドレス直接指定)、PIN による検証、登録情報の保持。
2. **情報取得**: 本体情報 (名称、ソフトウェア版数、時刻)、HDD 情報 (容量・空き)、チューナー/ライブ状態の表示、B-CAS 情報、ネットワーク情報、メッセージ (CA / EMM) の表示、録画失敗 (RecNG) 一覧。
3. **録画予約**: 予約一覧の表示、予約の作成・更新・削除、競合 (コンフリクト) の確認。予約作成はチャンネル・日時を指定する手動作成を基本とする (番組表グリッドからの作成は下記のとおり v1 の必須範囲外)。
4. **録画一覧 (リストアップ)**: 録画タイトル一覧 (件数・残コピー回数の表示を含む) と詳細情報の表示。
5. **再生の未実装通知**: 録画の再生は v1 では未実装とし、再生に相当する操作箇所ではその旨をアプリ内に通知する (§5.7 のスタブが「未対応」を返し、UI はそれを表示する)。

**v1 の必須範囲から外したもの** (当初案にあったが、最小範囲の決定により後続バージョン候補へ移した。§3 の対応表は資料として保持する):

- 番組表のグリッド表示 (取得経路自体が未確定事項 §10-1 のままであり、フェーズ 0 の調査対象としては残す)。
- 設定の変更系: 本体名称・視聴地域・時刻・ペアレンタル設定の変更、チャンネルスキャン、外付け HDD の登録・解放、DTCP-IP クライアント一覧とセッション停止。
- 録画の管理操作: タイトル情報の更新、タイトルの削除、サムネイル・チャプタ情報の表示、再生再開位置の設定。
- メタデータ閲覧: DLNA ContentDirectory の Browse による DIDL の取得と表示 (録画一覧の補完は後続で検討する)。

### 1.3 v1 でやらないこと (範囲外と理由)

| 対象 | 理由 |
|---|---|
| 録画再生 (実体転送) | DTCP-IP の AKE に DTLA 署名の証明書 + 機器秘密鍵の正規ペアが必須 ([32](https://github.com/mar1mo-41414/SonyNasne-DTCP/blob/main/docs/32_pydtcpip_survey.md) §3)。ペアが現時点で無い。将来段階 (§8) |
| ライブ視聴 (実体転送) | 同上。ライブ状態の**表示**は v1 に含めるが、映像の受信は含めない |
| リモート視聴 (Telepathy) | 在宅利用が第一目標という本人決定。Telepathy はアカウント連携 (SEN/PSN) と P2P 基盤を伴う別レイヤー ([21](https://github.com/mar1mo-41414/SonyNasne-DTCP/blob/main/docs/21_torne_mobile_ipa_static_analysis.md) §5、[41](https://github.com/mar1mo-41414/SonyNasne-DTCP/blob/main/docs/41_torne_vita_fagdec_eboot_analysis.md) §4.4) |
| ムーブ / ダビング | コピーを消費する操作であり、DTCP-IP が前提。誤操作時の被害が大きい |
| ファームウェア更新 (updateFileDownload 等) | Vita v1.00 の定義テーブルにのみ存在する経路 ([41](https://github.com/mar1mo-41414/SonyNasne-DTCP/blob/main/docs/41_torne_vita_fagdec_eboot_analysis.md) §3.3)。操作系クライアントの責務ではなく、失敗時の被害が大きい |
| 内蔵 HDD 初期化 (internalHDDInitialize) | 破壊的操作。全録画が消える。v1 の UI には出さない (出すかどうか自体が本人決定事項、§9) |
| ウェブビデオ経路 (ポート 58890) の再生 | [21](https://github.com/mar1mo-41414/SonyNasne-DTCP/blob/main/docs/21_torne_mobile_ipa_static_analysis.md) §3.4 / [41](https://github.com/mar1mo-41414/SonyNasne-DTCP/blob/main/docs/41_torne_vita_fagdec_eboot_analysis.md) §4.2 に存在する軽量再生経路だが、DTCP を伴わない形で成立するかは未検証。v1 では調査対象に留め、機能としては含めない |

### 1.4 将来拡張の境界

- 再生エンジンは §5.7 の境界 (インタフェース) の内側に閉じて実装し、v1 の操作系コードは再生の有無に依存しない形にする。
- v1 の録画一覧は、将来の再生起動に必要な識別子 (タイトル ID、DIDL の res 情報、DTCP1HOST / DTCP1PORT) を保持できるデータモデルにしておく (表示はしなくてよいが、捨てない)。

---

## 2. 材料 — 既存の到達点と計画への対応

| 材料 | 内容 | 計画での使い方 |
|---|---|---|
| [21](https://github.com/mar1mo-41414/SonyNasne-DTCP/blob/main/docs/21_torne_mobile_ipa_static_analysis.md) §3.2 | iOS 版 torne から抽出した WebAPI 62 件 (config 17 / recorded 13 / schedule 7 / status 25) | v1 機能とエンドポイントの対応 (§3) の主たる母集団 |
| [41](https://github.com/mar1mo-41414/SonyNasne-DTCP/blob/main/docs/41_torne_vita_fagdec_eboot_analysis.md) §3 | Vita 版の定義テーブル全読。両版共通 52 件、Vita 2.02 のみ 4 件 (いずれも iOS にも存在)、iOS のみ 6 件、v1.00 テーブルは 109 件 (Vita 独自 57 件を含む) | エンドポイントの実在の裏取り。母集団として最も広いのは v1.00 テーブル (109 件)。ただし「定義の存在 = 実働」は意味しないため、実働範囲はフェーズ 0 の実機検証で確定する |
| [21](https://github.com/mar1mo-41414/SonyNasne-DTCP/blob/main/docs/21_torne_mobile_ipa_static_analysis.md) §3.1・§3.3 | SSDP 発見 (ST: `urn:schemas-upnp-org:device:MediaServer:1`)、UPnP サービス (ContentDirectory:1、X_PvrControl:1、X_ScheduledRecording:2 / Ext:1)、DMS ポート 60151 の ObjID 形式 URL、EPG ファイル (`EPG_TRDEPG_FILE.dat` 等) の取得先 | 発見 (§5.2)、UPnP/DLNA 層 (§5.4)、番組表の取得経路候補 (§3・§10) |
| [37](https://github.com/mar1mo-41414/SonyNasne-DTCP/blob/main/docs/37_pydtcpip_live_verification.md) | 公式 FW 実機で、資格情報なしの discover / dump が成立。description・SCPD 4 件・Browse 19 件・録画メタデータ・メディア HEAD (200、`application/x-dtcp1`、DTCP1HOST/DTCP1PORT 付き) を採取し **403 は返らなかった**。DIDL に `av:COGCount` が存在 | メタデータ閲覧 (Browse) が資格情報なしで成立することの実証。録画一覧の残コピー回数表示の根拠 |
| [32](https://github.com/mar1mo-41414/SonyNasne-DTCP/blob/main/docs/32_pydtcpip_survey.md) | pydtcpip (MIT、Python、Sink 専用)。AKE (Full Authentication)・PCP 復号・Move を実装。証明書 (88 バイト) と秘密鍵 (20 バイト) の正規ペアは同梱されず利用者が用意する前提。nasne プロファイル `sie_nasne` 実装済み | 将来の再生エンジン (§8) の参照実装・プロトコルオラクル。v1 では使わない |
| 開発側の既存知見 | WebAPI のポートは 64210、認証ヘッダは `X-DTVToken` (Vita 版の全 ELF に平文で存在、[41](https://github.com/mar1mo-41414/SonyNasne-DTCP/blob/main/docs/41_torne_vita_fagdec_eboot_analysis.md) §4.3)。トークンは PIN を素材とする SHA-1 ベースの算出 (PIN は本体 MAC アドレスの下位 3 オクテット。算出式の詳細は開発側で実績のある形式を用い、フェーズ 0 で実機再検証する) | WebAPI クライアント (§5.3) の前提 |

---

## 3. 機能一覧と WebAPI エンドポイントの対応

エンドポイント名は [21](https://github.com/mar1mo-41414/SonyNasne-DTCP/blob/main/docs/21_torne_mobile_ipa_static_analysis.md) §3.2 / [41](https://github.com/mar1mo-41414/SonyNasne-DTCP/blob/main/docs/41_torne_vita_fagdec_eboot_analysis.md) §3.2 の表記 (カテゴリ/名前) に従う。「iOS のみ」「Vita のみ」の注記は両版の文字列実在の分類であり、実機での実働はフェーズ 0 で確認する。なお、v1 の必須範囲は §1.2 で確定しており、本節の表には後続バージョン候補の分も資料として含む (範囲の確定は §1.2 が正)。

### 3.1 発見・登録・初期設定

| 機能 | 手段 / エンドポイント |
|---|---|
| nasne 発見 | SSDP M-SEARCH (ST: MediaServer:1)。失敗時の手動登録 (アドレス入力) を併設 |
| PIN 検証 | `config/PINVerify` |
| クライアント情報の取得 | `status/requestClientInfoGet` (iOS のみ。Vita 両版に無し — 実働は要検証) |
| 設定完了状態の確認 | `status/isFinishSetup` / `config/finishSetup` |
| 視聴地域 | `status/areaInfoGet` / `config/areaInfoSet` |
| チャンネルスキャン | `config/channelScanStart` / `config/channelScanProgressGet` / `config/channelScanCancel` |
| チャンネル一覧 | `status/channelListGet` |
| 本体名称 | `status/boxNameGet` / `config/boxNameSet` |
| 本体時刻 | `status/currDateGet` / `config/currDateSet` |

### 3.2 状態表示

| 機能 | エンドポイント |
|---|---|
| ソフトウェア版数・更新確認 | `status/softwareVersionGet` / `status/updateCheck` |
| HDD 情報・一覧 | `status/HDDInfoGet` / `status/HDDListGet` |
| B-CAS 情報 | `status/BCASInfoGet` |
| ネットワーク情報 | `status/networkIfInfoGet` |
| ライブ状態 (表示のみ) | `status/liveStreamStatusListGet` (iOS のみ `status/multiTunerLiveStreamStatusListGet`、`status/dtvtunerDeviceInfoGet` も) |
| メッセージ表示 | `status/CAMsgInfoGet` / `status/EMMMsgInfoGet` |
| 録画失敗一覧 | `status/recNgListGet` / `config/recNgListDelete` |
| ペアレンタル設定 | `status/parentalRatingInfoGet` / `config/parentalRatingInfoSet` |
| DMS 停止理由 | `status/dmsStreamStopReasonListGet` (診断表示用) |

### 3.3 番組表

| 機能 | 手段 / エンドポイント |
|---|---|
| チャンネル構成 | `status/channelListGet` |
| EPG 版数確認 | `status/EPGVersionInfoGet` |
| 番組データ本体 | **取得経路が未確定** (§10)。候補は DMS (ポート 60151) の EPG ファイル (`EPG_TRDEPG_FILE.dat`、BS/CS/USB-HDD 系とロゴファイル) — [21](https://github.com/mar1mo-41414/SonyNasne-DTCP/blob/main/docs/21_torne_mobile_ipa_static_analysis.md) §3.3 で torne が取得する URL テンプレートとして確認済み。ファイル形式の解析がフェーズ 0 の課題 |

### 3.4 録画予約

| 機能 | エンドポイント |
|---|---|
| 予約一覧 | `schedule/reservedListGet` (iOS のみ `schedule/reservedListGet2` も) |
| 予約作成 | `schedule/reservedInfoCreate` |
| 予約更新 | `schedule/reservedInfoUpdate` |
| 予約削除 | `schedule/reservedInfoDelete` |
| 競合確認 | `schedule/conflictListGet` |
| ビットレート情報 | `schedule/reservedInfoBitrateGet` |
| (代替経路) | UPnP `X_ScheduledRecording:2` の SOAP アクション ([21](https://github.com/mar1mo-41414/SonyNasne-DTCP/blob/main/docs/21_torne_mobile_ipa_static_analysis.md) §3.3 にテンプレートあり)。WebAPI を主経路とし、UPnP は実機検証で WebAPI が不足する場合の予備とする |

### 3.5 録画一覧・管理

| 機能 | エンドポイント / 手段 |
|---|---|
| タイトル一覧 | `recorded/titleListGet` |
| 件数 | `recorded/recordedContentCountGet` / `recorded/recordedContentMaxCountGet` (いずれも iOS のみ) |
| 詳細情報の取得・設定 | `recorded/recordedContentAdditionalInfoGet` / `recorded/recordedContentAdditionalInfoSet` |
| タイトル情報の更新 | `recorded/titleUpdate` |
| サムネイル | `recorded/recordedContentThumbnailGet` / `recorded/thumbnailMapGet` |
| チャプタ情報 | `recorded/recordedContentChpDataGet` (Vita 2.02 と iOS に存在) |
| 再生再開位置の設定 | `recorded/recordedContentResumePositionSet` (再生自体は v1 外だが、位置情報の保持は一覧側の責務として扱う) |
| タイトル削除 | `recorded/titleDelete` |
| 補助メタデータ | `recorded/PMTMapGet` / `recorded/SEMapDataGet` (番組内部情報。v1 の UI には直接出さず、詳細表示の補助候補) |
| メタデータ閲覧 (DLNA) | ContentDirectory `Browse` による DIDL 取得。`av:COGCount` (残コピー回数)、res の protocolInfo と DTCP1HOST/DTCP1PORT を保持する ([37](https://github.com/mar1mo-41414/SonyNasne-DTCP/blob/main/docs/37_pydtcpip_live_verification.md)) |

### 3.6 HDD 管理・DTCP クライアント管理 (設定画面内)

| 機能 | エンドポイント |
|---|---|
| 外付け HDD 登録・進捗・解放 | `config/HDDRegister` / `config/HDDRegisterProgressGet` / `config/HDDRelease` |
| DTCP-IP クライアント一覧 (表示) | `status/dtcpipClientListGet` |
| DTCP-IP セッション停止 | `config/dtcpipClientStop` (他者の視聴セッションを止め得るため、UI 上は確認を必須とし、テスト方針 (§7) でも不用意に実行しない) |
| モバイルビットレート設定 | `status/mobileBitrateInfoGet` / `config/mobileBitrateInfoSet` (ウェブビデオ等の画質設定。再生系の設定だが設定値の読み書き自体は操作系。v1 に含めるかは線引きの確認事項、§9) |
| 内蔵 HDD 初期化 | `config/internalHDDInitialize` / `config/internalHDDInitializeProgressGet` — **v1 の UI には出さない** (§1.3) |

---

## 4. 技術方式の比較と推奨

決定は本人が行う (§9)。ここでは比較と推奨を示す。

### 4.1 候補

- **案 A: Flutter (Dart) 単一コードベース** — コア (発見・WebAPI・UPnP・状態管理) と UI を Dart で一元化し、iOS / Android の両方へビルドする。
- **案 B: Kotlin Multiplatform (KMP)** — コアを Kotlin で共有し、UI は各 OS ネイティブ (SwiftUI / Jetpack Compose) または Compose Multiplatform。
- **案 C: 個別ネイティブ実装 (Swift + Kotlin)** — API クライアントを含め両 OS で別実装。
- **案 D: Rust コア + FFI + ネイティブ UI** — プロトコル処理を Rust の共有ライブラリに寄せ、UI は SwiftUI / Jetpack Compose。
- **案 E: Python コア + 薄い殻** — pydtcpip の資産 (Python) をそのまま活かす構成。Android は Chaquopy 等、iOS は Python 埋め込み (BeeWare 等)。

### 4.2 比較

| 観点 | A: Flutter | B: KMP | C: 個別ネイティブ | D: Rust コア | E: Python コア |
|---|---|---|---|---|---|
| 実装量 (v1) | 最小 (UI・コアとも 1 実装) | 中 (コア 1 + UI 実質 2) | 最大 (全て 2 実装) | 大 (コア 1 + UI 2 + FFI) | 中 (ただし iOS 側の梱包が不安定要素) |
| 保守性 | 単一言語・単一コードベースで最も単純 | コア共有の恩恵はあるが iOS 側ツールチェーンが若い | 仕様変更時に 2 箇所修正が常態化 | コアは堅牢だが FFI 境界の保守が恒常コスト | 言語は 1 つだが梱包方式が OS ごとに別物 |
| 配布 (サイドロード前提) | IPA / APK 両対応の実績が豊富 | APK は通常経路、IPA は Kotlin/Native 経由で可 | 両方とも標準経路 | 両方とも可 (構築は最も複雑) | IPA の生成・署名まわりの実績が乏しい |
| 低レイヤ制御 (UDP マルチキャスト、ソケットオプション) | プラットフォームチャネルで原生 API に降りられる。SSDP の送受信は Dart の DatagramSocket でも概ね可能 | ネイティブ側で完全制御可 | 完全制御可 | 完全制御可 | OS の制約を Python ランタイム越しに受ける |
| 将来の DTCP 再生 (§8) との接続 | 再生エンジンは FFI / プラットフォームチャネル越しに別実装 (Rust / C / ネイティブ) を差し込む形になる。境界設計 (§5.7) が前提 | Kotlin/Java 実装への移植、または JNI/ネイティブ連携 | 各 OS で個別に移植 | **最も素直**: pydtcpip を参照実装として Rust へ移植すれば、そのままコアに同居できる | **pydtcpip を最も直接に再利用できる** (特に Android)。ただし iOS への Python 持ち込みが最大の弱点 |
| エージェント実装との相性 | 単一言語で検証サイクルが短い | 中 | 2 倍の実装・検証 | 構築環境の整備が重い | iOS 側の再現性が低い |

### 4.3 推奨

**推奨は案 A (Flutter)**。理由:

1. v1 の本体は「HTTP + JSON の API クライアントと、その画面」であり、規模が小さい。単一コードベースの利益 (実装量・保守・検証サイクル) が最も大きく効く領域である。
2. 配布がサイドロード前提 (App Store / Google Play の審査を通さない) のため、Flutter の弱点とされる審査・ポリシー面の不利がほぼ消える。IPA / APK の両生成に実績がある。
3. 将来の DTCP 再生は、どの案でも「pydtcpip (Python) の移植または連携」が本体作業になる。Flutter でも境界 (§5.7) を介した FFI / ネイティブ差し込みで受け止められ、v1 の方式選択が将来を塞がない。

代替案のトレードオフ (本人が重視する観点で変わる):

- **将来の DTCP 再生を最優先に据えるなら案 D (Rust コア)**。再生エンジンの移植先がコアと同居し、長期的には最も綺麗だが、v1 の到達は最も遅くなる。
- **pydtcpip のコード自体を動かすことに価値を見るなら案 E**。ただし iOS 側の梱包が不安定で、両 OS 対称の成果物という目標と相性が悪い。
- 案 B / C は「UI のネイティブらしさ」では優れるが、本プロジェクトの制約 (実装はエージェント、検証は本人の実機) では実装・検証の二重化コストが利益を上回ると判断する。

**決定 (2026-11-16)**: 本人が推奨どおり **案 A (Flutter)** で決定した (§9 の項目 3)。以降の §5 のアーキテクチャと §6 のフェーズは Flutter 前提で確定する。

---

## 5. アーキテクチャ

方式は案 A (Flutter) を前提に書くが、層の切り分け自体は他案でも共通する。

### 5.1 全体構成

```
[UI 層]  画面群 (§5.6)
   |
[アプリケーション層]  画面状態・キャッシュ・操作の調停
   |
[コア層]  発見 (SSDP) / WebAPI クライアント / UPnP-DLNA クライアント / ローカル状態
   |
[プラットフォーム層]  秘密情報ストレージ (Keychain / Keystore)、ネットワーク到達性、
                       将来: 再生エンジン (§5.7 の境界)
```

コア層は UI から独立させ、フェーズ 0 の実機検証で得た応答フィクスチャで単体テストできる形にする。

### 5.2 発見・登録

- SSDP M-SEARCH (`urn:schemas-upnp-org:device:MediaServer:1`) で LAN 内の nasne を列挙し、description (friendlyName / modelName) で nasne であることを確認する ([37](https://github.com/mar1mo-41414/SonyNasne-DTCP/blob/main/docs/37_pydtcpip_live_verification.md) で実機の description 形式は確認済み)。
- 発見できない環境 (マルチキャスト制限等) に備え、アドレスの手動登録を必須機能とする。
- 登録時に PIN 検証 (`config/PINVerify`) を行い、登録情報 (アドレス、機器識別、PIN) を保持する。PIN は秘密情報ストレージに置く (§5.5)。
- 複数台対応は、データモデルは複数台を保持できる形にし、UI は単一台前提とする (後から外せるようにする)。v1 の最小範囲決定からの扱いは §9 の項目 5 に記録した。
- OS 側の制約 (要・実装時確認): iOS のローカルネットワーク許可とマルチキャスト受信の扱い、Android のマルチキャストロック取得。発見が OS 制限で成立しない場合は手動登録へ誘導する。

### 5.3 WebAPI クライアントと認証

- ベース URL は `http://<nasne>:64210/`、パスは `<カテゴリ>/<名前>` (例: `recorded/titleListGet`)。応答は JSON 前提 (フェーズ 0 で各エンドポイントの実スキーマを確定する)。
- 認証は `X-DTVToken` ヘッダ。トークンは PIN を素材とする SHA-1 ベースの算出で、開発側に実績のある形式を用いる。**どのエンドポイントがトークンを要求するか (全てか、config 系のみか等) は文字列解析では確定していない**ため、フェーズ 0 でエンドポイントごとに要否を実測する。
- エラー処理: HTTP ステータスと応答 JSON のエラー情報を画面に伝える共通形にする。タイムアウトと再試行は読み取り系のみ (作成・削除等の書き込み系は自動再試行しない — 二重予約や二重削除を防ぐ)。
- クライアントは「定義テーブル駆動」にしない。v1 で使うエンドポイントだけを型付きで実装し、未使用の定義 (v1.00 テーブルの 109 件等) は取り込まない (実働未確認の面を広げないため)。

### 5.4 UPnP / DLNA 層

- ContentDirectory `Browse` で DIDL を取得し、録画メタデータの補完 (残コピー回数 `av:COGCount`、res の protocolInfo、DTCP1HOST / DTCP1PORT) に使う。資格情報なしで成立することは [37](https://github.com/mar1mo-41414/SonyNasne-DTCP/blob/main/docs/37_pydtcpip_live_verification.md) で実証済み。
- X_PvrControl / X_ScheduledRecording の SOAP は、WebAPI で代替できる範囲では使わない (経路を一本化し、検証面を小さく保つ)。番組表の取得経路の確定 (§3.3) で必要になれば、その範囲で採用する。
- DMS のポートは 60151 (発見時のデバイス記述から得る形を基本とし、固定値への依存は検証結果で判断する)。

### 5.5 ローカル状態

- 保持するもの: 登録済み nasne の一覧と PIN (秘密情報ストレージ)、チャンネル一覧のキャッシュ、番組表のキャッシュ (版数 `EPGVersionInfoGet` と組で管理)、予約・録画一覧の表示用キャッシュ (オフライン表示用。真実は常に nasne 側)。
- ローカルに録画実体や DTCP 資格情報を保持する設計は v1 には無い (資格情報は保持対象自体が存在しない)。

### 5.6 画面構成 (v1)

§1.2 の最小範囲に対応する画面は次のとおり。iPad の大画面対応も v1 に含める (§9 の項目 9) ため、レイアウトは画面幅に応じた伸縮を前提とする。

1. **ホーム / 状態**: 登録 nasne の状態サマリ (HDD 空き、録画中・視聴中の有無、メッセージ有無)。
2. **予約**: 一覧 (時系列)、作成・編集フォーム (チャンネル、日時、長さ、ビットレート、繰り返し等は API の許す範囲)、競合警告。
3. **録画済み**: 一覧 (残コピー回数、保護状態)、詳細 (追加情報)。再生に相当する操作では未実装の通知を出す (§1.2 の 5)。
4. **設定**: nasne 登録管理 (発見・手動登録・PIN 検証・登録解除)。

後続バージョン候補の画面 (当初案): 番組表 (チャンネル × 時間のグリッド、番組選択から予約作成)、本体設定 (名称・地域・時刻・ペアレンタル)、チャンネルスキャン、HDD 管理と DTCP-IP クライアント一覧、録画の削除・情報更新。

### 5.7 再生エンジンの境界 (将来の差し込み点)

- インタフェースとして `PlaybackEngine` を定義する。入力: 対象タイトルの res URL と DTCP 接続先 (DTCP1HOST / DTCP1PORT)、出力: 復号済み TS ストリームをプレイヤーへ渡す口。v1 では「未対応」を返すスタブのみを置く。
- UI 側はこの境界越しにだけ再生を要求し、境界の内側 (AKE、PCP 復号、資格情報の保持) は v1 の関心事にしない。
- 資格情報ペアが得られた場合の保持場所は秘密情報ストレージとし、アプリの通常の状態保存とは分離する (詳細は §8)。

---

## 6. フェーズ分けと完了条件

### フェーズ 0: API 実機検証 (PC 上の検証スクリプト)

- 目的: v1 で使うエンドポイントの実働・要求形式・応答スキーマ・トークン要否を、公式 FW 実機で確定する。
- 内容: 読み取り系を先に全数確認し、書き込み系 (予約作成・更新・削除等) は本人の承認したテスト対象でのみ確認する (§7)。番組表の取得経路 (EPG ファイル形式) の確定を含む (後続バージョン候補のための調査として)。
- **完了条件**: §1.2 の v1 機能に対応するエンドポイント (§3) について、要求/応答の実例 (フィクスチャ) が記録され、未確定事項 (§10) のうちフェーズ 0 担当分が解消または「実働しない」と実測で確定している。

### フェーズ 1: コア実装

- 目的: 発見・WebAPI クライアント・認証・UPnP Browse・ローカル状態を、UI から独立したコアとして実装する。
- **完了条件**: フェーズ 0 のフィクスチャに対する単体テストが通り、実機に対して読み取り系の一連の操作 (発見 → 状態取得 → 一覧取得) が CLI 相当のハーネスで再現できる。

### フェーズ 2: iOS アプリ (先行)

順序は本人の決定 (2026-11-16) で iOS 先行とした (§9 の項目 12)。

- 目的: コアに UI を載せ、IPA を生成して iPhone / iPad 実機で検証する。ローカルネットワーク許可まわりの挙動確認を含む。
- **完了条件**: §5.6 の v1 対象画面が実機の nasne に対して動作し、§1.2 の v1 機能 (書き込み系を含む) が iOS 実機で一巡する。IPA のサイドロード手順 (署名方法を含む) が記録される。

### フェーズ 3: Android アプリ

- 目的: 同一コア・UI で APK を生成し、Android 実機 (Xperia Ace、Android 12、LineageOS、§9 の項目 7) で検証する。
- **完了条件**: iOS と同範囲の機能が Android 実機で一巡する。APK の生成手順が再現可能な形で記録される。

### フェーズ 4: 配布整備

- 目的: 版数管理、ビルド手順の固定、説明文書 (導入手順・既知の制限) の整備。配布先は GitHub (§9 の項目 6)。
- **完了条件**: 両成果物 (IPA / APK) が手順どおりに再生成でき、導入手順だけで本人の端末に入れられる。

### フェーズ 5 (将来): DTCP 再生組み込み

- §8 のとおり。開始条件は資格情報ペアの調達であり、v1 の完了条件には含めない。

---

## 7. テスト方針

- **対象実機は公式 FW の nasne**。検証は本人の実機で行い、その実機は日常の録画にも使われている前提で臨む。
- クライアント側の検証端末 (§9 の項目 7・9): iOS は iPhone 15 Plus (主力)、iPhone SE (第 1 世代、iOS 15.8、脱獄済み)、iPad (LiveContainer 導入済み)。Android は Xperia Ace (Android 12、rooted、LineageOS)。対応 OS 下限 (iOS 15.0 / Android 10) の端末側の裏付けは iPhone SE (第 1 世代) が担う (§9.1)。
- 影響回避の原則:
  - 読み取り系の検証を先に済ませ、書き込み系は「いつ・何に対して行うか」を本人と合意してから行う。
  - 予約の作成・削除の検証は、短時間のテスト番組に限定し、検証後に残骸を残さない。本人の既存予約と競合させない (作成前に `schedule/conflictListGet` で確認する)。
  - チャンネルスキャン、HDD 登録・解放、時刻変更などの本体状態を変える操作は、録画予定のない時間帯に、本人の立会いのもとでのみ行う。
  - `config/dtcpipClientStop` は他者の視聴を止め得るため、検証対象から原則外す (どうしても必要な場合は本人の指示で)。
  - タイトル削除の検証は、本人が指定した削除可能な録画でのみ行う。
  - コピーを消費する操作 (ムーブ等) は v1 の範囲外であり、検証でも行わない。
- 実機の状態 (公式 FW / Debian 等の構成) は時期によって変わり得るため、検証セッションの開始時に構成を確認してから行う (開発側の記録作法に従う)。
- フィクスチャ (フェーズ 0 で採取した応答) は、個人情報 (番組名等) を含み得るため、リポジトリへの保存時はマスクする (pydtcpip の `dump --mask-private` と同種の扱い、[37](https://github.com/mar1mo-41414/SonyNasne-DTCP/blob/main/docs/37_pydtcpip_live_verification.md) §5 の前例に従う)。

---

## 8. 将来の DTCP 再生組み込み

### 8.1 pydtcpip の位置づけ

- pydtcpip ([32](https://github.com/mar1mo-41414/SonyNasne-DTCP/blob/main/docs/32_pydtcpip_survey.md)、MIT) は Sink 側の AKE (Full Authentication、ECDSA/ECDH)・PCP 復号 (AES-128-CBC)・Move までを実装した Python ライブラリで、nasne プロファイル `sie_nasne` を持つ。[37](https://github.com/mar1mo-41414/SonyNasne-DTCP/blob/main/docs/37_pydtcpip_live_verification.md) でプロファイルの前提 (modelName、DIDL の形、protocolInfo、`av:COGCount`) は実機で成立済み。残る未検証は AKE 以降 (証明書の受け入れ、クライアント登録との関係、近接チェックの通過) である ([32](https://github.com/mar1mo-41414/SonyNasne-DTCP/blob/main/docs/32_pydtcpip_survey.md) §7.3)。
- 本クライアントへの組み込みでは、pydtcpip は **参照実装およびプロトコルオラクル** (既知値テスト `tests/test_known_values.py` は実機で成功した計算値と照合する設計) として使うのが基本線になる。

### 8.2 モバイルへの移植課題

- pydtcpip は Python 3.13 以上 + asyncio + cryptography 等に依存する。モバイルへの直接埋め込みは Android では可能性があるが iOS では梱包・署名の面で弱く、両 OS 対称にはなりにくい (§4.2 の案 E の弱点)。
- 現実的な経路は、AKE / PCP のプロトコル部分を v1 のコア言語側 (または FFI 先の Rust / C) へ移植し、pydtcpip と既知値で突き合わせて正しさを担保すること。移植範囲は AKE の状態機械、楕円曲線演算 (DTCP 独自曲線)、鍵導出、PCP 復号、SRM 検証であり、DLNA 側は v1 のコアが既に担う。
- プロトコル上の注意 (モバイル固有): AKE の認証接続は IP TTL = 3 の設定と RTT 近接チェックへの即応を要する ([32](https://github.com/mar1mo-41414/SonyNasne-DTCP/blob/main/docs/32_pydtcpip_survey.md) §2.2)。モバイル OS のソケット API でこれらがどこまで制御できるかは、組み込み時点の検証事項。
- nasne 側の受け入れ条件 (クライアント登録の要否、証明書カテゴリの扱い) は、ペアが無い現時点では検証不能であり、組み込みフェーズの冒頭で実機検証する ([32](https://github.com/mar1mo-41414/SonyNasne-DTCP/blob/main/docs/32_pydtcpip_survey.md) §7.3 の 2・3)。

### 8.3 資格情報の扱い (将来)

- ペア (証明書 88 バイト + 秘密鍵 20 バイト) が得られた場合、その保持は秘密情報ストレージ (iOS Keychain / Android Keystore) に限定し、リポジトリや通常の設定ファイルには置かない。本書を含む記録文書にも値そのものは書かない (本リポジトリの作法どおり)。

---

## 9. 本人決定事項 (2026-11-16 決定)

初版では「本人が決めるべき事項」として一覧提示したもの。全項目が 2026-11-16 に本人決定済みとなったため、決定内容をここに記録する。項目 8 (対応 OS 下限) は本人の想定をもとに調査を行い、その結果と推奨を §9.1 に記録した。

1. **プロジェクトの正式名称**: **torne mobile HomeBrew エディション** (本人が以前から使っていた呼称を正式名称とした)。アプリの表示名も同じとする。
2. **リポジトリ**: **新規リポジトリ**を作成する。SonyNasne-DTCP は DTCP 専用のリポジトリであり、WebAPI クライアントまで含めるものではないため同居させない。本計画書は新規リポジトリの作成時にそちらへ移す (それまでは本書の位置に置く)。
3. **技術方式**: **Flutter** (§4 の推奨・案 A のとおりで決定)。
4. **識別子**: **com.markun.tmhb** (iOS バンドル ID / Android アプリケーション ID の共通。本人が常用する `com.markun` に、torne mobile HomeBrew の略 `tmhb` を付けたもの)。
5. **v1 の機能**: **最低限**で確定する。nasne と通信して、nasne の情報取得、録画 (予約)、録画のリストアップまで (§1.2 に反映済み)。再生機能は未実装とし、その旨をアプリ内に通知する形で確定した。初版で個別に確認事項としていた (a)〜(d) は、この最小範囲の決定からの扱いを次のとおりとする: (a) モバイルビットレート設定は v1 の必須範囲に含めない。(b) メッセージ表示 (CA / EMM) と録画失敗一覧は、情報取得 (状態表示) の一部として v1 に含める。(c) 複数台の nasne 対応は、データモデルは複数台を保持できる形とし、UI は単一台前提とする。(d) 破壊的操作 (内蔵 HDD 初期化) は UI に一切出さない (§1.3 のとおり)。
6. **配布方法**: **GitHub** で配布する。IPA も APK も GitHub 側に置く。
7. **Android 検証端末**: **Xperia Ace (Android 12、rooted、LineageOS)** を使う。
8. **対応 OS バージョンの下限**: **iOS 15.0 / Android 10 (API 29)** で確定する。調査結果と推奨根拠は §9.1。
9. **タブレット対応**: **iPad 対応を v1 に含める** (本人の iPad には LiveContainer が導入済みで、サイドロードによる検証が可能)。
10. **ライセンス**: **MIT**。将来 pydtcpip (MIT) のコードを移植・流用する場合も MIT 同士で整合する。
11. **アプリアイコン等の素材**: エージェント側で良さそうなものを作成する方針で決定した (実装フェーズの作業)。
12. **実装順序 (追加決定)**: **iOS が先**。§6 のフェーズ順を当初案の Android → iOS から iOS → Android に入れ替えた (反映済み)。

### 9.1 対応 OS 下限の調査 (項目 8)

調査日: 2026-11-16。一次情報は Flutter 公式ドキュメント "Supported deployment platforms" (docs.flutter.dev/reference/supported-platforms、Flutter 3.50 時点の記載、2026-11-11 更新) と Flutter リリースノート (調査時点の安定版は **Flutter 3.50**)。

**現在の Flutter 安定版がサポートする範囲 (公式)**:

| OS | Supported (サポート対象) | Unsupported |
|---|---|---|
| Android | API 24 〜 37 | API 23 以下 |
| iOS | 15 〜 27 | 14 以下 |

すなわち、フレームワーク側の下限は **Android = API 24 (Android 7.0)**、**iOS = 15.0** である。

**本人想定 (iOS 15 / Android 10) との設定可否**:

- **iOS 15.0**: 設定可能であり、同時に**現在の Flutter 安定版の下限そのもの**である。iOS 14 以下は公式に Unsupported であり、現行 Flutter では下限として設定できない (本人の想定が結果的にフレームワークの下限と一致した)。v1 で使う機能 (HTTP + JSON、UDP ソケット) に iOS 15 より新しい API を要するものはなく、この下限設定によって使えなくなる Flutter 機能はない。個別プラグインの下限は実装時の選定で確認する (標準的なプラグインの下限は iOS 15 以下に収まるものが大半)。
- **Android 10 (API 29)**: フレームワークの下限 (API 24) より上にあり、余裕を持って設定可能である。Flutter の機能・主要プラグインの下限は API 24 前後に集まっており、API 29 の設定で失うものはない。フレームワークの下限である API 24 まで下げることも技術的には可能だが、下げることで得られる対象端末は本プロジェクトには存在せず、検証面だけが広がるため採用しない。

**本人の端末事情との整合**:

- 脱獄済み iPhone SE (第 1 世代) の上限は **iOS 15.8** であり、下限 15.0 の範囲にちょうど収まる。この端末を検証に使えることが、iOS 下限を 15.0 に置く実務上の決定打でもある (16 以上に上げると切り捨てることになる)。
- 主力の iPhone 15 Plus と iPad は現行 OS で範囲内。
- Android 検証端末の Xperia Ace は Android 12 (API 31) で、API 29 の下限の範囲内。

**結論 (推奨 = 決定)**: **iOS 15.0 / Android 10 (API 29)**。両方とも本人の想定どおりであり、特に iOS については現行 Flutter の下限と一致するため、それ未満へ下げる余地自体がないことを併記する。

---

## 10. 未確定事項 (計画前提のリスク)

| # | 事項 | 影響 | 解消するフェーズ |
|---|---|---|---|
| 1 | 番組表データの取得経路と形式 (DMS の EPG ファイル形式が未解析) | 番組表 (後続バージョン候補) の実装方式が決まらない。v1 の必須範囲には影響しない | フェーズ 0 (調査として) |
| 2 | X-DTVToken の要否の範囲 (エンドポイントごとの要否) と、算出式の実機での最終確認 | WebAPI クライアントの認証設計 | フェーズ 0 |
| 3 | 各エンドポイントの要求/応答 JSON スキーマ (静的解析ではパス名までで、項目定義は未確定) | コアの型定義全般 | フェーズ 0 |
| 4 | iOS のみ存在する 6 件 (recordedContentCountGet 等) と Vita のみの定義の実働可否 | 機能の実装可否 (代替手段の要否) | フェーズ 0 |
| 5 | iOS のローカルネットワーク許可・マルチキャスト受信の制約下で SSDP 発見が成立するか | 発見機能の成立 (不成立なら手動登録が主経路になる) | フェーズ 2 (設計自体は §5.2 で吸収) |
| 6 | 資格情報ペアの調達可否 | フェーズ 5 (再生) の成否そのもの。v1 には影響しない | 範囲外 (調達の線は別途) |
| 7 | nasne 側の DTCP クライアント登録・AKE 受け入れ条件 | フェーズ 5 の開始条件 | フェーズ 5 冒頭 |

---

## 付記: 本書の範囲

本書は計画であり、実装・実機操作は一切行っていない。§9 の決定事項は 2026-11-16 に全て決定済みであり、次に進む場合はフェーズ 0 から着手する。本書は新規リポジトリの作成時にそちらへ移管する (§9 の項目 2)。
