/// App variant: the standard edition and the Android TV edition
/// share one code base. The entry point picks the variant
/// (lib/main.dart for standard, lib/main_tv.dart for TV) and the
/// bootstrap hands it to the provider container through
/// [appVariantProvider]. Variant differences stay at the level of
/// defaults and packaging — the TV edition is an Android product
/// flavor with its own minSdk and applicationId — never a fork of
/// the feature code. TV-specific behaviour work (focus navigation,
/// the video path on low-end TV hardware) builds on this base.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Which edition of the app this process is.
enum AppVariant {
  /// Phones, tablets and desktops. On Android this is the
  /// long-standing build: minSdk 29, applicationId com.markun.tmhb.
  standard,

  /// Android TV / Fire TV. A separate Android product flavor:
  /// minSdk 24, applicationId com.markun.tmhb.tv, entry point
  /// lib/main_tv.dart.
  tv;

  /// Whether this is the TV edition.
  bool get isTv => this == AppVariant.tv;

  /// The playback quality a viewing starts with when the user has
  /// not chosen one yet (nothing in the key-value store): the TV
  /// edition starts from the mobile transcode (the low-end TV
  /// hardware it targets is happiest with it), the standard
  /// edition from the original quality.
  bool get defaultUseMobilePlayback => isTv;
}

/// The variant of the running app. The bootstrap overrides this
/// with the entry point's variant; the plain default keeps tests
/// and headless contexts on the standard edition.
final appVariantProvider = Provider<AppVariant>((ref) => AppVariant.standard);
