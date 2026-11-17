# libmpv カスタムビルド (ARIB 字幕対応)

torne mobile HB が同梱する libmpv バイナリのカスタムビルド手順。
目的は **ARIB 字幕 (ARIB STD-B24) のデコードを有効化すること**。
media_kit が配布する標準バイナリは、FFmpeg の選択的有効化リストに
ARIB 字幕デコーダを含んでいないため、字幕トラックを選択しても
デコードされず描画できない (plan §54 で確定)。

## 方針

- デコーダは **libaribb24** を使う。media_kit のビルドが固定する
  FFmpeg 6.0 には libaribcaption ラッパーが存在せず (allcodecs に
  あるのは `ff_libaribb24_decoder` のみ)、ARIB 字幕は libaribb24
  経由でのみ有効化できる。FFmpeg 6.0 の非 GPL 構成では
  pkg-config で `aribb24 > 1.0.3` が要求される。これは 1.0.3
  タグが GPLv3 だったのに対し master が LGPLv3 へ再ライセンス
  済み (commit ed79dab) であることを版数で判定する仕組みのため、
  本ビルドでは master スナップショット (5e9be27) を版数 1.0.4
  とラベルして使う (コード自体は無改変)。
- libaribb24 の libpng 連携 (DRCS 外字の描画) は Android では
  無効 (NDK sysroot に libpng が無い)。テキスト字幕は影響しない。
  iOS では darwin スタックに libpng があるため有効 (後述)。

## Android (実施済み、plan §55)

上流: `media-kit/libmpv-android-video-build` commit `1ecf510`
(JAR 版数 v1.1.7、FFmpeg 6.0、mpv 78d4374、NDK 25.2.9519653)。

差分は `arib-android.patch` (5ファイル):

- `buildscripts/include/depinfo.sh`:
  `v_libaribb24` の追加と `dep_ffmpeg` への `libaribb24` 追加
- `buildscripts/include/download-deps.sh`:
  nkoriyama/aribb24 を固定コミットで取得
- `buildscripts/scripts/libaribb24.sh` (新規):
  autotools を arch 毎の VPATH ビルド (in-tree だと前 arch の
  オブジェクトが再利用され他 arch の prefix に混入するため必須)。
  版数ラベル 1.0.4 化と libpng チェックの真のオプション化を含む
- `buildscripts/flavors/default.sh`:
  `--enable-libaribb24` と `--enable-decoder=libaribb24` を追加
- `buildscripts/build.sh`:
  `sudo chmod` を `chmod` に (自分のファイルには sudo 不要なため。
  marnux では sudo がパスワード必須で非対話ビルドが止まる)

### 手順

前提: meson / ninja / nasm / cmake / JDK が入った Linux ホスト。
mbedtls の生成スクリプト用に Python の jinja2 と jsonschema が
必要 (venv を作って PATH に足す。システム Python には入れない)。

```sh
python3 -m venv build-venv
./build-venv/bin/pip install jinja2 jsonschema
export PATH=$PWD/build-venv/bin:$PATH

git clone https://github.com/media-kit/libmpv-android-video-build
cd libmpv-android-video-build
git checkout 1ecf510
git apply /path/to/arib-android.patch

cd buildscripts
TRAVIS=1 ./download.sh     # SDK (NDK 25.2.9519653) と依存ソースを取得
./patch.sh                  # 上流の ffmpeg / mpv パッチを適用
cp flavors/default.sh scripts/ffmpeg.sh
./build.sh --arch arm64     # armv7l / x86_64 / x86 も同様に
```

成果物は `prefix/<abi>/lib/libmpv.so`。上流 bundle と同様に
NDK の `llvm-strip --strip-all` で strip し、JAR 化する。
JAR の中身は上流 JAR と同じ構成 (`lib/<abi>/libmpv.so` +
`lib/<abi>/libmediakitandroidhelper.so`)。helper の .so は
メディアキット側のコードで字幕と無関係なため、上流 v1.1.7 の
公式 JAR からそのまま流用する。

```sh
# 例: arm64-v8a
mkdir -p pkg/lib/arm64-v8a
cp prefix/arm64-v8a/lib/libmpv.so pkg/lib/arm64-v8a/
unzip -o stock/default-arm64-v8a.jar 'lib/arm64-v8a/libmediakitandroidhelper.so' -d pkg
(cd pkg && zip -r ../default-arm64-v8a.jar lib/arm64-v8a)
md5sum default-*.jar
```

### 配布と取り込み

