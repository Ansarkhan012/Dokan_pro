import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/images/product_image_processing.dart';
import '../core/images/product_image_url.dart';
import '../features/products/product_image_sync.dart' show sha256Hex;

/// Platform administration contract (migration 202610140001). Every call is
/// authorised on the server by public.is_platform_admin(); this client holds
/// only the anon key and the admin's own session.
DateTime? _time(Object? v) =>
    v is String ? DateTime.tryParse(v)?.toUtc() : null;

final class AdminShop {
  const AdminShop({
    required this.id,
    required this.name,
    required this.phone,
    required this.address,
    required this.licenseStatus,
    required this.ownerEmails,
    required this.approvedDevices,
    required this.pendingDevices,
    this.planId,
    this.subscriptionStatus,
    this.periodEnd,
    this.graceUntil,
    this.licenseNote = '',
  });
  final String id, name, phone, address, licenseStatus, licenseNote;
  final List<String> ownerEmails;
  final int approvedDevices, pendingDevices;
  final String? planId, subscriptionStatus;
  final DateTime? periodEnd, graceUntil;

  factory AdminShop.fromJson(Map<String, dynamic> j) => AdminShop(
    id: j['id'] as String,
    name: j['name'] as String,
    phone: j['phone'] as String? ?? '',
    address: j['address'] as String? ?? '',
    licenseStatus: j['license_status'] as String,
    licenseNote: j['license_note'] as String? ?? '',
    ownerEmails: [
      for (final o in (j['owners'] as List? ?? const []))
        if ((o as Map)['email'] case final String email) email,
    ],
    approvedDevices: (j['approved_devices'] as num?)?.toInt() ?? 0,
    pendingDevices: (j['pending_devices'] as num?)?.toInt() ?? 0,
    planId: j['plan_id'] as String?,
    subscriptionStatus: j['subscription_status'] as String?,
    periodEnd: _time(j['period_end']),
    graceUntil: _time(j['grace_until']),
  );
}

final class AdminDevice {
  const AdminDevice({
    required this.id,
    required this.name,
    required this.deviceType,
    required this.formFactor,
    required this.approvalStatus,
    required this.isActive,
    required this.legacy,
    this.lastSeenAt,
    this.createdAt,
  });
  final String id, name, deviceType, formFactor, approvalStatus;
  final bool isActive, legacy;
  final DateTime? lastSeenAt, createdAt;

  factory AdminDevice.fromJson(Map<String, dynamic> j) => AdminDevice(
    id: j['id'] as String,
    name: j['device_name'] as String,
    deviceType: j['device_type'] as String,
    formFactor: j['form_factor'] as String,
    approvalStatus: j['approval_status'] as String,
    isActive: j['is_active'] as bool,
    legacy: j['legacy_grandfathered'] as bool? ?? false,
    lastSeenAt: _time(j['last_seen_at']),
    createdAt: _time(j['created_at']),
  );
}

final class AdminAuditEntry {
  const AdminAuditEntry({
    required this.action,
    required this.actorKind,
    required this.createdAt,
    required this.details,
    this.actorEmail,
    this.shopName,
    this.deviceId,
  });
  final String action, actorKind;
  final DateTime createdAt;
  final Map<String, dynamic> details;
  final String? actorEmail, shopName, deviceId;

  factory AdminAuditEntry.fromJson(Map<String, dynamic> j) => AdminAuditEntry(
    action: j['action'] as String,
    actorKind: j['actor_kind'] as String,
    createdAt: _time(j['created_at'])!,
    details: Map<String, dynamic>.from(j['details'] as Map? ?? const {}),
    actorEmail: j['actor_email'] as String?,
    shopName: j['shop_name'] as String?,
    deviceId: j['device_id'] as String?,
  );
}

/// The server's view of the signed-in account (platform_admin_access,
/// migration 202610160001). Only [granted] can use admin RPCs.
enum AdminAccess { none, mfaRequired, granted }

