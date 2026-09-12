// QR Connect: the only untrusted input is the scanned link, and the only
// thing that leaves this parser is a profile UUID or nothing. These pin
// down what counts as a member link and that the QR the Portfolio shows
// round-trips through the same parser.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';
import 'package:richfield_connect/services/member_link.dart';

const uid = '8f62db0a-1691-4851-8c85-0f1b64bed896';

void main() {
  test('the QR link round-trips to the same profile id', () {
    final link = MemberLink.linkFor(uid);
    expect(link, 'richfield://member/$uid');
    expect(MemberLink.profileIdFrom(Uri.parse(link)), uid);
  });

  test('a trailing slash or upper-case UUID still resolves', () {
    expect(MemberLink.profileIdFrom(Uri.parse('richfield://member/$uid/')), uid);
    expect(MemberLink.profileIdFrom(Uri.parse('richfield://member/${uid.toUpperCase()}')), uid);
  });

  test('auth links and foreign schemes are not member links', () {
    expect(MemberLink.profileIdFrom(Uri.parse('richfield://auth/confirmed?code=abc')), isNull);
    expect(MemberLink.profileIdFrom(Uri.parse('richfield://auth/recovery')), isNull);
    expect(MemberLink.profileIdFrom(Uri.parse('https://example.com/member/$uid')), isNull);
    expect(MemberLink.profileIdFrom(Uri.parse('richfield://members/$uid')), isNull);
  });

  test('anything that is not one bare UUID segment is dropped', () {
    expect(MemberLink.profileIdFrom(Uri.parse('richfield://member/')), isNull);
    expect(MemberLink.profileIdFrom(Uri.parse('richfield://member/not-a-uuid')), isNull);
    expect(MemberLink.profileIdFrom(Uri.parse('richfield://member/$uid/extra')), isNull);
    expect(MemberLink.profileIdFrom(Uri.parse("richfield://member/$uid'%20or%201=1")), isNull);
  });

  test('a pending id is handed over exactly once', () {
    MemberLink.pendingProfileId.value = uid;
    expect(MemberLink.consumePending(), uid);
    expect(MemberLink.consumePending(), isNull);
    expect(MemberLink.pendingProfileId.value, isNull);
  });

  testWidgets('the Portfolio QR encodes the member link without error', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Center(
        child: SizedBox(
          width: 220,
          height: 220,
          child: PrettyQrView.data(
            data: MemberLink.linkFor(uid),
            decoration: const PrettyQrDecoration(shape: PrettyQrSmoothSymbol(color: Colors.black)),
          ),
        ),
      ),
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byType(PrettyQrView), findsOneWidget);
  });
}