- JAR は本リポの GitHub リリースに置く
  (現行: タグ `libmpv-android-v1.1.7-arib1`)。
- アプリ側は `third_party/media_kit_libs_android_video`
  (pub の 1.3.8 を vendored したもの) の `android/build.gradle`
  が、そのリリースの URL と MD5 を指す。`pubspec.yaml` の
  `dependency_overrides` で vendored 版が優先される。
- JAR を更新したら: 新しいリリースタグを切り、vendored
  build.gradle の URL と MD5 を差し替える。ビルド時に Gradle が
  MD5 を検証するので、不一致はビルドエラーとして現れる。

### 検証方法

- `strings libmpv.so | grep ff_libaribb24_decoder` と
  ffmpeg の configuration 文字列に `--enable-libaribb24` /
  `--enable-decoder=libaribb24` が含まれること。
- 機能実証: 同じ libaribb24 スナップショットでホスト用
  FFmpeg 6.0 を組み、字幕付き TS からキューが抽出できること
  (§55 では x3 録画のキャプチャから 46 キューを抽出して
  §54 の Debian 実証と一致を確認)。

### 上流 media_kit が版数を上げたら

1. 新しい libmpv-android-video-build の commit と JAR 版数を
  確認し、FFmpeg の版数が変わっていないか見る。
2. FFmpeg が 6.0 のままなら `arib-android.patch` の再適用を
  試す (flavor の該当行が残っているか目視確認)。
3. FFmpeg が 7 以降に上がった場合は libaribcaption の採用を
  再検討する (7 系には libaribcaption ラッパーがある)。
4. JAR を再ビルド・新リリースタグで公開し、vendored
  build.gradle を差し替える。pub 側の
  media_kit_libs_android_video の版数が上がったら、vendored
  コピーも新しい版で取り直す。

## iOS (実施済み、plan §57)

上流: `media-kit/libmpv-darwin-build` commit `aadae8c`
(nix flake、成果物は
`libmpv-xcframeworks_v0.6.0_ios-universal-video-default.tar.gz`)。
FFmpeg は Android と同じ 6.0。

差分は `arib-darwin.patch` (9ファイル):

- `nix/packages/mk-pkg-aribb24/` (新規): aribb24 の autotools
  クロスビルド。Android と同じ固定コミット・同じ2つの sed
  (版数 1.0.4 ラベル、libpng チェックの真のオプション化)。
  libpng は `mk-pkg-libpng` を buildInputs に入れたため
  **DRCS も有効** (成果物の .pc に `Requires: libpng`、
  アーカイブ内に png 書き込み系シンボル参照を確認)。
  実装上の注意2点: (1) autoreconfHook は使わない。使うと
  configurePhase のコピー前に build ルートで autoreconfPhase が
  走って失敗する。`./bootstrap` が autoreconf を回すので、
  autoconf/automake/libtool を nativeBuildInputs に並べる。
  (2) stdenv の phase は同一シェルで cwd が引き継がれる。
  configurePhase が `src/_build` に入ったまま終わる前提で
  buildPhase/installPhase は素の `make` / `make install`。
- `nix/packages/mk-pkg-ffmpeg/default.nix`: video バリアントの
  buildInputs に aribb24 と libpng を追加。libpng は、aribb24 の
  .pc の `Requires: libpng` を ffmpeg の configure の
  pkg-config チェック (`--libs`/`--cflags` 展開) が解決する
  ためにも必須 (無いと版数チェックを通過しても
  "requires version higher than 1.0.3" で落ちる)。
- `nix/packages/mk-pkg-ffmpeg/meson.build`:
  `--enable-libaribb24` (video_common_options) と
  `--enable-decoder=libaribb24` (video_default_options) を追加。
- `nix/packages/mk-pkg-ffmpeg/default.nix` (依存の是正、
  plan §58): 現行 Xcode SDK の CoreMedia.tbd は、CoreMedia へ
  移転した Swift オーバーレイシンボルを `$ld$previous$` として
  宣言しており、移転前の版数を deployment target に含む
  リンクでは、ld が CoreMedia の代わりに libswiftCoreMedia
  (@rpath/libswiftCoreMedia.dylib) への依存を記録する。
  ffmpeg はそのシンボルを一切参照しない (nm -u で未定義の
  Swift シンボルが0件であることを確認済み) ため、この依存は
  偽物であり、installPhase で当該 load command を本来の
  `/System/Library/Frameworks/CoreMedia.framework/CoreMedia`
  へ書き戻す。