/// A TOTP factor being set up. [secret] and [uri] are shown to the admin
/// once, for the authenticator app; never logged or stored.
final class TotpEnrollment {
  const TotpEnrollment({
    required this.factorId,
    required this.secret,
    required this.uri,
  });
  final String factorId, secret, uri;
}

final class AdminPlan {
  const AdminPlan(this.id, this.name, this.billingCycle);
  final String id, name, billingCycle;
}

/// A global category (categories.shop_id is null), the only kind a catalog
/// product may use.
final class AdminCategory {
  const AdminCategory(this.id, this.name);
  final String id, name;
}

/// A row of the global catalog (public.master_products). [id] is null for a
/// product not saved yet.
final class AdminCatalogProduct {
  const AdminCatalogProduct({
    this.id,
    required this.name,
    required this.barcode,
    required this.defaultUnit,
    this.brand = '',
    this.categoryId,
    this.packLabel,
    this.isActive = true,
    this.imagePath,
  });
  final String? id, categoryId, packLabel, imagePath;
  final String name, brand, barcode, defaultUnit;
  final bool isActive;

  factory AdminCatalogProduct.fromJson(Map<String, dynamic> j) =>
      AdminCatalogProduct(
        id: j['id'] as String,
        name: j['name'] as String,
        brand: j['brand'] as String? ?? '',
        barcode: j['barcode'] as String,
        categoryId: j['category_id'] as String?,
        defaultUnit: j['default_unit'] as String,
        packLabel: j['pack_label'] as String?,
        isActive: j['is_active'] as bool? ?? true,
        imagePath: j['default_image_path'] as String?,
      );
}

/// Storage key of a global catalog photo with content hash [sha256Hex]
/// (policy product_images_admin_insert, migration 202610180001).
String catalogProductImageKey(String sha256Hex) => 'catalog/$sha256Hex.jpg';

/// Uploads a catalog photo already shrunk by [prepareCatalogPhoto] under its
/// content hash and points [productId] at it. Returns the storage key.
Future<String> attachCatalogPhoto(
  AdminGateway gateway,
  String productId,
  Uint8List jpeg,
) async {
  final key = catalogProductImageKey(sha256Hex(jpeg));
  await gateway.uploadCatalogImage(key, jpeg);
  await gateway.setCatalogImage(productId, key);
  return key;
}

/// Turns a picked image into the 512px catalog JPEG, off the UI isolate.
/// Throws [ProductImageException] for files that are not usable photos.
typedef CatalogPhotoPreparer = Future<Uint8List> Function(Uint8List source);
const CatalogPhotoPreparer prepareCatalogPhoto =
    prepareProductThumbnailInBackground;

abstract interface class AdminGateway {
  Future<String?> currentEmail();
  Future<void> signIn(String email, String password);
  Future<void> signOut();

  /// The server's decision. Admin RPCs work only at [AdminAccess.granted]
  /// (listed admin with a verified-MFA, AAL2 session).
  Future<AdminAccess> access();

  /// The admin's verified TOTP factor, or null when MFA is not enrolled yet.
  Future<String?> verifiedTotpFactorId();

  /// Starts TOTP enrolment (removing unfinished earlier attempts first).
  Future<TotpEnrollment> enrollTotp();

  /// Verifies a 6-digit code for [factorId]: completes enrolment or the
  /// sign-in challenge and upgrades the session to AAL2.
  Future<void> verifyTotp(String factorId, String code);

  /// Abandons an unverified enrolment.
  Future<void> cancelEnrollment(String factorId);
  Future<List<AdminShop>> shops();
  Future<List<AdminPlan>> plans();
  Future<String> createShop({
    required String name,
    required String phone,
    required String address,
    required String ownerEmail,
  });

