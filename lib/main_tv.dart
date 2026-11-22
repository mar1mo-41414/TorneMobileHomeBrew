/// torne mobile HomeBrew edition — TV entry point.
///
/// The TV edition is the same app as lib/main.dart, started as
/// [AppVariant.tv]: an Android product flavor of its own
/// (minSdk 24, applicationId com.markun.tmhb.tv) so TV hardware
/// too old for the standard edition's minSdk 29 can still
/// install it, with TV-level defaults (the first viewing starts
/// from the mobile transcode). Build it with:
///
///   flutter build apk --flavor tv -t lib/main_tv.dart
library;

import 'app/variant.dart';
import 'main.dart';

Future<void> main() => runTmhbApp(AppVariant.tv);
