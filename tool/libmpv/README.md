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

## iOS (未実施、経路のみ確定)

上流: `media-kit/libmpv-darwin-build` (nix flake、成果物は
`libmpv-xcframeworks_v0.6.0_ios-universal-video-default.tar.gz`)。
pub パッケージ `media_kit_libs_ios_video` の Makefile が
版数と SHA-256 を固定して取得する。

確認済みの構造:

- darwin 側の FFmpeg も 6.0 で、nix の
  `nix/packages/mk-pkg-ffmpeg/meson.build` が External Project
  として FFmpeg の configure を叩く。オプションリストは
  Android の flavor と並行に管理されており、ここに
  `--enable-libaribb24` と `--enable-decoder=libaribb24` を
  足すのが本筋。
- 依存は `nix/packages/mk-pkg-*` 単位で管理されるため、
  `mk-pkg-aribb24` の新規作成 (autotools のクロスビルド) と
  mk-pkg-ffmpeg の buildInputs への追加が必要。
- iOS スタックには libpng (Png16.framework) が既にあるため、
  DRCS の PNG 連携まで含められる可能性がある。
- ビルド実行には Mac + nix (Determinate installer 推奨) +
  Xcode のパス設定が要る。

実施時は Android と同様に、vendored した
media_kit_libs_ios_video の Makefile の版数・URL・SHA-256 を
自前リリースへ差し替える形にする。