  /// Creates the owner's login through the admin-create-owner Edge Function
  /// (service role stays on the server).
  Future<void> createOwnerLogin({
    required String email,
    required String temporaryPassword,
    required String fullName,
  });
  Future<void> assignOwner(String shopId, String email);
  Future<void> setShopStatus(String shopId, String status, String note);
  Future<void> renew(String shopId, String planId, int months);
  Future<List<AdminDevice>> devices(String shopId);
  Future<void> approveDevice(
    String deviceId, {
    String? replaceDeviceId,
    String? formFactor,
  });
  Future<void> rejectDevice(String deviceId, String note);
  Future<void> revokeDevice(String deviceId, String note);
  Future<void> setFormFactor(String deviceId, String formFactor);
  Future<List<AdminAuditEntry>> audit({String? shopId});

  /// Global categories, for the catalog product form.
  Future<List<AdminCategory>> catalogCategories();

  /// Catalog rows, active and hidden, matching [query] (name, brand or
  /// exact barcode); the first rows by name when [query] is empty.
  Future<List<AdminCatalogProduct>> catalogProducts({String query = ''});

  /// Creates ([AdminCatalogProduct.id] null) or edits a catalog row through
  /// admin_upsert_master_product. Returns the row id.
  Future<String> saveCatalogProduct(AdminCatalogProduct product);

  /// Uploads a catalog photo. A file already at [key] is success: keys are
  /// content hashes, so it is the same photo.
  Future<void> uploadCatalogImage(String key, Uint8List jpeg);

  /// Points the row at an uploaded catalog photo, or clears it when null.
  Future<void> setCatalogImage(String productId, String? key);
}

final class SupabaseAdminGateway implements AdminGateway {
  SupabaseAdminGateway(this.client);
  final SupabaseClient client;

  Future<Object?> _rpc(String name, [Map<String, dynamic>? params]) =>
      client.rpc(name, params: params);
  Future<List<Map<String, dynamic>>> _list(
    String name, [
    Map<String, dynamic>? params,
  ]) async => [
    for (final row in (await _rpc(name, params) as List? ?? const []))
      Map<String, dynamic>.from(row as Map),
  ];

  @override
  Future<String?> currentEmail() async => client.auth.currentUser?.email;
  @override
  Future<void> signIn(String email, String password) =>
      client.auth.signInWithPassword(email: email, password: password);
  @override
  Future<void> signOut() => client.auth.signOut();
  @override
  Future<AdminAccess> access() async =>
      switch (await _rpc('platform_admin_access')) {
        'granted' => AdminAccess.granted,
        'mfa_required' => AdminAccess.mfaRequired,
        _ => AdminAccess.none,
      };
  @override
  Future<String?> verifiedTotpFactorId() async {
    final factors = await client.auth.mfa.listFactors();
    for (final f in factors.totp) {
      if (f.status == FactorStatus.verified) return f.id;
    }
    return null;
  }

  @override
  Future<TotpEnrollment> enrollTotp() async {
    final factors = await client.auth.mfa.listFactors();
    for (final f in factors.all) {
      if (f.factorType == FactorType.totp &&
          f.status == FactorStatus.unverified) {
        await client.auth.mfa.unenroll(f.id);
      }
    }
    final r = await client.auth.mfa.enroll(
      factorType: FactorType.totp,
      issuer: 'Dokan Pro Admin',
      friendlyName:
          'Dokan Pro Admin ${DateTime.now().toUtc().toIso8601String()}',
    );
    final totp = r.totp;
    if (totp == null) throw StateError('TOTP enrolment unavailable');
    return TotpEnrollment(factorId: r.id, secret: totp.secret, uri: totp.uri);
  }

  @override
  Future<void> verifyTotp(String factorId, String code) async {
    await client.auth.mfa.challengeAndVerify(factorId: factorId, code: code);
  }

  @override
  Future<void> cancelEnrollment(String factorId) async {
    await client.auth.mfa.unenroll(factorId);
  }

