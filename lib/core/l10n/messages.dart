import 'package:intl/intl.dart' show Bidi;

import '../../l10n/app_localizations.dart';
import 'bidi.dart';

/// Domain and service code keeps its English messages (logs, tests, sync).
/// Widgets show them through these mappers, so each known message has a
/// translation; with English the result is exactly the original text.

/// The translation of a known domain message, or null when [message] is not
/// one this app knows (callers decide how to show it).
String? localizedKnownMessage(
  AppLocalizations l10n,
  String message,
) => switch (message) {
  // Checkout (LocalSaleService, PosCheckoutController).
  'Cart must not be empty' => l10n.saleErrCartEmpty,
  'Discount cannot be negative' => l10n.saleErrDiscountNegative,
  'Discount exceeds line value' => l10n.saleErrDiscountTooHigh,
  'Insufficient stock' => l10n.saleErrInsufficientStock,
  'Product requires a display name' => l10n.saleErrProductName,
  'Sale total cannot be negative' => l10n.saleErrTotalNegative,
  'Shop does not exist' => l10n.saleErrShopMissing,
  'Cashier is not active for this shop' => l10n.saleErrCashierInactive,
  'Credit customer is not active for this shop' =>
    l10n.saleErrCreditCustomerInactive,
  'Credit payment requires a customer' => l10n.saleErrCreditNeedsCustomer,
  'Customer credit limit exceeded' => l10n.saleErrCreditLimit,
  'Device is not active for this shop' => l10n.saleErrDeviceInactive,
  'Measured product requires kg or liter' => l10n.saleErrMeasuredUnit,
  'Payment amounts must be greater than zero' => l10n.saleErrPaymentPositive,
  'Payment total must equal sale total' => l10n.saleErrPaymentTotal,
  'Piece products are sold in whole units' => l10n.saleErrWholeUnits,
  'Product is not active for this shop' => l10n.saleErrProductInactive,
  'Product prices cannot be negative' => l10n.saleErrPriceNegative,
  'Quantities must be greater than zero' => l10n.saleErrQuantityPositive,
  // Payment plan (PosPaymentPlan.validate).
  'Enter a valid payment.' => l10n.payErrInvalid,
  'Payment total must equal the sale total.' => l10n.payErrTotal,
  'Select a customer for Udhaar.' => l10n.payErrUdhaarCustomer,
  'Cash received is less than the total.' => l10n.payErrCashShort,
  // Measured quantities (measureQuantityError).
  'Enter a valid quantity.' => l10n.measureErrInvalid,
  'Quantity must be more than zero.' => l10n.measureErrZero,
  'Quantity is too large.' => l10n.measureErrTooLarge,
  // Receipt printing (UnavailableReceiptPrinter).
  'No receipt printer is configured. You can retry from Sales.' =>
    l10n.receiptPrinterMissing,
  // Products (ProductManagementService, product forms, images).
  'This product is already in your shop' => l10n.prodErrAlreadyInShop,
  'Product name is required' => l10n.prodErrNameRequired,
  'Category is required' => l10n.prodErrCategoryRequired,
  'Product family name is required' => l10n.prodErrFamilyNameRequired,
  'Add at least one pack size' => l10n.prodErrNoPackSize,
  'Every pack needs a size label' => l10n.prodErrPackLabel,
  'Prices cannot be negative' => l10n.prodErrPricesNegative,
  'Loose products are sold by weight (kg) or volume (L)' =>
    l10n.prodErrLooseUnit,
  'Quick quantities are not valid' => l10n.prodErrPresetsInvalid,
  'Stock values cannot be negative' => l10n.prodErrStockNegative,
  'Enter valid non-negative values.' => l10n.prodErrValues,
  'Complete all required fields with valid values.' =>
    l10n.prodErrRequiredFields,
  'it could not be saved' => l10n.prodErrNotSaved,
  'Could not save the product. Please try again.' => l10n.prodErrSaveFailed,
  'Could not create the product. Please try again.' => l10n.prodErrCreateFailed,
  'Could not update product.' => l10n.prodErrUpdateFailed,
  'Catalog search failed. Check internet and try again.' =>
    l10n.productsCatalogSearchFailed,
  'Could not open that image. Try another.' => l10n.prodErrImageOpen,
  'The selected file is empty.' => l10n.prodErrImageEmpty,
  'The selected image is too large.' => l10n.prodErrImageTooLarge,
  'Choose a JPG, PNG or WebP product image.' => l10n.prodErrImageFormat,
  'That quick quantity is already in the list.' => l10n.presetErrDuplicate,
  'Keep at least one quick quantity.' => l10n.presetErrKeepOne,
  // Inventory adjustment.
  'Enter a valid quantity and reason.' => l10n.inventoryErrInvalid,
  // Bills, Khata and customers.
  'Sales could not be loaded. Please try again.' => l10n.billsLoadFailed,
  'Enter an amount greater than zero.' => l10n.khataErrAmountZero,
  'Name and a valid credit limit are required.' => l10n.customersErrRequired,
  'Customers could not be refreshed. Showing available offline data.' =>
    l10n.customersRefreshWarning,
  // Purchases, expenses, settings and cashier setup.
  'Could not save the purchase. Please try again.' =>
    l10n.purchasesErrSaveFailed,
  'Could not save the expense. Please try again.' => l10n.expensesErrSaveFailed,
  'Settings are unavailable offline until the first sync.' =>
    l10n.settingsOfflineUnavailable,
  'Showing cached settings.' => l10n.settingsShowingCached,
  'Enter a shop name and a non-negative stock threshold.' =>
    l10n.settingsErrRequired,
  'Could not save settings. Check your connection.' => l10n.settingsSaveFailed,
  'Enter the cashier name.' => l10n.cashierErrName,
  'PIN must contain 4 to 8 digits.' => l10n.cashierErrPin,
  'PINs do not match.' => l10n.cashierErrPinMismatch,
  'Could not create the cashier. Please try again.' => l10n.cashierErrCreate,
  'Could not update the cashier. Please try again.' => l10n.cashierErrUpdate,
  // Sign-in and sessions (safeUserMessage, AuthSessionController).
  'Wrong email or password.' => l10n.authErrWrongCredentials,
  'Your session expired. Please sign in again.' => l10n.authErrSessionExpired,
  'Could not register this device. Check your connection.' =>
    l10n.deviceErrRegister,
  // Device lobby warnings (DeviceModeService).
  'This device must be set up for cashier mode once. Ask the owner to sign in.' =>
    l10n.deviceWarnSetupOnce,
  'The offline cashier session expired. Connect to the internet and sign in again.' =>
    l10n.deviceWarnOfflineExpired,
  'Offline cashier access is unavailable because this shop or device no longer matches. Connect to the internet and sign in again.' =>
    l10n.deviceWarnMismatch,
  // Subscription (EntitlementPolicyService). Presentation only: the policy
  // decides, and its English message is unchanged.
  'Online subscription verification is required.' =>
    l10n.subMsgVerificationRequired,
  'Stored subscription proof is invalid. Verify online.' =>
    l10n.subMsgProofInvalid,
  'Device time changed significantly. Connect online to verify.' =>
    l10n.subMsgClockChanged,
  'Shop subscription needs renewal. Please contact the owner.' =>
    l10n.subMsgNeedsRenewal,
  'Grace period active. Online verification is needed.' => l10n.subMsgGrace,
  'Subscription ending soon.' => l10n.subMsgEndingSoon,
  'Subscription verified.' => l10n.subMsgVerified,
  'This shop is not active. Contact Dokan Pro Support.' =>
    l10n.subMsgShopNotActive,
  'This device is not approved. Contact Dokan Pro Support.' =>
    l10n.subMsgDeviceNotApproved,
  _ => _localizedTemplate(l10n, message),
};

