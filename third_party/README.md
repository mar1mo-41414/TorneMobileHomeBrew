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
