// Proves the R1 integration harness fails closed before touching a hosted or
// non-loopback target. Pure local: no Docker, no network.
@Tags(['r1-guard'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/http_stack.dart';
import '../support/local_target_guard.dart';

void main() {
  test('a hosted Supabase URL aborts before any client, socket or write exists', () async {
    final watcher = LocalOnlyHttpOverrides();
    final before = HttpOverrides.current;
    await HttpOverrides.runWithHttpOverrides(() async {
      await expectLater(
        LocalHttpStack.connect(url: 'https://abcdefghijklmnop.supabase.co', anonKey: 'x'),
        throwsA(isA<HostedTargetRefused>()),
      );
    }, watcher);
    expect(watcher.attempts, isEmpty, reason: 'no connection may be attempted');
    expect(HttpOverrides.current, same(before), reason: 'no global override installed');
  });

  for (final target in [
    'https://abcdefghijklmnop.supabase.co',
    'https://api.supabase.com',
    'http://192.168.1.10:54321',
    'http://10.0.0.5:54321',
    'http://example.com:54321',
    'http://localhost.evil.example:54321',
    'http://127.0.0.1.nip.io:54321',
    'ftp://127.0.0.1:54321',
    'not a url',
    '',
  ]) {
    test('refuses $target', () async {
      await expectLater(
        LocalTargetGuard.requireLocal(target),
        throwsA(isA<HostedTargetRefused>()),
      );
    });
  }

  for (final target in [
    'http://127.0.0.1:54321',
    'http://localhost:54421',
    'http://[::1]:54321',
  ]) {
    test('accepts $target', () async {
      expect((await LocalTargetGuard.requireLocal(target)).hasScheme, isTrue);
    });
  }

  test('socket-level override blocks a non-loopback connection before connecting', () async {
    final overrides = LocalOnlyHttpOverrides();
    Object? error;
    await HttpOverrides.runWithHttpOverrides(() async {
      final client = HttpClient();
      try {
        await client.getUrl(Uri.parse('http://203.0.113.10:80/rest/v1/'));
      } catch (e) {
        error = e;
      } finally {
        client.close(force: true);
      }
    }, overrides);
    expect(error, isA<HostedTargetRefused>());
    expect(overrides.attempts.single.host, '203.0.113.10');
  });
}