/// Messages that carry a value (a pack label, barcode or count). The value
/// is kept exactly as entered and isolated so it never reorders in Urdu.
String? _localizedTemplate(AppLocalizations l10n, String message) {
  // Values are isolated only in a right-to-left language, so English output
  // is exactly the source text.
  final rtl = Bidi.isRtlLanguage(l10n.localeName);
  String keep(String value) => rtl ? isolateAuto(value) : value;
  String keepLtr(String value) => rtl ? isolateLtr(value) : value;
  for (final (pattern, build) in <(RegExp, String Function(RegExpMatch))>[
    (
      RegExp(r'^Pack size (.+) is listed twice$'),
      (m) => l10n.prodErrPackTwice(keep(m[1]!)),
    ),
    (
      RegExp(r'^Barcode (.+) is already used in this shop$'),
      (m) => l10n.prodErrBarcodeUsed(keepLtr(m[1]!)),
    ),
    (
      RegExp(r'^Enter a sale price for (.+)$'),
      (m) => l10n.prodErrPackSalePrice(keep(m[1]!)),
    ),
    (
      RegExp(r'^Stock for (.+) must be whole packs$'),
      (m) => l10n.prodErrWholePacks(keep(m[1]!)),
    ),
    (
      RegExp(r'^Payment cannot exceed (.+)\.$'),
      (m) => l10n.khataErrExceeds(keepLtr(m[1]!)),
    ),
    (
      RegExp(r'^Use at most (\d+) quick quantities$'),
      (m) => l10n.prodErrPresetCount(m[1]!),
    ),
    (
      RegExp(r'^Use at most (\d+) quick quantities\.$'),
      (m) => l10n.prodErrPresetCountDot(m[1]!),
    ),
    (
      RegExp(r'^Pack (.*): enter a sale price and whole-pack stock\.$'),
      (m) => l10n.prodErrPackRow(keep(m[1]!)),
    ),
    (
      RegExp(
        r'^Pack (.*) was not created: (.*)\. (\d+) size\(s\) already saved; '
        r'press Create again to finish without duplicating them\.$',
      ),
      (m) => l10n.prodErrFamilyIncomplete(
        keep(m[1]!),
        localizedKnownMessage(l10n, m[2]!) ?? m[2]!,
        m[3]!,
      ),
    ),
  ]) {
    if (pattern.firstMatch(message) case final match?) return build(match);
  }
  return null;
}