  @override
  Future<List<AdminShop>> shops() async =>
      (await _list('admin_list_shops')).map(AdminShop.fromJson).toList();
  @override
  Future<List<AdminPlan>> plans() async => [
    for (final p in await _list('admin_list_plans'))
      AdminPlan(
        p['id'] as String,
        p['name'] as String,
        p['billing_cycle'] as String,
      ),
  ];
  @override
  Future<String> createShop({
    required String name,
    required String phone,
    required String address,
    required String ownerEmail,
  }) async =>
      await _rpc('admin_create_shop', {
            'p_name': name,
            'p_phone': phone,
            'p_address': address,
            'p_owner_email': ownerEmail,
          })
          as String;
  @override
  Future<void> createOwnerLogin({
    required String email,
    required String temporaryPassword,
    required String fullName,
  }) async {
    await client.functions.invoke(
      'admin-create-owner',
      body: {
        'email': email,
        'password': temporaryPassword,
        'full_name': fullName,
      },
    );
  }

  @override
  Future<void> assignOwner(String shopId, String email) =>
      _rpc('admin_assign_owner', {'p_shop_id': shopId, 'p_owner_email': email});
  @override
  Future<void> setShopStatus(String shopId, String status, String note) => _rpc(
    'admin_set_shop_status',
    {'p_shop_id': shopId, 'p_status': status, 'p_note': note},
  );
  @override
  Future<void> renew(String shopId, String planId, int months) => _rpc(
    'admin_renew_subscription',
    {'p_shop_id': shopId, 'p_plan_id': planId, 'p_months': months},
  );
  @override
  Future<List<AdminDevice>> devices(String shopId) async => (await _list(
    'admin_list_devices',
    {'p_shop_id': shopId},
  )).map(AdminDevice.fromJson).toList();
  @override
  Future<void> approveDevice(
    String deviceId, {
    String? replaceDeviceId,
    String? formFactor,
  }) => _rpc('admin_approve_device', {
    'p_device_id': deviceId,
    'p_replace_device_id': replaceDeviceId,
    'p_form_factor': formFactor,
  });
  @override
  Future<void> rejectDevice(String deviceId, String note) =>
      _rpc('admin_reject_device', {'p_device_id': deviceId, 'p_note': note});
  @override
  Future<void> revokeDevice(String deviceId, String note) =>
      _rpc('admin_revoke_device', {'p_device_id': deviceId, 'p_note': note});
  @override
  Future<void> setFormFactor(String deviceId, String formFactor) => _rpc(
    'admin_set_device_form_factor',
    {'p_device_id': deviceId, 'p_form_factor': formFactor},
  );
  @override
  Future<List<AdminAuditEntry>> audit({String? shopId}) async => (await _list(
    'admin_list_audit',
    {'p_shop_id': shopId, 'p_limit': 300},
  )).map(AdminAuditEntry.fromJson).toList();

  static const _catalogColumns =
      'id,name,brand,barcode,category_id,default_unit,pack_label,is_active,'
      'default_image_path';

  @override
  Future<List<AdminCategory>> catalogCategories() async => [
    for (final c
        in await client
            .from('categories')
            .select('id,name')
            .isFilter('shop_id', null)
            .eq('is_active', true)
            .order('name'))
      AdminCategory(c['id'] as String, c['name'] as String),
  ];
  @override
  Future<List<AdminCatalogProduct>> catalogProducts({String query = ''}) async {
    final q = query.trim();
    final rows = q.isEmpty
        ? await client
              .from('master_products')
              .select(_catalogColumns)
              .order('name')
              .order('id')
              .limit(200)
        : await client
              .from('master_products')
              .select(_catalogColumns)
              .or(
                'barcode.eq.${_filterValue(q)},'
                'name.ilike.${_filterValue('*$q*')},'
                'brand.ilike.${_filterValue('*$q*')}',
              )
              .order('name')
              .order('id')
              .limit(200);
    return rows.map(AdminCatalogProduct.fromJson).toList();
  }

