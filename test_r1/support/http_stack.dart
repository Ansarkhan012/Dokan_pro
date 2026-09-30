// R1 HTTP integration layer: the real Supabase HTTP path (Kong → GoTrue /
// PostgREST) of a disposable LOCAL stack, driven through the application's own
// gateway classes. Never a hosted project.
//
// Configure with --dart-define=R1_HTTP_URL=... and R1_HTTP_ANON_KEY=... (CI:
// from `supabase status -o env`; locally: tool/r1_integration/local_http_stack.sh).
// Setup uses only public APIs (GoTrue sign-up and the app's RPCs); no
// service-role key exists anywhere in this harness.
//
// Isolation: each test signs up its own owner and creates its own shop, so
// tests never share tenant data; the whole stack is discarded after the run.

import 'dart:io';

import 'package:supabase/supabase.dart';
import 'package:uuid/uuid.dart';

import 'local_target_guard.dart';

const r1HttpUrl = String.fromEnvironment('R1_HTTP_URL');
const r1HttpAnonKey = String.fromEnvironment('R1_HTTP_ANON_KEY');
const r1HttpConfigured = r1HttpUrl != '' && r1HttpAnonKey != '';
const r1HttpSkipReason =
    'needs --dart-define=R1_HTTP_URL/R1_HTTP_ANON_KEY for a local disposable stack';

String _id() => const Uuid().v4();

final class LocalHttpStack {
  LocalHttpStack._(this.url, this.anonKey, this.overrides);
  final Uri url;
  final String anonKey;
  final LocalOnlyHttpOverrides overrides;
  final _clients = <SupabaseClient>[];

  /// The guard runs before any client or socket exists; a hosted or
  /// non-loopback target throws [HostedTargetRefused] here.
  static Future<LocalHttpStack> connect({
    String url = r1HttpUrl,
    String anonKey = r1HttpAnonKey,
  }) async {
    final uri = await LocalTargetGuard.requireLocal(url);
    final overrides = LocalOnlyHttpOverrides();
    HttpOverrides.global = overrides;
    return LocalHttpStack._(uri, anonKey, overrides);
  }

  SupabaseClient newClient() {
    final client = SupabaseClient(
      url.toString(),
      anonKey,
      authOptions: const AuthClientOptions(
        autoRefreshToken: false,
        authFlowType: AuthFlowType.implicit,
      ),
    );
    _clients.add(client);
    return client;
  }

  /// A brand-new owner account (sign-up is enabled and auto-confirmed on the
  /// local stack, per supabase/config.toml).
  Future<OwnerSession> signUpOwner() async {
    final client = newClient();
    final email = 'owner-${_id()}@r1.test';
    const password = 'R1-local-only-pass-123!';
    final response = await client.auth.signUp(email: email, password: password);
    if (response.session == null) {
      await client.auth.signInWithPassword(email: email, password: password);
    }
    final userId = client.auth.currentUser?.id;
    if (userId == null) throw StateError('local sign-up produced no session');
    return OwnerSession(client, userId);
  }

  Future<void> dispose() async {
    for (final client in _clients) {
      await client.dispose();
    }
    _clients.clear();
    HttpOverrides.global = null;
  }
}

final class OwnerSession {
  OwnerSession(this.client, this.userId);
  final SupabaseClient client;
  final String userId;
}

/// Server-side shop fixture created only through the app's owner RPCs.
final class ServerShop {
  ServerShop._({
    required this.owner,
    required this.shopId,
    required this.deviceA,
    required this.deviceB,
    required this.productId,
    required this.freeProductId,
    required this.customerId,
  });

  final OwnerSession owner;
  final String shopId, deviceA, deviceB, productId, freeProductId, customerId;
  static const salePrice = 18000; // Rs 180.00
  static const openingStock = 10000; // 10 units
  static const categoryId = 'd0000000-0000-0000-0000-000000000005'; // seed: Beverages

  static Future<ServerShop> create(OwnerSession owner, {int? creditLimit}) async {
    final rpc = owner.client.rpc;
    final shopRows = await rpc('create_owner_shop', params: {'p_name': 'R1 shop'}) as List;
    final shopId = (shopRows.single as Map)['shop_id'] as String;
    Future<String> device(String name) async {
      final rows = await rpc('register_shop_device', params: {
        'p_shop_id': shopId,
        'p_device_name': name,
        'p_device_type': 'androidTablet',
        'p_device_identifier': _id(),
      }) as List;
      return (rows.single as Map)['device_id'] as String;
    }

    final deviceA = await device('R1 device A');
    final deviceB = await device('R1 device B');
    Future<String> product(String name, int price, int opening) async {
      final id = _id();
      await rpc('create_custom_shop_product', params: {
        'p_shop_id': shopId,
        'p_device_id': deviceA,
        'p_shop_product_id': id,
        'p_name': name,
        'p_category_id': categoryId,
        'p_barcode': null,
        'p_unit': 'piece',
        'p_pack_label': null,
        'p_image_path': null,
        'p_purchase_price': price == 0 ? 0 : 15000,
        'p_sale_price': price,
        'p_opening_quantity': opening,
        'p_low_stock_level': 0,
        'p_movement_id': _id(),
      });
      return id;
    }

    final productId = await product('Coke', salePrice, openingStock);
    final freeProductId = await product('Free bag', 0, openingStock);
    final customerId = await rpc('save_customer', params: {
      'p_shop_id': shopId,
      'p_customer_id': null,
      'p_name': 'Ahmed',
      'p_credit_limit': creditLimit,
    }) as String;
    return ServerShop._(
      owner: owner,
      shopId: shopId,
      deviceA: deviceA,
      deviceB: deviceB,
      productId: productId,
      freeProductId: freeProductId,
      customerId: customerId,
    );
  }
}

/// Stable extraction of the server's error contract from any failure.
final class ServerError {
  const ServerError(this.code, this.message, this.details);
  final String? code;
  final String message;
  final Object? details;

  static ServerError? of(Object error) => error is PostgrestException
      ? ServerError(error.code, error.message, error.details)
      : null;

  @override
  String toString() => 'ServerError(code: $code, message: $message)';
}
