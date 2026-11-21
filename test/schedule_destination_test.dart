/// Recording-destination selection (plan 89.14): the pure
/// availability / clamping logic of the reservation form, and
/// the destination as it lands in the X_CreateRecordSchedule
/// request for each choice.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tmhb/core/core.dart';
import 'package:tmhb/ui/schedule_destination.dart';

final xsrsUrl = Uri.parse('http://192.0.2.1:64230/XSRS');

String soapFixture(String name) =>
    File('test/fixtures/soap/$name').readAsStringSync();

/// An HDDListGet entry. The `internal` values follow the measured
/// response shape (plan 89.8): the internal drive reports
/// internalFlag 0 and the external SSD reported 1, so the flag is
/// not a reliable discriminator and the helpers must ignore it.
HddEntry entry(
  int id, {
  bool internal = false,
  bool mounted = true,
  bool registered = true,
}) => HddEntry(
  id: id,
  internal: internal,
  mounted: mounted,
  registered: registered,
);

NewRecordSchedule candidate(String destinationId) => NewRecordSchedule(
  start: DateTime.parse('2026-11-21T10:00:00+09:00'),
  durationSeconds: 300,
  channel: const ScheduleChannel(
    broadcastingType: 2,
    channelType: 2,
    serviceId: 56832,
  ),
  networkId: 30848,
  recordDestinationId: destinationId,
);

void main() {
  group('externalDestinationAvailable', () {
    test('internal drive only: no external choice', () {
      expect(externalDestinationAvailable([entry(0)]), isFalse);
    });

    test('registered and mounted external drive: available', () {
      expect(
        externalDestinationAvailable([entry(0), entry(1, internal: true)]),
        isTrue,
      );
    });

    test('external drive not mounted: unavailable', () {
      expect(
        externalDestinationAvailable([entry(0), entry(1, mounted: false)]),
        isFalse,
      );
    });

    test('external drive not registered: unavailable', () {
      expect(
        externalDestinationAvailable([entry(0), entry(1, registered: false)]),
        isFalse,
      );
    });

    test('no drives reported: unavailable', () {
      expect(externalDestinationAvailable(const []), isFalse);
    });
  });

  group('effectiveRecordDestination', () {
    test('internal choice stands either way', () {
      expect(effectiveRecordDestination('HDD', externalAvailable: true), 'HDD');
      expect(
        effectiveRecordDestination('HDD', externalAvailable: false),
        'HDD',
      );
    });

    test('external choice stands only while the drive is available', () {
      expect(
        effectiveRecordDestination('USBHDD', externalAvailable: true),
        'USBHDD',
      );
      expect(
        effectiveRecordDestination('USBHDD', externalAvailable: false),
        'HDD',
      );
    });

    test('unknown values fall back to the internal HDD', () {
      expect(effectiveRecordDestination('', externalAvailable: true), 'HDD');
      expect(
        effectiveRecordDestination('SOMETHING', externalAvailable: true),
        'HDD',
      );
    });
  });

  group('recordDestinationLabel', () {
    test('labels for the two destinations', () {
      expect(recordDestinationLabel('HDD'), '内蔵');
      expect(recordDestinationLabel('USBHDD'), '外付け');
    });
  });

  group('create request destination', () {
    test('the create item carries the internal destination', () {
      final xml = buildCreateItemXml(candidate('HDD'));
      expect(xml, contains('<recordDestinationID>HDD</recordDestinationID>'));
    });

    test('the create item carries the external destination', () {
      final xml = buildCreateItemXml(candidate('USBHDD'));
      expect(
        xml,
        contains('<recordDestinationID>USBHDD</recordDestinationID>'),
      );
    });

    test('the default candidate destination is the internal HDD', () {
      final xml = buildCreateItemXml(
        NewRecordSchedule(
          start: DateTime.parse('2026-11-21T10:00:00+09:00'),
          durationSeconds: 300,
          channel: const ScheduleChannel(
            broadcastingType: 2,
            channelType: 2,
            serviceId: 56832,
          ),
          networkId: 30848,
        ),
      );
      expect(xml, contains('<recordDestinationID>HDD</recordDestinationID>'));
    });

    test('createSchedule sends the chosen destination on the wire', () async {
      late String seenBody;
      final service = SoapScheduleService(
        soap: SoapTransport(
          client: MockClient((request) async {
            seenBody = request.body;
            return http.Response(
              soapFixture('create_response.xml'),
              200,
              headers: {'content-type': 'text/xml; charset=utf-8'},
            );
          }),
        ),
        controlUrl: xsrsUrl,
      );
      final id = await service.createSchedule(
        candidate(
          effectiveRecordDestination('USBHDD', externalAvailable: true),
        ),
      );
      expect(id, '10000000000000000003');
      // The Elements argument is transported XML-escaped (plan 12.3).
      expect(
        seenBody,
        contains(
          '&lt;recordDestinationID&gt;USBHDD&lt;/recordDestinationID&gt;',
        ),
      );
    });

    test('an external choice without the drive is sent as internal', () async {
      late String seenBody;
      final service = SoapScheduleService(
        soap: SoapTransport(
          client: MockClient((request) async {
            seenBody = request.body;
            return http.Response(
              soapFixture('create_response.xml'),
              200,
              headers: {'content-type': 'text/xml; charset=utf-8'},
            );
          }),
        ),
        controlUrl: xsrsUrl,
      );
      await service.createSchedule(
        candidate(
          effectiveRecordDestination('USBHDD', externalAvailable: false),
        ),
      );
      expect(
        seenBody,
        contains('&lt;recordDestinationID&gt;HDD&lt;/recordDestinationID&gt;'),
      );
    });
  });
}
