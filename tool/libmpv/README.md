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

差分は `arib-darwin.patch` (7ファイル):

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
  `libmpv-ios-v0.6.0-arib1`、ファイル名は上流と同じ
  `libmpv-xcframeworks_v0.6.0_ios-universal-video-default.tar.gz`、
  SHA-256 は `12cc6eda4596aa14921cddedcf6e062cbd792e6f571309c755e6dd4387e5069e`)。
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

### 上流 media_kit が版数を上げたら

Android の節と同じ手順 (新しい libmpv-darwin-build の
commit と xcframeworks 版数の確認、FFmpeg の版数確認、
パッチ再適用の試行、7 以降なら libaribcaption の再検討、
新リリースタグでの公開と vendored Makefile の差し替え)。
互換修正2件 (fp.h / sincosf) は上流や SDK の状況で
不要になる可能性があるため、再適用時に要否を確認する。
