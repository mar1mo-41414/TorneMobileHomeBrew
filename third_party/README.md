# third_party

pub.dev のパッケージをそのままコピーして改変した vendored
パッケージ置き場。`pubspec.yaml` の `dependency_overrides` で
hosted 版より優先される。

## media_kit_libs_android_video (pub 1.3.8 のコピー)

改変点は `android/build.gradle` の libmpv JAR の取得先のみ:
media-kit 公式の v1.1.7 JAR ではなく、ARIB 字幕デコーダ
(libaribb24) を有効化した自前ビルドの JAR を、本リポの
GitHub リリース (`libmpv-android-v1.1.7-arib1`) から取得する
(URL と MD5 を差し替え済み)。その他のファイルは pub 版と同一。

ビルド手順と保守方法は `tool/libmpv/README.md` と plan §55。

## media_kit_libs_ios_video (pub 1.1.4 のコピー)

改変点は `ios/Makefile` の libmpv xcframeworks の取得先のみ:
media-kit 公式の v0.6.0 ではなく、ARIB 字幕デコーダ
(libaribb24、DRCS の libpng 連携を含む) を有効化した自前
ビルドの tar.gz を、本リポの GitHub リリース
(`libmpv-ios-v0.6.0-arib2`) から取得する (URL と SHA-256 を
差し替え済み)。その他のファイルは pub 版と同一。

ビルド手順と保守方法は `tool/libmpv/README.md` と plan §57。

## media_kit_libs_macos_video (pub 1.1.4 のコピー)

改変点は `macos/Makefile` の libmpv xcframeworks の取得先のみ:
media-kit 公式の v0.6.0 ではなく、ARIB 字幕デコーダ
(libaribb24、DRCS の libpng 連携を含む) を有効化した自前
ビルドの tar.gz を、本リポの GitHub リリース
(`libmpv-macos-v0.6.0-arib1`) から取得する (URL と SHA-256 を
差し替え済み)。その他のファイルは pub 版と同一。

ビルド手順と保守方法は `tool/libmpv/README.md` (macOS の節)。
