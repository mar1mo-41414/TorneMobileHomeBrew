# dev ビルドのデスクトップ版 (Linux / Windows / macOS)

dev prerelease (タグ `dev`) には、CI が自動ビルドするモバイル版
(APK / IPA) に加えて、デスクトップ版も含める。

デスクトップ版は CI では作らない。dev ビルドのたびに担当がこの手順で
作り、資産を差し替える。資産名は固定で、差し替えで更新する
(ダウンロード URL は変わらない)。

| プラットフォーム | 資産名 | ビルド機 |
|---|---|---|
| Linux | `TorneMobileHomeBrew-dev-linux.tar.gz` | marnux |
| Windows | `TorneMobileHomeBrew-dev-windows.zip` | marog |
| macOS | `TorneMobileHomeBrew-dev-macos.zip` | Mac (署名後に任意で掲載) |

CI (`.github/workflows/dev-build.yml`) の prerelease 資産整理は、
上記のデスクトップ資産を保持リストに入れてあり、モバイル版の更新で
消えることはない。逆に、デスクトップ資産はこの手順で差し替えない限り
古いまま残るので、dev ビルドのたびに作り直すこと。

版数は pubspec.yaml のまま据え置く (版数を上げるのは実機確認が
通った正式リリース時だけ、という運用は dev でも同じ)。

## Linux (marnux)

```sh
cd ~/GitTmp/myClaude/TorneMobileHomeBrew
git pull
tool/build_linux_desktop.sh
# build/TorneMobileHomeBrew-linux-<version>.tar.gz ができる
cp build/TorneMobileHomeBrew-linux-<version>.tar.gz \
  /tmp/TorneMobileHomeBrew-dev-linux.tar.gz
gh release upload dev /tmp/TorneMobileHomeBrew-dev-linux.tar.gz \
  --repo mar1mo-41414/TorneMobileHomeBrew --clobber
```

`~/ダウンロード/TMHB/` は正式リリース専用なので dev は置かない。

## Windows (marog)

```powershell
cd $env:USERPROFILE\GitTmp\MyClaude\TorneMobileHomeBrew
git pull
flutter build windows --release
# build\windows\x64\runner\Release\ の中身が成果物
```

- zip: 中身を `TorneMobileHomeBrew-dev-windows` フォルダに入れて
  zip 化し、`TorneMobileHomeBrew-dev-windows.zip` として
  `gh release upload dev --clobber` で掲載する
  (正式リリースの zip と同じトップフォルダ付きの構成)。
- 実機確認用に、Desktop の `TorneMobileHomeBrew` フォルダの中身も
  新しいビルドに差し替える。Desktop にはフォルダだけを置き、
  zip は置かない。

## macOS (Mac)

ビルドとステージは担当側が行い、署名は Mac 常駐の署名係
(LaunchAgent) が行う。SSH セッションからは解錠済みキーチェーンに
触れず codesign が `errSecInternalComponent` で失敗するため、
GUI ログインセッション内で動く署名係に合図ファイル経由で
署名させる。鍵は Mac の外に出ない。

### ビルドとステージ (担当側)

```sh
cd ~/GitTmp/MyClaude/TorneMobileHomeBrew-desktop
git pull
tool/build_macos_desktop.sh
```

- ビルドは必ずこのスクリプト経由にする。`.xcworkspace` 経由でない
  xcodebuild は CocoaPods の embed 工程が走らず、フレームワーク
  欠落で起動不能な .app になる (スクリプト内に同梱ガードがある)。
- スクリプト内の署名工程は SSH 経由では失敗するのが正常。
  xcodebuild が終わっていれば、成果物の .app は
  `build/macos/Build/Products/Release/` に未署名で残る (ステージ完了)。
- Mac の非対話 PATH には `/opt/homebrew/bin` (CocoaPods) と
  Flutter が入っていないので、SSH 経由では PATH を補って実行する。

### 署名 (署名係)

署名係の設置物 (Mac 上):

- plist: `~/Library/LaunchAgents/com.markun.tmhb.signagent.plist`
  (WatchPaths で `requests/` を監視)
- 本体: `~/Library/Application Support/TMHBSignAgent/sign.sh`
- 待ち受け: 同ディレクトリの `requests/` / `results/` / `logs/`

使い方:

1. SSH 経由で `requests/<id>.req` を置く。1 行目が署名対象の
   .app のパス (空ファイルならステージ済みアプリが既定)。
2. 署名係が確立済みの形式で署名する: identity
   `torne-mobile-hb-signing`、entitlements は
   `macos/Runner/Signing.entitlements`、
   `codesign --force --deep --timestamp=none`、署名後に
   `codesign --verify --deep --strict` で検証する。
3. 結果は `results/<id>.result` に残る (`status: SUCCESS` を確認)。
   実行ログは `logs/sign.log`。
4. 初回のみ、キーチェーンのアクセス許可ダイアログが Mac の画面に
   出ることがある。その場合は画面で許可する (次回以降は出ない)。

署名係が使えない場合の予備経路として、ローカルターミナルで
署名コマンドを打つ従来運用も残す。

### 配置 (担当側)

- 署名済みアプリの署名を検証し、`~/Applications/torne mobile HB.app`
  へ ditto で差し替える。配置側でも署名検証と実行ファイルの
  ハッシュ一致を確認する。Desktop には何も置かない。
- 署名後の zip を `TorneMobileHomeBrew-dev-macos.zip` として
  prerelease に掲載するのは任意 (Mac ではローカル配置が正規経路)。