/// A checkout or validation message for the cashier. Unknown messages keep
/// their English detail (Urdu adds a translated lead-in).
String localizedSaleError(AppLocalizations l10n, String message) =>
    localizedKnownMessage(l10n, message) ?? l10n.saleErrorOther(message);

/// A known message translated; any other text unchanged.
String localizedMessage(AppLocalizations l10n, String message) =>
    localizedKnownMessage(l10n, message) ?? message;

/// The owner-facing reason stored on a sync operation (English, written by
/// the sync layer and kept for diagnostics). Known reasons are translated;
/// an unknown one is shown as stored. The stored row never changes.
String localizedSyncReason(AppLocalizations l10n, String reason) {
  final known = switch (reason) {
    'The cloud rejected this record as invalid or out of date.' =>
      l10n.syncReasonInvalid,
    'A different version of this record is already in the cloud.' =>
      l10n.syncReasonOtherVersion,
    'This change conflicts with the cloud and cannot be applied.' =>
      l10n.syncReasonConflict,
    'This device or cashier is no longer authorised.' =>
      l10n.syncReasonDeviceNotAuthorised,
    'This device or session is not authorised to sync.' =>
      l10n.syncReasonSessionNotAuthorised,
    'The sign-in session expired.' => l10n.syncReasonSessionExpired,
    'The sign-in session is missing.' => l10n.syncReasonSessionMissing,
    'This record was saved by an older app version and cannot be sent safely.' =>
      l10n.syncReasonOldVersion,
    'No connection to the cloud. It will retry automatically.' =>
      l10n.syncReasonOffline,
    'The cloud is temporarily unavailable. It will retry automatically.' =>
      l10n.syncReasonTemporary,
    'The cloud could not accept this record.' => l10n.syncReasonRejected,
    'An earlier record it depends on needs attention.' => l10n.syncReasonParent,
    _ => null,
  };
  if (known != null) return known;
  final flagged = RegExp(
    r'^Saved in the cloud, but it broke a shop rule \((.*)\)\. Please review it\.$',
  ).firstMatch(reason);
  if (flagged == null) return reason;
  final rtl = Bidi.isRtlLanguage(l10n.localeName);
  final rules = flagged[1]!
      .split(', ')
      .map(
        (rule) => switch (rule) {
          'customer credit limit exceeded' => l10n.syncFlagCreditLimit,
          // An unknown rule is a stable code: kept as is, never reordered.
          _ => rtl ? isolateLtr(rule) : rule,
        },
      )
      .join(rtl ? '، ' : ', ');
  return l10n.syncReasonFlagged(rules);
}

/// Built-in categories (seed data with fixed ids, shared by every shop) are
/// translated for display. Every other category is the shop's own and is
/// shown exactly as entered. Stored names are never changed.
String localizedCategoryName(
  AppLocalizations l10n,
  String id,
  String storedName,
) => switch (id) {
  'd0000000-0000-0000-0000-000000000001' => l10n.categoryHousehold,
  'd0000000-0000-0000-0000-000000000002' => l10n.categoryStaples,
  'd0000000-0000-0000-0000-000000000003' => l10n.categoryDairy,
  'd0000000-0000-0000-0000-000000000004' => l10n.categoryCookingEssentials,
  'd0000000-0000-0000-0000-000000000005' => l10n.categoryBeverages,
  'd0000000-0000-0000-0000-000000000006' => l10n.categorySnacks,
  _ => storedName,
};

/// A bill status as stored by the history query (`Completed`, `Voided`,
/// `Fully Returned`, `Partially Returned`): unchanged in English, translated
/// in Urdu. The stored value itself never changes.
String localizedSaleStatus(AppLocalizations l10n, String status) =>
    l10n.saleStatus(status.replaceAll(' ', ''), status);
