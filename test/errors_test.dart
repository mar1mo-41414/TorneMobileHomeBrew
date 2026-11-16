/// Tests for the unified error representation (plan 12.6).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tmhb/core/errors.dart';

void main() {
  group('NasneError.soapFault conversion table', () {
    test('402 is an invalid-args (implementation-side) error', () {
      final e = NasneError.soapFault(
        errorCode: '402',
        errorDescription: 'Action X_CreateRecordSchedule failed',
        source: 'soap:X_CreateRecordSchedule',
      );
      expect(e.category, NasneErrorCategory.soapFault);
      expect(e.code, '402');
      expect(e.messageKey, 'error.invalidArgs');
      expect(e.retryable, isFalse);
    });

    test('803 is the id-format error', () {
      final e = NasneError.soapFault(
        errorCode: '803',
        source: 'soap:X_DeleteRecordSchedule',
      );
      expect(e.messageKey, 'error.invalidIdFormat');
    });

    test('other codes fall back to the generic soap fault key', () {
      final e = NasneError.soapFault(
        errorCode: '500',
        errorDescription: 'Action X_GetConflictList failed',
        source: 'soap:X_GetConflictList',
      );
      expect(e.messageKey, 'error.soapFault');
      expect(e.detail, 'Action X_GetConflictList failed');
    });
  });

  group('NasneError factories', () {
    test('unreachable is retryable', () {
      final e = NasneError.unreachable('webapi:/status/boxNameGet');
      expect(e.category, NasneErrorCategory.unreachable);
      expect(e.retryable, isTrue);
    });

    test('HTTP 404 reads as not-implemented', () {
      final e = NasneError.http(404, 'webapi:/status/dtvtunerDeviceInfoGet');
      expect(e.messageKey, 'error.notImplemented');
      expect(e.code, '404');
    });

    test('unsupported is its own category (PlaybackEngine stub)', () {
      final e = NasneError.unsupported('playback:start');
      expect(e.category, NasneErrorCategory.unsupported);
      expect(e.messageKey, 'error.unsupported');
    });
  });
}
