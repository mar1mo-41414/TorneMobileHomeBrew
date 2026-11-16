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

**フェーズ 0 の実測による経路の確定 (2026-11-16 追記)**: 本節の表は静的解析時点の対応づけであり、各機能の**実際に使う経路 (トランスポート) は §11 の実測と §12.1 の確定表が正**である。特に録画予約・録画一覧については、当初「WebAPI (JSON) を主経路、UPnP を予備」としていた前提が実測で逆転した (JSON 形は LAN から到達できず、UPnP SOAP が主経路。§11.6・§11.7)。§3.3・§3.4・§3.5 は実測に合わせて書き換え済みである。

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
| チャンネル構成 | `status/channelListGet` (実測: 要パラメータ `broadcastingType`、地上は `=2`。§11.4) |
| 現在 / 次番組 (v1 の番組情報) | `status/liveStreamStatusListGet` の `EIT_PF` (実測で取得経路を確定。§11.4・§11.9)。v1 はこの「現在/次」表示で組む (§12.8) |
| チャンネルロゴ | `chEpg/channelLogoDataGet` (実測で取得可能、バイナリ応答。§11.4) |
| EPG 版数確認 | `status/EPGVersionInfoGet` (実測: 応答は JSON ではなくバイナリの版数テーブル。§11.4) |
| 番組データ本体 (EPG グリッド用) | **取得形式が未確定**。フェーズ 0 で、アプリ内テンプレートの経路 (DMS ポート 60151 の `EPG_*.dat`) は本機で到達不可と確定し、候補は `chEpg/EPGGet` の要求バイナリ形式の解明に絞られた (§11.9)。v1 をブロックしない研究スレッドとして分離する (§12.8) |

### 3.4 録画予約

**主経路は UPnP SOAP (ポート 64230、XsrsSrv の `X_ScheduledRecording:2`)** — フェーズ 0 の実測で確定した (§11.6・§11.7)。当初主経路と想定した JSON 形 (`schedule/*`) は 64210 で 404、他ポートでも到達できず、LAN のクライアントが使う面ではない。

| 機能 | 手段 (SOAP アクション) |
|---|---|
| 予約一覧 | `X_GetRecordScheduleList` (Result は xsrs 形式 XML) |
| 予約作成 | `X_CreateRecordSchedule` (全項目テンプレート必須。§11.7) |
| 予約更新 | `X_UpdateRecordSchedule` (sparse な部分更新のみ。開始時刻・長さは変更不可。§11.7) |
| 予約削除 | `X_DeleteRecordSchedule` (ID はリスト取得時の item id を使う。作成応答の `0x` 接頭辞付き ID は 803 で失敗する。§11.7) |
| 競合確認 | `X_GetConflictList` |
| (到達不可) | JSON 形の `schedule/reservedListGet` / `reservedInfoCreate` / `reservedInfoUpdate` / `reservedInfoDelete` / `conflictListGet` / `reservedInfoBitrateGet` は LAN から到達できない (§11.6)。定義テーブルには「LAN では使わない経路」として記録だけ残す (§12.2) |

### 3.5 録画一覧・管理

**タイトル一覧の主経路は UPnP SOAP の `X_GetTitleList` (64230、xsrs 形式)** — フェーズ 0 の実測で確定した (§11.7)。JSON 形の `recorded/titleListGet` は LAN から到達できない (§11.6)。メタデータの補完 (残コピー回数、res 情報) は DLNA Browse (§11.8)、件数は WebAPI の count 系 (実働を確認) を併用する。

| 機能 | エンドポイント / 手段 |
|---|---|
| タイトル一覧 | SOAP `X_GetTitleList` (主経路)。JSON 形 `recorded/titleListGet` は到達不可 |
| 件数 | `recorded/recordedContentCountGet` / `recorded/recordedContentMaxCountGet` (いずれも iOS のみとされていたが実働を確認。§11.4) |
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

方式は案 A (Flutter) を前提に書くが、層の切り分け自体は他案でも共通する。本節は方針の置き場とし、フェーズ 1 に向けた具体設計 (モジュール構成、データモデル、エラー表現) は §12 に置く。

### 5.0 設計原則: 差し替え可能なモジュール式 (2026-11-16 本人指示)

**今後も想定外の発見があり得る前提で、基本は差し替え可能なモジュール式にする。** フェーズ 0 では「予約・録画一覧の主経路は WebAPI (JSON)」という計画前提が実測で逆転した (§11.6)。この種の経路の逆転・仕様の相違は今後も起こり得るものとして、コア設計は次を原則とする。

1. **機能領域ごとにインタフェースを切る**: 発見・登録、情報取得、予約、録画一覧、設定、メタデータの各領域に、トランスポートに依存しないインタフェース (Dart の abstract class) を定義する。画面とドメインロジックはこのインタフェースにだけ依存し、具体的なトランスポート (SOAP / WebAPI JSON / DLNA) を知らない。
2. **トランスポート実装はインタフェースの裏側に置く**: SOAP 実装・WebAPI 実装・DLNA 実装は、それぞれ対応する領域インタフェースの差し替え可能な実装クラスとする。経路が変わった場合は、実装クラスの差し替えと組み立て (依存性注入) の変更で済み、画面・ドメイン側は書き換えない。
3. **エンドポイント定義は可能な範囲でデータ駆動にする**: パス / ポート、メソッド、パラメータ、認証要否、応答形式といったエンドポイントの属性は、定義テーブル (コード内の定数テーブル) に集約する。経路変更がコード全体の書き換えではなく、定義の差し替え + 実装クラスの追加・差し替えで済む形にする。ただし定義テーブルに載せるのは実測で確認した範囲に限る (未検証の定義を大量に取り込まない、という従来方針は維持する)。
4. **再生も同じ原則の一例とする**: §5.7 の `PlaybackEngine` 境界は、この原則を再生領域に適用したものと位置づける (v1 はスタブ実装、将来は実エンジンに差し替える)。
5. **アプリ内の表記は公式に準拠する** (2026-11-16 本人指示): モード名・状態名・項目名など、公式 (torne 公式アプリ・nasne の公式表記) に呼び方があるものは、独自の言い換えや生数値ではなく公式表記を優先する。画質モードの DR / 3倍 表記 (§16.4) はその一例。ただし公式表記が未確認のものは勝手に発明せず、生値のフォールバック表示のままにして未確定と記録する。

具体的なモジュール一覧とインタフェースの切り方は §12.2 に定める。

### 5.1 全体構成

```
[UI 層]  画面群 (§5.6)
   |
[アプリケーション層]  画面状態・キャッシュ・操作の調停
   |
[領域インタフェース]  発見・登録 / 情報取得 / 予約 / 録画一覧 / 設定 / メタデータ (§5.0)
   |
[トランスポート実装]  SOAP (XSRS・PvrControl・ContentDirectory) / WebAPI JSON / SSDP
                       + エンドポイント定義テーブル + ローカル状態
   |
[プラットフォーム層]  秘密情報ストレージ (Keychain / Keystore)、ネットワーク到達性、
                       将来: 再生エンジン (§5.7 の境界)
```

コア層は UI から独立させ、フェーズ 0 の実機検証で得た応答フィクスチャで単体テストできる形にする。

### 5.2 発見・登録

