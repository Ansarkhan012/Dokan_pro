// Private admin panel flows against an in-memory gateway. The fake applies
// the same rules the server does (admin role, two-device slots) so the UI is
// exercised against realistic refusals; the real enforcement is proven by
// supabase/tests_raw/platform_admin_licensing_security.sql.
import 'dart:typed_data';

import 'package:dukaan_pro/admin/admin_app.dart';
import 'package:dukaan_pro/admin/admin_gateway.dart';
import 'package:dukaan_pro/core/images/product_image_processing.dart';
import 'package:dukaan_pro/features/products/product_image_picker.dart';
import 'package:dukaan_pro/features/products/product_image_sync.dart'
    show sha256Hex;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  Future<void> pump(
    WidgetTester tester,
    _FakeAdmin g, {
    ProductImagePicker? picker,
  }) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      AdminApp(
        gateway: g,
        photoPicker: picker ?? _QueuedPicker(),
        // Same processing as the app, on the test isolate.
        preparePhoto: (b) async => prepareProductThumbnail(b),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> passwordSignIn(WidgetTester tester, String email) async {
    await tester.enterText(find.byType(TextField).at(0), email);
    await tester.enterText(find.byType(TextField).at(1), 'password-123');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();
  }

  Future<void> enterCode(WidgetTester tester, String code) async {
    await tester.enterText(find.byType(TextField).last, code);
    await tester.tap(find.widgetWithText(FilledButton, 'Verify'));
    await tester.pumpAndSettle();
  }

  /// Password, then the authenticator code: the only way into the panel.
  Future<void> signIn(WidgetTester tester, String email) async {
    await passwordSignIn(tester, email);
    if (find.text('Two-step verification').evaluate().isNotEmpty) {
      await enterCode(tester, _FakeAdmin.validCode);
    }
  }

  testWidgets('a non-admin account is refused and signed out', (tester) async {
    final g = _FakeAdmin();
    await pump(tester, g);
    await signIn(tester, 'owner@shop.pk');
    expect(
      find.text('This account is not a platform administrator.'),
      findsOneWidget,
    );
    expect(g.signedIn, isNull);
    expect(find.text('New shop'), findsNothing);
  });

  group('admin MFA', () {
    testWidgets('admin without MFA must enrol before any admin page', (
      tester,
    ) async {
      final g = _FakeAdmin()..mfaEnrolled = false;
      await pump(tester, g);
      await passwordSignIn(tester, 'admin@dokanpro.pk');
      expect(find.text('Set up two-step verification'), findsOneWidget);
      expect(find.text('JBSW Y3DP EHPK 3PXP'), findsOneWidget);
      expect(find.text('New shop'), findsNothing);
      // The server refuses admin RPCs to this aal1 session anyway.
      await expectLater(g.shops(), throwsA(isA<PostgrestException>()));
      await expectLater(
        g.saveCatalogProduct(
          const AdminCatalogProduct(
            name: 'Rogue',
            barcode: '1',
            defaultUnit: 'piece',
          ),
        ),
        throwsA(isA<PostgrestException>()),
      );

      await enterCode(tester, '12ab');
      expect(find.text('Enter the 6-digit code.'), findsOneWidget);
      await enterCode(tester, '000000');
      expect(find.textContaining('Code not accepted'), findsOneWidget);
      expect(g.aal2, isFalse);
      expect(find.text('New shop'), findsNothing);

      await enterCode(tester, _FakeAdmin.validCode);
      expect(g.aal2, isTrue);
      expect(g.mfaEnrolled, isTrue);
      expect(find.text('New shop'), findsOneWidget);
    });

    testWidgets('enrolled admin is challenged; cancel signs out', (
      tester,
    ) async {
      final g = _FakeAdmin();
      await pump(tester, g);
      await passwordSignIn(tester, 'admin@dokanpro.pk');
      expect(find.text('Two-step verification'), findsOneWidget);
      expect(find.text('New shop'), findsNothing);
      await tester.tap(find.text('Cancel and sign out'));
      await tester.pumpAndSettle();
      expect(g.signedIn, isNull);
      expect(find.text('Sign-in cancelled.'), findsOneWidget);
    });

    testWidgets('cancelled enrolment removes the unverified factor', (
      tester,
    ) async {
      final g = _FakeAdmin()..mfaEnrolled = false;
      await pump(tester, g);
      await passwordSignIn(tester, 'admin@dokanpro.pk');
      await tester.tap(find.text('Cancel and sign out'));
      await tester.pumpAndSettle();
      expect(g.cancelledFactors, ['f-new']);
      expect(g.signedIn, isNull);
    });

    testWidgets('an expired session during the challenge returns to login', (
      tester,
    ) async {
      final g = _FakeAdmin();
      await pump(tester, g);
      await passwordSignIn(tester, 'admin@dokanpro.pk');
      g.sessionExpired = true;
      await enterCode(tester, _FakeAdmin.validCode);
      expect(find.text('Your session ended. Sign in again.'), findsOneWidget);
      expect(find.text('New shop'), findsNothing);
      expect(g.aal2, isFalse);
    });

    test('MFA failures map to safe messages', () {
      expect(
        mfaFailure(
          const AuthApiException(
            'Invalid TOTP code entered',
            statusCode: '422',
            code: 'mfa_verification_failed',
          ),
        ),
        MfaFailure.wrongCode,
      );
      expect(
        mfaFailure(
          const AuthApiException(
            'expired',
            statusCode: '422',
            code: 'mfa_challenge_expired',
          ),
        ),
        MfaFailure.expired,
      );
      expect(
        mfaFailure(
          const AuthApiException('gone', statusCode: '401', code: 'bad_jwt'),
        ),
        MfaFailure.sessionEnded,
      );
      expect(mfaFailure(StateError('x')), MfaFailure.unavailable);
      for (final f in MfaFailure.values) {
        expect(mfaFailureText(f), isNot(contains('JBSW')));
      }
    });
  });

  testWidgets('admin creates, activates and renews a shop', (tester) async {
    final g = _FakeAdmin();
    await pump(tester, g);
    await signIn(tester, 'admin@dokanpro.pk');
    expect(find.text('No shops yet.'), findsOneWidget);

    await tester.tap(find.text('New shop'));
    await tester.pumpAndSettle();
    final fields = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(fields.at(0), 'Ali Kiryana');
    await tester.enterText(fields.at(3), 'ali@shop.pk');
    await tester.enterText(fields.at(4), 'Ali');
    await tester.enterText(fields.at(5), 'temporary-pass');
    await tester.tap(find.widgetWithText(FilledButton, 'Create shop'));
    await tester.pumpAndSettle();
    expect(g.ownerLogins, ['ali@shop.pk']);
    expect(find.text('Ali Kiryana'), findsOneWidget);
    expect(find.text('pending'), findsOneWidget);

    await tester.tap(find.text('Ali Kiryana'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Activate'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(g.shopsById.values.single.licenseStatus, 'active');

    await tester.tap(find.text('Renew'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Renew'));
    await tester.pumpAndSettle();
    expect(g.renewals, ['pro_monthly x1']);
    expect(
      g.log.map((e) => e.action),
      containsAll(['shop.created', 'shop.activated', 'subscription.renewed']),
    );
  });

  testWidgets('a third device needs a replacement approval', (tester) async {
    final g = _FakeAdmin()..seedShopWithDevices();
    await pump(tester, g);
    await signIn(tester, 'admin@dokanpro.pk');
    await tester.tap(find.text('Seeded'));
    await tester.pumpAndSettle();
    expect(find.text('pending'), findsOneWidget);

    // Approving without a replacement is refused by the slot rule.
    await tester.tap(find.text('Approve'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Approve'));
    await tester.pumpAndSettle();
    expect(find.textContaining('DPL04'), findsOneWidget);
    expect(g.devicesById['new-tab']!.approvalStatus, 'pending');

    // With a replacement the old tablet is revoked.
    await tester.tap(find.text('Approve'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('None'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Old tablet · OLDTAB').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Approve'));
    await tester.pumpAndSettle();
    expect(g.devicesById['new-tab']!.approvalStatus, 'approved');
    expect(g.devicesById['old-tab']!.approvalStatus, 'revoked');
    expect(g.log.last.action, 'device.replaced');
  });

  testWidgets('reinstalled tablet in an over-limit legacy shop: revoke '
      'obsolete registrations, then approve with replace', (tester) async {
    // Ali_shop shape: one physical tablet, reinstalled several times, so four
    // grandfathered approved registrations, then a fifth after a reinstall.
    final g = _FakeAdmin()..seedLegacyReinstalledShop();
    await pump(tester, g);
    await signIn(tester, 'admin@dokanpro.pk');
    await tester.tap(find.text('Legacy'));
    await tester.pumpAndSettle();
    // Each identical "Android tablet" row is told apart by its code.
    for (final code in [
      'A1000001',
      'A1000002',
      'A1000003',
      'A1000004',
      'B2000005',
    ]) {
      expect(find.textContaining('Code $code'), findsOneWidget);
    }

    Future<void> approveReplacing(String code) async {
      final pendingRow = find.ancestor(
        of: find.textContaining('Code B2000005'),
        matching: find.byType(ListTile),
      );
      await tester.tap(
        find.descendant(of: pendingRow, matching: find.text('Approve')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('None'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Android tablet · $code').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Approve'));
      await tester.pumpAndSettle();
    }

    // One replacement cannot fit five registrations into two slots; the
    // admin is told how to proceed and nothing changes.
    await approveReplacing('A1000004');
    expect(
      find.textContaining('Revoke unused registrations first'),
      findsOneWidget,
    );
    expect(g.devicesById['b2000005-new']!.approvalStatus, 'pending');
    expect(g.devicesById['a1000004-cur']!.approvalStatus, 'approved');

    // Retire the obsolete registrations one by one (audited, data kept).
    for (final code in ['A1000001', 'A1000002', 'A1000003']) {
      final row = find.ancestor(
        of: find.textContaining('Code $code'),
        matching: find.byType(ListTile),
      );
      await tester.tap(find.descendant(of: row, matching: find.text('Revoke')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'reinstall cleanup');
      await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
      await tester.pumpAndSettle();
    }

    await approveReplacing('A1000004');
    expect(g.devicesById['b2000005-new']!.approvalStatus, 'approved');
    expect(g.devicesById['a1000004-cur']!.approvalStatus, 'revoked');
    expect(
      g.devicesById.values.where((d) => d.approvalStatus == 'approved'),
      hasLength(1),
    );
    expect(g.log.last.action, 'device.replaced');
  });

  group('global catalog', () {
    Finder dialogField(int i) => find
        .descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        )
        .at(i);

    Future<void> openCatalog(WidgetTester tester) async {
      await tester.tap(find.text('Catalog'));
      await tester.pumpAndSettle();
    }

    Future<void> save(WidgetTester tester) async {
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
    }

    testWidgets('admin adds a product with a 512px content-hash photo', (
      tester,
    ) async {
      final g = _FakeAdmin();
      final picker = _QueuedPicker()..picks.add(_png());
      await pump(tester, g, picker: picker);
      await signIn(tester, 'admin@dokanpro.pk');
      await openCatalog(tester);
      expect(find.text('No catalog products.'), findsOneWidget);

      await tester.tap(find.text('New product'));
      await tester.pumpAndSettle();
      await save(tester);
      expect(find.text('Name and barcode are required.'), findsOneWidget);
      expect(g.catalog, isEmpty);

      await tester.enterText(dialogField(0), 'Lemon Max Bar');
      await tester.enterText(dialogField(1), 'Lemon Max');
      await tester.enterText(dialogField(2), '8964001000110');
      await tester.enterText(dialogField(3), '200 g');
      await tester.tap(find.text('None'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Household').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add photo'));
      await tester.pumpAndSettle();
      expect(find.text('Change photo'), findsOneWidget);
      await save(tester);

      final p = g.catalog.values.single;
      expect(p.name, 'Lemon Max Bar');
      expect(p.brand, 'Lemon Max');
      expect(p.barcode, '8964001000110');
      expect(p.packLabel, '200 g');
      expect(p.categoryId, 'cat-household');
      expect(p.defaultUnit, 'piece');
      final jpeg = g.uploads.values.single;
      expect(p.imagePath, 'catalog/${sha256Hex(jpeg)}.jpg');
      expect(g.uploads.keys.single, p.imagePath);
      final decoded = img.decodeJpg(jpeg)!;
      expect(decoded.width, 512);
      expect(decoded.height, 341);
      expect(g.log.map((e) => e.action), [
        'catalog.product_created',
        'catalog.image_set',
      ]);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Lemon Max Bar'), findsOneWidget);
    });

    testWidgets('edit refuses a taken barcode and a non-image, then hides '
        'the product', (tester) async {
      final g = _FakeAdmin()
        ..catalog['mp-1'] = const AdminCatalogProduct(
          id: 'mp-1',
          name: 'Surf Excel 1kg',
          barcode: '111',
          defaultUnit: 'unit',
          imagePath: 'catalog/old.jpg',
        )
        ..catalog['mp-2'] = const AdminCatalogProduct(
          id: 'mp-2',
          name: 'Milk 1L',
          barcode: '222',
          defaultUnit: 'liter',
        );
      final picker = _QueuedPicker()
        ..picks.add(Uint8List.fromList(List.filled(64, 7)));
      await pump(tester, g, picker: picker);
      await signIn(tester, 'admin@dokanpro.pk');
      await openCatalog(tester);
      await tester.tap(find.text('Surf Excel 1kg'));
      await tester.pumpAndSettle();
      // A legacy unit stays selectable.
      expect(find.text('unit'), findsWidgets);

      await tester.enterText(dialogField(2), '222');
      await save(tester);
      expect(find.textContaining('DPL07'), findsOneWidget);
      expect(g.catalog['mp-1']!.barcode, '111');

      await tester.tap(find.text('Change photo'));
      await tester.pumpAndSettle();
      expect(
        find.text('Choose a JPG, PNG or WebP product image.'),
        findsOneWidget,
      );

      await tester.enterText(dialogField(2), '111');
      await tester.tap(find.text('Shown in shop catalog'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove photo'));
      await tester.pumpAndSettle();
      await save(tester);
      expect(g.catalog['mp-1']!.isActive, isFalse);
      expect(g.catalog['mp-1']!.defaultUnit, 'unit');
      expect(g.catalog['mp-1']!.imagePath, isNull);
      expect(g.uploads, isEmpty);
      expect(find.text('hidden'), findsOneWidget);
      expect(g.log.map((e) => e.action), [
        'catalog.product_updated',
        'catalog.image_cleared',
      ]);
    });

    testWidgets('a failed upload keeps the saved product; retry attaches '
        'without a duplicate', (tester) async {
      final g = _FakeAdmin()..failUpload = true;
      final picker = _QueuedPicker()..picks.add(_png(width: 300, height: 300));
      await pump(tester, g, picker: picker);
      await signIn(tester, 'admin@dokanpro.pk');
      await openCatalog(tester);
      await tester.tap(find.text('New product'));
      await tester.pumpAndSettle();
      await tester.enterText(dialogField(0), 'Tea 190g');
      await tester.enterText(dialogField(2), '333');
      await tester.tap(find.text('Add photo'));
      await tester.pumpAndSettle();
      await save(tester);
      expect(
        find.textContaining('Product saved, but the photo was not'),
        findsOneWidget,
      );
      expect(find.textContaining('Not permitted.'), findsOneWidget);
      expect(g.catalog.values.single.imagePath, isNull);

      g.failUpload = false;
      await save(tester);
      expect(find.byType(AlertDialog), findsNothing);
      final p = g.catalog.values.single;
      expect(p.imagePath, startsWith('catalog/'));
      expect(g.log.map((e) => e.action), [
        'catalog.product_created',
        'catalog.product_updated',
        'catalog.image_set',
      ]);
    });

    test('attachCatalogPhoto uploads under the content hash first', () async {
      final g = _FakeAdmin()
        ..signedIn = 'admin@dokanpro.pk'
        ..aal2 = true
        ..catalog['mp-1'] = const AdminCatalogProduct(
          id: 'mp-1',
          name: 'Salt',
          barcode: '9',
          defaultUnit: 'piece',
        );
      final jpeg = prepareProductThumbnail(_png(width: 600, height: 900));
      final key = await attachCatalogPhoto(g, 'mp-1', jpeg);
      expect(key, matches(RegExp(r'^catalog/[0-9a-f]{64}\.jpg$')));
      expect(key, catalogProductImageKey(sha256Hex(jpeg)));
      expect(g.uploads[key], jpeg);
      expect(g.catalog['mp-1']!.imagePath, key);
      // Same bytes, same key: a re-upload is the same file.
      expect(await attachCatalogPhoto(g, 'mp-1', jpeg), key);
    });

    test('catalog rows and errors map safely', () {
      final p = AdminCatalogProduct.fromJson({
        'id': 'x',
        'name': 'Milk',
        'brand': null,
        'barcode': '1',
        'category_id': null,
        'default_unit': 'liter',
        'pack_label': '1 L',
        'is_active': false,
        'default_image_path': 'catalog/abc.jpg',
      });
      expect(p.brand, '');
      expect(p.isActive, isFalse);
      expect(p.imagePath, 'catalog/abc.jpg');
      expect(
        isExistingObjectError(
          const StorageException(
            'The resource already exists',
            statusCode: '409',
          ),
        ),
        isTrue,
      );
      expect(
        isExistingObjectError(
          const StorageException('denied', statusCode: '403'),
        ),
        isFalse,
      );
      expect(
        adminErrorText(const StorageException('denied', statusCode: '403')),
        'Not permitted.',
      );
      expect(
        adminErrorText(
          const ProductImageException('The selected file is empty.'),
        ),
        'The selected file is empty.',
      );
      expect(
        adminErrorText(
          const PostgrestException(
            message: 'DPL08: upload the photo before attaching it',
            code: 'P0002',
          ),
        ),
        'DPL08: upload the photo before attaching it',
      );
    });
  });
}

AdminShop _copyShop(AdminShop s, {String? status, String? plan}) => AdminShop(
  id: s.id,
  name: s.name,
  phone: s.phone,
  address: s.address,
  licenseStatus: status ?? s.licenseStatus,
  ownerEmails: s.ownerEmails,
  approvedDevices: s.approvedDevices,
  pendingDevices: s.pendingDevices,
  planId: plan ?? s.planId,
  periodEnd: s.periodEnd,
);

AdminDevice _device(String id, String name, String form, String status) =>
    AdminDevice(
      id: id,
      name: name,
      deviceType: form == 'mobile' ? 'mobile' : 'androidTablet',
      formFactor: form,
      approvalStatus: status,
      isActive: status == 'approved',
      legacy: false,
    );

final class _QueuedPicker implements ProductImagePicker {
  final picks = <Uint8List?>[];
  @override
  Future<Uint8List?> pick() async => picks.removeAt(0);
}

/// A real photo-sized PNG, so the 512px JPEG step does real work.
Uint8List _png({int width = 1200, int height = 800}) => img.encodePng(
  img.Image(width: width, height: height)..clear(img.ColorRgb8(200, 40, 40)),
);

final class _FakeAdmin implements AdminGateway {
  static const validCode = '246810';
  final catalog = <String, AdminCatalogProduct>{};
  final uploads = <String, Uint8List>{};
  bool failUpload = false;

  @override
  Future<List<AdminCategory>> catalogCategories() async => const [
    AdminCategory('cat-household', 'Household'),
    AdminCategory('cat-dairy', 'Dairy'),
  ];
  @override
  Future<List<AdminCatalogProduct>> catalogProducts({String query = ''}) async {
    final q = query.trim().toLowerCase();
    return [
      for (final p in catalog.values)
        if (q.isEmpty ||
            p.barcode == q ||
            p.name.toLowerCase().contains(q) ||
            p.brand.toLowerCase().contains(q))
          p,
    ];
  }

  @override
  Future<String> saveCatalogProduct(AdminCatalogProduct p) async {
    _requireAdmin();
    if (catalog.values.any((x) => x.barcode == p.barcode && x.id != p.id)) {
      throw const PostgrestException(
        message: 'DPL07: another catalog product already uses this barcode',
        code: '23505',
      );
    }
    final old = p.id == null ? null : catalog[p.id];
    if (p.id != null && old == null) {
      throw const PostgrestException(message: 'not found', code: 'P0002');
    }
    final id = p.id ?? 'mp-${catalog.length + 1}';
    catalog[id] = AdminCatalogProduct(
      id: id,
      name: p.name,
      brand: p.brand,
      barcode: p.barcode,
      categoryId: p.categoryId,
      defaultUnit: p.defaultUnit,
      packLabel: p.packLabel,
      isActive: p.isActive,
      imagePath: old?.imagePath,
    );
    _log(old == null ? 'catalog.product_created' : 'catalog.product_updated');
    return id;
  }

  @override
  Future<void> uploadCatalogImage(String key, Uint8List jpeg) async {
    _requireAdmin();
    if (failUpload) {
      throw const StorageException(
        'new row violates policy',
        statusCode: '403',
      );
    }
    uploads[key] = jpeg;
  }

  @override
  Future<void> setCatalogImage(String productId, String? key) async {
    _requireAdmin();
    if (key != null && !uploads.containsKey(key)) {
      throw const PostgrestException(
        message: 'DPL08: upload the photo before attaching it',
        code: 'P0002',
      );
    }
    final p = catalog[productId]!;
    catalog[productId] = AdminCatalogProduct(
      id: p.id,
      name: p.name,
      brand: p.brand,
      barcode: p.barcode,
      categoryId: p.categoryId,
      defaultUnit: p.defaultUnit,
      packLabel: p.packLabel,
      isActive: p.isActive,
      imagePath: key,
    );
    _log(key == null ? 'catalog.image_cleared' : 'catalog.image_set');
  }

  String? signedIn;
  bool mfaEnrolled = true, aal2 = false, sessionExpired = false;
  final cancelledFactors = <String>[];
  final shopsById = <String, AdminShop>{};
  final devicesById = <String, AdminDevice>{};
  final deviceShop = <String, String>{};
  final ownerLogins = <String>[];
  final renewals = <String>[];
  final log = <AdminAuditEntry>[];

  void _log(String action) => log.add(
    AdminAuditEntry(
      action: action,
      actorKind: 'platform_admin',
      createdAt: DateTime.now().toUtc(),
      details: const {},
    ),
  );

  void _requireAdmin() {
    if (signedIn != 'admin@dokanpro.pk' || !aal2) {
      throw const PostgrestException(
        message: 'platform administrator required',
        code: '42501',
      );
    }
  }

  void seedShopWithDevices() {
    shopsById['s1'] = const AdminShop(
      id: 's1',
      name: 'Seeded',
      phone: '',
      address: '',
      licenseStatus: 'active',
      ownerEmails: ['o@shop.pk'],
      approvedDevices: 2,
      pendingDevices: 1,
    );
    for (final d in [
      _device('old-tab', 'Old tablet', 'tablet', 'approved'),
      _device('phone', 'Phone', 'mobile', 'approved'),
      _device('new-tab', 'New tablet', 'tablet', 'pending'),
    ]) {
      devicesById[d.id] = d;
      deviceShop[d.id] = 's1';
    }
  }

  void seedLegacyReinstalledShop() {
    shopsById['s2'] = const AdminShop(
      id: 's2',
      name: 'Legacy',
      phone: '',
      address: '',
      licenseStatus: 'active',
      ownerEmails: ['o@legacy.pk'],
      approvedDevices: 4,
      pendingDevices: 1,
    );
    for (final d in [
      _device('a1000001-old', 'Android tablet', 'tablet', 'approved'),
      _device('a1000002-old', 'Android tablet', 'tablet', 'approved'),
      _device('a1000003-old', 'Android tablet', 'tablet', 'approved'),
      _device('a1000004-cur', 'Android tablet', 'tablet', 'approved'),
      _device('b2000005-new', 'Android tablet', 'tablet', 'pending'),
    ]) {
      devicesById[d.id] = d;
      deviceShop[d.id] = 's2';
    }
  }

  @override
  Future<String?> currentEmail() async => signedIn;
  @override
  Future<void> signIn(String email, String password) async {
    signedIn = email;
    aal2 = false;
  }

  @override
  Future<void> signOut() async {
    signedIn = null;
    aal2 = false;
  }

  @override
  Future<AdminAccess> access() async => signedIn != 'admin@dokanpro.pk'
      ? AdminAccess.none
      : aal2
      ? AdminAccess.granted
      : AdminAccess.mfaRequired;
  @override
  Future<String?> verifiedTotpFactorId() async => mfaEnrolled ? 'f-1' : null;
  @override
  Future<TotpEnrollment> enrollTotp() async => const TotpEnrollment(
    factorId: 'f-new',
    secret: 'JBSWY3DPEHPK3PXP',
    uri: 'otpauth://totp/Dokan%20Pro%20Admin?secret=JBSWY3DPEHPK3PXP',
  );
  @override
  Future<void> verifyTotp(String factorId, String code) async {
    if (sessionExpired) {
      throw const AuthApiException(
        'session missing',
        statusCode: '401',
        code: 'session_not_found',
      );
    }
    if (code != validCode) {
      throw const AuthApiException(
        'Invalid TOTP code entered',
        statusCode: '422',
        code: 'mfa_verification_failed',
      );
    }
    mfaEnrolled = true;
    aal2 = true;
  }

  @override
  Future<void> cancelEnrollment(String factorId) async =>
      cancelledFactors.add(factorId);
  @override
  Future<List<AdminShop>> shops() async {
    _requireAdmin();
    return shopsById.values.toList();
  }

  @override
  Future<List<AdminPlan>> plans() async => const [
    AdminPlan('trial', 'Trial', 'trial'),
    AdminPlan('pro_monthly', 'Pro', 'monthly'),
  ];
  @override
  Future<String> createShop({
    required String name,
    required String phone,
    required String address,
    required String ownerEmail,
  }) async {
    _requireAdmin();
    final id = 'shop-${shopsById.length + 1}';
    shopsById[id] = AdminShop(
      id: id,
      name: name,
      phone: phone,
      address: address,
      licenseStatus: 'pending',
      ownerEmails: [ownerEmail],
      approvedDevices: 0,
      pendingDevices: 0,
      planId: 'trial',
    );
    _log('shop.created');
    return id;
  }

  @override
  Future<void> createOwnerLogin({
    required String email,
    required String temporaryPassword,
    required String fullName,
  }) async {
    _requireAdmin();
    ownerLogins.add(email);
  }

  @override
  Future<void> assignOwner(String shopId, String email) async =>
      _requireAdmin();
  @override
  Future<void> setShopStatus(String shopId, String status, String note) async {
    _requireAdmin();
    shopsById[shopId] = _copyShop(shopsById[shopId]!, status: status);
    _log(status == 'active' ? 'shop.activated' : 'shop.suspended');
  }

  @override
  Future<void> renew(String shopId, String planId, int months) async {
    _requireAdmin();
    renewals.add('$planId x$months');
    shopsById[shopId] = _copyShop(shopsById[shopId]!, plan: planId);
    _log('subscription.renewed');
  }

  @override
  Future<List<AdminDevice>> devices(String shopId) async => [
    for (final e in devicesById.entries)
      if (deviceShop[e.key] == shopId) e.value,
  ];
  @override
  Future<void> approveDevice(
    String deviceId, {
    String? replaceDeviceId,
    String? formFactor,
  }) async {
    _requireAdmin();
    final d = devicesById[deviceId]!;
    final form = formFactor ?? d.formFactor;
    // One transaction on the server: the replaced device is revoked only if
    // the approval then fits the slots.
    final taken = devicesById.values.where(
      (x) =>
          x.id != deviceId &&
          x.id != replaceDeviceId &&
          x.approvalStatus == 'approved',
    );
    if (taken.any((x) => x.formFactor == form) || taken.length >= 2) {
      throw PostgrestException(
        message: 'DPL04: this shop already has an approved $form device',
        code: '42501',
      );
    }
    if (replaceDeviceId != null) {
      final old = devicesById[replaceDeviceId]!;
      devicesById[replaceDeviceId] = _device(
        old.id,
        old.name,
        old.formFactor,
        'revoked',
      );
    }
    devicesById[deviceId] = _device(d.id, d.name, form, 'approved');
    _log(replaceDeviceId == null ? 'device.approved' : 'device.replaced');
  }

  @override
  Future<void> rejectDevice(String deviceId, String note) async {
    final d = devicesById[deviceId]!;
    devicesById[deviceId] = _device(d.id, d.name, d.formFactor, 'rejected');
  }

  @override
  Future<void> revokeDevice(String deviceId, String note) async {
    final d = devicesById[deviceId]!;
    devicesById[deviceId] = _device(d.id, d.name, d.formFactor, 'revoked');
  }

  @override
  Future<void> setFormFactor(String deviceId, String formFactor) async {}
  @override
  Future<List<AdminAuditEntry>> audit({String? shopId}) async {
    _requireAdmin();
    return log.reversed.toList();
  }
}
