// RFC 6238 TOTP (SHA-1, 30-second step, 6 digits), as authenticator apps
// compute it. Local harness only: lets the R1 platform admin verify the TOTP
// factor it enrols, because admin RPCs require an AAL2 session (migration
// 202610160001). Never used by the app.
import 'dart:typed_data';

import 'package:pointycastle/export.dart';
import 'package:supabase/supabase.dart';

String totpCode(String base32Secret, {DateTime? at}) {
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
  final bits = StringBuffer();
  for (final c in base32Secret.replaceAll('=', '').toUpperCase().split('')) {
    bits.write(alphabet.indexOf(c).toRadixString(2).padLeft(5, '0'));
  }
  final s = bits.toString();
  final key = Uint8List.fromList([
    for (var i = 0; i + 8 <= s.length; i += 8)
      int.parse(s.substring(i, i + 8), radix: 2),
  ]);
  final step = (at ?? DateTime.now()).millisecondsSinceEpoch ~/ 30000;
  final counter = ByteData(8)..setUint64(0, step);
  final mac = HMac(SHA1Digest(), 64)..init(KeyParameter(key));
  final h = mac.process(counter.buffer.asUint8List());
  final o = h[h.length - 1] & 0xf;
  final value =
      ((h[o] & 0x7f) << 24) | (h[o + 1] << 16) | (h[o + 2] << 8) | h[o + 3];
  return (value % 1000000).toString().padLeft(6, '0');
}

/// Enrols a TOTP factor for the signed-in user and verifies it, leaving the
/// client with an AAL2 session.
Future<void> elevateToAal2(SupabaseClient client) async {
  final enrolled = await client.auth.mfa.enroll(
    factorType: FactorType.totp,
    friendlyName: 'r1-${DateTime.now().microsecondsSinceEpoch}',
  );
  await client.auth.mfa.challengeAndVerify(
    factorId: enrolled.id,
    code: totpCode(enrolled.totp!.secret),
  );
}