  /// Quotes a PostgREST `or` filter value so commas and parentheses in the
  /// admin's search text stay literal.
  static String _filterValue(String v) =>
      '"${v.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';

  @override
  Future<String> saveCatalogProduct(AdminCatalogProduct p) async =>
      await _rpc('admin_upsert_master_product', {
            'p_id': p.id,
            'p_name': p.name,
            'p_brand': p.brand,
            'p_barcode': p.barcode,
            'p_category_id': p.categoryId,
            'p_default_unit': p.defaultUnit,
            'p_pack_label': p.packLabel,
            'p_is_active': p.isActive,
          })
          as String;
  @override
  Future<void> uploadCatalogImage(String key, Uint8List jpeg) async {
    try {
      await client.storage
          .from(productImageBucket)
          .uploadBinary(
            key,
            jpeg,
            fileOptions: const FileOptions(
              contentType: 'image/jpeg',
              cacheControl: '31536000',
            ),
          );
    } on StorageException catch (e) {
      if (!isExistingObjectError(e)) rethrow;
    }
  }

  @override
  Future<void> setCatalogImage(String productId, String? key) => _rpc(
    'admin_set_master_product_image',
    {'p_id': productId, 'p_path': key},
  );
}

/// Storage's answer to uploading a key that is already taken.
bool isExistingObjectError(StorageException e) =>
    e.statusCode == '409' || e.message.toLowerCase().contains('already exists');

/// A short, non-sensitive reason for an admin-facing error.
/// Why an MFA step failed, without echoing codes or secrets.
enum MfaFailure { wrongCode, expired, sessionEnded, unavailable }

MfaFailure mfaFailure(Object error) {
  if (error is AuthException) {
    final code = error.code ?? '';
    if (code == 'mfa_challenge_expired') return MfaFailure.expired;
    if (code == 'mfa_verification_failed' ||
        code == 'mfa_verification_rejected' ||
        code == 'validation_failed' ||
        error.statusCode == '422' ||
        error.statusCode == '400') {
      return MfaFailure.wrongCode;
    }
    if (error.statusCode == '401' ||
        error.statusCode == '403' ||
        code == 'session_not_found' ||
        code == 'bad_jwt' ||
        error is AuthSessionMissingException) {
      return MfaFailure.sessionEnded;
    }
  }
  return MfaFailure.unavailable;
}

String mfaFailureText(MfaFailure f) => switch (f) {
  MfaFailure.wrongCode =>
    'Code not accepted. Enter the current 6-digit code from the '
        'authenticator app (check the PC and phone clocks).',
  MfaFailure.expired => 'That code request expired. Enter a new code.',
  MfaFailure.sessionEnded => 'Your session ended. Sign in again.',
  MfaFailure.unavailable =>
    'Verification is unavailable. Check the connection and try again.',
};

String adminErrorText(Object error) {
  if (error is PostgrestException) {
    final m = RegExp(r'DPL0\d: [^\n]+').firstMatch(error.message);
    if (m != null) {
      // Slot full: legacy shops can hold more approved devices than the
      // limit, and one replacement frees only one slot.
      return m.group(0)!.startsWith('DPL04')
          ? '${m.group(0)!}. Revoke unused registrations first (match the '
                'device code the owner reads from the device), then approve '
                'with Replace.'
          : m.group(0)!;
    }
    if (error.code == '42501') return 'Not permitted.';
    return error.message;
  }
  if (error is FunctionException) {
    final d = error.details;
    return d is Map && d['error'] is String
        ? d['error'] as String
        : 'Request failed (${error.status}).';
  }
  if (error is AuthException) return error.message;
  if (error is ProductImageException) return error.message;
  if (error is StorageException) {
    return error.statusCode == '403' || error.statusCode == '401'
        ? 'Not permitted.'
        : 'Photo upload failed (${error.message}).';
  }
  return 'Request failed. Check the connection.';
}
