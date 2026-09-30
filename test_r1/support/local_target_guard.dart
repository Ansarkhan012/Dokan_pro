// Fail-closed guard that keeps every R1 integration test on local infrastructure.
//
// Two independent layers:
// 1. `LocalTargetGuard.requireLocal` validates the configured URL before any
//    client exists. Only `localhost` or a loopback IP literal is accepted; any
//    other host name is refused without a DNS lookup, and known hosted Supabase
//    domains are refused explicitly.
// 2. `LocalOnlyHttpOverrides` checks every socket the test isolate opens, so a
//    request that bypasses the configured client still cannot leave the
//    machine.

import 'dart:io';

final class HostedTargetRefused implements Exception {
  HostedTargetRefused(this.target, this.reason);
  final String target;
  final String reason;
  @override
  String toString() => 'HostedTargetRefused($target): $reason';
}

abstract final class LocalTargetGuard {
  static const _hostedSuffixes = [
    'supabase.co',
    'supabase.com',
    'supabase.in',
    'supabase.net',
    'supabase.red',
  ];

  /// Returns the parsed URL only if it points at this machine.
  static Future<Uri> requireLocal(String raw) async {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw HostedTargetRefused(raw, 'not an absolute URL');
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      throw HostedTargetRefused(raw, 'unsupported scheme ${uri.scheme}');
    }
    final host = uri.host.toLowerCase();
    for (final suffix in _hostedSuffixes) {
      if (host == suffix || host.endsWith('.$suffix')) {
        throw HostedTargetRefused(raw, 'hosted Supabase domain');
      }
    }
    if (!isLoopbackHost(host)) {
      throw HostedTargetRefused(raw, 'host is not localhost or a loopback IP literal');
    }
    if (host == 'localhost') {
      final addresses = await InternetAddress.lookup('localhost');
      if (addresses.isEmpty || !addresses.every((a) => a.isLoopback)) {
        throw HostedTargetRefused(raw, 'localhost does not resolve to loopback');
      }
    }
    return uri;
  }

  /// Pure syntactic check, no DNS: `localhost` or a loopback IP literal.
  static bool isLoopbackHost(String host) {
    final h = host.toLowerCase();
    if (h == 'localhost') return true;
    final literal = InternetAddress.tryParse(
      h.startsWith('[') && h.endsWith(']') ? h.substring(1, h.length - 1) : h,
    );
    return literal != null && literal.isLoopback;
  }
}

/// Refuses any outgoing connection whose target is not loopback.
final class LocalOnlyHttpOverrides extends HttpOverrides {
  final attempts = <Uri>[];

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.connectionFactory = (url, proxyHost, proxyPort) {
      attempts.add(url);
      final target = proxyHost ?? url.host;
      if (!LocalTargetGuard.isLoopbackHost(target)) {
        throw HostedTargetRefused(url.toString(), 'non-loopback connection blocked');
      }
      return Socket.startConnect(target, proxyPort ?? url.port);
    };
    return client;
  }
}
