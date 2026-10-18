import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ur.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ur'),
  ];

  /// Tooltip and accessible label of the language switcher button.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get languageMenuTooltip;

  /// Name of the English language, always written in English (endonym).
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// Name of the Urdu language, always written in Urdu (endonym).
  ///
  /// In en, this message translates to:
  /// **'اردو'**
  String get languageUrdu;

  /// Heading above the Urdu font choice (Nastaliq or Naskh) in the language menu.
  ///
  /// In en, this message translates to:
  /// **'Urdu font'**
  String get urduFontHeading;

  /// Nastaliq style Urdu font option (Noto Nastaliq Urdu).
  ///
  /// In en, this message translates to:
  /// **'Nastaliq'**
  String get urduFontNastaliq;

  /// Naskh style Urdu font option (Noto Naskh Arabic); more compact.
  ///
  /// In en, this message translates to:
  /// **'Naskh'**
  String get urduFontNaskh;

  /// Dismisses a dialog without changes. Deliberately different from voiding a bill (بل منسوخ کریں).
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get commonCancel;

  /// Saves a form.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get commonSave;

  /// Closes a dialog or sheet.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get commonClose;

  /// Tries a failed load or sync again.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get commonRetry;

  /// Signs the owner out of this device.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get commonSignOut;

  /// Empties the current bill or a field.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get commonClear;

  /// Removes an item, e.g. a chosen product photo.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get commonRemove;

  /// Form footer hint: fields marked * must be filled.
  ///
  /// In en, this message translates to:
  /// **'* Required'**
  String get commonRequiredHint;

  /// Shown when the on-device database cannot be opened.
  ///
  /// In en, this message translates to:
  /// **'Could not open local data.'**
  String get commonLocalDataUnavailable;

  /// POS sidebar: the sale (billing) screen.
  ///
  /// In en, this message translates to:
  /// **'Sale'**
  String get navSale;

  /// POS sidebar: product list.
  ///
  /// In en, this message translates to:
  /// **'Products'**
  String get navProducts;

  /// POS sidebar: past bills.
  ///
  /// In en, this message translates to:
  /// **'Bills'**
  String get navBills;

  /// POS sidebar: customer credit ledger (Khata / Udhaar).
  ///
  /// In en, this message translates to:
  /// **'Khata'**
  String get navKhata;

  /// Button that returns from owner sign-in to the cashier PIN screen.
  ///
  /// In en, this message translates to:
  /// **'Back to cashier login'**
  String get navBackToCashierLogin;

  /// Owner home: sales and profit summary.
  ///
  /// In en, this message translates to:
  /// **'Owner Dashboard'**
  String get ownerNavDashboard;

  /// Owner home: shop settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get ownerNavSettings;

  /// Owner home: bills, returns and voids.
  ///
  /// In en, this message translates to:
  /// **'Sales & Returns'**
  String get ownerNavSalesReturns;

  /// Owner home: stock levels and adjustments.
  ///
  /// In en, this message translates to:
  /// **'Inventory'**
  String get ownerNavInventory;

  /// Owner home: create and edit products.
  ///
  /// In en, this message translates to:
  /// **'Manage products'**
  String get ownerNavProducts;

  /// Owner home: customers and their Udhaar ledger.
  ///
  /// In en, this message translates to:
  /// **'Manage customers / Khata'**
  String get ownerNavCustomers;

  /// Owner home: suppliers, purchases and supplier payments.
  ///
  /// In en, this message translates to:
  /// **'Suppliers & Purchases'**
  String get ownerNavPurchases;

  /// Owner home: shop expenses.
  ///
  /// In en, this message translates to:
  /// **'Expenses'**
  String get ownerNavExpenses;

  /// Owner home entry and screen title: records that could not be saved online.
  ///
  /// In en, this message translates to:
  /// **'Sync issues'**
  String get syncIssuesTitle;

  /// Status chip: everything is saved online.
  ///
  /// In en, this message translates to:
  /// **'Synced'**
  String get syncStatusSynced;

  /// Status chip: sales saved on the tablet, waiting to upload.
  ///
  /// In en, this message translates to:
  /// **'Pending sync'**
  String get syncStatusPending;

  /// Status chip: uploading now.
  ///
  /// In en, this message translates to:
  /// **'Syncing'**
  String get syncStatusSyncing;

  /// Status chip: no internet; billing continues.
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get syncStatusOffline;

  /// Status chip and state: a record needs the owner to look at it.
  ///
  /// In en, this message translates to:
  /// **'Needs attention'**
  String get syncStatusNeedsAttention;

  /// Tooltip on the Needs attention chip, shown to cashiers.
  ///
  /// In en, this message translates to:
  /// **'Some records could not sync. The owner can review them.'**
  String get syncStatusNeedsAttentionHint;

  /// Empty state of the sync issues screen.
  ///
  /// In en, this message translates to:
  /// **'No sync issues.'**
  String get syncNoIssues;

  /// Reassurance above the sync issue list.
  ///
  /// In en, this message translates to:
  /// **'Nothing here was deleted. Records stay on this device until they sync.'**
  String get syncNothingDeleted;

  /// Shown when a sync issue has no stored reason.
  ///
  /// In en, this message translates to:
  /// **'This record could not sync.'**
  String get syncReasonFallback;

  /// Detail line of a sync issue. code is a technical code (never translated), time is dd/MM HH:mm, attempts a number.
  ///
  /// In en, this message translates to:
  /// **'Code: {code} • {state} • {time} • attempts {attempts}'**
  String syncAttentionDetails(
    String code,
    String state,
    String time,
    String attempts,
  );

  /// A record that synced but broke a shop rule.
  ///
  /// In en, this message translates to:
  /// **'Synced, flagged'**
  String get syncStateFlagged;

  /// A record waiting for the device or cashier to be authorised again.
  ///
  /// In en, this message translates to:
  /// **'Waiting for authorisation'**
  String get syncStateWaitingAuthorisation;

  /// Button: the owner has seen a flagged record.
  ///
  /// In en, this message translates to:
  /// **'Acknowledge'**
  String get syncAcknowledge;

  /// Sync issue title for a sale. reference is the bill number (never translated).
  ///
  /// In en, this message translates to:
  /// **'Sale • {reference}'**
  String syncEntitySale(String reference);

  /// Sync issue title for a voided bill.
  ///
  /// In en, this message translates to:
  /// **'Bill void'**
  String get syncEntityVoid;

  /// Sync issue title for a bill return.
  ///
  /// In en, this message translates to:
  /// **'Bill return'**
  String get syncEntityReturn;

  /// Sync issue title for an Udhaar payment received.
  ///
  /// In en, this message translates to:
  /// **'Customer payment'**
  String get syncEntityCustomerPayment;

  /// Sync issue title for a purchase.
  ///
  /// In en, this message translates to:
  /// **'Purchase'**
  String get syncEntityPurchase;

  /// Sync issue title for a payment to a supplier.
  ///
  /// In en, this message translates to:
  /// **'Supplier payment'**
  String get syncEntitySupplierPayment;

  /// Sync issue title for an expense.
  ///
  /// In en, this message translates to:
  /// **'Expense'**
  String get syncEntityExpense;

  /// Sync issue title for a manual stock change.
  ///
  /// In en, this message translates to:
  /// **'Stock adjustment'**
  String get syncEntityStockAdjustment;

  /// Web preview placeholder.
  ///
  /// In en, this message translates to:
  /// **'Sync issues are available on Android and Windows.'**
  String get syncIssuesDeviceOnly;

  /// Short month name for dates such as 5 Oct 2026. month is 1-12. Urdu uses the full Gregorian month name.
  ///
  /// In en, this message translates to:
  /// **'{month, select, 1{Jan} 2{Feb} 3{Mar} 4{Apr} 5{May} 6{Jun} 7{Jul} 8{Aug} 9{Sep} 10{Oct} 11{Nov} 12{Dec} other{}}'**
  String monthShort(String month);

  /// Morning suffix for 12-hour times. Kept as AM in Urdu (as on Pakistani receipts and phones); native review may change it.
  ///
  /// In en, this message translates to:
  /// **'AM'**
  String get timeAm;

  /// Afternoon/evening suffix for 12-hour times. Kept as PM in Urdu; native review may change it.
  ///
  /// In en, this message translates to:
  /// **'PM'**
  String get timePm;

  /// A date that is today.
  ///
  /// In en, this message translates to:
  /// **'Today, {time}'**
  String relativeToday(String time);

  /// A date that was yesterday. Urdu avoids plain کل, which also means tomorrow.
  ///
  /// In en, this message translates to:
  /// **'Yesterday, {time}'**
  String relativeYesterday(String time);

  /// A date that is tomorrow.
  ///
  /// In en, this message translates to:
  /// **'Tomorrow, {time}'**
  String relativeTomorrow(String time);

  /// Any other date with its time.
  ///
  /// In en, this message translates to:
  /// **'{date}, {time}'**
  String dateWithTime(String date, String time);

  /// Payment method stored as cash.
  ///
  /// In en, this message translates to:
  /// **'Cash'**
  String get paymentCash;

  /// Payment method stored as digital (JazzCash, Easypaisa, bank).
  ///
  /// In en, this message translates to:
  /// **'Digital'**
  String get paymentDigital;

  /// Payment method stored as credit (the customer owes the shop).
  ///
  /// In en, this message translates to:
  /// **'Udhaar'**
  String get paymentUdhaar;

  /// A bill paid with more than one method.
  ///
  /// In en, this message translates to:
  /// **'Split'**
  String get paymentSplit;

  /// A Rs 0 bill with no payment.
  ///
  /// In en, this message translates to:
  /// **'No payment'**
  String get paymentNone;

  /// Kilogram label after a weight, e.g. 2.5 kg.
  ///
  /// In en, this message translates to:
  /// **'kg'**
  String get unitKg;

  /// Gram label after a weight below 1 kg, e.g. 250 g.
  ///
  /// In en, this message translates to:
  /// **'g'**
  String get unitGram;

  /// Liter label after a volume, e.g. 1.5 L.
  ///
  /// In en, this message translates to:
  /// **'L'**
  String get unitLiter;

  /// Milliliter label after a volume below 1 L, e.g. 750 ml.
  ///
  /// In en, this message translates to:
  /// **'ml'**
  String get unitMilliliter;

  /// A measured quantity: amount is digits (e.g. 2.5), unit one of the unit labels.
  ///
  /// In en, this message translates to:
  /// **'{amount} {unit}'**
  String measureQuantity(String amount, String unit);

  /// Price per unit, e.g. Rs 130.00/kg. price is already formatted.
  ///
  /// In en, this message translates to:
  /// **'{price}/{unit}'**
  String unitPrice(String price, String unit);

  /// Sale screen heading.
  ///
  /// In en, this message translates to:
  /// **'New Sale'**
  String get posNewSaleHeading;

  /// Line under the heading: today's sales total and number of bills. amount is a formatted price such as Rs 350.00 (kept left to right).
  ///
  /// In en, this message translates to:
  /// **'Today: {amount}  •  {bills} bills'**
  String posTodaySummary(String amount, String bills);

  /// Hint in the sale search field.
  ///
  /// In en, this message translates to:
  /// **'Search product or scan barcode'**
  String get posSearchHint;

  /// Category chip that shows every product.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get posCategoryAll;

  /// Empty product grid (search or category has no match).
  ///
  /// In en, this message translates to:
  /// **'No local products found.'**
  String get posNoProducts;

  /// Scanned barcode is not in the catalogue.
  ///
  /// In en, this message translates to:
  /// **'No product matches that barcode.'**
  String get posNoBarcodeMatch;

  /// Shown in the bill, the payment dialog and a snackbar when the owner's new prices reached the tablet while items were in the cart.
  ///
  /// In en, this message translates to:
  /// **'Prices changed since these items were added. Check the total before taking payment.'**
  String get posPricesChangedTitle;

  /// One changed cart price. product is shown as entered; oldPrice and newPrice are formatted amounts.
  ///
  /// In en, this message translates to:
  /// **'{product}: was {oldPrice}, now {newPrice}'**
  String posPriceChangeLine(String product, String oldPrice, String newPrice);

  /// Warning above the sale grid when the shop has more active products than the POS loads. shown and total are formatted counts.
  ///
  /// In en, this message translates to:
  /// **'Showing the first {shown} of {total} products (A–Z). Later products cannot be found or scanned here. Archive products you no longer sell.'**
  String posCatalogTruncated(String shown, String total);

  /// Warning in the payment dialog when the shop has more active customers than the POS loads for Udhaar. shown and total are formatted counts.
  ///
  /// In en, this message translates to:
  /// **'Only the first {shown} of {total} customers (A–Z) can be picked here. Ask the owner to deactivate customers who no longer buy on Udhaar.'**
  String posCustomersTruncated(String shown, String total);

  /// Button on a product card: add to the current bill.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get posAdd;

  /// Confirms a changed quantity of a bill line.
  ///
  /// In en, this message translates to:
  /// **'Update'**
  String get posUpdate;

  /// Stock on a product card; stock is a number or a measure such as 40 kg.
  ///
  /// In en, this message translates to:
  /// **'Stock {stock}'**
  String posStock(String stock);

  /// Stock on a product card when it is low.
  ///
  /// In en, this message translates to:
  /// **'Stock {stock} • Low'**
  String posStockLow(String stock);

  /// Lowest price of a pack family, e.g. From Rs 95.00.
  ///
  /// In en, this message translates to:
  /// **'From {price}'**
  String posFromPrice(String price);

  /// Number of sizes in a pack family.
  ///
  /// In en, this message translates to:
  /// **'{count} pack sizes'**
  String posPackSizes(String count);

  /// Number of sizes in a pack family when one of them is low on stock.
  ///
  /// In en, this message translates to:
  /// **'{count} pack sizes • Low'**
  String posPackSizesLow(String count);

  /// Exactly one pack (count is 1).
  ///
  /// In en, this message translates to:
  /// **'{count} pack'**
  String posPackOne(String count);

  /// Several packs, e.g. 24 packs.
  ///
  /// In en, this message translates to:
  /// **'{count} packs'**
  String posPackMany(String count);

  /// Pack size whose stock is not counted.
  ///
  /// In en, this message translates to:
  /// **'Stock not tracked'**
  String get posStockNotTracked;

  /// Product without a barcode (cashier product list).
  ///
  /// In en, this message translates to:
  /// **'No barcode'**
  String get posNoBarcode;

  /// Low stock warning (cashier product list).
  ///
  /// In en, this message translates to:
  /// **'Low stock'**
  String get posLowStock;

  /// Price and stock in the cashier product list.
  ///
  /// In en, this message translates to:
  /// **'{price} • Stock {stock}'**
  String posPriceAndStock(String price, String stock);

  /// Banner after an interrupted checkout. amount is a formatted price such as Rs 350.00 (kept left to right).
  ///
  /// In en, this message translates to:
  /// **'Last sale saved on this device: {amount} at {time}'**
  String posLastSaleSaved(String amount, String time);

  /// Opens the last saved sale's receipt.
  ///
  /// In en, this message translates to:
  /// **'View / Reprint'**
  String get posViewReprint;

  /// Hides a banner.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get posDismiss;

  /// The receipt of a saved sale could not be read.
  ///
  /// In en, this message translates to:
  /// **'The receipt could not be opened. Find it in Bills.'**
  String get posReceiptUnavailable;

  /// Leaves the POS when it could not open.
  ///
  /// In en, this message translates to:
  /// **'Log out'**
  String get posLogOut;

  /// The on-device POS database could not be opened.
  ///
  /// In en, this message translates to:
  /// **'The local POS could not be opened. Check this device’s local storage and try again.'**
  String get posOpenFailed;

  /// Heading of the bill panel.
  ///
  /// In en, this message translates to:
  /// **'Current Bill'**
  String get posCurrentBill;

  /// Narrow screens: opens the bill sheet when it is empty.
  ///
  /// In en, this message translates to:
  /// **'Open Current Bill'**
  String get posOpenCurrentBill;

  /// Narrow screens: opens the bill sheet; count is the number of lines. amount is a formatted price such as Rs 350.00 (kept left to right).
  ///
  /// In en, this message translates to:
  /// **'Current Bill • {count} • {amount}'**
  String posCurrentBillSummary(String count, String amount);

  /// Number of lines in the bill.
  ///
  /// In en, this message translates to:
  /// **'{count} items'**
  String posItemCount(String count);

  /// Empty bill panel.
  ///
  /// In en, this message translates to:
  /// **'Tap a product to begin a sale.'**
  String get posEmptyBill;

  /// Bill subtotal label.
  ///
  /// In en, this message translates to:
  /// **'Subtotal'**
  String get posSubtotal;

  /// Bill discount label.
  ///
  /// In en, this message translates to:
  /// **'Discount'**
  String get posDiscount;

  /// Bill total label.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get posTotal;

  /// Main checkout button. amount is a formatted price such as Rs 350.00 (kept left to right).
  ///
  /// In en, this message translates to:
  /// **'Pay {amount}'**
  String posPay(String amount);

  /// Checkout button while the sale is being saved.
  ///
  /// In en, this message translates to:
  /// **'Completing…'**
  String get posCompleting;

  /// Puts the bill aside (not available yet).
  ///
  /// In en, this message translates to:
  /// **'Hold Bill'**
  String get posHoldBill;

  /// Payment dialog title. amount is a formatted price such as Rs 350.00 (kept left to right).
  ///
  /// In en, this message translates to:
  /// **'Payment • {amount}'**
  String payTitle(String amount);

  /// Cash the customer handed over.
  ///
  /// In en, this message translates to:
  /// **'Cash received'**
  String get payCashReceived;

  /// Explains that digital payments are only recorded.
  ///
  /// In en, this message translates to:
  /// **'Digital payment will be recorded without a gateway.'**
  String get payDigitalNote;

  /// Split payment: cash part.
  ///
  /// In en, this message translates to:
  /// **'Cash amount'**
  String get payCashAmount;

  /// Split payment: digital part.
  ///
  /// In en, this message translates to:
  /// **'Digital amount'**
  String get payDigitalAmount;

  /// Split payment: Udhaar part.
  ///
  /// In en, this message translates to:
  /// **'Udhaar amount'**
  String get payUdhaarAmount;

  /// Cash to give back to the customer. amount is a formatted price such as Rs 350.00 (kept left to right).
  ///
  /// In en, this message translates to:
  /// **'Change: {amount}'**
  String payChange(String amount);

  /// Confirms the payment and saves the sale.
  ///
  /// In en, this message translates to:
  /// **'Complete Sale'**
  String get payComplete;

  /// Customer who takes the sale on Udhaar.
  ///
  /// In en, this message translates to:
  /// **'Udhaar customer'**
  String get payUdhaarCustomer;

  /// Customer's Udhaar before this sale. amount is a formatted price such as Rs 350.00 (kept left to right).
  ///
  /// In en, this message translates to:
  /// **'Existing balance: {amount}'**
  String payExistingBalance(String amount);

  /// Udhaar added by this sale. amount is a formatted price such as Rs 350.00 (kept left to right).
  ///
  /// In en, this message translates to:
  /// **'This sale on Udhaar: {amount}'**
  String payThisSaleUdhaar(String amount);

  /// Customer's Udhaar after this sale. amount is a formatted price such as Rs 350.00 (kept left to right).
  ///
  /// In en, this message translates to:
  /// **'New balance: {amount}'**
  String payNewBalance(String amount);

  /// Customer's Udhaar limit. amount is a formatted price such as Rs 350.00 (kept left to right).
  ///
  /// In en, this message translates to:
  /// **'Credit limit: {amount}'**
  String payCreditLimit(String amount);

  /// Udhaar sale would pass the customer's limit.
  ///
  /// In en, this message translates to:
  /// **'Credit limit exceeded. Ask the owner to increase the limit.'**
  String get payCreditLimitExceeded;

  /// Title after a successful checkout.
  ///
  /// In en, this message translates to:
  /// **'Sale completed'**
  String get saleCompleted;

  /// Saved sale whose receipt could not be shown right away.
  ///
  /// In en, this message translates to:
  /// **'The sale is saved. Open its receipt from Bills.'**
  String get saleSavedOpenFromBills;

  /// Sale saved locally and online.
  ///
  /// In en, this message translates to:
  /// **'Saved on this tablet • Synced'**
  String get saleSavedSynced;

  /// Sale saved locally, upload pending (also offline).
  ///
  /// In en, this message translates to:
  /// **'Saved on this tablet • Waiting to sync'**
  String get saleSavedWaiting;

  /// Opens Bills to see the receipt.
  ///
  /// In en, this message translates to:
  /// **'View receipt'**
  String get saleViewReceipt;

  /// Closes the result and starts a new sale.
  ///
  /// In en, this message translates to:
  /// **'New sale'**
  String get saleNew;

  /// Retried checkout whose content changed.
  ///
  /// In en, this message translates to:
  /// **'This sale was already saved with different details. Nothing new was recorded.'**
  String get saleCheckoutConflict;

  /// Checkout failed before anything was saved.
  ///
  /// In en, this message translates to:
  /// **'Sale could not be completed. Nothing was charged.'**
  String get saleFailed;

  /// A rare checkout error without a translation; message is the technical English reason.
  ///
  /// In en, this message translates to:
  /// **'{message}'**
  String saleErrorOther(String message);

  /// Shown when checkout is refused: Cart must not be empty
  ///
  /// In en, this message translates to:
  /// **'Cart must not be empty'**
  String get saleErrCartEmpty;

  /// Shown when checkout is refused: Discount cannot be negative
  ///
  /// In en, this message translates to:
  /// **'Discount cannot be negative'**
  String get saleErrDiscountNegative;

  /// Shown when checkout is refused: Discount exceeds line value
  ///
  /// In en, this message translates to:
  /// **'Discount exceeds line value'**
  String get saleErrDiscountTooHigh;

  /// Shown when checkout is refused: Insufficient stock
  ///
  /// In en, this message translates to:
  /// **'Insufficient stock'**
  String get saleErrInsufficientStock;

  /// Shown when checkout is refused: Product requires a display name
  ///
  /// In en, this message translates to:
  /// **'Product requires a display name'**
  String get saleErrProductName;

  /// Shown when checkout is refused: Sale total cannot be negative
  ///
  /// In en, this message translates to:
  /// **'Sale total cannot be negative'**
  String get saleErrTotalNegative;

  /// Shown when checkout is refused: Shop does not exist
  ///
  /// In en, this message translates to:
  /// **'Shop does not exist'**
  String get saleErrShopMissing;

  /// Shown when checkout is refused: Cashier is not active for this shop
  ///
  /// In en, this message translates to:
  /// **'Cashier is not active for this shop'**
  String get saleErrCashierInactive;

  /// Shown when checkout is refused: Credit customer is not active for this shop
  ///
  /// In en, this message translates to:
  /// **'Credit customer is not active for this shop'**
  String get saleErrCreditCustomerInactive;

  /// Shown when checkout is refused: Credit payment requires a customer
  ///
  /// In en, this message translates to:
  /// **'Credit payment requires a customer'**
  String get saleErrCreditNeedsCustomer;

  /// Shown when checkout is refused: Customer credit limit exceeded
  ///
  /// In en, this message translates to:
  /// **'Customer credit limit exceeded'**
  String get saleErrCreditLimit;

  /// Shown when checkout is refused: Device is not active for this shop
  ///
  /// In en, this message translates to:
  /// **'Device is not active for this shop'**
  String get saleErrDeviceInactive;

  /// Shown when checkout is refused: Measured product requires kg or liter
  ///
  /// In en, this message translates to:
  /// **'Measured product requires kg or liter'**
  String get saleErrMeasuredUnit;

  /// Shown when checkout is refused: Payment amounts must be greater than zero
  ///
  /// In en, this message translates to:
  /// **'Payment amounts must be greater than zero'**
  String get saleErrPaymentPositive;

  /// Shown when checkout is refused: Payment total must equal sale total
  ///
  /// In en, this message translates to:
  /// **'Payment total must equal sale total'**
  String get saleErrPaymentTotal;

  /// Shown when checkout is refused: Piece products are sold in whole units
  ///
  /// In en, this message translates to:
  /// **'Piece products are sold in whole units'**
  String get saleErrWholeUnits;

  /// Shown when checkout is refused: Product is not active for this shop
  ///
  /// In en, this message translates to:
  /// **'Product is not active for this shop'**
  String get saleErrProductInactive;

  /// Shown when checkout is refused: Product prices cannot be negative
  ///
  /// In en, this message translates to:
  /// **'Product prices cannot be negative'**
  String get saleErrPriceNegative;

  /// Shown when checkout is refused: Quantities must be greater than zero
  ///
  /// In en, this message translates to:
  /// **'Quantities must be greater than zero'**
  String get saleErrQuantityPositive;

  /// Shown when checkout is refused: Enter a valid payment.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid payment.'**
  String get payErrInvalid;

  /// Shown when checkout is refused: Payment total must equal the sale total.
  ///
  /// In en, this message translates to:
  /// **'Payment total must equal the sale total.'**
  String get payErrTotal;

  /// Shown when checkout is refused: Select a customer for Udhaar.
  ///
  /// In en, this message translates to:
  /// **'Select a customer for Udhaar.'**
  String get payErrUdhaarCustomer;

  /// Shown when checkout is refused: Cash received is less than the total.
  ///
  /// In en, this message translates to:
  /// **'Cash received is less than the total.'**
  String get payErrCashShort;

  /// Shown when checkout is refused: Enter a valid quantity.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid quantity.'**
  String get measureErrInvalid;

  /// Shown when checkout is refused: Quantity must be more than zero.
  ///
  /// In en, this message translates to:
  /// **'Quantity must be more than zero.'**
  String get measureErrZero;

  /// Shown when checkout is refused: Quantity is too large.
  ///
  /// In en, this message translates to:
  /// **'Quantity is too large.'**
  String get measureErrTooLarge;

  /// Stock left of a loose product, e.g. Available 40 kg.
  ///
  /// In en, this message translates to:
  /// **'Available {quantity}'**
  String measureAvailable(String quantity);

  /// Quantity of this product already in the bill.
  ///
  /// In en, this message translates to:
  /// **'In bill: {quantity}'**
  String measureInBill(String quantity);

  /// Heading for typing an exact weight or volume.
  ///
  /// In en, this message translates to:
  /// **'Custom quantity'**
  String get measureCustomQuantity;

  /// Label of the typed quantity field.
  ///
  /// In en, this message translates to:
  /// **'Quantity'**
  String get measureQuantityLabel;

  /// Live total before a valid quantity is typed.
  ///
  /// In en, this message translates to:
  /// **'Total —'**
  String get measureTotalNone;

  /// Live total for the typed quantity. amount is a formatted price such as Rs 350.00 (kept left to right).
  ///
  /// In en, this message translates to:
  /// **'Total {amount} for {quantity}'**
  String measureTotalFor(String amount, String quantity);

  /// Warning: more than the stock (negative stock allowed).
  ///
  /// In en, this message translates to:
  /// **'Only {available} in stock.'**
  String measureOnlyInStock(String available);

  /// Refusal: more than the stock (negative stock not allowed).
  ///
  /// In en, this message translates to:
  /// **'Only {available} available.'**
  String measureOnlyAvailable(String available);

  /// Receipt dialog title.
  ///
  /// In en, this message translates to:
  /// **'Receipt'**
  String get receiptTitle;

  /// Prints the receipt again.
  ///
  /// In en, this message translates to:
  /// **'Print / Reprint'**
  String get receiptPrint;

  /// Print tapped while no printer is set up.
  ///
  /// In en, this message translates to:
  /// **'No receipt printer is configured. You can retry from Sales.'**
  String get receiptPrinterMissing;

  /// Date and cashier name on the receipt.
  ///
  /// In en, this message translates to:
  /// **'{dateTime} • {cashier}'**
  String receiptDateCashier(String dateTime, String cashier);

  /// Customer name on the receipt (as entered).
  ///
  /// In en, this message translates to:
  /// **'Customer: {name}'**
  String receiptCustomer(String name);

  /// One receipt line: quantity, product name as entered, line total.
  ///
  /// In en, this message translates to:
  /// **'{quantity} × {name}  {amount}'**
  String receiptLine(String quantity, String name, String amount);

  /// Unit price under a receipt line.
  ///
  /// In en, this message translates to:
  /// **'@ {price}'**
  String receiptAtPrice(String price);

  /// Price of one piece.
  ///
  /// In en, this message translates to:
  /// **'{price} each'**
  String receiptEach(String price);

  /// Receipt subtotal. amount is a formatted price such as Rs 350.00 (kept left to right).
  ///
  /// In en, this message translates to:
  /// **'Subtotal {amount}'**
  String receiptSubtotal(String amount);

  /// Receipt discount; amount already carries the minus sign.
  ///
  /// In en, this message translates to:
  /// **'Discount {amount}'**
  String receiptDiscount(String amount);

  /// Receipt total. amount is a formatted price such as Rs 350.00 (kept left to right).
  ///
  /// In en, this message translates to:
  /// **'Total {amount}'**
  String receiptTotal(String amount);

  /// Amount returned from this bill. amount is a formatted price such as Rs 350.00 (kept left to right).
  ///
  /// In en, this message translates to:
  /// **'Returned {amount}'**
  String receiptReturned(String amount);

  /// Total minus returns. amount is a formatted price such as Rs 350.00 (kept left to right).
  ///
  /// In en, this message translates to:
  /// **'Net {amount}'**
  String receiptNet(String amount);

  /// One payment on the receipt, e.g. Cash: Rs 500.00.
  ///
  /// In en, this message translates to:
  /// **'{method}: {amount}'**
  String receiptPayment(String method, String amount);

  /// Cash received. amount is a formatted price such as Rs 350.00 (kept left to right).
  ///
  /// In en, this message translates to:
  /// **'Received {amount}'**
  String receiptReceived(String amount);

  /// Cash given back. amount is a formatted price such as Rs 350.00 (kept left to right).
  ///
  /// In en, this message translates to:
  /// **'Change {amount}'**
  String receiptChange(String amount);

  /// Built-in product category (seeded, fixed id). English must equal the seeded name.
  ///
  /// In en, this message translates to:
  /// **'Household'**
  String get categoryHousehold;

  /// Built-in product category (seeded, fixed id). English must equal the seeded name.
  ///
  /// In en, this message translates to:
  /// **'Staples'**
  String get categoryStaples;

  /// Built-in product category (seeded, fixed id). English must equal the seeded name.
  ///
  /// In en, this message translates to:
  /// **'Dairy'**
  String get categoryDairy;

  /// Built-in product category (seeded, fixed id). English must equal the seeded name.
  ///
  /// In en, this message translates to:
  /// **'Cooking Essentials'**
  String get categoryCookingEssentials;

  /// Built-in product category (seeded, fixed id). English must equal the seeded name.
  ///
  /// In en, this message translates to:
  /// **'Beverages'**
  String get categoryBeverages;

  /// Built-in product category (seeded, fixed id). English must equal the seeded name.
  ///
  /// In en, this message translates to:
  /// **'Snacks'**
  String get categorySnacks;

  /// Web preview title; shopName as entered.
  ///
  /// In en, this message translates to:
  /// **'{shopName} • POS preview'**
  String posPreviewTitle(String shopName);

  /// Web preview.
  ///
  /// In en, this message translates to:
  /// **'Cashier authentication successful'**
  String get posPreviewAuthenticated;

  /// Web preview; cashierName as entered.
  ///
  /// In en, this message translates to:
  /// **'{cashierName} is signed in.'**
  String posPreviewSignedIn(String cashierName);

  /// Web preview explanation.
  ///
  /// In en, this message translates to:
  /// **'The offline POS database is available on Android and Windows. Chrome remains an auth and onboarding preview target.'**
  String get posPreviewNote;

  /// Web preview button.
  ///
  /// In en, this message translates to:
  /// **'End preview session'**
  String get posPreviewEnd;

  /// Shown while more items load.
  ///
  /// In en, this message translates to:
  /// **'Loading…'**
  String get commonLoading;

  /// Retries loading a screen.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get commonTryAgain;

  /// Hint for a field that may stay empty.
  ///
  /// In en, this message translates to:
  /// **'Optional'**
  String get commonOptional;

  /// Save button while saving.
  ///
  /// In en, this message translates to:
  /// **'Saving…'**
  String get commonSaving;

  /// Edit button tooltip.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get commonEdit;

  /// Search button.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get commonSearch;

  /// Search button while searching.
  ///
  /// In en, this message translates to:
  /// **'Searching…'**
  String get commonSearching;

  /// Reloads data.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get commonRefresh;

  /// A stored product unit (piece, pack, kg, gram, liter, bottle, carton, dozen, bag). key is the stored value (never translated); english is how this screen already shows it in English. Urdu translates known units; unknown units stay as they are.
  ///
  /// In en, this message translates to:
  /// **'{key, select, other{{english}}}'**
  String unitName(String key, String english);

  /// Owner product management screen title.
  ///
  /// In en, this message translates to:
  /// **'Products'**
  String get productsTitle;

  /// Tab: products already in the shop.
  ///
  /// In en, this message translates to:
  /// **'My Products'**
  String get productsTabMine;

  /// Tab: add from the catalogue or create a custom product.
  ///
  /// In en, this message translates to:
  /// **'Add Product'**
  String get productsTabAdd;

  /// Product data could not be opened.
  ///
  /// In en, this message translates to:
  /// **'Could not open products. Please try again.'**
  String get productsOpenFailed;

  /// A product was added or changed.
  ///
  /// In en, this message translates to:
  /// **'Product saved to My Products.'**
  String get productsSaved;

  /// Search field on My Products.
  ///
  /// In en, this message translates to:
  /// **'Search name or barcode'**
  String get productsSearchLabel;

  /// Category filter label.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get productsCategoryLabel;

  /// Category filter option for no filter.
  ///
  /// In en, this message translates to:
  /// **'All categories'**
  String get productsAllCategories;

  /// Product without a category.
  ///
  /// In en, this message translates to:
  /// **'Uncategorized'**
  String get productsUncategorized;

  /// Empty product or stock list.
  ///
  /// In en, this message translates to:
  /// **'No products match this filter.'**
  String get productsNoMatch;

  /// Loads the next page of products.
  ///
  /// In en, this message translates to:
  /// **'Load more'**
  String get productsLoadMore;

  /// Product saved but its local photo could not be changed.
  ///
  /// In en, this message translates to:
  /// **'Product saved. The image could not be updated on this tablet.'**
  String get productsImageNotUpdated;

  /// Product created but its local photo could not be stored.
  ///
  /// In en, this message translates to:
  /// **'Product created. The image could not be saved on this tablet.'**
  String get productsImageNotSaved;

  /// Prices on a product card; each already formatted (e.g. Rs 130.00/kg).
  ///
  /// In en, this message translates to:
  /// **'Sale {sale} • Purchase {purchase}'**
  String productsSaleAndPurchase(String sale, String purchase);

  /// A product hidden from sale.
  ///
  /// In en, this message translates to:
  /// **'Inactive'**
  String get productsInactive;

  /// Heading of the catalogue search.
  ///
  /// In en, this message translates to:
  /// **'Search Master Catalog'**
  String get productsSearchMasterCatalog;

  /// Catalogue search field.
  ///
  /// In en, this message translates to:
  /// **'Product name, brand, or barcode'**
  String get productsCatalogQueryLabel;

  /// Online catalogue search failed.
  ///
  /// In en, this message translates to:
  /// **'Catalog search failed. Check internet and try again.'**
  String get productsCatalogSearchFailed;

  /// Catalogue result already in the shop.
  ///
  /// In en, this message translates to:
  /// **'Open / edit'**
  String get productsOpenEdit;

  /// Button and dialog title for a product that is not in the catalogue.
  ///
  /// In en, this message translates to:
  /// **'Create Custom Product'**
  String get productsCreateCustom;

  /// Adds a catalogue product with its prices and stock.
  ///
  /// In en, this message translates to:
  /// **'Add to My Shop'**
  String get productsAddToShop;

  /// Low-stock level when adding from the catalogue.
  ///
  /// In en, this message translates to:
  /// **'Low-stock threshold'**
  String get productsLowStockThreshold;

  /// Cost price field.
  ///
  /// In en, this message translates to:
  /// **'Purchase price'**
  String get fieldPurchasePrice;

  /// Cost price of a loose product per kg or L.
  ///
  /// In en, this message translates to:
  /// **'Purchase price per {unit}'**
  String fieldPurchasePricePer(String unit);

  /// Selling price field.
  ///
  /// In en, this message translates to:
  /// **'Sale price'**
  String get fieldSalePrice;

  /// Selling price of a loose product per kg or L.
  ///
  /// In en, this message translates to:
  /// **'Sale price per {unit}'**
  String fieldSalePricePer(String unit);

  /// Stock when the product is created; also a stock movement name.
  ///
  /// In en, this message translates to:
  /// **'Opening stock'**
  String get fieldOpeningStock;

  /// Opening stock of a loose product in kg or L.
  ///
  /// In en, this message translates to:
  /// **'Opening stock ({unit})'**
  String fieldOpeningStockIn(String unit);

  /// Stock level that shows a low-stock warning.
  ///
  /// In en, this message translates to:
  /// **'Low-stock alert at'**
  String get fieldLowStockAlert;

  /// Low-stock level of a loose product in kg or L.
  ///
  /// In en, this message translates to:
  /// **'Low-stock alert at ({unit})'**
  String fieldLowStockAlertIn(String unit);

  /// Barcode field.
  ///
  /// In en, this message translates to:
  /// **'Barcode'**
  String get fieldBarcode;

  /// Size label of one pack, e.g. 250 g.
  ///
  /// In en, this message translates to:
  /// **'Pack size'**
  String get fieldPackSize;

  /// Cost of one pack size.
  ///
  /// In en, this message translates to:
  /// **'Purchase cost'**
  String get fieldPurchaseCost;

  /// Subtitle of Create Custom Product.
  ///
  /// In en, this message translates to:
  /// **'For items that are not in the master catalog.'**
  String get customSubtitle;

  /// Creates the product.
  ///
  /// In en, this message translates to:
  /// **'Create Product'**
  String get customCreate;

  /// Create button while saving.
  ///
  /// In en, this message translates to:
  /// **'Creating…'**
  String get customCreating;

  /// Form section heading.
  ///
  /// In en, this message translates to:
  /// **'Product details'**
  String get customProductDetails;

  /// Selling type: sold by count.
  ///
  /// In en, this message translates to:
  /// **'Single Piece'**
  String get sellingPiece;

  /// Selling type: sold by weight or volume.
  ///
  /// In en, this message translates to:
  /// **'Loose / Measured'**
  String get sellingLoose;

  /// Selling type: one product family with several pack sizes.
  ///
  /// In en, this message translates to:
  /// **'Packaged Variants'**
  String get sellingPackaged;

  /// Name of a pack family, required.
  ///
  /// In en, this message translates to:
  /// **'Product family name *'**
  String get customFamilyName;

  /// Product name, required.
  ///
  /// In en, this message translates to:
  /// **'Product name *'**
  String get customProductName;

  /// Example family name (brand stays as written).
  ///
  /// In en, this message translates to:
  /// **'e.g. Tapal Danedar'**
  String get customFamilyHint;

  /// Form section heading for pack sizes.
  ///
  /// In en, this message translates to:
  /// **'Pack sizes'**
  String get customPackSizes;

  /// Category, required.
  ///
  /// In en, this message translates to:
  /// **'Category *'**
  String get customCategoryRequired;

  /// Unit of a piece product, required.
  ///
  /// In en, this message translates to:
  /// **'Unit *'**
  String get customUnitRequired;

  /// Loose product sold by weight.
  ///
  /// In en, this message translates to:
  /// **'Weight (kg)'**
  String get measureWeightKg;

  /// Loose product sold by volume.
  ///
  /// In en, this message translates to:
  /// **'Volume (L)'**
  String get measureVolumeL;

  /// Optional size label of a piece product.
  ///
  /// In en, this message translates to:
  /// **'Pack size / label'**
  String get customPackLabel;

  /// Example pack label.
  ///
  /// In en, this message translates to:
  /// **'e.g. 500 g'**
  String get customPackLabelHint;

  /// Form section heading.
  ///
  /// In en, this message translates to:
  /// **'Pricing & stock'**
  String get customPricingStock;

  /// Preset weights or volumes the cashier taps.
  ///
  /// In en, this message translates to:
  /// **'Quick quantities'**
  String get customQuickQuantities;

  /// Lets the cashier type any quantity.
  ///
  /// In en, this message translates to:
  /// **'Allow custom quantity'**
  String get customAllowCustom;

  /// Explains Allow custom quantity.
  ///
  /// In en, this message translates to:
  /// **'Cashier may type any amount, not only quick quantities.'**
  String get customAllowCustomHint;

  /// Heading of the photo card.
  ///
  /// In en, this message translates to:
  /// **'Product image'**
  String get imageSection;

  /// Empty photo card.
  ///
  /// In en, this message translates to:
  /// **'Choose product image'**
  String get imageChoose;

  /// Choose a different photo.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get imageChange;

  /// Accessibility label of the photo card.
  ///
  /// In en, this message translates to:
  /// **'Change product image'**
  String get imageChangeSemantics;

  /// Accessibility label of the chosen photo.
  ///
  /// In en, this message translates to:
  /// **'Product image preview'**
  String get imagePreviewSemantics;

  /// Allowed photo formats.
  ///
  /// In en, this message translates to:
  /// **'Optional · JPG, PNG or WebP'**
  String get imageFormats;

  /// Edit dialog title; the product name follows as subtitle.
  ///
  /// In en, this message translates to:
  /// **'Edit product'**
  String get editTitle;

  /// Fixed selling mode of a loose product.
  ///
  /// In en, this message translates to:
  /// **'Loose product · sold by weight (kg)'**
  String get editLooseWeight;

  /// Fixed selling mode of a loose product.
  ///
  /// In en, this message translates to:
  /// **'Loose product · sold by volume (L)'**
  String get editLooseVolume;

  /// Form section heading.
  ///
  /// In en, this message translates to:
  /// **'Availability'**
  String get editAvailability;

  /// Product is available for sale.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get editActive;

  /// Explains the Active switch.
  ///
  /// In en, this message translates to:
  /// **'Inactive products are hidden from sale.'**
  String get editActiveHint;

  /// Duplicate warning title.
  ///
  /// In en, this message translates to:
  /// **'This product may already exist'**
  String get dupTitle;

  /// Before the list of similar products.
  ///
  /// In en, this message translates to:
  /// **'Your shop already has:'**
  String get dupAlreadyHas;

  /// After a product that has the same barcode.
  ///
  /// In en, this message translates to:
  /// **'(same barcode)'**
  String get dupSameBarcode;

  /// More similar products not listed.
  ///
  /// In en, this message translates to:
  /// **'and {count} more'**
  String dupMore(String count);

  /// Explains the duplicate warning.
  ///
  /// In en, this message translates to:
  /// **'Creating it again makes a separate product with its own stock. Go back to edit, or create it anyway.'**
  String get dupExplain;

  /// Returns to the form.
  ///
  /// In en, this message translates to:
  /// **'Go back'**
  String get dupGoBack;

  /// Creates the product despite the warning.
  ///
  /// In en, this message translates to:
  /// **'Create anyway'**
  String get dupCreateAnyway;

  /// Heading of one pack size card.
  ///
  /// In en, this message translates to:
  /// **'Pack size {number}'**
  String packRowTitle(String number);

  /// This pack size already exists on the server.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get packRowSaved;

  /// Removes a pack size card.
  ///
  /// In en, this message translates to:
  /// **'Remove pack size'**
  String get packRemove;

  /// Example pack size.
  ///
  /// In en, this message translates to:
  /// **'e.g. 250 g'**
  String get packSizeHint;

  /// Opening stock in whole packs.
  ///
  /// In en, this message translates to:
  /// **'Opening stock (packs)'**
  String get packOpeningStock;

  /// Low-stock level in whole packs.
  ///
  /// In en, this message translates to:
  /// **'Low-stock alert (packs)'**
  String get packLowStock;

  /// Adds another pack size.
  ///
  /// In en, this message translates to:
  /// **'Add pack size'**
  String get packAdd;

  /// No more quick quantities can be added.
  ///
  /// In en, this message translates to:
  /// **'Quick quantities full ({max})'**
  String presetFull(String max);

  /// Field to add a quick quantity.
  ///
  /// In en, this message translates to:
  /// **'Add quick quantity'**
  String get presetAdd;

  /// Inventory screen failed to load.
  ///
  /// In en, this message translates to:
  /// **'Inventory could not be loaded.'**
  String get inventoryLoadFailed;

  /// Tab: stock per product.
  ///
  /// In en, this message translates to:
  /// **'Current Stock'**
  String get inventoryTabCurrent;

  /// Tab: stock movements.
  ///
  /// In en, this message translates to:
  /// **'Movement History'**
  String get inventoryTabHistory;

  /// Inventory search field.
  ///
  /// In en, this message translates to:
  /// **'Search product or barcode'**
  String get inventorySearchLabel;

  /// Filter: low stock.
  ///
  /// In en, this message translates to:
  /// **'Low'**
  String get inventoryFilterLow;

  /// Filter: out of stock.
  ///
  /// In en, this message translates to:
  /// **'Out'**
  String get inventoryFilterOut;

  /// Empty movement history.
  ///
  /// In en, this message translates to:
  /// **'No stock movements yet.'**
  String get inventoryNoMovements;

  /// Adjustment saved on the device.
  ///
  /// In en, this message translates to:
  /// **'Stock adjustment saved locally.'**
  String get inventoryAdjustSaved;

  /// Adjustment was not saved.
  ///
  /// In en, this message translates to:
  /// **'Stock adjustment could not be saved. Check the quantity and try again.'**
  String get inventoryAdjustFailed;

  /// Adjustment dialog title; name as entered.
  ///
  /// In en, this message translates to:
  /// **'Adjust {name}'**
  String inventoryAdjustTitle(String name);

  /// Kind of adjustment.
  ///
  /// In en, this message translates to:
  /// **'Reason'**
  String get inventoryReason;

  /// Adjustment that may add or remove stock.
  ///
  /// In en, this message translates to:
  /// **'Manual correction (+ / -)'**
  String get inventoryManualCorrection;

  /// Quantity that may be negative.
  ///
  /// In en, this message translates to:
  /// **'Quantity (+ / -)'**
  String get inventoryQuantitySigned;

  /// Required explanation of an adjustment.
  ///
  /// In en, this message translates to:
  /// **'Reason / note *'**
  String get inventoryReasonNote;

  /// Saves the adjustment.
  ///
  /// In en, this message translates to:
  /// **'Save Adjustment'**
  String get inventorySaveAdjustment;

  /// Status pill.
  ///
  /// In en, this message translates to:
  /// **'Out of stock'**
  String get inventoryOutOfStock;

  /// Under the stock number.
  ///
  /// In en, this message translates to:
  /// **'in stock'**
  String get inventoryInStock;

  /// Opens the adjustment dialog.
  ///
  /// In en, this message translates to:
  /// **'Adjust'**
  String get inventoryAdjust;

  /// Stock movement: opening stock.
  ///
  /// In en, this message translates to:
  /// **'Opening stock'**
  String get movementOpening;

  /// Stock movement: purchase.
  ///
  /// In en, this message translates to:
  /// **'Purchase'**
  String get movementPurchase;

  /// Stock movement: sale.
  ///
  /// In en, this message translates to:
  /// **'Sale'**
  String get movementSale;

  /// Stock movement: a voided sale returned its stock.
  ///
  /// In en, this message translates to:
  /// **'Void'**
  String get movementVoid;

  /// Stock movement: returned items.
  ///
  /// In en, this message translates to:
  /// **'Return'**
  String get movementReturn;

  /// Stock movement and adjustment reason: damaged or wasted.
  ///
  /// In en, this message translates to:
  /// **'Damaged / wastage'**
  String get movementDamage;

  /// Stock movement: manual adjustment.
  ///
  /// In en, this message translates to:
  /// **'Adjustment'**
  String get movementAdjustment;

  /// Stock movement: correction.
  ///
  /// In en, this message translates to:
  /// **'Stock correction'**
  String get movementCorrection;

  /// Web preview placeholder.
  ///
  /// In en, this message translates to:
  /// **'Inventory management is available on Windows and Android.'**
  String get inventoryWebOnly;

  /// Web preview placeholder.
  ///
  /// In en, this message translates to:
  /// **'Product management uses the native Drift catalog. Open Dukaan Pro on Windows or Android.'**
  String get productsWebOnly;

  /// Shown when a product or stock form is refused: This product is already in your shop
  ///
  /// In en, this message translates to:
  /// **'This product is already in your shop'**
  String get prodErrAlreadyInShop;

  /// Shown when a product or stock form is refused: Product name is required
  ///
  /// In en, this message translates to:
  /// **'Product name is required'**
  String get prodErrNameRequired;

  /// Shown when a product or stock form is refused: Category is required
  ///
  /// In en, this message translates to:
  /// **'Category is required'**
  String get prodErrCategoryRequired;

  /// Shown when a product or stock form is refused: Product family name is required
  ///
  /// In en, this message translates to:
  /// **'Product family name is required'**
  String get prodErrFamilyNameRequired;

  /// Shown when a product or stock form is refused: Add at least one pack size
  ///
  /// In en, this message translates to:
  /// **'Add at least one pack size'**
  String get prodErrNoPackSize;

  /// Shown when a product or stock form is refused: Every pack needs a size label
  ///
  /// In en, this message translates to:
  /// **'Every pack needs a size label'**
  String get prodErrPackLabel;

  /// Shown when a product or stock form is refused: Pack size {label} is listed twice
  ///
  /// In en, this message translates to:
  /// **'Pack size {label} is listed twice'**
  String prodErrPackTwice(String label);

  /// Shown when a product or stock form is refused: Barcode {barcode} is already used in this shop
  ///
  /// In en, this message translates to:
  /// **'Barcode {barcode} is already used in this shop'**
  String prodErrBarcodeUsed(String barcode);

  /// Shown when a product or stock form is refused: Enter a sale price for {label}
  ///
  /// In en, this message translates to:
  /// **'Enter a sale price for {label}'**
  String prodErrPackSalePrice(String label);

  /// Shown when a product or stock form is refused: Prices cannot be negative
  ///
  /// In en, this message translates to:
  /// **'Prices cannot be negative'**
  String get prodErrPricesNegative;

  /// Shown when a product or stock form is refused: Stock for {label} must be whole packs
  ///
  /// In en, this message translates to:
  /// **'Stock for {label} must be whole packs'**
  String prodErrWholePacks(String label);

  /// Shown when a product or stock form is refused: Loose products are sold by weight (kg) or volume (L)
  ///
  /// In en, this message translates to:
  /// **'Loose products are sold by weight (kg) or volume (L)'**
  String get prodErrLooseUnit;

  /// Shown when a product or stock form is refused: Use at most {max} quick quantities
  ///
  /// In en, this message translates to:
  /// **'Use at most {max} quick quantities'**
  String prodErrPresetCount(String max);

  /// Shown when a product or stock form is refused: Use at most {max} quick quantities.
  ///
  /// In en, this message translates to:
  /// **'Use at most {max} quick quantities.'**
  String prodErrPresetCountDot(String max);

  /// Shown when a product or stock form is refused: Quick quantities are not valid
  ///
  /// In en, this message translates to:
  /// **'Quick quantities are not valid'**
  String get prodErrPresetsInvalid;

  /// Shown when a product or stock form is refused: Stock values cannot be negative
  ///
  /// In en, this message translates to:
  /// **'Stock values cannot be negative'**
  String get prodErrStockNegative;

  /// Shown when a product or stock form is refused: Enter valid non-negative values.
  ///
  /// In en, this message translates to:
  /// **'Enter valid non-negative values.'**
  String get prodErrValues;

  /// Shown when a product or stock form is refused: Complete all required fields with valid values.
  ///
  /// In en, this message translates to:
  /// **'Complete all required fields with valid values.'**
  String get prodErrRequiredFields;

  /// Shown when a product or stock form is refused: Pack {label}: enter a sale price and whole-pack stock.
  ///
  /// In en, this message translates to:
  /// **'Pack {label}: enter a sale price and whole-pack stock.'**
  String prodErrPackRow(String label);

  /// Shown when a product or stock form is refused: Pack {label} was not created: {reason}. {count} size(s) already saved; press Create again to finish without duplicating them.
  ///
  /// In en, this message translates to:
  /// **'Pack {label} was not created: {reason}. {count} size(s) already saved; press Create again to finish without duplicating them.'**
  String prodErrFamilyIncomplete(String label, String reason, String count);

  /// Shown when a product or stock form is refused: it could not be saved
  ///
  /// In en, this message translates to:
  /// **'it could not be saved'**
  String get prodErrNotSaved;

  /// Shown when a product or stock form is refused: Could not save the product. Please try again.
  ///
  /// In en, this message translates to:
  /// **'Could not save the product. Please try again.'**
  String get prodErrSaveFailed;

  /// Shown when a product or stock form is refused: Could not create the product. Please try again.
  ///
  /// In en, this message translates to:
  /// **'Could not create the product. Please try again.'**
  String get prodErrCreateFailed;

  /// Shown when a product or stock form is refused: Could not update product.
  ///
  /// In en, this message translates to:
  /// **'Could not update product.'**
  String get prodErrUpdateFailed;

  /// Shown when a product or stock form is refused: Could not open that image. Try another.
  ///
  /// In en, this message translates to:
  /// **'Could not open that image. Try another.'**
  String get prodErrImageOpen;

  /// Shown when a product or stock form is refused: The selected file is empty.
  ///
  /// In en, this message translates to:
  /// **'The selected file is empty.'**
  String get prodErrImageEmpty;

  /// Shown when a product or stock form is refused: The selected image is too large.
  ///
  /// In en, this message translates to:
  /// **'The selected image is too large.'**
  String get prodErrImageTooLarge;

  /// Shown when a product or stock form is refused: Choose a JPG, PNG or WebP product image.
  ///
  /// In en, this message translates to:
  /// **'Choose a JPG, PNG or WebP product image.'**
  String get prodErrImageFormat;

  /// Shown when a product or stock form is refused: That quick quantity is already in the list.
  ///
  /// In en, this message translates to:
  /// **'That quick quantity is already in the list.'**
  String get presetErrDuplicate;

  /// Shown when a product or stock form is refused: Keep at least one quick quantity.
  ///
  /// In en, this message translates to:
  /// **'Keep at least one quick quantity.'**
  String get presetErrKeepOne;

  /// Shown when a product or stock form is refused: Enter a valid quantity and reason.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid quantity and reason.'**
  String get inventoryErrInvalid;

  /// Bills list failed to load.
  ///
  /// In en, this message translates to:
  /// **'Sales could not be loaded. Please try again.'**
  String get billsLoadFailed;

  /// Empty bills list.
  ///
  /// In en, this message translates to:
  /// **'No sales match these filters.'**
  String get billsNoMatch;

  /// Bills search field.
  ///
  /// In en, this message translates to:
  /// **'Bill #, customer name or phone'**
  String get billsSearchLabel;

  /// Cashier filter label.
  ///
  /// In en, this message translates to:
  /// **'Cashier'**
  String get billsCashier;

  /// Cashier filter: no filter.
  ///
  /// In en, this message translates to:
  /// **'All cashiers'**
  String get billsAllCashiers;

  /// Period filter.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get billsToday;

  /// Period filter.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get billsYesterday;

  /// Period filter.
  ///
  /// In en, this message translates to:
  /// **'This Week'**
  String get billsThisWeek;

  /// Period filter before dates are chosen.
  ///
  /// In en, this message translates to:
  /// **'Custom dates'**
  String get billsCustomDates;

  /// Period filter after dates are chosen.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get billsCustom;

  /// Payment filter: no filter.
  ///
  /// In en, this message translates to:
  /// **'All payments'**
  String get billsAllPayments;

  /// Summary tile.
  ///
  /// In en, this message translates to:
  /// **'Today\'s sales'**
  String get billsTodaySales;

  /// Exactly one bill (count is 1).
  ///
  /// In en, this message translates to:
  /// **'{count} bill'**
  String billsCountOne(String count);

  /// Number of bills.
  ///
  /// In en, this message translates to:
  /// **'{count} bills'**
  String billsCountMany(String count);

  /// Bill status. key is the stored status without spaces (Completed, Voided, FullyReturned, PartiallyReturned); english is the stored status shown unchanged in English.
  ///
  /// In en, this message translates to:
  /// **'{key, select, other{{english}}}'**
  String saleStatus(String key, String english);

  /// Bill saved on the device, not uploaded yet.
  ///
  /// In en, this message translates to:
  /// **'Waiting to sync'**
  String get billWaitingToSync;

  /// Cashier of a bill (name as entered).
  ///
  /// In en, this message translates to:
  /// **'Cashier: {name}'**
  String billCashier(String name);

  /// Amount returned from a bill.
  ///
  /// In en, this message translates to:
  /// **'Returned'**
  String get billReturned;

  /// Total minus returns.
  ///
  /// In en, this message translates to:
  /// **'Net'**
  String get billNet;

  /// One payment of a bill; method is Cash, Digital, Udhaar…
  ///
  /// In en, this message translates to:
  /// **'Paid by {method}'**
  String billPaidBy(String method);

  /// One return of a bill; reason as entered. amount is already formatted (e.g. Rs 350.00) and kept left to right.
  ///
  /// In en, this message translates to:
  /// **'Return: {dateTime} • {reason} • {amount}'**
  String billReturnLine(String dateTime, String reason, String amount);

  /// Why a bill was voided (as entered).
  ///
  /// In en, this message translates to:
  /// **'Void reason: {reason}'**
  String billVoidReason(String reason);

  /// Opens the void dialog.
  ///
  /// In en, this message translates to:
  /// **'Void'**
  String get billVoid;

  /// Opens the return dialog; also its title.
  ///
  /// In en, this message translates to:
  /// **'Return items'**
  String get billReturnItems;

  /// Sales & Returns could not open.
  ///
  /// In en, this message translates to:
  /// **'Sales could not be opened.'**
  String get salesOpenFailed;

  /// A return was saved.
  ///
  /// In en, this message translates to:
  /// **'Return saved locally.'**
  String get returnSaved;

  /// A return was refused.
  ///
  /// In en, this message translates to:
  /// **'Return could not be saved. Check quantities and try again.'**
  String get returnFailed;

  /// Quantity to return of one bill line; name as on the bill, quantity sold.
  ///
  /// In en, this message translates to:
  /// **'{name} (sold {quantity})'**
  String returnLineLabel(String name, String quantity);

  /// How the refund is given.
  ///
  /// In en, this message translates to:
  /// **'Refund method'**
  String get returnRefundMethod;

  /// Refund taken off the customer's Udhaar.
  ///
  /// In en, this message translates to:
  /// **'Udhaar adjustment'**
  String get returnUdhaarAdjustment;

  /// Saves the return.
  ///
  /// In en, this message translates to:
  /// **'Save Return'**
  String get returnSave;

  /// Required reason field.
  ///
  /// In en, this message translates to:
  /// **'Reason *'**
  String get commonReasonRequired;

  /// Void dialog title.
  ///
  /// In en, this message translates to:
  /// **'Void sale'**
  String get voidTitle;

  /// Confirms the void.
  ///
  /// In en, this message translates to:
  /// **'Void Sale'**
  String get voidConfirm;

  /// A void was saved.
  ///
  /// In en, this message translates to:
  /// **'Sale void recorded locally.'**
  String get voidSaved;

  /// A void was refused.
  ///
  /// In en, this message translates to:
  /// **'Void is allowed only for an owner within 15 minutes and before any return.'**
  String get voidRefused;

  /// Web preview title.
  ///
  /// In en, this message translates to:
  /// **'Sales'**
  String get salesWebTitle;

  /// Web preview placeholder.
  ///
  /// In en, this message translates to:
  /// **'Sales management is available on Windows and Android.'**
  String get salesWebOnly;

  /// Khata search field.
  ///
  /// In en, this message translates to:
  /// **'Search customer name or phone'**
  String get khataSearchLabel;

  /// Khata failed to load; error is technical text.
  ///
  /// In en, this message translates to:
  /// **'Could not load Khata: {error}'**
  String khataLoadFailed(String error);

  /// Empty Khata search.
  ///
  /// In en, this message translates to:
  /// **'No customers found.'**
  String get khataNoCustomers;

  /// Customer without a phone number.
  ///
  /// In en, this message translates to:
  /// **'No phone'**
  String get khataNoPhone;

  /// Customer owes nothing.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get khataBalanceClear;

  /// Amount the customer owes. amount is already formatted (e.g. Rs 350.00) and kept left to right.
  ///
  /// In en, this message translates to:
  /// **'{amount} due'**
  String khataDue(String amount);

  /// Records Udhaar paid back; also the dialog title.
  ///
  /// In en, this message translates to:
  /// **'Receive Payment'**
  String get khataReceivePayment;

  /// Outstanding Udhaar.
  ///
  /// In en, this message translates to:
  /// **'Balance'**
  String get khataBalance;

  /// Customer Udhaar limit.
  ///
  /// In en, this message translates to:
  /// **'Credit limit'**
  String get khataCreditLimit;

  /// No credit limit.
  ///
  /// In en, this message translates to:
  /// **'Not set'**
  String get khataNotSet;

  /// Total sold on Udhaar.
  ///
  /// In en, this message translates to:
  /// **'Credit sales'**
  String get khataCreditSales;

  /// Total paid back.
  ///
  /// In en, this message translates to:
  /// **'Payments'**
  String get khataPayments;

  /// Ledger heading.
  ///
  /// In en, this message translates to:
  /// **'Statement'**
  String get khataStatement;

  /// Empty ledger.
  ///
  /// In en, this message translates to:
  /// **'No ledger entries yet.'**
  String get khataNoEntries;

  /// Balance after a ledger line. amount is already formatted (e.g. Rs 350.00) and kept left to right.
  ///
  /// In en, this message translates to:
  /// **'Balance {amount}'**
  String khataRunningBalance(String amount);

  /// Ledger line: a sale on Udhaar.
  ///
  /// In en, this message translates to:
  /// **'Sale'**
  String get ledgerSale;

  /// Ledger line: Udhaar paid back.
  ///
  /// In en, this message translates to:
  /// **'Payment'**
  String get ledgerPayment;

  /// Ledger line: starting balance.
  ///
  /// In en, this message translates to:
  /// **'Opening balance'**
  String get ledgerOpeningBalance;

  /// Ledger line: a return reduced the Udhaar.
  ///
  /// In en, this message translates to:
  /// **'Return adjustment'**
  String get ledgerReturnAdjustment;

  /// Ledger line: manual correction.
  ///
  /// In en, this message translates to:
  /// **'Manual adjustment'**
  String get ledgerManualAdjustment;

  /// A stored payment method shown as stored in English (e.g. cash); Urdu translates known methods.
  ///
  /// In en, this message translates to:
  /// **'{key, select, other{{english}}}'**
  String paymentStored(String key, String english);

  /// Udhaar payment saved.
  ///
  /// In en, this message translates to:
  /// **'Payment saved locally and queued for sync.'**
  String get khataPaymentSaved;

  /// Udhaar payment refused.
  ///
  /// In en, this message translates to:
  /// **'Payment could not be recorded. Nothing was changed.'**
  String get khataPaymentFailed;

  /// Payment amount field.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get khataAmount;

  /// Optional payment reference, e.g. a JazzCash ID.
  ///
  /// In en, this message translates to:
  /// **'Reference (optional)'**
  String get khataReferenceOptional;

  /// Optional note.
  ///
  /// In en, this message translates to:
  /// **'Note (optional)'**
  String get khataNoteOptional;

  /// Saves the payment.
  ///
  /// In en, this message translates to:
  /// **'Record Payment'**
  String get khataRecordPayment;

  /// Owner customers screen title.
  ///
  /// In en, this message translates to:
  /// **'Customers / Khata'**
  String get customersTitle;

  /// Adds a customer; also the form title.
  ///
  /// In en, this message translates to:
  /// **'Add customer'**
  String get customersAdd;

  /// Customer form title when editing.
  ///
  /// In en, this message translates to:
  /// **'Edit customer'**
  String get customersEdit;

  /// Customers failed to open; error is technical text.
  ///
  /// In en, this message translates to:
  /// **'Could not open customers: {error}'**
  String customersOpenFailed(String error);

  /// Customers search field.
  ///
  /// In en, this message translates to:
  /// **'Search name or phone'**
  String get customersSearchLabel;

  /// No customers.
  ///
  /// In en, this message translates to:
  /// **'No customers yet. Add the first customer.'**
  String get customersEmpty;

  /// Customer saved.
  ///
  /// In en, this message translates to:
  /// **'Customer saved.'**
  String get customersSaved;

  /// Customer not saved.
  ///
  /// In en, this message translates to:
  /// **'Customer could not be saved.'**
  String get customersSaveFailed;

  /// Customer name, required.
  ///
  /// In en, this message translates to:
  /// **'Name *'**
  String get customerName;

  /// Phone number.
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get customerPhone;

  /// Address.
  ///
  /// In en, this message translates to:
  /// **'Address'**
  String get customerAddress;

  /// Notes about the customer.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get customerNotes;

  /// Optional Udhaar limit.
  ///
  /// In en, this message translates to:
  /// **'Credit limit (optional)'**
  String get customerCreditLimitOptional;

  /// Web preview placeholder.
  ///
  /// In en, this message translates to:
  /// **'Customer offline management is available on Android and Windows.'**
  String get customersWebOnly;

  /// Message: Enter an amount greater than zero.
  ///
  /// In en, this message translates to:
  /// **'Enter an amount greater than zero.'**
  String get khataErrAmountZero;

  /// Message: Payment cannot exceed {amount}.
  ///
  /// In en, this message translates to:
  /// **'Payment cannot exceed {amount}.'**
  String khataErrExceeds(String amount);

  /// Message: Name and a valid credit limit are required.
  ///
  /// In en, this message translates to:
  /// **'Name and a valid credit limit are required.'**
  String get customersErrRequired;

  /// Message: Customers could not be refreshed. Showing available offline data.
  ///
  /// In en, this message translates to:
  /// **'Customers could not be refreshed. Showing available offline data.'**
  String get customersRefreshWarning;

  /// Tab: suppliers.
  ///
  /// In en, this message translates to:
  /// **'Suppliers'**
  String get purchasesTabSuppliers;

  /// Tab: purchases; also a dashboard card.
  ///
  /// In en, this message translates to:
  /// **'Purchases'**
  String get purchasesTabPurchases;

  /// Adds a supplier; also the form title.
  ///
  /// In en, this message translates to:
  /// **'Add supplier'**
  String get suppliersAdd;

  /// Supplier form title when editing.
  ///
  /// In en, this message translates to:
  /// **'Edit supplier'**
  String get suppliersEdit;

  /// Starts a purchase.
  ///
  /// In en, this message translates to:
  /// **'New purchase'**
  String get purchasesNew;

  /// New purchase screen title.
  ///
  /// In en, this message translates to:
  /// **'New Purchase'**
  String get purchasesNewTitle;

  /// Supplier search field.
  ///
  /// In en, this message translates to:
  /// **'Search supplier name or phone'**
  String get suppliersSearch;

  /// Purchase search field.
  ///
  /// In en, this message translates to:
  /// **'Search supplier or invoice'**
  String get purchasesSearch;

  /// No suppliers.
  ///
  /// In en, this message translates to:
  /// **'No suppliers yet.'**
  String get suppliersEmpty;

  /// No purchases.
  ///
  /// In en, this message translates to:
  /// **'No purchases yet.'**
  String get purchasesEmpty;

  /// What the shop still owes a supplier. Amounts are already formatted (e.g. Rs 350.00) and kept left to right.
  ///
  /// In en, this message translates to:
  /// **'{amount} payable'**
  String suppliersPayable(String amount);

  /// Purchase list line: date, invoice or reference, number of items.
  ///
  /// In en, this message translates to:
  /// **'{date} • {reference} • {count} items'**
  String purchaseRowDetails(String date, String reference, String count);

  /// Purchase without an invoice number.
  ///
  /// In en, this message translates to:
  /// **'No reference'**
  String get purchasesNoReference;

  /// Purchase fully paid; also an amount label.
  ///
  /// In en, this message translates to:
  /// **'Paid'**
  String get purchaseStatusPaid;

  /// Purchase partly paid.
  ///
  /// In en, this message translates to:
  /// **'Partial'**
  String get purchaseStatusPartial;

  /// Purchase on supplier credit.
  ///
  /// In en, this message translates to:
  /// **'Credit'**
  String get purchaseStatusCredit;

  /// Supplier not saved.
  ///
  /// In en, this message translates to:
  /// **'Supplier could not be saved.'**
  String get suppliersSaveFailed;

  /// Purchase saved.
  ///
  /// In en, this message translates to:
  /// **'Purchase saved locally.'**
  String get purchasesSaved;

  /// Supplier contact person.
  ///
  /// In en, this message translates to:
  /// **'Contact person'**
  String get supplierContactPerson;

  /// Supplier, required.
  ///
  /// In en, this message translates to:
  /// **'Supplier *'**
  String get purchaseSupplierRequired;

  /// Supplier invoice number.
  ///
  /// In en, this message translates to:
  /// **'Invoice/reference'**
  String get purchaseInvoiceReference;

  /// Date of the purchase.
  ///
  /// In en, this message translates to:
  /// **'Purchase date'**
  String get purchaseDate;

  /// Paid now to the supplier.
  ///
  /// In en, this message translates to:
  /// **'Amount paid'**
  String get purchaseAmountPaid;

  /// Saves the purchase.
  ///
  /// In en, this message translates to:
  /// **'Save Purchase'**
  String get purchaseSave;

  /// A purchase line: quantity and unit cost.
  ///
  /// In en, this message translates to:
  /// **'Qty {quantity} @ {cost}'**
  String purchaseLineQtyCost(String quantity, String cost);

  /// Name shown for a product without a name.
  ///
  /// In en, this message translates to:
  /// **'Product'**
  String get purchaseProductFallback;

  /// Purchase line dialog title.
  ///
  /// In en, this message translates to:
  /// **'Purchase item'**
  String get purchaseItemTitle;

  /// Cost of one unit.
  ///
  /// In en, this message translates to:
  /// **'Unit cost'**
  String get purchaseUnitCost;

  /// Supplier balance heading. Amounts are already formatted (e.g. Rs 350.00) and kept left to right.
  ///
  /// In en, this message translates to:
  /// **'Payable {amount}'**
  String supplierPayableHeading(String amount);

  /// Supplier totals. Amounts are already formatted (e.g. Rs 350.00) and kept left to right.
  ///
  /// In en, this message translates to:
  /// **'Purchases {purchases} • Payments {payments}'**
  String supplierTotals(String purchases, String payments);

  /// Supplier payment dialog title.
  ///
  /// In en, this message translates to:
  /// **'Supplier Payment'**
  String get supplierPaymentTitle;

  /// Optional reference field.
  ///
  /// In en, this message translates to:
  /// **'Reference'**
  String get commonReference;

  /// Optional note field.
  ///
  /// In en, this message translates to:
  /// **'Note'**
  String get commonNote;

  /// Saves the supplier payment.
  ///
  /// In en, this message translates to:
  /// **'Record'**
  String get supplierPaymentRecord;

  /// Purchase totals. Amounts are already formatted (e.g. Rs 350.00) and kept left to right.
  ///
  /// In en, this message translates to:
  /// **'Total {total} • Paid {paid} • Due {due}'**
  String purchaseTotals(String total, String paid, String due);

  /// New purchase is incomplete.
  ///
  /// In en, this message translates to:
  /// **'Select supplier/items and enter a valid payment.'**
  String get purchasesErrSelection;

  /// Adds an expense category.
  ///
  /// In en, this message translates to:
  /// **'Add category'**
  String get expensesAddCategory;

  /// Adds an expense; also the form title.
  ///
  /// In en, this message translates to:
  /// **'Add Expense'**
  String get expensesAdd;

  /// Expense total this month.
  ///
  /// In en, this message translates to:
  /// **'This month'**
  String get expensesThisMonth;

  /// Expense search field.
  ///
  /// In en, this message translates to:
  /// **'Search description/category'**
  String get expensesSearch;

  /// No date filter.
  ///
  /// In en, this message translates to:
  /// **'Any date'**
  String get expensesAnyDate;

  /// No expenses match.
  ///
  /// In en, this message translates to:
  /// **'No expenses found.'**
  String get expensesEmpty;

  /// Expense reference as entered.
  ///
  /// In en, this message translates to:
  /// **'Reference: {reference}'**
  String expensesReferenceLine(String reference);

  /// Create category dialog title.
  ///
  /// In en, this message translates to:
  /// **'Custom category'**
  String get expensesCustomCategory;

  /// Category name field.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get expensesCategoryName;

  /// Category not created.
  ///
  /// In en, this message translates to:
  /// **'Category could not be created.'**
  String get expensesCategoryFailed;

  /// Expense saved.
  ///
  /// In en, this message translates to:
  /// **'Expense saved locally.'**
  String get expensesSaved;

  /// Expense description, required.
  ///
  /// In en, this message translates to:
  /// **'Description *'**
  String get expenseDescriptionRequired;

  /// Expense amount, required.
  ///
  /// In en, this message translates to:
  /// **'Amount *'**
  String get expenseAmountRequired;

  /// Date of the expense.
  ///
  /// In en, this message translates to:
  /// **'Expense date'**
  String get expenseDate;

  /// Expense form is incomplete.
  ///
  /// In en, this message translates to:
  /// **'Complete all required fields.'**
  String get expensesErrRequired;

  /// Default expense category (fixed id per shop). English must equal the seeded name.
  ///
  /// In en, this message translates to:
  /// **'Rent'**
  String get expenseCatRent;

  /// Default expense category (fixed id per shop). English must equal the seeded name.
  ///
  /// In en, this message translates to:
  /// **'Electricity'**
  String get expenseCatElectricity;

  /// Default expense category (fixed id per shop). English must equal the seeded name.
  ///
  /// In en, this message translates to:
  /// **'Gas'**
  String get expenseCatGas;

  /// Default expense category (fixed id per shop). English must equal the seeded name.
  ///
  /// In en, this message translates to:
  /// **'Internet'**
  String get expenseCatInternet;

  /// Default expense category (fixed id per shop). English must equal the seeded name.
  ///
  /// In en, this message translates to:
  /// **'Salary'**
  String get expenseCatSalary;

  /// Default expense category (fixed id per shop). English must equal the seeded name.
  ///
  /// In en, this message translates to:
  /// **'Transport'**
  String get expenseCatTransport;

  /// Default expense category (fixed id per shop). English must equal the seeded name.
  ///
  /// In en, this message translates to:
  /// **'Delivery'**
  String get expenseCatDelivery;

  /// Default expense category (fixed id per shop). English must equal the seeded name.
  ///
  /// In en, this message translates to:
  /// **'Maintenance'**
  String get expenseCatMaintenance;

  /// Default expense category (fixed id per shop). English must equal the seeded name.
  ///
  /// In en, this message translates to:
  /// **'Food/Tea'**
  String get expenseCatFoodTea;

  /// Default expense category (fixed id per shop). English must equal the seeded name.
  ///
  /// In en, this message translates to:
  /// **'Packaging'**
  String get expenseCatPackaging;

  /// Default expense category (fixed id per shop). English must equal the seeded name.
  ///
  /// In en, this message translates to:
  /// **'Miscellaneous'**
  String get expenseCatMiscellaneous;

  /// Dashboard title; shop name as entered.
  ///
  /// In en, this message translates to:
  /// **'{shop} • Dashboard'**
  String dashTitle(String shop);

  /// Report failed.
  ///
  /// In en, this message translates to:
  /// **'Could not calculate this report.'**
  String get dashReportFailed;

  /// Report period chip. key is the stored preset (today, week, month, year, custom); english is shown unchanged in English.
  ///
  /// In en, this message translates to:
  /// **'{key, select, other{{english}}}'**
  String reportPreset(String key, String english);

  /// Note above the dashboard.
  ///
  /// In en, this message translates to:
  /// **'Cached device data • pending operations may not be reflected on other devices.'**
  String get dashCachedNote;

  /// Warning about partially returned sales.
  ///
  /// In en, this message translates to:
  /// **'{count} partially returned sale(s) are excluded. Profit is provisional until returns accounting is implemented.'**
  String dashPartialReturns(String count);

  /// Dashboard card.
  ///
  /// In en, this message translates to:
  /// **'Net Sales'**
  String get dashNetSalesCard;

  /// Dashboard card.
  ///
  /// In en, this message translates to:
  /// **'Gross Profit'**
  String get dashGrossProfit;

  /// Dashboard card.
  ///
  /// In en, this message translates to:
  /// **'Net Profit'**
  String get dashNetProfit;

  /// Dashboard card: owed by customers.
  ///
  /// In en, this message translates to:
  /// **'Customer Udhaar'**
  String get dashCustomerUdhaar;

  /// Dashboard card: owed to suppliers.
  ///
  /// In en, this message translates to:
  /// **'Supplier Payable'**
  String get dashSupplierPayable;

  /// Dashboard card: products low on stock.
  ///
  /// In en, this message translates to:
  /// **'Low Stock'**
  String get dashLowStockCard;

  /// Dashboard section.
  ///
  /// In en, this message translates to:
  /// **'Sales'**
  String get dashSales;

  /// Dashboard row.
  ///
  /// In en, this message translates to:
  /// **'Gross sales'**
  String get dashGrossSales;

  /// Dashboard row.
  ///
  /// In en, this message translates to:
  /// **'Returns / voids'**
  String get dashReturnsVoids;

  /// Dashboard row.
  ///
  /// In en, this message translates to:
  /// **'Net sales'**
  String get dashNetSales;

  /// Dashboard row.
  ///
  /// In en, this message translates to:
  /// **'Average bill'**
  String get dashAverageBill;

  /// Dashboard row: new customer credit.
  ///
  /// In en, this message translates to:
  /// **'Udhaar created'**
  String get dashUdhaarCreated;

  /// Dashboard row.
  ///
  /// In en, this message translates to:
  /// **'Period purchases'**
  String get dashPeriodPurchases;

  /// Dashboard row: new supplier credit.
  ///
  /// In en, this message translates to:
  /// **'Credit created'**
  String get dashCreditCreated;

  /// Dashboard row: number of purchases.
  ///
  /// In en, this message translates to:
  /// **'Transactions'**
  String get dashTransactions;

  /// Chart heading.
  ///
  /// In en, this message translates to:
  /// **'Sales vs Purchases'**
  String get dashSalesVsPurchases;

  /// Ranking.
  ///
  /// In en, this message translates to:
  /// **'Top products by sales'**
  String get dashTopSales;

  /// Ranking.
  ///
  /// In en, this message translates to:
  /// **'Top products by quantity'**
  String get dashTopQuantity;

  /// Ranking.
  ///
  /// In en, this message translates to:
  /// **'Highest gross profit products'**
  String get dashTopProfit;

  /// Ranking.
  ///
  /// In en, this message translates to:
  /// **'Expenses by category'**
  String get dashExpensesByCategory;

  /// Ranking.
  ///
  /// In en, this message translates to:
  /// **'Expenses by payment method'**
  String get dashExpensesByMethod;

  /// Ranking.
  ///
  /// In en, this message translates to:
  /// **'Top customer debtors'**
  String get dashTopDebtors;

  /// Ranking.
  ///
  /// In en, this message translates to:
  /// **'Top supplier payable'**
  String get dashTopSupplierPayable;

  /// Ranking.
  ///
  /// In en, this message translates to:
  /// **'Low stock (current / threshold)'**
  String get dashLowStockList;

  /// Empty ranking.
  ///
  /// In en, this message translates to:
  /// **'No data'**
  String get dashNoData;

  /// Profit warning.
  ///
  /// In en, this message translates to:
  /// **'{count} sale lines excluded from profit because cost snapshots were invalid.'**
  String dashMissingCost(String count);

  /// Dashboard section.
  ///
  /// In en, this message translates to:
  /// **'Cashier performance'**
  String get dashCashierPerformance;

  /// One cashier's bills and payments. Amounts are already formatted (e.g. Rs 350.00) and kept left to right.
  ///
  /// In en, this message translates to:
  /// **'{bills} bills • Cash {cash} • Digital {digital} • Udhaar {udhaar}'**
  String dashCashierLine(
    String bills,
    String cash,
    String digital,
    String udhaar,
  );

  /// Empty chart.
  ///
  /// In en, this message translates to:
  /// **'No period activity'**
  String get dashNoActivity;

  /// Settings offline before the first sync.
  ///
  /// In en, this message translates to:
  /// **'Settings are unavailable offline until the first sync.'**
  String get settingsOfflineUnavailable;

  /// Settings shown from this device.
  ///
  /// In en, this message translates to:
  /// **'Showing cached settings.'**
  String get settingsShowingCached;

  /// Settings form invalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a shop name and a non-negative stock threshold.'**
  String get settingsErrRequired;

  /// Settings not saved.
  ///
  /// In en, this message translates to:
  /// **'Could not save settings. Check your connection.'**
  String get settingsSaveFailed;

  /// Settings saved.
  ///
  /// In en, this message translates to:
  /// **'Settings saved.'**
  String get settingsSaved;

  /// Settings section.
  ///
  /// In en, this message translates to:
  /// **'Subscription'**
  String get settingsSubscription;

  /// Settings section.
  ///
  /// In en, this message translates to:
  /// **'Shop details'**
  String get settingsShopDetails;

  /// Shop name field.
  ///
  /// In en, this message translates to:
  /// **'Shop name'**
  String get settingsShopName;

  /// Shop currency (PKR).
  ///
  /// In en, this message translates to:
  /// **'Currency'**
  String get settingsCurrency;

  /// Shop time zone.
  ///
  /// In en, this message translates to:
  /// **'Time zone'**
  String get settingsTimeZone;

  /// The shop time zone.
  ///
  /// In en, this message translates to:
  /// **'Pakistan (Asia/Karachi)'**
  String get settingsTimeZoneValue;

  /// Settings section.
  ///
  /// In en, this message translates to:
  /// **'Stock'**
  String get settingsStock;

  /// Negative stock switch.
  ///
  /// In en, this message translates to:
  /// **'Allow selling below zero stock'**
  String get settingsAllowNegative;

  /// Default low-stock level.
  ///
  /// In en, this message translates to:
  /// **'Default low-stock alert level'**
  String get settingsDefaultLowStock;

  /// Text printed at the end of receipts.
  ///
  /// In en, this message translates to:
  /// **'Receipt footer'**
  String get settingsReceiptFooter;

  /// Receipt paper width.
  ///
  /// In en, this message translates to:
  /// **'Paper width'**
  String get settingsPaperWidth;

  /// Receipt switch.
  ///
  /// In en, this message translates to:
  /// **'Show phone on receipt'**
  String get settingsShowPhone;

  /// Receipt switch.
  ///
  /// In en, this message translates to:
  /// **'Show address on receipt'**
  String get settingsShowAddress;

  /// Settings section.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get settingsNotifications;

  /// Alerts switch.
  ///
  /// In en, this message translates to:
  /// **'Owner alerts'**
  String get settingsOwnerAlerts;

  /// Explains the alerts switch.
  ///
  /// In en, this message translates to:
  /// **'Alerts are not available yet. Your choice is saved for when they are.'**
  String get settingsAlertsHint;

  /// Saves settings.
  ///
  /// In en, this message translates to:
  /// **'Save settings'**
  String get settingsSave;

  /// Settings section.
  ///
  /// In en, this message translates to:
  /// **'Registered devices'**
  String get settingsDevices;

  /// Settings section and panel heading.
  ///
  /// In en, this message translates to:
  /// **'Cashiers'**
  String get settingsCashiers;

  /// Subscription loading.
  ///
  /// In en, this message translates to:
  /// **'Checking subscription…'**
  String get settingsCheckingSubscription;

  /// Subscription state.
  ///
  /// In en, this message translates to:
  /// **'Trial active'**
  String get subStateTrial;

  /// Subscription state.
  ///
  /// In en, this message translates to:
  /// **'Expires soon'**
  String get subStateExpiringSoon;

  /// Subscription state.
  ///
  /// In en, this message translates to:
  /// **'Offline grace'**
  String get subStateOfflineGrace;

  /// Subscription state.
  ///
  /// In en, this message translates to:
  /// **'Online verification required'**
  String get subStateVerify;

  /// Subscription state.
  ///
  /// In en, this message translates to:
  /// **'Expired'**
  String get subStateExpired;

  /// Subscription allows sales.
  ///
  /// In en, this message translates to:
  /// **'This tablet can record sales'**
  String get subCanRecord;

  /// Subscription blocks sales.
  ///
  /// In en, this message translates to:
  /// **'Verification or renewal needed'**
  String get subNeedsRenewal;

  /// Subscription plan.
  ///
  /// In en, this message translates to:
  /// **'Plan'**
  String get subPlan;

  /// No plan information.
  ///
  /// In en, this message translates to:
  /// **'Unavailable'**
  String get subUnavailable;

  /// Subscription end date.
  ///
  /// In en, this message translates to:
  /// **'Current period ends'**
  String get subPeriodEnds;

  /// Offline grace end.
  ///
  /// In en, this message translates to:
  /// **'Works offline until'**
  String get subOfflineUntil;

  /// Last online check.
  ///
  /// In en, this message translates to:
  /// **'Last checked online'**
  String get subLastChecked;

  /// Never checked online.
  ///
  /// In en, this message translates to:
  /// **'Not yet'**
  String get subNotYet;

  /// Renew tapped.
  ///
  /// In en, this message translates to:
  /// **'Online renewal is not available in the app yet.'**
  String get subRenewUnavailable;

  /// Renew button.
  ///
  /// In en, this message translates to:
  /// **'Renew subscription'**
  String get subRenew;

  /// This device in the device list; name as registered.
  ///
  /// In en, this message translates to:
  /// **'{name} (this device)'**
  String deviceThisDevice(String name);

  /// Device type and registration date.
  ///
  /// In en, this message translates to:
  /// **'{type} • Registered {date}'**
  String deviceRegistered(String type, String date);

  /// Device type.
  ///
  /// In en, this message translates to:
  /// **'Android tablet'**
  String get deviceAndroidTablet;

  /// Device type.
  ///
  /// In en, this message translates to:
  /// **'Windows computer'**
  String get deviceWindows;

  /// Device type.
  ///
  /// In en, this message translates to:
  /// **'Mobile'**
  String get deviceMobile;

  /// Explains where sync status is.
  ///
  /// In en, this message translates to:
  /// **'Sync status for this tablet is shown at the top of the sales screen.'**
  String get settingsSyncHint;

  /// Explains the language setting.
  ///
  /// In en, this message translates to:
  /// **'Saved on this device only. Changing it keeps you signed in.'**
  String get settingsLanguageHint;

  /// Creates a cashier.
  ///
  /// In en, this message translates to:
  /// **'Create cashier'**
  String get cashierCreate;

  /// Cashier cannot log in.
  ///
  /// In en, this message translates to:
  /// **'Disabled'**
  String get cashierDisabled;

  /// Cashier name field.
  ///
  /// In en, this message translates to:
  /// **'Cashier name'**
  String get cashierName;

  /// Cashier PIN field.
  ///
  /// In en, this message translates to:
  /// **'Numeric PIN'**
  String get cashierNumericPin;

  /// Repeat the PIN.
  ///
  /// In en, this message translates to:
  /// **'Confirm PIN'**
  String get cashierConfirmPin;

  /// Message: Could not save the purchase. Please try again.
  ///
  /// In en, this message translates to:
  /// **'Could not save the purchase. Please try again.'**
  String get purchasesErrSaveFailed;

  /// Message: Could not save the expense. Please try again.
  ///
  /// In en, this message translates to:
  /// **'Could not save the expense. Please try again.'**
  String get expensesErrSaveFailed;

  /// Message: Enter the cashier name.
  ///
  /// In en, this message translates to:
  /// **'Enter the cashier name.'**
  String get cashierErrName;

  /// Message: PIN must contain 4 to 8 digits.
  ///
  /// In en, this message translates to:
  /// **'PIN must contain 4 to 8 digits.'**
  String get cashierErrPin;

  /// Message: PINs do not match.
  ///
  /// In en, this message translates to:
  /// **'PINs do not match.'**
  String get cashierErrPinMismatch;

  /// Message: Could not create the cashier. Please try again.
  ///
  /// In en, this message translates to:
  /// **'Could not create the cashier. Please try again.'**
  String get cashierErrCreate;

  /// Message: Could not update the cashier. Please try again.
  ///
  /// In en, this message translates to:
  /// **'Could not update the cashier. Please try again.'**
  String get cashierErrUpdate;

  /// Supplier payment saved.
  ///
  /// In en, this message translates to:
  /// **'Supplier payment saved locally.'**
  String get supplierPaymentSaved;

  /// Supplier payment refused.
  ///
  /// In en, this message translates to:
  /// **'Supplier payment could not be recorded. Nothing was changed.'**
  String get supplierPaymentFailed;

  /// Owner sign-in screen title and the lobby button that opens it.
  ///
  /// In en, this message translates to:
  /// **'Owner sign in'**
  String get authOwnerSignIn;

  /// Sign-up screen title and the button that switches to sign-up.
  ///
  /// In en, this message translates to:
  /// **'Create owner account'**
  String get authCreateOwnerAccount;

  /// Owner sign-up: full name field.
  ///
  /// In en, this message translates to:
  /// **'Full name'**
  String get authFullName;

  /// Owner email field. The value is always typed left to right.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get authEmail;

  /// Owner password field.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get authPassword;

  /// Sign-in button while the request is running.
  ///
  /// In en, this message translates to:
  /// **'Please wait…'**
  String get authPleaseWait;

  /// Owner sign-up button.
  ///
  /// In en, this message translates to:
  /// **'Sign up'**
  String get authSignUp;

  /// Owner sign-in button.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get authSignIn;

  /// Switches the sign-up form back to sign-in.
  ///
  /// In en, this message translates to:
  /// **'Have an account? Sign in'**
  String get authHaveAccount;

  /// Sign-in refused: wrong email or password.
  ///
  /// In en, this message translates to:
  /// **'Wrong email or password.'**
  String get authErrWrongCredentials;

  /// Sign-in failed: no network.
  ///
  /// In en, this message translates to:
  /// **'No connection to the server. Check your internet and try again.'**
  String get authErrNoConnection;

  /// The owner's sign-in session expired.
  ///
  /// In en, this message translates to:
  /// **'Your session expired. Please sign in again.'**
  String get authErrSessionExpired;

  /// Sign-in failed for another server reason.
  ///
  /// In en, this message translates to:
  /// **'Could not sign in. Please check your details and try again.'**
  String get authErrSignInDetails;

  /// Sign-in failed unexpectedly (usually the connection).
  ///
  /// In en, this message translates to:
  /// **'Could not sign in. Check your connection and try again.'**
  String get authErrSignInConnection;

  /// Title when the owner's shop could not be loaded after sign-in.
  ///
  /// In en, this message translates to:
  /// **'Bootstrap failed'**
  String get onboardLoadFailedTitle;

  /// The owner's shop could not be loaded after sign-in.
  ///
  /// In en, this message translates to:
  /// **'Could not load your shop. Check your connection and try again.'**
  String get onboardLoadFailed;

  /// First-time setup: create shop screen title.
  ///
  /// In en, this message translates to:
  /// **'Create your shop'**
  String get onboardCreateShopTitle;

  /// Create shop: phone field.
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get onboardShopPhone;

  /// Create shop: address field.
  ///
  /// In en, this message translates to:
  /// **'Address'**
  String get onboardShopAddress;

  /// Create shop button while saving.
  ///
  /// In en, this message translates to:
  /// **'Creating shop…'**
  String get onboardCreatingShop;

  /// Create shop button.
  ///
  /// In en, this message translates to:
  /// **'Create shop'**
  String get onboardCreateShop;

  /// Shop creation failed.
  ///
  /// In en, this message translates to:
  /// **'Could not create your shop. Please try again.'**
  String get onboardErrCreateShop;

  /// Register device: device name field.
  ///
  /// In en, this message translates to:
  /// **'Device name'**
  String get deviceName;

  /// Register device button while saving.
  ///
  /// In en, this message translates to:
  /// **'Registering…'**
  String get deviceRegistering;

  /// Register device button.
  ///
  /// In en, this message translates to:
  /// **'Register this device'**
  String get deviceRegister;

  /// This device was revoked by the owner.
  ///
  /// In en, this message translates to:
  /// **'Device is revoked.'**
  String get deviceRevoked;

  /// Shown on the owner hub when this device is registered and active.
  ///
  /// In en, this message translates to:
  /// **'Device active. Local sales foundation is ready.'**
  String get deviceActive;

  /// Device registration lookup failed.
  ///
  /// In en, this message translates to:
  /// **'Could not check this device registration. Check your connection.'**
  String get deviceErrCheck;

  /// Device registration failed.
  ///
  /// In en, this message translates to:
  /// **'Could not register this device. Check your connection.'**
  String get deviceErrRegister;

  /// Cashier mode needs one owner unlock to provision this device.
  ///
  /// In en, this message translates to:
  /// **'Unlock owner mode once to set up cashier mode on this device.'**
  String get deviceErrCashierNeedsOwner;

  /// Cashier mode provisioning failed.
  ///
  /// In en, this message translates to:
  /// **'Could not set up cashier mode on this device. Check your connection.'**
  String get deviceErrCashierSetup;

  /// Locking owner mode before cashier mode failed.
  ///
  /// In en, this message translates to:
  /// **'Could not secure owner mode on this device. Try again.'**
  String get deviceErrSecureOwner;

  /// Startup could not resolve the device mode.
  ///
  /// In en, this message translates to:
  /// **'This device could not be opened. Try again.'**
  String get deviceOpenFailed;

  /// The owner session could not be removed before cashier mode.
  ///
  /// In en, this message translates to:
  /// **'Owner mode could not be closed safely on this device, so cashier mode was not opened. Restart the app and try again.'**
  String get deviceOwnerRemovalFailed;

  /// Device lobby warning: not yet provisioned for cashier mode.
  ///
  /// In en, this message translates to:
  /// **'This device must be set up for cashier mode once. Ask the owner to sign in.'**
  String get deviceWarnSetupOnce;

  /// Device lobby warning: the cached cashier session expired.
  ///
  /// In en, this message translates to:
  /// **'The offline cashier session expired. Connect to the internet and sign in again.'**
  String get deviceWarnOfflineExpired;

  /// Device lobby warning: local shop or device data no longer matches.
  ///
  /// In en, this message translates to:
  /// **'Offline cashier access is unavailable because this shop or device no longer matches. Connect to the internet and sign in again.'**
  String get deviceWarnMismatch;

  /// Cashier login heading. The app name stays in English; shopName is shown as entered.
  ///
  /// In en, this message translates to:
  /// **'Dukaan Pro — {shopName}'**
  String cashierLoginHeading(String shopName);

  /// Cashier list failed to load.
  ///
  /// In en, this message translates to:
  /// **'Could not load cashiers. Please try again.'**
  String get cashierLoadFailed;

  /// Cashier login: there are no cashiers.
  ///
  /// In en, this message translates to:
  /// **'No cashier has been created yet.'**
  String get cashierNoneCreated;

  /// Cashier login: every cashier is disabled.
  ///
  /// In en, this message translates to:
  /// **'No active cashier is available.'**
  String get cashierNoneActive;

  /// Cashier login: no cashier and no owner access.
  ///
  /// In en, this message translates to:
  /// **'Ask the owner to sign in and add a cashier.'**
  String get cashierAskOwner;

  /// Button: create the first cashier.
  ///
  /// In en, this message translates to:
  /// **'Create first cashier'**
  String get cashierCreateFirst;

  /// Button: open cashier setup.
  ///
  /// In en, this message translates to:
  /// **'Manage cashiers'**
  String get cashierManage;

  /// Button: close cashier setup.
  ///
  /// In en, this message translates to:
  /// **'Hide cashier setup'**
  String get cashierHideSetup;

  /// Cashier login: cashier dropdown.
  ///
  /// In en, this message translates to:
  /// **'Select cashier'**
  String get cashierSelect;

  /// Cashier login: PIN field.
  ///
  /// In en, this message translates to:
  /// **'PIN'**
  String get cashierPin;

  /// Cashier login button while checking the PIN.
  ///
  /// In en, this message translates to:
  /// **'Signing in…'**
  String get cashierSigningIn;

  /// Cashier login button.
  ///
  /// In en, this message translates to:
  /// **'Start Shift / Login'**
  String get cashierStartShift;

  /// Cashier login: the PIN is not 4 to 8 digits.
  ///
  /// In en, this message translates to:
  /// **'Enter the cashier’s 4 to 8 digit PIN.'**
  String get cashierErrPinFormat;

  /// Cashier login succeeded.
  ///
  /// In en, this message translates to:
  /// **'Cashier authenticated. Offline billing remains available until local expiry.'**
  String get cashierAuthenticated;

  /// Cashier login refused (wrong PIN or locked out).
  ///
  /// In en, this message translates to:
  /// **'Login failed or temporarily locked.'**
  String get cashierLoginFailed;

  /// Title of an owner screen opened while owner mode is locked.
  ///
  /// In en, this message translates to:
  /// **'Owner access required'**
  String get ownerAccessRequired;

  /// Owner screen body while owner mode is locked.
  ///
  /// In en, this message translates to:
  /// **'Owner mode is locked on this device. Ask the owner to unlock it.'**
  String get ownerLockedAskOwner;

  /// Owner hub prompt while owner mode is locked.
  ///
  /// In en, this message translates to:
  /// **'Owner mode is locked. Enter the owner password.'**
  String get ownerLockedEnterPassword;

  /// Owner unlock: password field.
  ///
  /// In en, this message translates to:
  /// **'Owner password'**
  String get ownerPassword;

  /// Owner unlock button while checking.
  ///
  /// In en, this message translates to:
  /// **'Checking…'**
  String get ownerChecking;

  /// Owner unlock button.
  ///
  /// In en, this message translates to:
  /// **'Unlock owner mode'**
  String get ownerUnlock;

  /// Owner unlock refused.
  ///
  /// In en, this message translates to:
  /// **'Wrong owner password.'**
  String get ownerErrWrongPassword;

  /// Owner unlock could not reach the server.
  ///
  /// In en, this message translates to:
  /// **'Could not check the password. Check your connection.'**
  String get ownerErrCheckPassword;

  /// Subscription: no stored proof on this device.
  ///
  /// In en, this message translates to:
  /// **'Online subscription verification is required.'**
  String get subMsgVerificationRequired;

  /// Subscription: the stored proof failed verification.
  ///
  /// In en, this message translates to:
  /// **'Stored subscription proof is invalid. Verify online.'**
  String get subMsgProofInvalid;

  /// Subscription: the device clock moved backwards.
  ///
  /// In en, this message translates to:
  /// **'Device time changed significantly. Connect online to verify.'**
  String get subMsgClockChanged;

  /// Subscription expired: recording sales and stock is blocked.
  ///
  /// In en, this message translates to:
  /// **'Shop subscription needs renewal. Please contact the owner.'**
  String get subMsgNeedsRenewal;

  /// Subscription: past its period, inside the offline grace.
  ///
  /// In en, this message translates to:
  /// **'Grace period active. Online verification is needed.'**
  String get subMsgGrace;

  /// Subscription: ends within a few days.
  ///
  /// In en, this message translates to:
  /// **'Subscription ending soon.'**
  String get subMsgEndingSoon;

  /// Subscription: active and verified.
  ///
  /// In en, this message translates to:
  /// **'Subscription verified.'**
  String get subMsgVerified;

  /// Sync reason for code DPV01.
  ///
  /// In en, this message translates to:
  /// **'The cloud rejected this record as invalid or out of date.'**
  String get syncReasonInvalid;

  /// Sync reason for code DPC01.
  ///
  /// In en, this message translates to:
  /// **'A different version of this record is already in the cloud.'**
  String get syncReasonOtherVersion;

  /// Sync reason for code DPX01.
  ///
  /// In en, this message translates to:
  /// **'This change conflicts with the cloud and cannot be applied.'**
  String get syncReasonConflict;

  /// Sync reason for code DPA01.
  ///
  /// In en, this message translates to:
  /// **'This device or cashier is no longer authorised.'**
  String get syncReasonDeviceNotAuthorised;

  /// Sync reason for codes 42501 and 403.
  ///
  /// In en, this message translates to:
  /// **'This device or session is not authorised to sync.'**
  String get syncReasonSessionNotAuthorised;

  /// Sync reason for codes PGRST301 and 401.
  ///
  /// In en, this message translates to:
  /// **'The sign-in session expired.'**
  String get syncReasonSessionExpired;

  /// Sync reason for code PGRST302.
  ///
  /// In en, this message translates to:
  /// **'The sign-in session is missing.'**
  String get syncReasonSessionMissing;

  /// Sync reason: legacy timestamp payload.
  ///
  /// In en, this message translates to:
  /// **'This record was saved by an older app version and cannot be sent safely.'**
  String get syncReasonOldVersion;

  /// Sync reason: no network.
  ///
  /// In en, this message translates to:
  /// **'No connection to the cloud. It will retry automatically.'**
  String get syncReasonOffline;

  /// Sync reason: a temporary server error.
  ///
  /// In en, this message translates to:
  /// **'The cloud is temporarily unavailable. It will retry automatically.'**
  String get syncReasonTemporary;

  /// Sync reason: an unknown server error.
  ///
  /// In en, this message translates to:
  /// **'The cloud could not accept this record.'**
  String get syncReasonRejected;

  /// Sync reason: a record it depends on needs attention.
  ///
  /// In en, this message translates to:
  /// **'An earlier record it depends on needs attention.'**
  String get syncReasonParent;

  /// Synced but flagged by a shop rule. rules is a list of broken rules.
  ///
  /// In en, this message translates to:
  /// **'Saved in the cloud, but it broke a shop rule ({rules}). Please review it.'**
  String syncReasonFlagged(String rules);

  /// Shop rule broken by a synced sale.
  ///
  /// In en, this message translates to:
  /// **'customer credit limit exceeded'**
  String get syncFlagCreditLimit;

  /// Web preview placeholder for expenses.
  ///
  /// In en, this message translates to:
  /// **'Offline expense management is available on Android and Windows.'**
  String get expensesWebOnly;

  /// Web preview placeholder for purchases.
  ///
  /// In en, this message translates to:
  /// **'Purchasing is available on Android and Windows.'**
  String get purchasesWebOnly;

  /// Web preview dashboard title; shopName is shown as entered.
  ///
  /// In en, this message translates to:
  /// **'{shopName} Dashboard'**
  String dashboardWebTitle(String shopName);

  /// Web preview placeholder for the dashboard.
  ///
  /// In en, this message translates to:
  /// **'Offline owner reports are available on Android and Windows.'**
  String get dashboardWebOnly;

  /// Checkout or cart refused: the product has less stock than requested. product is shown as entered; available is a formatted quantity.
  ///
  /// In en, this message translates to:
  /// **'Not enough stock for {product}. Available: {available}.'**
  String saleErrNotEnoughStock(String product, String available);

  /// Checkout or cart refused: the product's recorded stock is already negative from earlier sales.
  ///
  /// In en, this message translates to:
  /// **'Stock for {product} is below zero ({stock}). Correct the stock in Inventory before selling it.'**
  String saleErrStockBelowZero(String product, String stock);

  /// Stock adjustment: the quantity field is empty.
  ///
  /// In en, this message translates to:
  /// **'Enter a quantity, for example 20, +20 or -5.'**
  String get inventoryErrQuantityMissing;

  /// Stock adjustment: the quantity is not a number.
  ///
  /// In en, this message translates to:
  /// **'Enter a number such as 20, +20, -5 or 2.5 (up to 3 decimals).'**
  String get inventoryErrQuantityFormat;

  /// Stock adjustment: quantity is zero.
  ///
  /// In en, this message translates to:
  /// **'Quantity cannot be zero.'**
  String get inventoryErrQuantityZero;

  /// Stock adjustment: a negative quantity for opening stock or damage.
  ///
  /// In en, this message translates to:
  /// **'Enter this quantity without a minus sign. To remove stock, choose Manual correction or Damaged / wastage.'**
  String get inventoryErrQuantitySign;

  /// Stock adjustment: a decimal quantity for a piece product.
  ///
  /// In en, this message translates to:
  /// **'This product is counted in whole units. Enter a whole number.'**
  String get inventoryErrWholeUnits;

  /// Stock adjustment: the reason/note is empty.
  ///
  /// In en, this message translates to:
  /// **'Enter a reason for this adjustment.'**
  String get inventoryErrReasonRequired;

  /// Stock adjustment refused by the shop's negative-stock rule.
  ///
  /// In en, this message translates to:
  /// **'This adjustment would make stock negative.'**
  String get inventoryErrWouldGoNegative;

  /// Stock adjustment Save button while saving.
  ///
  /// In en, this message translates to:
  /// **'Saving…'**
  String get inventorySaving;

  /// Edit product: a pack variant cannot change the family name or category (no atomic server update yet).
  ///
  /// In en, this message translates to:
  /// **'This is one pack size. Its name and category are shared by every size and cannot be changed here yet.'**
  String get editFamilyShared;

  /// Edit product: the unit cannot change after stock history exists.
  ///
  /// In en, this message translates to:
  /// **'The unit is fixed once the product has stock or sales.'**
  String get editUnitLocked;

  /// Edit product: stock section heading.
  ///
  /// In en, this message translates to:
  /// **'Stock'**
  String get editStockSection;

  /// Edit product: stock is not edited directly.
  ///
  /// In en, this message translates to:
  /// **'Stock changes only through Adjust stock, so every change is recorded.'**
  String get editStockHint;

  /// Edit product: opens the stock adjustment dialog.
  ///
  /// In en, this message translates to:
  /// **'Adjust stock'**
  String get editAdjustStock;

  /// Edit product: owner action that archives the product (hidden from new sales, history kept).
  ///
  /// In en, this message translates to:
  /// **'Archive Product'**
  String get editArchive;

  /// Archive confirmation title; name is shown as entered.
  ///
  /// In en, this message translates to:
  /// **'Archive {name}?'**
  String archiveTitle(String name);

  /// Delete confirmation while counting history.
  ///
  /// In en, this message translates to:
  /// **'Checking where this product is used…'**
  String get archiveChecking;

  /// Delete confirmation: how often the product appears in history.
  ///
  /// In en, this message translates to:
  /// **'Bill lines: {bills} · Purchase lines: {purchases} · Returns: {returns} · Stock movements: {movements}'**
  String archiveHistoryCounts(
    String bills,
    String purchases,
    String returns,
    String movements,
  );

  /// Archive confirmation for a product with history.
  ///
  /// In en, this message translates to:
  /// **'This product has sales or stock history. Archiving hides it from new sales; old bills, stock history and reports keep it. You can restore it at any time.'**
  String get archiveHistoryExplain;

  /// Archive confirmation for a product without history.
  ///
  /// In en, this message translates to:
  /// **'This product has no sales or stock history. Archiving hides it from new sales. You can restore it at any time.'**
  String get archiveUnusedExplain;

  /// Archive confirmation button.
  ///
  /// In en, this message translates to:
  /// **'Archive Product'**
  String get archiveConfirm;

  /// Delete confirmation button while archiving.
  ///
  /// In en, this message translates to:
  /// **'Archiving…'**
  String get archiveWorking;

  /// After archiving; name is shown as entered.
  ///
  /// In en, this message translates to:
  /// **'{name} archived. It is no longer sold; its history is kept.'**
  String archiveDone(String name);

  /// Archiving failed (it needs the internet).
  ///
  /// In en, this message translates to:
  /// **'Could not archive the product. Check your connection and try again.'**
  String get archiveFailed;

  /// Restore an archived product.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get restoreAction;

  /// After restoring; name is shown as entered.
  ///
  /// In en, this message translates to:
  /// **'{name} restored and available for sale.'**
  String restoreDone(String name);

  /// Restoring failed.
  ///
  /// In en, this message translates to:
  /// **'Could not restore the product. Check your connection and try again.'**
  String get restoreFailed;

  /// Products list: status filter label.
  ///
  /// In en, this message translates to:
  /// **'Show'**
  String get productsStatusLabel;

  /// Products list filter: all.
  ///
  /// In en, this message translates to:
  /// **'All products'**
  String get productsStatusAll;

  /// Products list filter: active products.
  ///
  /// In en, this message translates to:
  /// **'For sale'**
  String get productsStatusActive;

  /// Products list filter and badge: archived products.
  ///
  /// In en, this message translates to:
  /// **'Archived'**
  String get productsStatusArchived;

  /// Product card button: set the Urdu display name of a product.
  ///
  /// In en, this message translates to:
  /// **'Urdu name'**
  String get productUrduNameAction;

  /// Title of the Urdu display name dialog. name is the product name.
  ///
  /// In en, this message translates to:
  /// **'Urdu name for {name}'**
  String productUrduNameTitle(String name);

  /// Explains that the Urdu name is display-only.
  ///
  /// In en, this message translates to:
  /// **'Shown only when the app is in Urdu. The English product name is not changed.'**
  String get productUrduNameHint;

  /// Shown when no automatic translation service is available.
  ///
  /// In en, this message translates to:
  /// **'Automatic translation is off until the translation models are downloaded in Settings. You can enter the Urdu name yourself.'**
  String get productUrduNameAutoOff;

  /// Button that deletes the owner's Urdu name for a product.
  ///
  /// In en, this message translates to:
  /// **'Remove Urdu name'**
  String get productUrduNameRemove;

  /// Snackbar after saving a product's Urdu name.
  ///
  /// In en, this message translates to:
  /// **'Urdu name saved'**
  String get productUrduNameSaved;

  /// Settings section heading for on-device Urdu product name translation.
  ///
  /// In en, this message translates to:
  /// **'Offline Urdu Translation'**
  String get offlineTranslationHeading;

  /// Shown on devices without on-device translation (Windows, web).
  ///
  /// In en, this message translates to:
  /// **'Automatic Urdu product names work on Android tablets only. Urdu names entered by hand still work.'**
  String get offlineTranslationUnsupported;

  /// Shown while checking whether the translation models are on the device.
  ///
  /// In en, this message translates to:
  /// **'Checking translation models…'**
  String get offlineTranslationChecking;

  /// Translation models are not on this device yet.
  ///
  /// In en, this message translates to:
  /// **'Models not downloaded. Download required to show product names in Urdu automatically.'**
  String get offlineTranslationNotDownloaded;

  /// Explains the model download size and Wi-Fi use.
  ///
  /// In en, this message translates to:
  /// **'One-time download of about 60 MB (English and Urdu models, about 30 MB each) over Wi-Fi. After that, product names are translated on this tablet without internet.'**
  String get offlineTranslationSize;

  /// Button that starts the translation model download.
  ///
  /// In en, this message translates to:
  /// **'Download Translation Models'**
  String get offlineTranslationDownload;

  /// Shown during the model download (no percentage is available).
  ///
  /// In en, this message translates to:
  /// **'Downloading translation models… You can keep using the app.'**
  String get offlineTranslationDownloading;

  /// Models are downloaded and translation works offline.
  ///
  /// In en, this message translates to:
  /// **'Ready for offline translation. Product names are translated on this tablet without internet.'**
  String get offlineTranslationReady;

  /// Shown when the model download failed or timed out.
  ///
  /// In en, this message translates to:
  /// **'Download failed. Check the Wi-Fi connection and retry.'**
  String get offlineTranslationFailed;

  /// Button to retry the model download over Wi-Fi.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get offlineTranslationRetry;

  /// Button to retry the model download allowing mobile data.
  ///
  /// In en, this message translates to:
  /// **'Download using mobile data'**
  String get offlineTranslationUseMobileData;

  /// Title of the confirmation dialog before downloading the models.
  ///
  /// In en, this message translates to:
  /// **'Download translation models?'**
  String get offlineTranslationConfirmTitle;

  /// Confirm button in the download dialog.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get offlineTranslationConfirmDownload;

  /// Note that machine translations can be corrected by hand.
  ///
  /// In en, this message translates to:
  /// **'Machine translations can be wrong. Correct any name with the Urdu name button in Products.'**
  String get offlineTranslationMachineNote;

  /// Shown where self-registration used to be; shops are created by support only.
  ///
  /// In en, this message translates to:
  /// **'Contact Dokan Pro Support for Activation'**
  String get activationContactSupport;

  /// Explains why there is no sign-up.
  ///
  /// In en, this message translates to:
  /// **'New shops and owner accounts are created by Dokan Pro Support.'**
  String get activationSupportNote;

  /// Button that emails a password reset link.
  ///
  /// In en, this message translates to:
  /// **'Forgot password?'**
  String get authForgotPassword;

  /// Neutral confirmation after requesting a reset.
  ///
  /// In en, this message translates to:
  /// **'If this email has an account, a password reset link has been sent.'**
  String get authResetSent;

  /// Reset requested with an empty email field.
  ///
  /// In en, this message translates to:
  /// **'Enter your email first.'**
  String get authResetNeedsEmail;

  /// Signed-in user has no shop membership.
  ///
  /// In en, this message translates to:
  /// **'No shop on this account'**
  String get activationNoShopTitle;

  /// Body for an account with no shop.
  ///
  /// In en, this message translates to:
  /// **'This account is not linked to a shop yet. Contact Dokan Pro Support for Activation.'**
  String get activationNoShopBody;

  /// Licence status pending.
  ///
  /// In en, this message translates to:
  /// **'This shop is waiting for activation by Dokan Pro Support.'**
  String get activationShopPending;

  /// Licence status suspended.
  ///
  /// In en, this message translates to:
  /// **'This shop is suspended. Billing stops once the offline grace ends. Contact Dokan Pro Support.'**
  String get activationShopSuspended;

  /// Licence status active.
  ///
  /// In en, this message translates to:
  /// **'Shop active'**
  String get activationShopActive;

  /// Subscription end date.
  ///
  /// In en, this message translates to:
  /// **'Subscription valid until {date}'**
  String activationValidUntil(String date);

  /// Subscription already ended.
  ///
  /// In en, this message translates to:
  /// **'Subscription ended on {date}. Contact Dokan Pro Support to renew.'**
  String activationExpiredOn(String date);

  /// Device registered beyond the two-device limit, e.g. after an uninstall/reinstall or cleared app data.
  ///
  /// In en, this message translates to:
  /// **'Device replacement requires admin approval. This shop already uses its device slots (1 mobile and 1 tablet), so this new registration is waiting. Contact Dokan Pro Support and give them the device code below.'**
  String get deviceApprovalPending;

  /// Short code of this device registration for support. code is 8 letters/digits, never translated.
  ///
  /// In en, this message translates to:
  /// **'Device code: {code}'**
  String deviceApprovalCode(String code);

  /// Button: re-check approval after support approved the device.
  ///
  /// In en, this message translates to:
  /// **'Check again'**
  String get deviceApprovalCheckAgain;

  /// Device rejected by support.
  ///
  /// In en, this message translates to:
  /// **'This device was not approved. Contact Dokan Pro Support.'**
  String get deviceApprovalRejected;

  /// Policy message: server refused because the shop is pending or suspended.
  ///
  /// In en, this message translates to:
  /// **'This shop is not active. Contact Dokan Pro Support.'**
  String get subMsgShopNotActive;

  /// Policy message: server refused this device.
  ///
  /// In en, this message translates to:
  /// **'This device is not approved. Contact Dokan Pro Support.'**
  String get subMsgDeviceNotApproved;

  /// Subscription state label: refused by the server.
  ///
  /// In en, this message translates to:
  /// **'Blocked'**
  String get subStateBlocked;

  /// Title of the in-app update dialog.
  ///
  /// In en, this message translates to:
  /// **'Dokan Pro update available'**
  String get updateTitle;

  /// Title when the signed release marks the update as required.
  ///
  /// In en, this message translates to:
  /// **'Dokan Pro update required'**
  String get updateRequiredTitle;

  /// version is like 1.0.3 (never translated).
  ///
  /// In en, this message translates to:
  /// **'Installed version: {version}'**
  String updateInstalledVersion(String version);

  /// version is like 1.0.4 (never translated).
  ///
  /// In en, this message translates to:
  /// **'New version: {version}'**
  String updateNewVersion(String version);

  /// size is like 45.2 MB.
  ///
  /// In en, this message translates to:
  /// **'Download size: {size}'**
  String updateDownloadSize(String size);

  /// Heading above the release notes.
  ///
  /// In en, this message translates to:
  /// **'What\'s new'**
  String get updateWhatsNew;

  /// Reassurance that updating keeps business data.
  ///
  /// In en, this message translates to:
  /// **'The app is updated in place: sales, Udhaar, products and settings stay on this device.'**
  String get updateDataSafe;

  /// Shown for required updates; the app is never locked.
  ///
  /// In en, this message translates to:
  /// **'This version is no longer supported. Please update soon. Billing and your records stay available until then.'**
  String get updateRequiredNote;

  /// Button: start downloading the update.
  ///
  /// In en, this message translates to:
  /// **'Update now'**
  String get updateNow;

  /// Button: postpone an optional update.
  ///
  /// In en, this message translates to:
  /// **'Later'**
  String get updateLater;

  /// Button on a required update: keep using the app.
  ///
  /// In en, this message translates to:
  /// **'Continue for now'**
  String get updateContinue;

  /// Button: stop the download.
  ///
  /// In en, this message translates to:
  /// **'Cancel download'**
  String get updateCancel;

  /// Button after a failed download or install.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get updateRetry;

  /// Button: close the update dialog.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get updateClose;

  /// percent is 0-100.
  ///
  /// In en, this message translates to:
  /// **'Downloading… {percent}%'**
  String updateDownloading(String percent);

  /// After download, before install.
  ///
  /// In en, this message translates to:
  /// **'Checking the downloaded file…'**
  String get updateVerifying;

  /// Android shows its own install confirmation.
  ///
  /// In en, this message translates to:
  /// **'Confirm the installation in the Android window. Dokan Pro restarts as the new version.'**
  String get updateInstalling;

  /// Android "Install unknown apps" permission needed.
  ///
  /// In en, this message translates to:
  /// **'Allow Dokan Pro to install updates'**
  String get updatePermissionTitle;

  /// The quoted switch name is Android's own (English) label.
  ///
  /// In en, this message translates to:
  /// **'Android needs your permission once. Tap Open settings, turn on \"Allow from this source\", come back and tap Update now.'**
  String get updatePermissionBody;

  /// Button: open Android install permission screen.
  ///
  /// In en, this message translates to:
  /// **'Open settings'**
  String get updateOpenSettings;

  /// Settings action.
  ///
  /// In en, this message translates to:
  /// **'Check for updates'**
  String get updateCheckNow;

  /// While the manual check runs.
  ///
  /// In en, this message translates to:
  /// **'Checking for updates…'**
  String get updateChecking;

  /// Manual check found nothing newer.
  ///
  /// In en, this message translates to:
  /// **'Dokan Pro is up to date.'**
  String get updateUpToDate;

  /// Manifest unreachable.
  ///
  /// In en, this message translates to:
  /// **'Could not check for updates. Check the internet connection and try again.'**
  String get updateErrOffline;

  /// Manifest signature or fields invalid.
  ///
  /// In en, this message translates to:
  /// **'The update information could not be verified, so nothing was changed.'**
  String get updateErrManifest;

  /// Network error or timeout during download.
  ///
  /// In en, this message translates to:
  /// **'The download did not finish. Check the internet and try again.'**
  String get updateErrDownload;

  /// Size or SHA-256 mismatch.
  ///
  /// In en, this message translates to:
  /// **'The downloaded file failed the safety check and was deleted. Try again.'**
  String get updateErrCorrupt;

  /// Wrong package or version in the APK.
  ///
  /// In en, this message translates to:
  /// **'This file is not a valid Dokan Pro update and was not installed.'**
  String get updateErrPackage;

  /// Signing certificate does not match the installed app.
  ///
  /// In en, this message translates to:
  /// **'This update is not signed by Dokan Pro and was not installed. Contact Dokan Pro Support.'**
  String get updateErrSigner;

  /// Installer failure.
  ///
  /// In en, this message translates to:
  /// **'Android could not install the update. The current app and its data are unchanged.'**
  String get updateErrInstall;

  /// User cancelled the Android confirmation.
  ///
  /// In en, this message translates to:
  /// **'Installation cancelled. You can update later.'**
  String get updateInstallCancelled;

  /// Editable product name when adding a catalog product; the catalog keeps its own name.
  ///
  /// In en, this message translates to:
  /// **'Name in your shop'**
  String get productsNameInShop;

  /// Loads the next page of catalog products.
  ///
  /// In en, this message translates to:
  /// **'Show more'**
  String get productsCatalogShowMore;

  /// Catalog product added but the shop name failed to save.
  ///
  /// In en, this message translates to:
  /// **'Product added, but its new name was not saved. Change it from My Products.'**
  String get productsAddedNameNotSaved;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ur'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ur':
      return AppLocalizationsUr();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