- SSDP M-SEARCH (`urn:schemas-upnp-org:device:MediaServer:1`) で LAN 内の nasne を列挙し、description (friendlyName / modelName) で nasne であることを確認する ([37](https://github.com/mar1mo-41414/SonyNasne-DTCP/blob/main/docs/37_pydtcpip_live_verification.md) で実機の description 形式は確認済み)。**実機の SSDP 応答には USN ヘッダが無いため、発見の識別は USN に依存せず、LOCATION (ポート 58888 のデバイス記述) の取得と内容確認を正とする** (§11.2)。
- 発見できない環境 (マルチキャスト制限等) に備え、アドレスの手動登録を必須機能とする。
- 登録の検証は `config/PINVerify` で行う。PIN は本体 MAC アドレスから導出され (`status/networkIfInfoGet` の `macAddr`、§11.5)、PINVerify は「導出した PIN から計算したトークンが正しいこと」の確認である (PIN そのものは送らない)。登録情報 (アドレス、機器識別、MAC) を保持し、PIN の導出素材は秘密情報ストレージに置く (§5.5)。
- 複数台対応は、データモデルは複数台を保持できる形にし、UI は単一台前提とする (後から外せるようにする)。v1 の最小範囲決定からの扱いは §9 の項目 5 に記録した。
- OS 側の制約 (要・実装時確認): iOS のローカルネットワーク許可とマルチキャスト受信の扱い、Android のマルチキャストロック取得。発見が OS 制限で成立しない場合は手動登録へ誘導する。

### 5.3 WebAPI クライアントと認証

WebAPI (JSON) が担うのは**情報取得・状態・設定系と登録検証**であり、予約・録画一覧は担わない (§12.1)。これはフェーズ 0 の実測に基づく分担である。

- ベース URL は `http://<nasne>:64210/`、パスは `<カテゴリ>/<名前>` (例: `status/HDDListGet`)。応答は原則 JSON だが、バイナリを返すものもある (`status/EPGVersionInfoGet`、`chEpg/channelLogoDataGet`、各種 Map 取得。§11.4)。応答形式はエンドポイント定義側の属性として持つ (§12.2)。
- 認証は `X-DTVToken` ヘッダ。算出式は `base64(SHA1(PIN + パス + 本文の先頭 256 文字))` で確定した (§11.5)。要否も実測で確定済み: **GET は全て認証なし、POST の Set 系は必須**。トークンの算出と保持は認証モジュールに閉じ、領域インタフェースの側には出さない (§12.4)。
- エラー処理: HTTP ステータスと応答 JSON の `errorcode` を、§12.6 の統一エラー表現へ変換して画面に伝える。タイムアウトと再試行は読み取り系のみ (作成・削除等の書き込み系は自動再試行しない — 二重予約や二重削除を防ぐ)。
- エンドポイントの属性 (パス、メソッド、パラメータ、認証要否、応答形式) は定義テーブルに集約する (§5.0 の原則 3)。テーブルに載せるのは v1 で使う実測済みの範囲に限り、応答のパースはエンドポイントごとの型付きモデルで行う (定義テーブルは「行き先と形式」の管理、モデルは「中身の型」の管理と分ける)。

### 5.4 UPnP / DLNA 層

- **X_ScheduledRecording の SOAP (ポート 64230) が、予約 CRUD・競合確認・録画タイトル一覧の主経路である** (フェーズ 0 で実測。当初案の「WebAPI で代替できる範囲では SOAP を使わない」は実測により取り消す)。X_PvrControl はタイトル詳細等の補助に使う。詳細は §12.3。
- ContentDirectory `Browse` (ポート 58888) で DIDL を取得し、録画メタデータの補完 (残コピー回数 `av:COGCount`、res の protocolInfo、DTCP1HOST / DTCP1PORT) に使う。資格情報なしで成立することは [37](https://github.com/mar1mo-41414/SonyNasne-DTCP/blob/main/docs/37_pydtcpip_live_verification.md) で実証済みで、フェーズ 0 でも再確認した (§11.8)。
- DMS のデバイス記述・ContentDirectory の control は**ポート 58888**にある。アプリ内テンプレートにあった 60151 は本機では listen していない (§11.3)。ポートや control URL は固定値に決め打ちせず、発見時に得たデバイス記述から解決することを基本とする (§12.3)。

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

- インタフェースとして `PlaybackEngine` を定義する。入力: 対象タイトルの res URL と DTCP 接続先 (DTCP1HOST / DTCP1PORT)、出力: 復号済み TS ストリームをプレイヤーへ渡す口。v1 では「未対応」を返すスタブのみを置く。**この境界は §5.0 の設計原則 (差し替え可能なモジュール式) を再生領域に適用した一例であり、他の機能領域のインタフェースと同じ考え方で切る。**
- UI 側はこの境界越しにだけ再生を要求し、境界の内側 (AKE、PCP 復号、資格情報の保持) は v1 の関心事にしない。
- 資格情報ペアが得られた場合の保持場所は秘密情報ストレージとし、アプリの通常の状態保存とは分離する (詳細は §8)。

---

## 6. フェーズ分けと完了条件

### フェーズ 0: API 実機検証 (PC 上の検証スクリプト)

- 目的: v1 で使うエンドポイントの実働・要求形式・応答スキーマ・トークン要否を、公式 FW 実機で確定する。
- 内容: 読み取り系を先に全数確認し、書き込み系 (予約作成・更新・削除等) は本人の承認したテスト対象でのみ確認する (§7)。番組表の取得経路 (EPG ファイル形式) の確定を含む (後続バージョン候補のための調査として)。
- **完了条件**: §1.2 の v1 機能に対応するエンドポイント (§3) について、要求/応答の実例 (フィクスチャ) が記録され、未確定事項 (§10) のうちフェーズ 0 担当分が解消または「実働しない」と実測で確定している。

### フェーズ 1: コア実装

- 目的: §5.0 の設計原則 (差し替え可能なモジュール式) に沿って、領域インタフェースとトランスポート実装 (SSDP / WebAPI JSON / SOAP / DLNA)、エンドポイント定義テーブル、認証、ローカル状態を、UI から独立したコアとして実装する。具体設計は §12。
- 内容の順序 (§12.9): (1) プロジェクト土台とコアの骨格 (インタフェース、定義テーブル、統一エラー) → (2) 発見・登録と情報取得 (読み取り系の縦切り) → (3) SOAP 層と予約・録画一覧 → (4) DLNA メタデータの統合。
- **完了条件**: フェーズ 0 のフィクスチャに対する単体テストが全モジュールで通り、実機に対して「発見 → 登録検証 → 状態取得 → 予約の一覧・作成・削除 → 録画一覧の取得」が CLI 相当のハーネスで再現できる。トランスポート実装の差し替えが、画面・ドメイン側の変更なしに行える構成であること (インタフェースに対するモック実装でテストが書けることをもって確認する)。

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
| 1 | 番組表データ本体の取得形式 (`chEpg/EPGGet` の要求バイナリ形式)。DMS の EPG ファイル経路は本機で到達不可と確定済み | 番組表グリッド (後続バージョン候補) の実装方式のみ。v1 は EIT_PF の現在/次番組で組むため影響しない (§12.8) | **研究スレッドとして分離** (フェーズ 0 で部分解消、§11.9・§11.10)。v1 の進行はブロックしない |
| 2 | X-DTVToken の要否の範囲 (エンドポイントごとの要否) と、算出式の実機での最終確認 | WebAPI クライアントの認証設計 | **解消済み** (フェーズ 0、§11.5) |
| 3 | 各エンドポイントの要求/応答スキーマ | コアの型定義全般 | **解消済み** (フェーズ 0、§11.4・§11.7・§11.8。検証済み範囲) |
| 4 | iOS のみ存在する 6 件 (recordedContentCountGet 等) と Vita のみの定義の実働可否 | 機能の実装可否 (代替手段の要否) | **解消済み** (フェーズ 0、§11.10) |
| 5 | iOS のローカルネットワーク許可・マルチキャスト受信の制約下で SSDP 発見が成立するか | 発見機能の成立 (不成立なら手動登録が主経路になる) | **判定済み (2026-11-16 実機確認): LC サイドロード環境では不成立** (§16.2)。代替としてサブネット走査式発見を追加 (§16.3)。手動登録は正常動作を確認 |
| 6 | 資格情報ペアの調達可否 | フェーズ 5 (再生) の成否そのもの。v1 には影響しない | 範囲外 (調達の線は別途) |
| 7 | nasne 側の DTCP クライアント登録・AKE 受け入れ条件 | フェーズ 5 の開始条件 | フェーズ 5 冒頭 |

---

## 付記: 本書の範囲

本書は計画書であり、アプリ本体の実装はまだ行っていない (フェーズ 0 の実機検証は §11 に記録したとおり実施済み)。§9 の決定事項は 2026-11-16 に全て決定済み。本書は新規リポジトリ (TorneMobileHomeBrew) へ移管済みであり、本書が計画の正本である。フェーズ 0 は完了し (§11.12)、フェーズ 1 は §12 の再設計に基づいて着手する。

---

## 11. フェーズ 0 の実施結果 (2026-11-16)

計画 (§6 フェーズ 0) に基づき、公式 FW 実機で API 実機検証を行った記録。生の応答 (フィクスチャ) と検証スクリプト、書き込み操作の全ログは marnux の作業領域 `~/GitTmp/myClaude/tmhb.work/2026-11-16-phase0/` に保存した (リポジトリには入れない。§7 のマスク方針に従い、本節には構造と要点のみを書く。MAC アドレス・PIN・トークン値・HDD シリアル・番組名・コンテンツ ID の実値は記載しない)。

### 11.1 実施条件と範囲

- 日時: 2026-11-16 13:24–13:44 (JST)。実施場所は marnux (同一 LAN)。
- 対象実機: 公式 FW (ソフトウェア版数 `0260` = 2.60、`status/softwareVersionGet` で確認)、HDD-B 構成。日常録画に使われている実機であり、検証中も録画セッションへの干渉は行っていない (停止系・コピー消費操作は従来どおり対象外)。
- 範囲: 読み取り系の全数確認に加え、本人の承認 (2026-11-16、録画と SPI は保存済みで消えて困るデータはないとの判断) を受けて書き込み系も検証した。書き込みは「予約はテスト用の将来番組で作成→確認→更新→削除の往復」「設定変更は変更前の値を控えて元へ戻す」「既存の本番予約・既存録画は変更しない」の方法で実施し、全操作を作業領域の `write_ops.log` に記録した。
- **計画前提との重要な相違**: §3 では録画予約・録画一覧の主経路を WebAPI (JSON) とし UPnP を予備としていたが、実測では **LAN における実働経路は UPnP SOAP (XSRS) であり、schedule / recorded の JSON 形は LAN から到達できなかった** (§11.6・§11.7)。フェーズ 1 の設計はこの実測に合わせる必要がある。

### 11.2 発見 (SSDP) の実挙動

- M-SEARCH (ST: `urn:schemas-upnp-org:device:MediaServer:1`) に実機が応答する。LOCATION は `http://<実機>:58888/` (DMS のデバイス記述)。
- **癖: 実機の SSDP 応答には USN ヘッダが無い** (DMS デバイス分。uuid は別バリアント応答の ST に現れる)。クライアントは USN の存在に依存しないこと。
- デバイス記述: friendlyName / modelName とも `nasne`、manufacturer は Sony Computer Entertainment Inc.、s-bras:productName は CECH-ZNR2J、`av:standardCDS` 5.0、`av:videoRoot` は `0/video`。サービスは ConnectionManager / ContentDirectory (いずれも 58888) と X_PvrControl / X_ScheduledRecording (いずれも 64230)。SCPD 4 件とも取得できた。
- 別個のルートデバイスとして Telepathy デバイス (ポート 33413、devdesc.xml) も SSDP で広告される。

### 11.3 ポートとサーバの実測マップ

| ポート | 実体 | 実測結果 |
|---|---|---|
| 64210 | `webapi` バイナリ (公式 FW rootfs の静的調査でも同定) | JSON API のサブセットを実装 (§11.4・§11.5)。GET は認証なし、POST (Set 系) は X-DTVToken 必須 |
| 64220 | WANProxySrv (WebUI app.js の `REMOTE_API_PORT`) | 素の HTTP 要求は全て 400。リモートアクセス用のプロトコル/登録が前提で、LAN からの直接利用はできない |
| 64230 | XsrsSrv | UPnP SOAP (X_PvrControl / X_ScheduledRecording) が LAN で実働 (§11.7)。JSON 形のパスもサーバ側には存在するが素の JSON 要求は 400 (§11.6) |
| 58888 | DMS (UPnP) | デバイス記述・ContentDirectory / ConnectionManager の control・SCPD |
| 58890 | ウェブビデオ HTTP | DIDL の res URL の指す先 (`/web/video/pvr?id=...&quality=...`、§11.8) |
| 60151 | (アプリ内テンプレート上の DMS コンテンツポート) | **本機では listen していない** (接続拒否)。§11.9 |
| 33413 | Telepathy デバイス | SSDP 広告のみ確認 |
| 80 | WebUI 系 HTTP | API パスには 400 を返す。本検証では深追いしていない |

### 11.4 WebAPI (JSON、64210) — 検証済み読み取りエンドポイント

全て GET・認証なしで HTTP 200 + `errorcode: 0` の JSON を返すことを確認した (応答キーは実測)。

| エンドポイント | 応答の要点 |
|---|---|
| `status/softwareVersionGet` | `softwareVersion` (="0260")、`backdatedVersion` |
| `status/updateCheck` | `existFlag` |
| `status/isFinishSetup` | `finishSetUpFlag` |
| `status/boxNameGet` | `name` |
| `status/currDateGet` | `currDate` (ISO 形式)、`type` |
| `status/areaInfoGet` | `areaIdentifierCode`、`pref`、`zipCode` |
| `status/channelListGet` | **要パラメータ `broadcastingType`**。`=2` で 200 (地上 24 チャンネル)、`=0` / `=1` は 400。`channel[]` の項目は networkId / transportStreamId / serviceId / serviceType / channelNumber / serviceName / freqChannelNo / remoteControlKeyId 等 |
| `status/HDDListGet` | `HDD[]` (id / internalFlag / mountStatus / registerFlag)、`number` |
| `status/HDDInfoGet` | **要パラメータ `id`**。`HDD` に format / name / vendorID / productID / serialNumber / usedVolumeSize / freeVolumeSize / totalVolumeSize (バイト単位) |
| `status/BCASInfoGet` | `cardId` / `info` / `returnCode` / `status` / `sw` |
| `status/networkIfInfoGet` | `macAddr` / `ipv4Addr` / `gateway` / `subnetMask` / `primaryDNS` / `secondaryDNS` / `enableDHCPFlag`。PIN はこの `macAddr` から導出される (§11.5) |
| `status/recNgListGet` | `item` / `number` (実施時 3 件) |
| `status/liveStreamStatusListGet` | **集約ステータス**。トップレベル 31 キーに CAMsg / EMMMsg / EIT_PF / dtvChannelList / bsChannelList / csChannelList / tvTimerList / recContentsList / recNgList / dmsStreamStopReasonList 等を含む。メッセージ表示とライブ状態の実用上の取得元はこれ |
| `status/dtcpipClientListGet` | `number` (実施時 0) |
| `status/parentalRatingInfoGet` | `parentalRatingInfo` |
| `status/mobileBitrateInfoGet` | `bitrateInfo` (整数) |
| `status/dmsStreamStopReasonListGet` | `number` (実施時 0) |
| `status/requestClientInfoGet` | iOS のみ存在とされていたが**実働する**。`client` に**要求元クライアント自身**の情報 (ipv4Addr / macAddr / registerFlag / name / userAgent / cn / lastAccessDate) が返る |
| `recorded/recordedContentCountGet` | iOS のみ存在とされていたが実働。`count` (実施時 2) |
| `recorded/recordedContentMaxCountGet` | 同上、実働。`count` (=3000) |
| `config/internalHDDInitializeProgressGet` | `completePercent` / `status` |
| `config/HDDRegisterProgressGet` | **要パラメータ `id`**。同上の進捗形 |
| `config/channelScanProgressGet` | **要パラメータ `broadcastingType`**。同上の進捗形 |
| `recorded/thumbnailMapGet` / `recorded/PMTMapGet` / `recorded/SEMapDataGet` | **要パラメータ `id`** (タイトル ID)。`application/binary` のバイナリ応答 |
| `chEpg/channelLogoDataGet` | **要パラメータ `broadcastingType`**。バイナリ応答 (実施時 8,452 バイト、チャンネルロゴデータ) |
| `status/EPGVersionInfoGet` | **要パラメータ `broadcastingType`**。応答は **JSON ではなくバイナリ** (実施時 2,900 バイト。チャンネル毎の EPG 版数テーブルとみられる) |

未確定のまま残したもの (パラメータ形式が特定できなかった):

- `status/CAMsgInfoGet` / `status/EMMMsgInfoGet`: 素の GET・POST・`broadcastingType` 付きのいずれも 400。内容自体は `liveStreamStatusListGet` で取得できるため v1 への影響はない。
- `recorded/recordedContentAdditionalInfoGet`: `id` パラメータで 200 だが応答が空。パラメータ名の確定が残る。
- `recorded/recordedContentThumbnailGet`: `id` では 400。Vita 定義テーブルのキーから `thumbnailEntryId` が必要な見込みだが、その値の出所 (JSON 形 titleListGet) が LAN で到達できないため未確定。

実在しないもの (404、本 FW では未実装と確定):

- `status/dtvtunerDeviceInfoGet`、`status/multiTunerLiveStreamStatusListGet` (いずれも iOS のみ存在の 2 件)。

### 11.5 WebAPI (JSON、64210) — 認証と書き込み検証

認証 (X-DTVToken) の確定事項 (§10 の項目 2 への回答):

- 形式は開発側の既存知見どおり: `X-DTVToken = base64(SHA1(PIN + パス + 本文の先頭 256 文字))`、Content-Type は `application/x-www-form-urlencoded`。PIN は本体 MAC アドレスの下位 3 バイト (`status/networkIfInfoGet` の `macAddr` からコロンを除いた文字列の 7 文字目以降、その表記のまま小文字)。
- **GET は全て認証なし** (§11.4)。**POST の Set 系はトークン必須**で、対照実験で証明した: `config/boxNameSet` はトークン無しで 400 (拒否)、トークン付きで 200。
- `config/PINVerify` は **POST + トークン、本文なし** で `errorcode: 0` となる。PIN そのものをパラメータで送る必要はなく、トークンの正しさ自体が検証になる。

検証した書き込み (全て往復で確認し、元へ戻した):

| 操作 | 結果 |
|---|---|
| `config/PINVerify` | 成功 (上記) |
| `config/boxNameSet` | テスト名へ変更 → `boxNameGet` で確認 → 元の名称へ復元 → 確認。一連成功 |
| `config/mobileBitrateInfoSet` | `bitrateInfo` 0 → 1 → 確認 → 0 へ復元 → 確認。一連成功 |

### 11.6 schedule / recorded の JSON 形が LAN で到達できないこと

- `schedule/reservedListGet` / `reservedListGet2` / `conflictListGet` / `reservedInfoBitrateGet`、`recorded/titleListGet` は、64210 では GET・POST とも **404**、64220 / 64230 では **一律 400** で、LAN から JSON 形では到達できなかった (トークン有無・パラメータ・Origin ヘッダのバリエーションでも変わらず)。
- 公式 FW rootfs の静的調査による所在: 64210 のサーバ (`webapi` バイナリ) のテーブルにこれらの名前は**無く**、`titleListGet` 等のパス文字列は XsrsSrv と WANProxySrv にのみ存在する。すなわち JSON 形はリモート経路 (WANProxy 配下) のための面であり、LAN のクライアントが使う面ではない、というのが実測と整合する解釈である。
- 代わりに LAN で実働する経路は UPnP SOAP (§11.7) と ContentDirectory Browse (§11.8) であり、torne 側の定義テーブルのキー名 (searchCriteria / filter / startingIndex / requestedCount / sortCriteria) が XSRS の SOAP 引数名と一致することとも整合する。

### 11.7 UPnP SOAP (XSRS / X_PvrControl、64230) — 検証結果と予約の往復

認証なしで実働を確認したアクション:

- `X_ScheduledRecording:2` (control URL は `/XSRS` と `/xsrs/control/X_ScheduledRecording` の両形とも可): `X_GetRecordScheduleList`、`X_GetTitleList`、`X_GetConflictList`、`X_CreateRecordSchedule`、`X_UpdateRecordSchedule`、`X_DeleteRecordSchedule`。
- `X_PvrControl:1`: `X_GetFirmwareVersion`、`X_GetLiveChList` (引数 BroadcastType は `"DTT"` のような文字列。WebAPI の数値 `broadcastingType` とは別体系)、`X_GetTitleInfo`、`X_GetTitleDetail`。`X_GetMediaInfo` は recordDestinationID の値の形式が合わず 500 Fault (値形式は未確定)。

スキーマ (実測):

- `X_GetRecordScheduleList` の Result は xsrs 形式 XML。予約が無ければ空の xsrs 文書が返る (検証開始時点で予約は 0 件だった)。
- `X_GetTitleList` の Result も xsrs 形式で、item の項目は title / scheduledStartDateTime / scheduledDuration / scheduledChannelID / desiredQualityMode / genreID / reservationCreatorID / titleProtectFlag / titleNewFlag / recordingFlag / recordDestinationID / recordSize / lastPlaybackTime (resumePoint 属性付き) / portableRecordFile。件数は `recordedContentCountGet` と一致した (2 件)。

予約の往復検証 (テスト予約: 2 日後の未明 04:00、300 秒、地上の実在チャンネル。作成 → 読み取り確認 → 更新 → 削除 → 不在確認) で確定した事項:

- **作成は torne 本体の埋め込みテンプレートの全項目形でのみ成功する**。必須形: `item id=""`、scheduledStartDateTime (ISO 形式、タイムゾーンは `+09:00` のコロン形)、scheduledDuration (秒)、scheduledConditionID (空で受理され、サーバ側で "1" に正規化される)、scheduledChannelID (broadcastingType / channelType 属性付き、値は serviceId の `0x%04x` 形)、desiredQualityMode、**desiredMatchingID (type="SI_PROGRAMID"、値は `,,0x<networkId>,0x<eventId>` の形。サーバ側で 4 要素形に正規化される)**、reservationCreatorID、priorityFlag、recordDestinationID。desiredMatchingID を欠く最小形は 402 (Invalid Args) で失敗した。**作成に title 要素は含まれない** (番組名は EPG イベント側から決まる)。
- **削除の ID の罠**: 作成応答の `RecordScheduleID` は `0x` 接頭辞付きで返るが、その値をそのまま削除に使うと **803 で失敗する**。削除には**リスト取得で得た item の id (接頭辞なし)** を使う。
- **更新は sparse な部分更新のみ**: torne の更新テンプレートは item の id と scheduledConditionID / desiredQualityMode / priorityFlag (/ recordDestinationID) だけを含む形で、この形では受理される (HTTP 200、Result に item id が返る)。開始時刻と duration は更新テンプレートに含まれず、**このアクションでは変更できない** (一括形で送っても duration の変更は反映されなかった。保存済み item の verbatim 送信は 402)。時刻・長さの変更は削除+再作成が前提という設計とみられる。
- **desiredQualityMode の変更は未反映**: sparse 形で 100 → 101 を送り受理されたが、保存値は 100 のままだった。101 が無効な値なのか、画質が作成後変更不可なのかは未確定 (フェーズ 1 以降の残件)。
- 検証後の最終状態: テスト予約は全て削除し、リストが空であることを確認した。既存予約・既存録画への変更は行っていない。

### 11.8 DLNA ContentDirectory Browse (58888)

- デバイス記述の control URL への Browse が認証なしで成立する (docs/37 の再確認 + 構造の確定)。
- コンテナ構成: ルート → `0/video` に genre / date / all / folder / LiveTuner の 5 コンテナ。`0/video/all` が全録画 (2 件、件数は WebAPI・XSRS と一致)。
- DIDL の item 項目: dc:title / dc:date / dc:description、upnp:class / genre / channelName / channelNr / scheduledStartTime / scheduledEndTime、arib:longDescription / captionInfo / audioComponentType / videoComponentType 等、**`av:COGCount` (残コピー回数、実施時 10)**、res。
- res の protocolInfo は `application/x-dtcp1` で DTCP1HOST / DTCP1PORT を含む (AKE 用ポートは動的。実施時は 57343)。**res URL は 58890 のウェブビデオ経路** (`/web/video/pvr?id=<タイトルID>&quality=dr`、`&quality=mobile`、`&sep` バリアント) を指す。60151 は使われていない。

### 11.9 番組表 (EPG) 取得経路の結論 (§10 の項目 1 への回答)

確定した事実:

1. アプリ内テンプレートの経路 (DMS ポート 60151 の `EPG_TRDEPG_FILE.dat` ほか 8 ファイル名 — TRD/BS/CS/HA の EPG とロゴ) は、**本機では到達できない**。60151 は listen しておらず接続拒否、同じパスは 58890 / 64210 / 58888 のいずれでも 404。
2. `chEpg/` カテゴリは 64210 に実在する。`chEpg/channelLogoDataGet` は取得可能 (バイナリ)。しかし **`chEpg/EPGGet` (Vita の文字列では POST + `application/binary` + X-DTVToken) は空ボディでは 400**、`chEpg/EITPFGet` も単純な GET 形では 400 で、**要求バイナリの形式が未確定**。
3. `status/EPGVersionInfoGet` は JSON ではなくバイナリの版数テーブルを返す。

結論: **番組表データ本体の取得形式はフェーズ 0 では確定できなかった** (経路の候補は chEpg/EPGGet に絞られたが、要求形式の解明が残る)。現時点で実用可能な番組情報は、チャンネル構成 (`status/channelListGet`) と現在/次番組 (`status/liveStreamStatusListGet` の EIT_PF) まで。EPG グリッドは v1 の必須範囲外 (§1.2) であり、本件は後続フェーズの残件として、アプリ側コードの解析 (EPGGet 要求バイナリの組み立て) から再開するのが筋である。

### 11.10 §10 の未確定事項への対応

| # | 事項 | フェーズ 0 の結果 |
|---|---|---|
| 1 | 番組表の取得経路と形式 | **部分的に解消**。DMS の .dat 経路は本機で到達不可と確定し、候補は chEpg/EPGGet に絞られたが、要求バイナリ形式は未確定 (§11.9)。残件として継続 |
| 2 | X-DTVToken の要否と算出式 | **解消**。GET は認証なし、POST Set 系は必須 (対照実験で証明)。算出式と PINVerify の形も確定 (§11.5) |
| 3 | 各エンドポイントの要求/応答スキーマ | **解消** (検証済みの範囲)。§11.4・§11.7・§11.8 に構造を記録し、フィクスチャは作業領域に保存 |
| 4 | iOS のみ / Vita のみの定義の実働可否 | **解消**。iOS のみ 6 件のうち recordedContentCountGet / recordedContentMaxCountGet / requestClientInfoGet は実働、reservedListGet2 は JSON 形では到達不可 (SOAP 側にも Get2 は無い)、dtvtunerDeviceInfoGet / multiTunerLiveStreamStatusListGet は 404 (未実装)。Vita のみ 4 件のうち mobileBitrateInfoGet / Set は実働を確認。recordedContentChpDataGet は XsrsSrv 側の機能で JSON 形は未検証、liveStreamPCRGet / liveStreamPCRGet2 はライブ系パラメータが必要で未検証 |

### 11.11 実施した書き込み操作の総括

作業領域 `write_ops.log` に全記録がある。要約:

- `config/PINVerify` ×1 (成功)。
- `config/boxNameSet`: トークン無しの対照 (400 で拒否) → テスト名へ変更 → 確認 → 元へ復元 → 確認。
- `config/mobileBitrateInfoSet`: 0 → 1 → 確認 → 0 へ復元 → 確認。
- 予約 (SOAP): テンプレートと更新・削除の形式を確定するために作成を 3 ラウンド実施し、各回とも削除して不在を確認した。初回の削除は ID の `0x` 接頭辞の罠 (803) で一度失敗したが、即座に正しい ID で削除し、リストが空であることを確認してから次へ進んだ。
- **実施しなかった書き込み**: タイトル削除 (削除対象のテスト録画が存在せず、実在する 2 件は本人の通常録画のため。エンドポイント自体は SOAP の X_DeleteTitle が存在)、`config/recNgListDelete` (録画失敗履歴の削除は不可逆のため見送り)、チャンネルスキャン / HDD 登録・解放 / 地域・時刻・ペアレンタル変更 / finishSetup (§7 のとおり本体状態を変える操作は本人の立会い・合意が別途必要)、`config/dtcpipClientStop` (計画どおり対象外)、内蔵 HDD 初期化 (対象外)。
- 最終状態の確認: 本体名称は元の値、bitrateInfo は 0、予約リストは空、録画件数は 2 件で不変。

### 11.12 フェーズ 0 の完了判定

§6 の完了条件 (v1 機能に対応するエンドポイントの要求/応答の実例が記録され、フェーズ 0 担当分の未確定事項が解消または実測で確定している) に対して:

- 発見・登録 (SSDP / PINVerify)、情報取得 (status 系)、録画予約 (SOAP の作成・一覧・競合・更新・削除)、録画一覧 (XSRS / Browse / 件数) について、実働する経路と実スキーマを確定した。**フェーズ 0 は完了**とする。
- 計画との差分として、予約・録画一覧の主経路は JSON WebAPI ではなく UPnP SOAP であることが確定した (§11.1)。フェーズ 1 のコア設計 (WebAPI クライアントと UPnP クライアントの分担) はこの実測を前提に組み直すこと。
- 残件 (フェーズ 1 以降): EPGGet の要求バイナリ形式 (§11.9)、desiredQualityMode の変更可否 (§11.7)、CAMsgInfoGet / EMMMsgInfoGet / recordedContentAdditionalInfoGet / recordedContentThumbnailGet のパラメータ形式 (§11.4)、X_GetMediaInfo の recordDestinationID の値形式 (§11.7)。
- 2026-11-16: フェーズ 0 (API 実機検証) を実施し、結果を §11 に記録した。計画書の正本は本書であり、実機検証の記録も本書に集約する。

---

## 12. フェーズ 1 に向けた再設計 (2026-11-16)

フェーズ 0 の実測 (§11) と設計原則 (§5.0) を受けて、フェーズ 1 のコア設計をここに確定させる。§5 は方針、本節は具体設計であり、両者が食い違う場合は本節を正とする (§3・§5・§6 の該当箇所は本節に合わせて同日書き換え済み)。

### 12.1 トランスポート構成の確定

機能領域ごとに、実測で確定した主経路は次のとおりである。いずれも同一 LAN 内、公式 FW 2.60 での実測に基づく。

| 機能領域 | 主経路 | 所在 | 認証 | 根拠 |
|---|---|---|---|---|
| 発見 | SSDP M-SEARCH → デバイス記述の取得 | UDP 1900 / HTTP 58888 (DMS) | なし | §11.2。応答に USN が無いため識別は記述の内容で行う |
| 登録検証 | WebAPI `config/PINVerify` (POST) | 64210 | X-DTVToken 必須 (本文なし) | §11.5 |
| 情報取得 | WebAPI GET (`status/*`) | 64210 | なし | §11.4。集約ステータス `liveStreamStatusListGet` を含む |
| チャンネル | WebAPI GET `status/channelListGet` | 64210 | なし (要 `broadcastingType`) | §11.4 |
| 予約 (一覧・作成・更新・削除・競合) | UPnP SOAP `X_ScheduledRecording:2` | 64230 (XsrsSrv) | なし | §11.7 |
| 録画一覧 | UPnP SOAP `X_GetTitleList` を主経路とし、件数は WebAPI の count 系、メタデータ補完は DLNA Browse | 64230 / 64210 / 58888 | なし | §11.7・§11.8・§11.4 |
| タイトル詳細の補助 | UPnP SOAP `X_PvrControl` (`X_GetTitleInfo` / `X_GetTitleDetail` / `X_GetLiveChList`) | 64230 | なし | §11.7 |
| 設定 (読み書き) | WebAPI GET / POST (`status/*Get`、`config/*Set`) | 64210 | GET はなし、POST は X-DTVToken 必須 | §11.4・§11.5。v1 の必須範囲は読み取り中心 (§1.2) |
| メタデータ | DLNA ContentDirectory `Browse` | 58888 | なし | §11.8 |

使わない経路 (実測で確定): WANProxySrv (64220、LAN からの直接利用はできない)、`schedule/*`・`recorded/titleListGet` の JSON 形 (LAN から到達不可)、ポート 60151 (listen していない)、Telepathy (33413、v1 の範囲外)。

### 12.2 モジュール設計

§5.0 の原則を Flutter コアのモジュール構成に落とす。v1 では単一アプリ内のレイヤード構成とし、コア (`lib/core/` 相当) は UI に依存しない形を保つ (将来のパッケージ分離を妨げないため)。

**領域インタフェース** (画面とドメインロジックが依存するのはここまで):

| インタフェース | 責務 | v1 の主実装 |
|---|---|---|
| `DiscoveryService` | SSDP スキャン、デバイス記述の取得と nasne の同定、手動アドレスの検証 | SSDP + 記述 XML (58888) |
| `RegistrationService` | 登録フロー (記述取得 → MAC 取得 → PIN 導出 → PINVerify)、登録情報の保持 | WebAPI (64210) |
| `DeviceInfoService` | 本体情報、HDD、ライブ状態集約、メッセージ、RecNG、チャンネル一覧 | WebAPI GET (64210) |
| `ScheduleService` | 予約の一覧・作成・更新・削除、競合確認 | SOAP XSRS (64230) |
| `TitleCatalogService` | 録画タイトル一覧・件数・詳細。DIDL との結合を含む統合モデルの提供 | SOAP XSRS (64230) + WebAPI count + DLNA Browse (58888) |
| `SettingsService` | 設定値の読み取り (名称、bitrate 等) と、将来の書き込み口 | WebAPI (64210) |
| `MetadataService` | DIDL の取得とパース (コンテナ走査、item のメタデータ) | DLNA Browse (58888) |
| `PlaybackEngine` | 再生 (§5.7)。v1 は「未対応」を返すスタブ | スタブ |

**トランスポート層** (インタフェース実装の裏側に置く、差し替え単位):

- `WebApiTransport`: GET / POST、トークン付与、JSON / バイナリ応答の振り分け、`errorcode` の解釈。
- `SoapTransport`: SOAP エンベロープの組み立て、Result の二重 XML パース (§12.3)、Fault の解釈。ContentDirectory の Browse もこの上に載せる。
- `SsdpTransport`: M-SEARCH の送受信と応答の収集。
- 認証は `TokenProvider` に分離する (PIN 導出と X-DTVToken 算出。純粋関数として単体テスト可能にする)。

**エンドポイント定義テーブル**: エンドポイントの属性はコード内の定数テーブルに集約する。WebAPI は (パス、メソッド、必須パラメータ、認証要否、応答形式 JSON/バイナリ)、SOAP は (サービス URN、control URL の解決規則、アクション名、引数名、Result の形式 xsrs/DIDL/スカラー) を持つ。載せる範囲は実測済みのものに限る。応答の中身のパースはエンドポイントごとの型付きモデルが担い、定義テーブルは「行き先・形式・認証」の管理に徹する (モデルまでデータ駆動にはしない — xsrs のような複合形式は型付きパーサの方が安全なため)。

**組み立て**: 実装クラスの生成と注入はアプリ内の 1 箇所 (composition root) に集約する。v1 の規模では手書きの DI で十分であり、コード生成系の DI フレームワークは導入しない (差し替え可能性はインタフェースと composition root で担保する)。

### 12.3 SOAP クライアント層の設計

- エンベロープは文字列テンプレートで組み立て、引数値は必ず XML エスケープする。`Elements` 引数 (xsrs 文書全体) もエスケープして埋め込む (フェーズ 0 の検証スクリプトと同方式で実証済み)。
- 応答のパースは二段で行う: (1) SOAP エンベロープを XML としてパースし、`Result` の文字列を取り出す。(2) その文字列を xsrs / DIDL 文書として再パースする。XML パースには `package:xml` を使う。
- xsrs の `item` (id 属性 + 子要素群) の読み取り基盤は予約一覧とタイトル一覧で共通化し、領域モデルへの変換は各 Service 実装が行う。
- control URL は、発見時に得たデバイス記述の serviceList から serviceType で解決することを正とする。フェーズ 0 では X_ScheduledRecording の control URL に `/XSRS` と `/xsrs/control/X_ScheduledRecording` の両形が使えたため、記述から解決できない場合のフォールバック候補として両形を定義テーブルに持つ。
- **SCPD は実行時に解釈しない**。アクションと引数は定義テーブルに型付きで持つ。理由: SCPD の引数情報だけでは xsrs のような複合引数の実形式は分からず、実測で確定した形式 (§11.7) が正であるため。SCPD の取得自体は診断・能力確認用に残す。
- 競合確認 (`X_GetConflictList`) の Fault について (フェーズ 1 の実機再確認で確定、§13.6): フェーズ 0 で「予約 0 件だと HTTP 500 の Fault が返る」と観測したが、原因は件数ではなく候補 item の**日時表記**だった。受信形の `+0900` 圧縮形で候補を送ると書き込み系アクションに拒否される (id 属性なしで 402、`id=""` で 803) が、`+09:00` コロン形なら予約 0 件でも正常に応答する。したがって Fault は「競合なし」ではなく要求形のエラーとしてそのまま伝播させ、成功扱いにしない。送信日時はトランスポート層で必ずコロン形に整形する (§13.8)。

### 12.4 WebAPI クライアント層の設計

- GET 群は認証なし。応答は型付きモデルへパースする。`liveStreamStatusListGet` は generation 付き部分オブジェクト (CAMsg / EMMMsg / EIT_PF / recNgList / チャンネルリスト等) の集約スナップショットとしてモデル化し、部分ごとに generation を保持する。v1 ではポーリングや generation 差分の最適化はせず、画面表示時の取得 + 手動更新を基本とする (§12.7)。
- メッセージ表示 (CA / EMM) と RecNG は集約スナップショットから取る。個別の `CAMsgInfoGet` / `EMMMsgInfoGet` はパラメータ形式が未確定のため使わない (§11.4)。
- POST の Set 系は `TokenProvider` がパスと本文からトークンを算出して付与する。PIN は登録情報に保持した MAC アドレスから導出する (§11.5)。
- バイナリ応答 (`EPGVersionInfoGet`、`channelLogoDataGet`、各種 Map 取得) は定義テーブルの応答形式属性で振り分け、モデル層へはバイト列として渡す。ロゴは画像表示にそのまま使える。EPG 版数テーブルの解釈は研究スレッド側 (§12.8) の関心事とする。
- 再試行は冪等な GET のみ (回数・間隔は控えめに)。POST は再試行しない (§5.3)。

### 12.5 データモデル

#### 予約 (RecordSchedule) — xsrs item 由来

| 項目 | 内容と注意 |
|---|---|
| id | **正規形はリスト取得時の item id (数字文字列)**。作成応答の `RecordScheduleID` は `0x` 接頭辞付きで返るが、そのまま削除に使うと 803 で失敗するため、モデルでは接頭辞を取り除いた形に正規化し、応答形は保持しない |
| scheduledStartDateTime | 送信は `+09:00` のコロン形、受信は `+0900` 形 (§11.7)。内部表現はオフセット付き日時とし、表記差はトランスポート層で吸収する |
| scheduledDuration | 秒 |
| scheduledConditionID | 作成時は空を送り、サーバ側で `"1"` に正規化される。モデルでは「未指定 = サーバ既定」と扱う |
| channel | `scheduledChannelID` (broadcastingType / channelType 属性付き、値は serviceId の `0x%04x` 形)。Channel モデルへの参照キーとする |
| desiredQualityMode | 画質モード (実測の作成値は 100) |
| desiredMatchingID | type=`SI_PROGRAMID`、値は `,,0x<networkId>,0x<eventId>` の形で送り、サーバ側で 4 要素形に正規化される。**作成に必須** (欠くと 402)。手動予約では eventId なしの形が受理されることをフェーズ 0 で確認した |
| reservationCreatorID / priorityFlag / recordDestinationID | 作成テンプレートの必須項目。destination は実測で `"HDD"` |
| title | **作成には含めない** (番組名は desiredMatchingID 経由で EPG イベント側から決まる)。一覧の item に番組名相当が現れる場合は表示用に保持してよい |

操作の意味論 (モデルの契約として固定する):

- **作成は全項目テンプレートが必須**。モデルからテンプレートを生成する箇所で必須項目を全て埋め、欠けた状態では送信しない (欠けると 402 になることを実測済み)。
- **更新は sparse な部分更新のみ**。変更できるのは scheduledConditionID / desiredQualityMode / priorityFlag / recordDestinationID。**開始時刻と duration はこのアクションでは変更できない**ため、「予約の時刻・長さの変更」はアプリケーション層で削除 + 再作成として提供する。
- desiredQualityMode の変更は、受理されても保存値に反映されない場合がある (未確定、§11.7)。モデル層は「更新後は必ず再取得し、再取得値を正とする」契約にし、画面もそれに従う。

#### 録画タイトル (RecordedTitle) — XSRS item を主、DIDL で補完

| 項目 | 出所と注意 |
|---|---|
| id / title | XSRS item の id 属性 / title |
| scheduledStartDateTime / scheduledDuration | XSRS (録画の開始と長さ) |
| scheduledChannelID / desiredQualityMode / genreID | XSRS。genreID は type 属性付き |
| titleProtectFlag / titleNewFlag / recordingFlag | XSRS (保護、新着、録画中) |
| recordDestinationID / reservationCreatorID | XSRS |
| recordSize | XSRS。**単位が未確定**のため表示には使わず生値を保持する (容量表示は DIDL の cleartextSize と duration を優先する) |
| lastPlaybackTime (resumePoint 属性) | XSRS。再開位置は属性側にある |
| description / longDescription | DIDL (dc:description、arib:longDescription) |
| copyCountRemaining | DIDL の `av:COGCount` (実測 10) |
| res 群 | DIDL。各 res の URL (quality = dr / mobile / sep のバリアント)、protocolInfo (DTCP1HOST / DTCP1PORT を含む)、duration、cleartextSize。**将来の再生用に保持する** (§1.4) |

XSRS と DIDL の結合キーはタイトル ID である。DIDL の item id は `0/video/all/pvr?id=<タイトルID>` の形をしているため、末尾のタイトル ID を取り出して結合する。結合は `TitleCatalogService` の実装内で行い、画面には統合済みモデルだけを渡す (画面は出所を知らない)。

#### チャンネル (Channel)

- 出所は `status/channelListGet` (要 `broadcastingType`、地上は 2)。項目: networkId / transportStreamId / serviceId / serviceType / channelNumber / serviceName / freqChannelNo / remoteControlKeyId。
- 表記体系の違いを定義テーブルで吸収する: WebAPI は数値の broadcastingType、SOAP の `X_GetLiveChList` は文字列の BroadcastType (`"DTT"` 等)、xsrs の scheduledChannelID は属性 + serviceId の 0x 形。放送種別 (地上/BS/CS) の対応表は定義テーブルに置く。
- 予約作成時のチャンネル指定は serviceId を正とし、表示名は Channel から引く。

#### nasne 情報・状態

- `DeviceInfo`: 名称 (boxNameGet)、softwareVersion、currDate、areaInfo、isFinishSetup の状態。
- `HddInfo`: HDDListGet (id / internalFlag / mountStatus / registerFlag) と HDDInfoGet (total / used / free のバイト値、format、name) の組。serialNumber 等の機器特定値はモデルに保持しても表示・記録ではマスクする (§7 の作法)。
- `NetworkInfo`: macAddr (PIN 導出の源)、ipv4Addr、gateway 等。
- `LiveStatus`: `liveStreamStatusListGet` の集約スナップショット (§12.4)。CAMsg / EMMMsg / EIT_PF / recNgList / チャンネルリスト / チューナー状態等を部分オブジェクトとして保持する。
- `ProgramInfo` (EIT_PF): 現在 / 次番組 (§12.8)。フェーズ 0 のフィクスチャ採取時点では EIT_PF は generation のみの未投入状態だったため、**実エントリの項目形式はフェーズ 1 の冒頭で実機から採取して確定する** (小さな確認事項であり、設計全体はブロックしない)。

### 12.6 エラー表現

全トランスポートのエラーを、領域インタフェースの境界で統一エラー表現に変換する。画面はトランスポート固有のエラー形式を知らない。

統一エラーの形: { 分類、コード (元の数値/文字列を保持)、発生元 (領域・トランスポート・エンドポイント/アクション)、再試行可否、利用者向け説明のキー }。

分類: `unreachable` (到達不可・タイムアウト)、`http` (ステータス異常)、`webapi` (JSON の errorcode ≠ 0、または 400 拒否)、`soapFault` (UPnP errorCode + errorDescription)、`parse` (応答形式の不一致)、`validation` (クライアント側の入力検証)、`unsupported` (未対応・スタブ。PlaybackEngine の「未対応」を含む)。

実測したコードの解釈 (変換表に固定する):

| コード | 出所 | 解釈と扱い |
|---|---|---|
| 400 | WebAPI (HTTP) | パラメータ不正、または POST でトークン無し/不正 (対照実験で証明、§11.5)。POST で発生したらまずトークンと形式を疑う |
| 402 | SOAP Fault (Invalid Args) | 要求の形の誤り。利用者の操作ミスではなく実装側の問題として扱い、利用者向けには一般的な失敗として表示する |
| 404 | WebAPI (HTTP) | その FW では未実装のエンドポイント (例: dtvtunerDeviceInfoGet)。「機能の不在」として扱い、画面設計では項目自体を出さない判断に使う |
| 803 | SOAP Fault | ID の形式不正 (作成応答の `0x` 接頭辞付き ID を削除に使った場合、§11.7)。モデル層の正規化で防止するのが本筋で、発生したら実装上の問題として扱う |
| 500 | SOAP Fault 全般 | errorCode と errorDescription を併せて解釈する。`X_GetConflictList` の空時 Fault のような個別の癖は、変換表に個別ルールとして追記していく (§12.3) |

書き込み系のエラーは握りつぶさず、操作の結果として画面に返す。再試行ポリシーは §12.4 (冪等な GET のみ)。

### 12.7 状態管理と画面構成

- 状態管理は **Riverpod** を採用する。理由: provider 経由で領域インタフェースを注入でき、テスト時に実装をモックへ差し替えることが §5.0 の原則と一致するため。代替 (素の ChangeNotifier + 手書き DI) でも原則は満たせるが、差し替えの手続きが一様になる分だけ Riverpod を採る。
- キャッシュ: 登録情報とチャンネル一覧は永続化する (保持先の分担は §5.5)。予約・録画一覧は表示用キャッシュを持ち、真実は常に nasne 側とする。LiveStatus は画面表示時の取得 + 手動更新を基本とし、常時ポーリングはしない。
- 画面は §5.6 の 4 画面 (ホーム/状態、予約、録画済み、設定) を v1 とする。予約フォームは §12.5 の意味論を反映する: 時刻・長さは「編集」ではなく削除 + 再作成になる導線とし、競合の警告は `X_GetConflictList` の結果で出す。録画詳細の再生操作は `PlaybackEngine` スタブの `unsupported` を受けて未実装通知を出す (§1.2 の 5)。
- iPad 対応: 画面幅のブレークポイントでナビゲーション形式 (下部タブ / サイドレール) と一覧・詳細の 2 ペイン表示を切り替える。状態管理とモデルは画面幅に依存させない。

### 12.8 番組表の v1 方針と研究スレッドの分離

- **v1 の番組情報は `channelListGet` (チャンネル構成) と `liveStreamStatusListGet` の EIT_PF (現在 / 次番組) で組む**。「いま・このあと何を放送しているか」の表示と、手動予約 (チャンネル・日時指定) の補助が v1 の範囲である。EPG グリッド表示と番組選択からの予約作成は後続バージョン候補のまま (§1.2)。
- チャンネルロゴ (`chEpg/channelLogoDataGet`、取得可能) はチャンネル表示の補助に使える。
- **`chEpg/EPGGet` の要求バイナリ形式の解明は、v1 をブロックしない研究スレッドとして分離する**。再開点は (a) アプリ側コードの解析 (torne が EPGGet の要求バイナリを組み立てる箇所の特定)、(b) `EPGVersionInfoGet` のバイナリ版数テーブルとの対応付け。成果が出た場合の取り込み条件は、§5.0 の原則どおり「`MetadataService` (または新設の EPG 領域インタフェース) の裏側への実装追加で済み、画面側の変更を要しない形」であることとする。

### 12.9 フェーズ 1 の実装順序 (最初に作るもの)

§6 フェーズ 1 の完了条件に対応する実装の順序は次のとおりとする。

1. **土台**: Flutter プロジェクトの生成 (識別子 `com.markun.tmhb`、OS 下限 iOS 15.0 / Android API 29)、コアの骨格 (領域インタフェース、エンドポイント定義テーブル、統一エラー、`TokenProvider` とその既知値テスト — フェーズ 0 の算出実績と突き合わせる)。
2. **読み取りの縦切り**: SSDP 発見 → デバイス記述の取得 → 登録 (PINVerify) → 情報取得 (DeviceInfo / HDD / チャンネル / LiveStatus) が、CLI 相当のハーネスで実機に対して通ること。EIT_PF の実エントリ形式の採取 (§12.5) もここで行う。
3. **SOAP 層と予約・録画一覧**: `SoapTransport` と xsrs パーサ基盤 → `ScheduleService` (一覧・作成・更新・削除・競合) と `TitleCatalogService` の XSRS 側を、フィクスチャに対する単体テスト + 実機での往復で実装する。`X_GetConflictList` の空時 Fault の再確認 (§12.3) もここで行う。
4. **メタデータ統合**: DLNA Browse → DIDL パース → RecordedTitle への結合 (COGCount、res 群の保持)。
5. **ローカル状態と差し替え可能性の確認**: 登録情報・チャンネルの永続化、表示用キャッシュ、各インタフェースに対するモック実装での単体テスト (画面・ドメイン側がトランスポートに依存していないことの確認)。

---

## 13. フェーズ 1 の実施結果 (2026-11-16)

§12.9 の順序で実装し、§6 のフェーズ 1 完了条件を満たした。実機検証はフェーズ 0 と同条件 (公式 FW 2.60 + HDD-B、テスト予約は作成→確認→削除で後始末、既存予約・既存録画には触れない) で行った。

### 13.1 環境

- Flutter SDK を marnux の `~/GitTmp/flutter` に安定版 clone で導入 (ホーム直下には置かない)。**Flutter 3.50.0 / Dart 3.14.0**。
- この SDK では `package:flutter/material.dart` が非推奨となり `package:material_ui/material_ui.dart` (pub.dev 托管、版 1.11.0) へ移行していたため、雛形に倣いそちらを使用し、pubspec の直接依存に明記した。
- Android SDK / APK・IPA ビルドはフェーズ 1 の範囲外 (関門は Dart テスト + 実機ハーネス)。

### 13.2 実装範囲

- `lib/core/` — §12.2 の 8 領域インタフェース (`services/interfaces.dart`) と実装群。
  - トランスポート: `transport/webapi_transport.dart` (GET は到達性エラーのみ再試行、POST はトークン付与・再試行なし、バイナリ応答の振り分け)、`transport/ssdp_transport.dart`、`transport/soap_transport.dart` (フェーズ 0 と同一の封筒形式、Fault→統一エラー変換)、`transport/xml_util.dart`。
  - サービス実装: 発見 (SSDP→記述解釈)、登録 (PINVerify)、情報取得、設定、予約 (SOAP XSRS)、タイトル目録 (XSRS 主 + DIDL 結合)、メタデータ (DLNA Browse)、再生スタブ (未対応を統一エラーで返す)。
  - パース: `parsing/xsrs.dart` (二段パース、作成テンプレート、疎な更新)、`parsing/didl.dart`。
  - 永続化: `store/registration_store.dart` (登録ストア、キー値ストア、チャンネルキャッシュ。各メモリ版と JSON ファイル版)。
- `lib/app/providers.dart` — Riverpod 合成ルート (インタフェースへのプロバイダ + 機器別サービス束の組立)。
- `lib/main.dart` — カウンタ雛形を合成ルートの最小シェルに置換 (本格 UI はフェーズ 2)。
- `tool/harness.dart` — 実機ハーネス (discover / info / live / eitpf / schedule-list / schedule-cycle / titles / conflict-probe / conflict-matrix / create-probe / update-matrix)。機微な値 (MAC 後半、HDD シリアル、B-CAS ID、PIN、トークン) は出力しない。
- テストフィクスチャ: フェーズ 0 の実測応答をマスクして `test/fixtures/` (webapi / soap / dlna / upnp_description.xml) に収録。ID 類は XSRS↔DIDL の結合が保たれるよう対応付けて置換した。

### 13.3 テスト結果

- `flutter test`: **54 件全合格**。内訳は TokenProvider 既知値、統一エラー変換、WebAPI モデル (マスク済みフィクスチャ)、記述解釈、トランスポート (モック HTTP)、xsrs パース/生成、SOAP サービス (モック + フィクスチャ)、DIDL パース、タイトル結合、ストア往復、プロバイダのモック差し替え、シェルのスモーク。
- `flutter analyze`: **No issues**。
- 段階コミット毎の検証 (worktree で個別実行): ステップ 2 = 32 件、ステップ 3 = 38 件、いずれも全合格。

### 13.4 実機ハーネスの結果

- `discover`: SSDP で 1 台を発見し、記述から 4 サービスのコントロール URL を解決。
- `info`: PINVerify 成功。機器情報 (名称、FW 0260、現在時刻、エリア、HDD 一覧と詳細、地デジ 24 局、recNg 3 件、クライアント情報) を取得。
- `live`: LiveStatus の 29 セクションと generation を取得 (EIT_PF については §13.5)。
- `schedule-list`: 0 件 (検証前の素の状態)。
- `titles`: 件数 API = 2 と一致。XSRS 2 件に DIDL 補完 (COGCount 9 / 10、res 3 件ずつ、DTCP ホスト/ポート、再生時間、cleartextSize、チャンネル名) がタイトル ID で結合された。
- `schedule-cycle`: 作成 (応答 ID を正規化) → 一覧で確認 → 競合確認 (同一候補が自分自身と競合 = 1 件) → 更新 (受理、再読込値を表示) → 削除 → 消滅確認、まで全行程成功。検証後の機器状態は予約 0 件・録画 2 件で不変。

### 13.5 EIT_PF の実エントリ形式 — 採取ならず

フェーズ 0 に続き今回も `EIT_PF` は `{"generation": 0}` のみで、エントリ実体は採取できなかった (2 回の独立した採取で同結果)。他のセクション (dtvChannelList 等) は generation が進んでいるため、EIT_PF は「チューナーが同調中/配信中」等の状態でのみ生成される可能性が残るが、未検証。パーサは防御的 (既知キーは型付き、未知は生保持) のままとし、形式の確定は残件とする。

### 13.6 競合確認の Fault の結論 (§12.3 の前提を訂正)

§12.3 に残した「予約 0 件で X_GetConflictList が Fault を返す癖」という読みは**誤りだった**。実機の変種行列で切り分けた結論:

- 原因は候補 item の**日時表記**だった。フェーズ 0 の write_probe2 の候補は受信形の `+0900` 圧縮形を使っており、xsrs の書き込み系アクションはこの表記を拒否する。`+09:00` コロン形に変えるだけで、予約 0 件でも正常応答 (空の競合リスト) になる。
- Fault のコードは候補の形で変わる: item に id 属性が無い形では 402「Action X_GetConflictList failed」 (フェーズ 0 フィクスチャの姿。バイト同一の再送でも再現)、`id=""` 付きでは 803。
- title 要素の有無、scheduledConditionID の有無、desiredMatchingID の有無は競合確認の成否に影響しなかった。
- これに伴い、サービス層に実装しかけていた「Fault 時は一覧が空なら競合なしとする」フォールバック規則は**誤った前提に基づくため撤去**した。Fault は要求形のエラーとしてそのまま伝播させる。
- 同根の混同が §11.7 の「作成には desiredMatchingID が必須」にも及んでいた: コロン形日時であれば desiredMatchingID 無しでも作成は成功した (実機で作成→一覧→削除まで確認)。作成の全文テンプレート (torne 形) はそのまま維持する (機器側で正規化される実績形であり、害はない)。

### 13.7 更新契約の確定 (実機行列)

X_UpdateRecordSchedule の疎な更新について、8 変種の実機行列で次を確定した:

- **priorityFlag が必須で、かつ変更フィールドが 1 つ以上必要**。priorityFlag 単独 = 853、それ以外のフィールド集合で priorityFlag が無いと 402、priorityFlag + 他 1 フィールド以上で受理。
- モデルに反映: `ScheduleUpdate.priorityFlag` を必須化し、変更フィールド無しの更新はクライアント側で検証エラーにする。
- **受理されても値が反映されるとは限らない**: priorityFlag 0→1、desiredQualityMode 100→101 はいずれも受理されたが再読込では元の値のままだった。§12.5 の「更新後は再読込を正とする」契約はこの実測をもって必須とする。desiredQualityMode の有効値域は未確定。

### 13.8 時刻整形の確定

送信日時の整形は、実行環境のローカル時刻帯に依存せず**機器ローカル (JST、+09:00) の壁時計**で描画する形に確定した (実測の機器タイムスタンプは全て +0900 であり、予約は「機器での壁時計時刻」を意味するため)。Dart の `DateTime.parse` はオフセット付き文字列を UTC 化する点も含め、往復 (パース→整形) が元の表記に戻ることをテストで固定した。

### 13.9 完了条件への照合 (§6 フェーズ 1)

- フィクスチャ単体テストが全モジュールで通る: 充足 (54 件)。
- 実機で「発見 → 登録検証 → 状態取得 → 予約の一覧・作成・削除 → 録画一覧」がハーネスで再現できる: 充足 (§13.4)。
- トランスポート差し替えが画面・ドメイン変更なしに行える構成: 充足 (プロバイダ差し替えテストでモック実装への交換を実証)。

### 13.10 残件とフェーズ 2 への引き継ぎ

- EIT_PF の実エントリ形式 (§13.5): 同調/配信中の採取が次の手。MetadataService の背後に差し込める形は維持されている。
- 更新の反映セマンティクス (§13.7): 反映されるフィールド・値域の同定は未了。UI では再読込値を表示する前提で設計する。
- ファイル版ストアの実配線 (ドキュメントディレクトリの確定) はフェーズ 2 のアプリ組み立てで行う (現状プロバイダのデフォルトはメモリ版)。
- アイコン等の素材作成 (§9 の項目 11) はフェーズ 2 で実施。
- §12.3 本文の「空時 Fault」記述は本節 §13.6 が正であり、フェーズ 2 で §12.3 本文を確定内容に書き換えた (§14)。

## 14. フェーズ 2 の実施記録 (2026-11-16)

### 14.1 Mac 側ビルド環境

- 作業機: MarkBookM4 (macOS 27.3)、Xcode 27.1 (xcode-select は Xcode を指す)。CocoaPods 1.17.0 は Homebrew で導入済みだった (非対話シェルでは /opt/homebrew/bin が PATH に無いため、ビルド時は明示的に通す)。
- Flutter 3.50.0 (安定版、arm64 tarball) を Mac の ~/GitTmp/flutter に導入し、marnux と同バージョンに揃えた。
- リポは Mac の ~/GitTmp/TorneMobileHomeBrew に clone し、pull 専用のビルド用クローンとした (コードの正本作業コピーは marnux)。
- Mac 上で flutter test 56 件全合格。flutter doctor は Xcode 項目 ✓ (Android toolchain はフェーズ 3 の対象のため未整備、Flutter の PATH 警告のみ)。

### 14.2 ファイル版ストアの実配線 (§13.10 の残件)

- path_provider (^2.1.6) を追加し、アプリのドキュメントディレクトリ内の registrations.json / key_values.json に JsonFileRegistrationStore / JsonFileKeyValueStore を接続した (lib/app/bootstrap.dart の fileStoreContainer を、main が UncontrolledProviderScope で設置する)。
- テストを追加した (test/bootstrap_test.dart): ストアがファイル版であることの型確認と、コンテナを作り直しても登録とチャンネルキャッシュが読み戻せること。全体で 56 件全合格、flutter analyze もクリーン。
- commit: 060f1fe。

### 14.3 アイコン (§9 の項目 11)

- 原画 (レトロ TV + アンテナ、画面に録画ドットと再生三角、背景インディゴ) を assets/icon/app_icon_source.webp としてリポに収録した。
- 角丸の外側の白を、原画の背景色インディゴ (#211753) で埋めたフルブリードの 1024×1024 PNG (assets/icon/app_icon_1024.png) を作成し、flutter_launcher_icons (^0.14.4) で iOS / Android のアイコンセットを生成した。
- commit: 5d33f69。

### 14.4 §12.3 の訂正

- §12.3 本文に残っていた「空時 Fault」の旧記述を、§13.6 の確定内容 (原因は候補 item の日時表記の圧縮形 `+0900` であり、コロン形 `+09:00` なら予約 0 件でも正常応答する) に書き換えた。
- commit: b6381fb。

### 14.5 署名なし IPA の生成

- 方法: `flutter build ios --no-codesign --release` で Runner.app を生成し、Payload 形式に zip して IPA 化した (LiveContainer / AltServer でのサイドロードを想定)。
- 成果物: Mac の ~/Downloads/TorneMobileHomeBrew-1.0.0.ipa、7,099,647 バイト、SHA-256 `2171b8b074fac51e0ff9ba3127b8dedf37d34b9c648f1e8835f9000ef3406eb2`。バンドル ID は com.markun.tmhb、バージョン 1.0.0。
- 実機 (iPhone / iPad) へのインストールと起動確認は本人が行う (本記録の範囲外)。

### 14.6 残件

- §5.6 の v1 画面の実装 (フェーズ 2 の残り)。実機で LAN 通信を行う際は Info.plist への NSLocalNetworkUsageDescription の追加が必要になる (§6 フェーズ 2 の完了条件にあるローカルネットワーク許可の挙動確認とあわせて実施する)。
- EIT_PF 実エントリ形式の確定、更新の反映セマンティクス (§13.10 から継続)。

## 15. v1 画面の実施記録 (2026-11-16)

§5.6 の v1 画面を実装し、フェーズ 2 の残件 (§14.6) のうち画面実装と Info.plist 対応を完了した。実機 (iPhone / iPad) へのインストールと画面・通信の確認は本人の担当であり、本節の範囲外である。

### 15.1 §5.6 との対応

| §5.6 の画面 | 実装 | 内容 |
|---|---|---|
| 1. ホーム / 状態 | `lib/ui/home_screen.dart` | 本体情報 (名称・ソフトウェア版数・本体時刻・地域)、HDD (一覧 + 詳細、使用率と空き容量)、ライブ状態 (EIT_PF の現在/次番組、CA/EMM メッセージ)、録画失敗 (RecNG) 一覧、ネットワーク情報、B-CAS 情報 (カード ID はマスク表示)。セクションごとに独立取得・再試行し、アプリバーの更新で全再取得する |
| 2. 予約 | `lib/ui/schedules_screen.dart`、`lib/ui/schedule_form.dart` | 時系列一覧、作成・編集フォーム、削除 (確認ダイアログ付き)、競合警告 (作成前に `X_GetConflictList` を確認し、競合があれば一覧を示して続行可否を問う) |
| 3. 録画済み | `lib/ui/titles_screen.dart` | XSRS + DIDL 統合モデルの一覧 (残コピー回数・保護・新着・録画中を表示)、件数/上限の表示、詳細 (概要・詳細説明・サイズ・再開位置・res 品質)。再生ボタンは `PlaybackEngine` 境界越しに要求し、スタブの未対応を「再生は未実装です」の通知ダイアログに変換する (§1.2 の 5、§5.7) |
| 4. 設定 | `lib/ui/settings_screen.dart` | 登録管理のみ (v1 の範囲どおり): SSDP 発見 → 登録、手動アドレス登録 (記述取得を試み、失敗時は直接形で登録フローへ)、登録の検証 (PINVerify)、登録解除、利用する nasne の選択。MAC アドレスは PIN 導出素材のため下位 3 オクテットをマスクして表示する |

iPad 対応 (§12.7): 幅 720px 以上で下部タブからナビゲーションレールへ切り替え、幅 1000px 以上では予約・録画済みの両画面が一覧 + 詳細の 2 ペイン表示になる。状態管理とモデルは画面幅に依存しない。

### 15.2 状態管理と差し替え可能性

- アプリ状態は `lib/app/state.dart` に集約した: 登録一覧 (AsyncNotifier、ストア連動)、選択中ホスト、タブ位置、機器別データプロバイダ (本体情報・HDD・ライブ状態・RecNG・ネットワーク・B-CAS・チャンネル・予約・録画・件数)。チャンネル一覧は `ChannelCache` に永続化し、取得失敗時はキャッシュへフォールバックする。予約・録画は表示用取得のみで、真実は常に nasne 側 (§12.7)。
- 画面は領域インタフェースにのみ依存する構成を維持し、ウィジェットテストはフェイク実装への差し替え (composition root の override) で全画面を検証する (§5.0 の原則どおり、UI 実装に伴うコア側の変更は無し)。

### 15.3 実機契約 (§13 の確定事項) の UI への反映

- 作成はコアが torne 形式のフルテンプレートを生成する (§11.7)。フォームはチャンネル (地上のチャンネル一覧から serviceId で指定)・日付・開始時刻・長さ (分)・画質モード・優先フラグを入力し、送信日時はコア側で JST の `+09:00` コロン形に整形される (§13.8)。
- 編集は sparse 更新の契約 (§13.7) どおり: priorityFlag を常時含み、変更可能フィールド (条件 ID・画質モード・録画先) を併せて送る。変更が無い場合は送信しない。更新後は一覧を再取得し、再取得値を正とする (§12.5)。
- 開始時刻・長さの変更は削除 + 再作成として提供する。再作成時の競合確認では、置き換え対象の予約自身との競合を除外する。作成が成功した後にのみ元の予約を削除する (作成失敗時に元の予約が残る順序とした)。
- 削除・更新に使う ID は一覧側の数値文字列のみ (作成応答の `0x` 形はモデル層で正規化済み、§12.5)。

### 15.4 アプリのタイトル表記 (本人指示、2026-11-16)

アプリのタイトル表記を **torne mobile HB** に変更した。変更箇所は表示名のみであり、バンドル ID `com.markun.tmhb`、パッケージ名、リポ名、計画書上のプロジェクト名は変更していない。

- iOS: `CFBundleDisplayName` を `torne mobile HB` に変更 (IPA 内の Info.plist で同値を確認済み)。
- Android: `android:label` を `torne mobile HB` に変更。
- アプリ内: `MaterialApp` の title とホーム画面の AppBar を `torne mobile HB` とした。

### 15.5 プラットフォーム対応

- iOS の `Info.plist` に `NSLocalNetworkUsageDescription` を追加した (文面: 「nasne を LAN 内で発見し、操作するためにローカルネットワークへのアクセスが必要です。」)。IPA 内に同キーが含まれることを確認済み。
- Android のマニフェストに `INTERNET` / `ACCESS_NETWORK_STATE` 権限を追加した (リリースビルドでは LAN 通信に必須。フェーズ 3 の前提として先行して入れた)。
- **判定 (2026-11-16 実機確認)**: iOS で UDP マルチキャストの送受信を行うには、ローカルネットワーク許可に加えてマルチキャスト用エンタイトルメント (`com.apple.developer.networking.multicast`) が必要とされる場合がある。このエンタイトルメントは Apple の承認制であり、サイドロード配布では取得できない。**本人の実機確認 (LiveContainer) で SSDP 発見は不成立と確定した** (§16.2)。§10 の項目 5 はこれをもって判定済み。代替の発見経路としてサブネット走査式発見を追加した (§16.3)。

### 15.6 テスト結果

- ウィジェットテストを 10 件追加した (`test/ui_test.dart`: ホーム表示、予約一覧、作成、競合警告の受理、削除、sparse 更新、時刻変更 = 削除+再作成、録画一覧と再生未実装通知、設定での発見→登録、広幅レイアウトのレール + 2 ペイン)。シェルのスモークテスト (`test/widget_test.dart`) は新画面に合わせて書き換えた。
- `flutter test`: **66 件全合格** (marnux / Mac の双方で確認)。`flutter analyze`: 双方で No issues。

### 15.7 実機への読み取り確認

- UI が載るサービス層はフェーズ 1 のハーネスで実機往復を検証済みであり、本実装後に読み取り専用の再確認を行った: 予約一覧 0 件、録画タイトル 2 件 (DIDL 補完・COGCount・res 付き) を取得し、実機の状態 (予約 0 件・録画 2 件) が不変であることを確認した。書き込み系の往復は行っていない (UI 経由の実機確認は本人の実機検証に委ねる)。

### 15.8 署名なし IPA

- 方法は §14.5 と同じ (Mac で `flutter build ios --no-codesign --release` → Payload 形式に zip)。中間生成物は Mac のビルド用クローン内に留め、Mac の Downloads 等には置いていない。
- 成果物: `TorneMobileHomeBrew-1.0.0.ipa`、**8,554,214 バイト**、SHA-256 `741d872e1378242798cb6ecc987efafe284752c365de06c32f30281b2644b414`。
- 配置先 (本人の新ルール): marnux の `~/tmp/Decrypted-ipa/` (常に最新ビルドの置き場であり、本人が LiveContainer でテストする)。配置後にサイズと SHA-256 が Mac 側の生成物と一致することを確認した。前回 (§14) のシェル版 IPA はこの版で置き換わった。

### 15.9 commit 一覧

- `e82ff1a` フェーズ2: v1 画面 (§5.6) の実装
- `9013af3` プラットフォーム: タイトル表記と LAN 通信の前提
- 本節 (§15 の記録)

### 15.10 残件

- 実機確認 (本人担当): **実施済み (2026-11-16)** — インストール・起動・手動登録・ホーム表示・録画一覧の表示を確認。SSDP 発見は不成立と確定 (§16.2)。残るは実機からの予約作成・編集・削除の一巡 (§6 フェーズ 2 の完了条件) と、サブネット走査式発見 (§16.3) の実機確認。
- EIT_PF の実エントリ形式 (§13.5 から継続): ホーム画面のライブ状態は防御的パースのまま実装しており、実エントリが投入された応答での表示確認は未了。
- 更新の反映セマンティクス (§13.7 から継続): UI は再取得値を正とする契約で実装済みであり、追加の同定は任意。

---

## 16. 実機確認のフィードバック対応 (2026-11-16)

本人の実機確認 (iPhone + LiveContainer、§15.10) で得た 3 件のフィードバック — タイトルの文字化け、SSDP 発見の不成立、画質モードの数値表記 — への対応を記録する。

### 16.1 文字化け (ARIB 外字) の原因特定と修正

**症状**: 録画済み一覧とホームの録画失敗一覧で、タイトル末尾の特定文字だけが欠落文字 (「?」の箱) で表示される。通常の漢字・かな・英数字は正常。

**原因の特定 (実機の生応答から)**: 実機 (公式 FW 2.60) から X_GetTitleList (SOAP)、DLNA Browse、recNgListGet (WebAPI) の生レスポンスを取得し、タイトル文字列のコードポイントを全て洗い出した。欠落文字の正体は次の私用領域 (PUA) コードポイントだった。

| 出現箇所 | 文字列末尾 | コードポイント |
|---|---|---|
| 録画タイトル 1 (XSRS / DIDL 共通) | 「５分でみんなの手話（４）家族」の後 | U+E0FE, U+E0FD |
| 録画タイトル 2 (XSRS / DIDL 共通) | 「さわやか自然百景　選　大阪　泉州のため池」の後 | U+E0FE |
| 録画失敗 1 (recNg) | 「きょうの健康　ＣＯＰＤ新ガイドラインで対策　注目！新たな治療の選択肢」の後 | U+E184, U+E0FE |
| 録画失敗 2 (recNg) | 「ＮＨＫ手話ニュース８４５」の後 | U+E0FD |

**切り分け**: PUA コードポイントは生バイト列・UTF-8 デコード結果・アプリのパース結果のいずれにも存在していた。よって喪失段階は (a) 転送・デコードでも (b) パースでもなく、**(c) 表示フォントにグリフが無い段階** である (iOS / Android のシステムフォントはこの PUA 割り当てを持たない)。

**コードポイントの同定**: これらは ARIB STD-B24 の追加記号 (90 区 48–84 点、番組表記号群) を、ARIB 外字フォント対応表 (AFS、ARIB STD-B24 準拠) の PUA 割り当てで符号化したものである。グリフは同対応表のフォントイメージで 1 文字ずつ同定し、独立したレコーダ実装の変換表でも交差確認した (U+E0FD = 手、U+E0FE = 字、U+E184 = 解、等)。出現文脈 (手話番組に [手]、等) とも一致する。

**修正**: パース層 (デバイス由来テキストがモデルに入る入口) で、既知の番組表記号 PUA を角括弧表記 ([手]、[字] 等、日本の EPG ソフトの一般的な変換作法) に置換する `normalizeBroadcastText` を新設した (`lib/core/broadcast_text.dart`)。適用箇所は xsrs のタイトル (録画・予約)、DIDL の title / description / longDescription / channelName、EIT_PF のタイトル、recNg のタイトル、チャンネル名 (serviceName / serviceProviderName)。変換表は 90 区 48–84 点のうち PUA に割り当てられた 34 文字で、同区の他の点は正規 Unicode (U+2B1B 等) に割り当てられているため変換不要である。

| PUA | ARIB | 変換後 | PUA | ARIB | 変換後 | PUA | ARIB | 変換後 |
|---|---|---|---|---|---|---|---|---|
| E0F8 | 90/48 | [HV] | E0FE | 90/54 | [字] | E185 | 90/61 | [SS] |
| E0F9 | 90/49 | [SD] | E0FF | 90/55 | [双] | E186 | 90/62 | [B] |
| E0FA | 90/50 | [P] | E180 | 90/56 | [デ] | E187 | 90/63 | [N] |
| E0FB | 90/51 | [W] | E181 | 90/57 | [S] | E18A | 90/66 | [天] |
| E0FC | 90/52 | [MV] | E182 | 90/58 | [二] | E18B | 90/67 | [交] |
| E0FD | 90/53 | [手] | E183 | 90/59 | [多] | E18C | 90/68 | [映] |
| | | | E184 | 90/60 | [解] | E18D | 90/69 | [無] |
| E18E | 90/70 | [料] | E193 | 90/75 | [新] | E199 | 90/81 | [吹] |
| E190 | 90/72 | [前] | E194 | 90/76 | [初] | E19A | 90/82 | [PPV] |
| E191 | 90/73 | [後] | E195 | 90/77 | [終] | E19C | 90/84 | [ほか] |
| E192 | 90/74 | [再] | E196 | 90/78 | [生] | | | |
| | | | E197 | 90/79 | [販] | | | |
| | | | E198 | 90/80 | [声] | | | |

**対象外 (未確定として記録)**: 表に無い PUA は素通しする (ラベルを発明しない、§5.0 原則 5)。追加漢字の PUA (85/86 区)、90 区 48 点未満と 91 区以降の記号 PUA は実機で未観測のため未対応であり、出現が確認されたら同じ手順 (対応表でのグリフ同定) で表を拡張する。

### 16.2 SSDP 発見の実機判定

本人の実機確認 (iPhone + LiveContainer) の結果:

- 「LAN 内の nasne を探す」では **発見できなかった** (SSDP 不成立)。
- **手動登録は正常動作** し、登録後にホーム表示・録画一覧が正しく表示された。

§10 の項目 5 はこれをもって **「LC サイドロード環境では SSDP 不成立」と確定** する (マルチキャスト用エンタイトルメントがサイドロードでは取得できないためとみられる)。発見の代替経路として §16.3 のサブネット走査を追加した。手動登録は引き続き常時利用できる。

### 16.3 サブネット走査式発見の追加

マルチキャストを使わないユニキャスト走査で発見を成立させる、`DiscoveryService` の新実装を追加した (§5.0 のモジュール原則どおり、既存インタフェースの裏側の追加であり UI の変更はない)。

- **構成**: `SubnetScanDiscoveryService` (`lib/core/services/discovery_scan.dart`)。`CompositeDiscoveryService` が SSDP → 走査の順に試し、最初に結果が得られた方式で確定する。設定画面の「LAN 内の nasne を探す」は従来どおり `discover()` を呼ぶだけであり、組み立て (providers) の変更のみで有効になる。
- **対象サブネットの決め方**: dart:io の `NetworkInterface` から端末自身のプライベート IPv4 アドレス (10/8、172.16/12、192.168/16) を集め、その /24 を対象とする。dart:io ではネットマスクを取得できないため /24 を仮定する (家庭内 LAN の標準形。/24 より広いサブネットでは同一 /24 内のみが対象になる割り切りを明記する)。
- **識別方法**: 各ホスト (1–254) へ `GET http://<host>:64210/status/boxNameGet` を短いタイムアウトで送り、`errorcode: 0` かつ `name` キーを持つ JSON 応答を候補とする (安価な一次フィルタ)。候補は SSDP と同じ原則で、58888 の機器説明 (description) を取得して modelName で nasne を確定する。説明が取得できない候補は、手動登録と同じく実測済みフォールバック形式 (`NasneDevice.direct`) で扱う。
- **タイムアウト・並列度**: プローブのタイムアウト 800 ms、並列 64。1 サブネットの走査は最悪でも ceil(254/64) × 800 ms ≈ **3.2 秒**。サブネットは 1 つずつ走査し、発見した時点で打ち切る (電話は通常 1 サブネットのみ。仮想サブネットの多い環境で、発見後に死んだサブネットの走査を続けないため)。
- **実測**: marnux (仮想含む 8 サブネット環境) から実機 192.168.11.129 を走査単体で発見し、description による識別まで完了した。所要時間は調整前 51.6 秒 → 並列度 64 + サブネット単位の打ち切り適用後 22.7 秒 (死んだ仮想サブネット 6 個を実 LAN より先に走査する marnux 固有の事情を含む。電話の 1 サブネット環境では上記の ~3.2 秒が上限)。合成 (SSDP 先行) では SSDP が 3.4 秒で発見した。
- **所要時間の見込み (アプリ実機)**: SSDP の待ち時間 (3 秒) + 走査 ~3.2 秒が上限の目安。SSDP が使える環境では従来どおり SSDP のみで終わる。

### 16.4 画質モードの公式表記

本人の決定 (§5.0 原則 5 の適用例): 録画モード (画質モード、`desiredQualityMode`) は数値ではなく nasne の公式の呼び方で表示する。

- **100 = DR、101 = 3倍**。これ以外の値の公式表記は未確認のため、数値のままフォールバック表示する (ラベルを発明しない)。
- 実装は表示変換 `qualityModeLabel` (`lib/ui/format.dart`) であり、モデル層の保持値は従来どおり数値のまま。
- 適用箇所: タイトル詳細の画質モード、予約詳細の画質モード、予約一覧の画質、予約フォームの画質選択肢。

### 16.5 テスト結果と IPA

- 追加テスト 14 件: 変換表と実測文字列の変換・パース入口での正規化 (`test/broadcast_text_test.dart` 7 件)、画質ラベル (`test/format_test.dart` 2 件)、走査の識別・フォールバック・早期打ち切り・合成の順序 (`test/discovery_scan_test.dart` 5 件)。
- `flutter test`: **80 件全合格**、`flutter analyze`: No issues (marnux / Mac の双方で確認)。
- 署名なし IPA: `TorneMobileHomeBrew-1.0.0.ipa`、**8,560,119 バイト**、SHA-256 `23759a563b243b081126a55161cdb8df970a5e2472e27fe54d7758cff3af297c`。配置先は marnux の `~/tmp/Decrypted-ipa/` (最新として更新、配置後にサイズと SHA-256 の一致を確認)。Mac の Downloads 等には置いていない。

### 16.6 commit 一覧

- `ff9c50d` fix: ARIB 外字 (私用領域) の表示変換を追加
- `4c2e372` feat: サブネット走査式の発見を追加 (SSDP の代替経路)
- `05b3f0d` ui: 画質モードを公式表記 (DR / 3倍) で表示
- 本節 (§16 の記録と §5.0 / §10 / §15.5 / §15.10 の判定反映)

## 17. フェーズ 3 の実施記録 (2026-11-16)

同一コア・UI のまま Android のビルド環境を確立し、リリース APK を生成した。実機 (Xperia Ace、Android 12、LineageOS) へのインストールと機能一巡の確認は本人担当として残る (§17.6)。

### 17.1 Android ビルド環境 (marnux)

- **Android SDK**: `~/GitTmp/android-sdk` に新規導入 (Flutter SDK と同じく `~/GitTmp` 配下に揃え、ホーム直下には置かない)。command line tools は 11076708 (2023-10 版) を `cmdline-tools/latest` に配置し、`flutter config --android-sdk ~/GitTmp/android-sdk` で設定。ライセンスは sdkmanager で同意済み。
- **導入コンポーネント**: platform-tools 37.0.1、platforms;android-36 (rev 2)、build-tools;36.0.0。ビルド時に AGP が追加で自動導入したもの: platforms;android-35 (rev 2)、NDK 28.2.13676358 (r28c)、CMake 3.22.1。
- **JDK**: システムの OpenJDK 21.0.13 をそのまま使用 (新規導入なし)。Gradle はプロジェクトの wrapper 9.5.0。
- `flutter doctor`: Android toolchain は ✓。残る注記は PATH 未設定の警告 (フルパス運用のため無害) と、システム側 `/usr/lib/android-sdk` の adb との二重検出 (情報のみ) の 2 件で、いずれもビルドに影響しない。

### 17.2 APK ビルド

- 手順: `flutter build apk --release` (marnux、リポルート)。初回は Gradle と依存・NDK のダウンロードを含み assembleRelease 268 秒、2 回目以降は 42〜52 秒。
- 成果物は全 ABI 入りの単一 APK (fat APK)。ABI 分割や AAB は配布形態の話であり、フェーズ 4 で扱う。
- Android 固有のビルド問題 (Gradle / Kotlin / 依存) は発生しなかった。

### 17.3 署名の扱い

- 現行の release ビルドはテンプレート既定の **debug 鍵** で署名される (apksigner で検証済み: Signer は Android Debug 証明書)。当面のサイドロード検証用としてはこれで足りる。
- **配布用の署名方針 (release keystore の作成・保管・CI での扱い) はフェーズ 4 の論点** とし、ここでは決定しない。debug 鍵のままでは将来の更新互換 (同一署名での上書き) を配布鍵と混同できない点に注意する。

### 17.4 SSDP の MulticastLock 対応

Android では Wi-Fi のマルチキャスト受信がドライバにフィルタされ得るため、SSDP 探索中だけ WifiManager.MulticastLock を保持する仕組みを追加した (サブネット走査が代替として成立しているため必須ではないが、小さな追加で SSDP の第一経路を活かせる)。

- **コア側**: `SsdpTransport` に純 Dart のインタフェース `MulticastLockGuard` (acquire / release) を追加し、`search()` の間だけ保持する。`SsdpDiscoveryService` が `lockGuard` を受けて transport へ渡す。インタフェースは「ベストエフォートで例外を投げない」契約。
- **アプリ側**: `lib/app/multicast_lock.dart` の `MethodChannelMulticastLockGuard` がチャネル `com.markun.tmhb/multicast_lock` を叩く。Android 以外では no-op、チャネル不在・失敗時も握りつぶして発見自体は継続する。組み立て (providers) で SSDP 実装に注入。
- **ネイティブ側**: `MainActivity.kt` にハンドラを追加し、`createMulticastLock("torne-mobile-hb-ssdp")` (参照カウントなし) を acquire / release する。権限 `CHANGE_WIFI_MULTICAST_STATE` を AndroidManifest に追加。
- **検証**: 単体テスト 3 件を追加 (ガードの保持区間、ガードなしでの完了、非 Android での no-op)。APK の権限にも `CHANGE_WIFI_MULTICAST_STATE` が含まれることを apkanalyzer で確認した。実機での SSDP 成立可否は本人の実機確認で判定する (§17.6)。

### 17.5 テスト結果

- `flutter test`: **87 件全合格**、`flutter analyze`: No issues (marnux / Mac の双方で確認)。内訳: フェーズ 3 開始時 80 件 → MulticastLock の 3 件で 83 件 → §18 の表記修正の 4 件で 87 件。

### 17.6 APK と残件

- **APK**: `TorneMobileHomeBrew-1.0.0.apk`、**54,850,923 バイト**、SHA-256 `aae463c7939a2ce275e90296818cb433186e520548a279913d5b4d39b5b25ba0`。配置先は marnux の `~/ダウンロード/` (IPA の `~/tmp/Decrypted-ipa/` ルールは LC 用途のものなので APK には適用しない)。§18 の表記修正を含む最終コード (`7e668a7`) からのビルド。
- apkanalyzer / apksigner での確認: applicationId `com.markun.tmhb`、versionName 1.0.0、minSdk 29、targetSdk 36、権限は INTERNET / ACCESS_NETWORK_STATE / CHANGE_WIFI_MULTICAST_STATE、署名は debug 証明書。
- **残件 (本人担当)**: Xperia Ace 実機へのインストールと、iOS と同範囲の機能一巡 (§6 フェーズ 3 の完了条件)。特に SSDP 発見が MulticastLock で成立するか、手動登録・走査との比較を含め実機で判定する。

### 17.7 commit 一覧

- `94ce74d` feat: Android の SSDP 受信用に MulticastLock を追加
- `7e668a7` ui: 地域名とソフトウェア版数を公式表記で表示 (§18 と共通)
- 本節 (§17 / §18 の記録)

## 18. 表記修正: 地域名とソフトウェア版数 (2026-11-16)

§5.0 原則 5 (公式表記準拠) の適用例として、ホームの本体情報の 2 項目を公式表記に合わせた。いずれも表示層のみの変換で、モデルの保持値は従来どおり生値のままである。

### 18.1 地域 (pref コード → 地域名)

**症状**: 本体情報の「地域」が数値 (41) のまま表示されていた。

**調査**:
- `areaInfoGet` の生レスポンス (フェーズ 0 フィクスチャ) は `{errorcode, areaIdentifierCode: 55, pref: 41, zipCode}` のみで、**名称を取れるフィールドは無い**。
- 本人仮説の都道府県コード (JIS X 0401) では 41 = 佐賀となり、実機 (福岡設定、受信局は北九州) の 41 と一致しない。**nasne の地域コードは JIS そのままではない (Sony 独自の地域表)** と判断し、JIS 表は採用しなかった。
- 公式の地域名一覧は torne 公式資産から取得した: PS Vita 版 torne の `PvrResource.cxml` (SPVR リソース) の文字列テーブルに、53 地域の名称 (北海道（札幌）〜沖縄) が公式表記で収録されている。
- ただし同文字列テーブルの並び順はコード順ではない (福岡は 46 番目に現れるが実測コードは 41)。コンテナ側の設定データにも (コード, 名称) の組は無く、**コードとの対応が裏取りできたのは 41 = 福岡のみ** である。

**実装**: 表示変換 `areaPrefLabel` (`lib/ui/format.dart`) に、裏取り済みの **41 = 福岡** のみを登録し、未知のコードは数値のままフォールバックする (対応表を推測で埋めない)。適用箇所はホームの本体情報「地域」 (地域コードの表示はここだけ)。他の地域の実機が得られたら、同じ手順 (実機の pref と公式名一覧の照合) で表を拡張する。

### 18.2 ソフトウェア版数 (0260 → 2.60)

**根拠**: 公式の nasne 設定画面では版数は「Ver:2.60」と表示される (本人が公式画面のスクリーンショットで提示)。一方アプリは API の生値「0260」をそのまま出していた。

**実装**: 表示変換 `softwareVersionLabel` (`lib/ui/format.dart`) で、4 桁数字の生値を「2.60」の形に直す (先行ゼロは落とす)。想定外の形式は生値フォールバック。適用箇所はホームの本体情報「ソフトウェア」 (ラベルは従来どおり)。

### 18.3 テストと成果物

- 追加テスト 4 件 (`test/format_test.dart`): 地域名の変換とフォールバック (JIS では福岡になる 40 が数値のままであることも含む)、版数の変換とフォールバック。総計 87 件全合格 (§17.5)。
- **IPA**: 本修正を含む署名なし IPA を Mac で再ビルドし、marnux `~/tmp/Decrypted-ipa/TorneMobileHomeBrew-1.0.0.ipa` を最新に更新した。**8,562,069 バイト**、SHA-256 `8163ce08f6c6392a87171426b3e5d6e47ba1cd772425d163a58772238de90118` (配置後にサイズ・ハッシュ一致を確認。Mac の Downloads 等には置いていない)。
- **APK**: 同じコードからのビルドが §17.6 の APK である。

## 19. 地域コード対応表の拡充とフェーズ 3 実機確認の確定 (2026-11-16)

### 19.1 経緯

§18 では areaInfoGet の数値 (41) と公式地域名の対応が 41 = 福岡しか裏取りできず、他は数値フォールバックとしていた。その後、本人が公式 nasne 設定の「地域選択」画面のスクリーンショットを提供し、これを元に調査することになった。同画面の一覧は 53 地域で、並び順では福岡が 46 番目となり、コード 41 とは一致しない (差は 5) ことが課題だった。

### 19.2 発見 1: アプリが表示していた「41」は areaIdentifierCode ではなく pref

areaInfoGet の生レスポンスは `{errorcode: 0, areaIdentifierCode: 55, pref: 41, zipCode: "0000000"}` である (§18.1 のフィクスチャにも両数値は記録されていた)。§18 で「地域コード 41」と呼んでいたのは **pref** であり、もう一つの数値 areaIdentifierCode = 55 を対応付けに使っていなかった。公式の対応付けはこの 2 数値の組で行われる (19.3)。

### 19.3 発見 2: 実機自身の Web UI に公式対応表 (56 件) が内蔵されている

本人のスクリーンショット (nasne®設定) は実機が配信する Web UI で、その配信元は `http://192.168.11.129:64210/nasne_home/` (ポート 80 から 301 で誘導される)。同 UI の `lib/app.js` に次が含まれていた:

- 文字列リソース `optionArea1`〜`optionArea56` (地域名。例: optionArea48 = 「福岡県」)
- `areaArray`: `AreaInfo(areaRes, areaCode, prefBit)` の 56 件。(areaCode, prefBit) の組がキー
- `getAreaInfo` の解決ロジック: areaInfoGet の (areaIdentifierCode, pref) が (areaCode, prefBit) の両方に一致するエントリの名称を返す。設定側の `setAreaInfo` (areaInfoSet) も同じ表を逆引きする

つまり対応表は推測ではなく、実機自身の公式 UI が使う表そのものを実機から取得できた。証拠ファイル (app.js、抽出スクリプト、抽出結果、実機の areaInfoGet 応答) は作業領域 `tmhb.work/2026-11-16-area-table/` に保存した。

### 19.4 アンカー検証と表の構造

- 実機の実測 (areaIdentifierCode=55, pref=41) を表に引くと **福岡県** となり、本人の福岡設定と一致する (アンカー成立)。
- pref は JIS X 0401 の都道府県コード +1 である (青森 JIS 2 → pref 3、…、福岡 JIS 40 → pref 41、沖縄 JIS 47 → pref 48)。北海道は下位地域で pref 1 と 2 に分かれ、これが全体を +1 ずらしている。追加として 49 = 東京都島部、50 = 鹿児島県島部がある。§18 で「nasne の地域コードは JIS そのままではない」とした観察は、この +1 ずれと北海道分割で説明が付く (JIS 41 = 佐賀は、pref では 42 に対応する)。
- areaIdentifierCode には重複がある: 12 (pref 1 = 旭川 (空知以外) / pref 2 = 旭川 (空知))、23 (pref 14 = 東京都 (除く島部) / pref 49 = 東京都島部)、58 (pref 47 = 鹿児島県 (除く南西諸島) / pref 50 = 鹿児島県島部)。単独の数値では一意に決まらず、組がキーになるのはこのため。
- pref だけでも、北海道の pref 1・2 を除く 48 件は一意に定まる。

### 19.5 torne 側名称表との照合

Vita 版 torne の `PvrResource.cxml` の文字列プールにある 53 地域名 (北海道（札幌）〜沖縄) と、Web UI 表の名称を torne 表記に変換したものを照合した:

- Web UI の 56 件を表示名に変換すると 52 件が torne の名称とそのまま一致し、旭川の 2 件は torne の「北海道（旭川）」に対応する。残る東京島部・鹿児島島部は torne の一覧に無い。
- §18 で「福岡は 46 番目」としたのは文字列プールの出現順であり、コード順でも Web UI の表示順でもない。46 と 41 の差 5 は順序の取り違えによるもので、対応付けの根拠にはならないことを確認した。

アプリの表示名は torne の表記 (53 名) を正とし、torne に無い分割 3 件 (旭川・空知、東京島部、鹿児島・南西諸島) のみ Web UI 名を同じ表記に整えて表示する (北海道（旭川・空知）、東京（島部）、鹿児島（南西諸島）)。

### 19.6 調べて対応表の根拠にしなかった資料

- `channelList.bin` (Vita 版 torne): チャンネル設定のバイナリ (CHLISTID / SVRCONFG レコード) で、地域コードと名称の対応は含まれていなかった。
- `PvrResource.cxml` の文字列プールの並び順: 19.5 のとおり名称集合の照合にのみ用い、順序は根拠にしていない。
- EPGVersionInfoGet のバイナリ表: 実機 Web UI から表そのものが得られたため、追加調査は不要と判断した。

### 19.7 実装

- `areaPrefLabel` (pref 単独・1 件のみ) を廃し、`areaLabel(areaIdentifierCode, pref)` (`lib/ui/format.dart`) に置き換えた。(組 → 名称) の 56 件表を正とし、組が引けない場合は pref のみで一意に定まる場合に限り名称を返し、それ以外は生数値フォールバックとする (名称は発明しない、§5.0 原則 5)。
- モデル (DeviceInfo) はフェーズ 1 から areaIdentifierCode と pref の両方を保持していたため、変更は表示層のみ。ホームの本体情報「地域」には両フィールドを渡す。
- §18 の「40 は数値のまま」というテスト期待は本表で覆った: pref 40 は公式表では 高知 であり、数値フォールバックではなくなる (§18.1・§18.3 の該当記述は本節をもって更新される)。
- 実装した表の組が公式表と完全一致することは、19.3 の抽出結果との機械照合でも確認した (56 件一致)。
- テスト (`test/format_test.dart`): アンカー (55, 41) = 福岡、全域からの代表組、分割 3 組の判別、pref 単独フォールバック (一意な場合のみ)、曖昧な pref 1・2 と未知値の生値フォールバック。総計 **90 件全合格**、`flutter analyze` クリーン (marnux / Mac 双方)。

### 19.8 成果物

- **IPA**: 本修正を含む署名なし IPA を Mac で再ビルドし、marnux `~/tmp/Decrypted-ipa/TorneMobileHomeBrew-1.0.0.ipa` を最新に更新した。**8,564,491 バイト**、SHA-256 `324ab6fb4a0cead448ddf29c9d336f01383a710e537b13010ab643fae03c1b18` (配置後にサイズ・ハッシュ一致を確認。Mac の Downloads 等には置いていない)。
- **APK**: marnux で再ビルドし `~/ダウンロード/TorneMobileHomeBrew-1.0.0.apk` に配置した。**54,850,923 バイト**、SHA-256 `3a6b0598dcfadbdb7375ac3b5379d54fd26f7dae097034a684d1cfbdec45b943` (libapp.so 内に新しい地域名文字列が含まれることを確認)。
- 実機へは読み取りのみで、状態は変えていない (録画 2 件は count API で再確認した)。

### 19.9 フェーズ 3 実機確認の確定 (追記)

- 本人が Xperia Ace で APK の実機確認を行い、「特に問題なし、文字化けも含めおかしなところなし」と報告した。これにより §6 のフェーズ 3 完了条件 (実機インストールと機能一巡) を満たした。
- 発見については、最初の一覧には nasne が出ておらず、本人が「探す」ボタンを押して発見できた。UI 上は SSDP で見つかったのかサブネット走査で見つかったのか区別できないため、記録は「Android では探すボタンで発見が成立した。経路 (SSDP / 走査) の区別は UI からは付かず、SSDP 単体の成否は未確定のまま」とする (§17 の MulticastLock 実装についても、成否の確定はしない)。

## 20. フェーズ 4: GitHub 配布 (2026-11-16)

### 20.1 公開リポジトリ

- GitHub に public リポジトリを作成し、main を同期した: https://github.com/mar1mo-41414/TorneMobileHomeBrew
- 作成直後の可視性が private になっていたため、API で public へ変更し、未認証の HTTP アクセスで 200 が返ることまで確認した。
- 公開に先立ち、README を公開向けに整備した (「現状」を v1.0.0 リリース済みに更新し、動作条件・インストール手順・使い方・既知の制限を追記)。あわせて、従来の記録にあった開発環境固有の記述 1 件を、公開文書向けに一般化した。

### 20.2 Android 配布用署名

- 配布用 keystore を新規に作成した (RSA 2048、alias `tmhb-release`、有効期間 10,000 日)。保管場所はリポジトリ外の marnux `~/.local/share/tmhb-signing/` (ディレクトリ 700、ファイル 600) で、keystore 本体 (`release.keystore`) と、パスワードを含む `key.properties` を置く。パスワードの値そのものは本書を含むリポジトリには書かない。
- 署名証明書の SHA-256: `e60cfedabb6f9e937213a5d1cb32621c806acb09220f7e3271b684d369aad1d5`
- ビルド側の仕組み (`android/app/build.gradle.kts`): 環境変数 `TMHB_KEY_PROPERTIES` が指すプロパティファイル (storeFile / storePassword / keyAlias / keyPassword) があれば配布用署名を使い、無ければ debug 鍵へフォールバックする (公開クローンでもそのままビルドできる)。`key.properties` と `*.jks` / `*.keystore` は .gitignore に追加した。
- 署名が変わるため、debug 署名の開発版からは上書きインストールできない (初回のみアンインストールして入れ直しが必要)。この注意はリリースノートに明記した。

### 20.3 リリース v1.0.0

- GitHub Release v1.0.0 を作成した: https://github.com/mar1mo-41414/TorneMobileHomeBrew/releases/tag/v1.0.0
- 添付物 (いずれも本節時点の最新 main `2d69f38` から生成):
  - **IPA** (署名なし、§19 までの全修正を含む再ビルド): 8,564,491 バイト、SHA-256 `9dd81a1890e647879b8db9c91e65336ed5742cbbe8d1ede55f6c9cf8bb935352`。同梱 Info.plist の CFBundleDisplayName が「torne mobile HB」であることを確認した。手元の最新ビルド置き場 (`~/tmp/Decrypted-ipa/`) にも同一ファイルを配置した。
  - **APK** (配布用署名): 54,850,923 バイト、SHA-256 `147addc4562943232c8fe0eb1879bc570c5f36e0d796aefc2644e05213ee762b`。apksigner で署名証明書が 20.2 の証明書と一致することを確認した。`~/ダウンロード/` の APK も同一ファイル (配布用署名版) に置き換えた。
- リリースノートには、機能の一覧、再生が未実装であること、動作条件、インストール方法 (iOS は LiveContainer / AltServer、Android は APK 直接インストール)、iOS サイドロード環境では SSDP が効かず走査 / 手動登録になること、署名変更に伴う再インストール注意、配布物の SHA-256 と署名証明書フィンガプリントを記載した。

### 20.4 フェーズ 4 完了条件との対応

- §6 の完了条件「両成果物 (IPA / APK) が手順どおりに再生成でき、導入手順だけで本人の端末に入れられる」について: IPA は §14 の手順 (Mac で署名なしビルド → Payload 形式に梱包)、APK は §17 の手順 + 20.2 の署名で再生成でき、導入手順は README とリリースノートに整備した。リリース添付物と本人の手元にある最新ビルドは同一ファイルであり、入れ替えはそのまま行える。