- `nix/packages/mk-out-frameworks/{ios,macos}/build-*.sh`:
  フレームワーク化の依存書き換えを、`${DEPS}` から作る
  フレームワークへの依存だけに限定するガード。範囲外の
  @rpath 依存まで書き換えると、実在しないフレームワーク名を
  作ってしまう (arib1 では上記の libswiftCoreMedia が
  SwiftCoreMedia.framework という実在しない依存に化け、
  アプリが起動直後に dyld エラーで落ちた。plan §58)。
- `packages.lock.nix`: aribb24 エントリ (版数 1.0.4、固定
  コミットのアーカイブ URL と sha256 は実測値)。
- 現在の Xcode/SDK 向け互換修正2件 (上流スタック側の問題で、
  字幕とは無関係だが踏まないとビルドが通らない):
  - `mk-pkg-libpng`: pngpriv.h の `#include <fp.h>` を
    `<math.h>` に置換。fp.h は古典 Mac OS のヘッダで現行 SDK
    には無く、TARGET_OS_MAC 定義時に踏む。libpng は従来
    スタック内の誰にも使われていなかったため未露見だった。
  - `mk-pkg-harfbuzz`: VarCompositeGlyph.hh の唯一の
    `sincosf` 呼び出しを `__sincosf` に置換。現行 SDK の
    math.h は素の sincosf を宣言しない (シンボル自体は
    リンクできるため meson チェックは HAVE_SINCOSF を定義
    してしまう)。

### 手順

前提: Mac + Xcode + nix。nix は Determinate installer で導入
(flakes がデフォルト有効)。導入直後はデーモンが起動して
いないことがあり、その場合は
`sudo launchctl bootstrap system /Library/LaunchDaemons/systems.determinate.nix-daemon.plist`
で起動し、`nix store ping` が `Store URL: daemon` を返す
ことを確認する。

```sh
git clone https://github.com/media-kit/libmpv-darwin-build
cd libmpv-darwin-build
git checkout aadae8c
git apply /path/to/arib-darwin.patch

# まず aribb24 単体で早期検証
make XCODE_PATH=/Applications/Xcode.app TARGET=mk-pkg-aribb24-ios-arm64

# 本体 (ios universal video default のアーカイブ一式)
make XCODE_PATH=/Applications/Xcode.app TARGET=mk-out-archive-xcframeworks-ios-universal-video-default
```

成果物は `result/libmpv-xcframeworks_develop_ios-universal-video-default.tar.gz`
(VERSION を指定しないと版数表記は develop になる。配布時は
下記のとおり上流のファイル名に揃えてリネームする)。

### 配布と取り込み

- tar.gz は本リポの GitHub リリースに置く (現行: タグ
  `libmpv-ios-v0.6.0-arib2`、ファイル名は上流と同じ
  `libmpv-xcframeworks_v0.6.0_ios-universal-video-default.tar.gz`、
  SHA-256 は `99a29c7b802f21f02dba6dc987869b5324f61c0521208e0d7f71af95dc6c2d6c`)。
  arib1 は上記の依存事故で起動しないため使用禁止 (plan §58)。
- アプリ側は `third_party/media_kit_libs_ios_video`
  (pub の 1.1.4 を vendored したもの) の `ios/Makefile` が、
  そのリリースの URL と SHA-256 を指す。`pubspec.yaml` の
  `dependency_overrides` で vendored 版が優先される。
- tar.gz を更新したら: 新しいリリースタグを切り、vendored
  Makefile の URL と SHA-256 を差し替える。ビルド時に
  Makefile が SHA-256 を検証するので、不一致はビルド
  エラーとして現れる。

### 検証方法

- 成果物の Libavcodec (dylib) の configuration 文字列に
  `--enable-libaribb24` / `--enable-decoder=libaribb24` が
  含まれ、`libaribb24 decoder` 等のデコーダ文字列があること。
  `otool -L` で libpng16 へのリンクも確認できる。
- 機能実証: 同じパッチ済みソースと macOS 用 aribb24
  パッケージでホスト用 FFmpeg 6.0 CLI を組み、字幕付き TS
  からキューが抽出できること (§57 では x3 録画のキャプチャ
  で実施。Android §55 の 46 キューと照合)。
- 出荷前監査 (必須、plan §58): `audit_load_commands.py`
  (本ディレクトリ) で、アーカイブの展開先と、IPA 内の
  .app を走査し、全 Mach-O の load command が実機で
  解決可能であることを機械的に確認する。判定基準は
  スクリプト冒頭の docstring のとおり (@rpath の
  フレームワーク依存は同梱されていること、裸の @rpath
  dylib 依存は不可、絶対パスは /System/Library/ と
  /usr/lib/ のみ可)。arib1 の事故はこの監査で検出できる
  (公式アーカイブと arib2 は通過、arib1 は12件の
  未解決依存で失敗することを確認済み)。

  ```sh
  python3 tool/libmpv/audit_load_commands.py <展開したアーカイブのルート>
  python3 tool/libmpv/audit_load_commands.py <IPA を展開した Payload/*.app>
  ```

### 上流 media_kit が版数を上げたら

Android の節と同じ手順 (新しい libmpv-darwin-build の
commit と xcframeworks 版数の確認、FFmpeg の版数確認、
パッチ再適用の試行、7 以降なら libaribcaption の再検討、
新リリースタグでの公開と vendored Makefile の差し替え)。
互換修正2件 (fp.h / sincosf) は上流や SDK の状況で
不要になる可能性があるため、再適用時に要否を確認する。

## Windows (実施済み、plan §61)

上流は `media-kit/libmpv-win32-video-cmake` (CMake superbuild、
自前の GCC/MinGW クロスツールチェーンを構築する方式)。
ビルドは Linux (marnux) で完結する。公式配布の libmpv
(2023-09-24、FFmpeg 6.0) には ARIB 字幕デコーダが無いため、
字幕はこの自前ビルドが前提になる。Android/iOS の aribb24 と
違い、Windows では FFmpeg 7 世代の **libaribcaption** 経路を
使う (libaribcaption 本体は MIT ライセンス)。

確定した版数の組み合わせ (arib1):

- FFmpeg **n7.1.5** に固定 (release/7.1 追随では superbuild の
  dash/hls パッチと両立するタグが無いため。dash パッチは再生成)
- mpv v0.39.0、libaribcaption master `d59c9d6`
- クロス GCC は固定スナップショットが消滅していたため
  **14.3.0 リリース版**に substitution

### 手順

1. `libmpv-win32-video-cmake` をフォークし、`tool/libmpv/arib-win32.patch`
   を適用する。配線の要点は3点: `packages/CMakeLists.txt` の
   ep 一覧に `libaribcaption` を追加、`packages/ffmpeg.cmake` の
   DEPENDS に追加、ffmpeg の configure 引数に
   `--enable-libaribcaption` と `--enable-decoder=libaribcaption`
   を追加 (ffmpeg.cmake は `--disable-decoders` を全体に掛ける
   ため、デコーダ側の明示有効化が必須)。
2. パッチには配線以外の互換修正も含まれる (libaribcaption の
   `-DHAVE_OPENSSL=1` 除去、mpv の新ヘッダ不整合の修正と
   osd_libass 代替実装、死リンクの差し替え、fontconfig /
   vulkan の版数固定 等)。詳細は作業記録
   (`tmhb.work/2026-11-17-windows-survey/libmpv-build-record.md`)。
3. superbuild を実行し (`ninja mpv`)、得られた `libmpv-2.dll` /
   `libmpv.dll.a` / `include/mpv/*.h` を公式 7z と同じ
   レイアウトで 7z 化する。

### 配布と取り込み

- GitHub リリース `libmpv-windows-v1.0.11-arib1` に 7z を置く
  (MD5 は vendored パッケージ側の検証に使われる)。
- `third_party/media_kit_libs_windows_video` (pub 1.0.11 の
  vendored コピー) の `windows/CMakeLists.txt` が、公式の
  2023-09-24 アーカイブではなくこの 7z を取得する
  (ファイル名・URL・MD5 を差し替え済み)。

### 検証方法

- DLL の FFmpeg configuration 文字列に
  `--enable-libaribcaption` と `--enable-decoder=libaribcaption`
  が含まれること、デコーダ名 `libaribcaption` の文字列が
  DLL 内に存在すること、ffmpeg の configure ログで
  Enabled external libraries / Enabled decoders の両方に
  掲載されていること。
- 実機 (Windows) での字幕描画の確認はアプリ組み込み後の
  段で行う (ビルド単体では未実施)。

### 上流 media_kit が版数を上げたら

新しい `media_kit_libs_windows_video` が新しい公式アーカイブを
固定してきたら、その FFmpeg 版数と字幕デコーダの有無を
再検査する。公式に libaribcaption 入りのビルドが出れば
自前ビルドは不要になるが、公式リリースは 2023-09-24 で
止まっているため、当面は本手順が正になる。
