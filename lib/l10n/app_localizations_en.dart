// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get languageMenuTooltip => 'Language';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageUrdu => 'اردو';

  @override
  String get urduFontHeading => 'Urdu font';

  @override
  String get urduFontNastaliq => 'Nastaliq';

  @override
  String get urduFontNaskh => 'Naskh';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonSave => 'Save';

  @override
  String get commonClose => 'Close';

  @override
  String get commonRetry => 'Retry';

  @override
  String get commonSignOut => 'Sign out';

  @override
  String get commonClear => 'Clear';

  @override
  String get commonRemove => 'Remove';

  @override
  String get commonRequiredHint => '* Required';

  @override
  String get commonLocalDataUnavailable => 'Could not open local data.';

  @override
  String get navSale => 'Sale';

  @override
  String get navProducts => 'Products';

  @override
  String get navBills => 'Bills';

  @override
  String get navKhata => 'Khata';

  @override
  String get navBackToCashierLogin => 'Back to cashier login';

  @override
  String get ownerNavDashboard => 'Owner Dashboard';

  @override
  String get ownerNavSettings => 'Settings';

  @override
  String get ownerNavSalesReturns => 'Sales & Returns';

  @override
  String get ownerNavInventory => 'Inventory';

  @override
  String get ownerNavProducts => 'Manage products';

  @override
  String get ownerNavCustomers => 'Manage customers / Khata';

  @override
  String get ownerNavPurchases => 'Suppliers & Purchases';

  @override
  String get ownerNavExpenses => 'Expenses';

  @override
  String get syncIssuesTitle => 'Sync issues';

  @override
  String get syncStatusSynced => 'Synced';

  @override
  String get syncStatusPending => 'Pending sync';

  @override
  String get syncStatusSyncing => 'Syncing';

  @override
  String get syncStatusOffline => 'Offline';

  @override
  String get syncStatusNeedsAttention => 'Needs attention';

  @override
  String get syncStatusNeedsAttentionHint =>
      'Some records could not sync. The owner can review them.';

  @override
  String get syncNoIssues => 'No sync issues.';

  @override
  String get syncNothingDeleted =>
      'Nothing here was deleted. Records stay on this device until they sync.';

  @override
  String get syncReasonFallback => 'This record could not sync.';

  @override
  String syncAttentionDetails(
    String code,
    String state,
    String time,
    String attempts,
  ) {
    return 'Code: $code • $state • $time • attempts $attempts';
  }

  @override
  String get syncStateFlagged => 'Synced, flagged';

  @override
  String get syncStateWaitingAuthorisation => 'Waiting for authorisation';

  @override
  String get syncAcknowledge => 'Acknowledge';

  @override
  String syncEntitySale(String reference) {
    return 'Sale • $reference';
  }

  @override
  String get syncEntityVoid => 'Bill void';

  @override
  String get syncEntityReturn => 'Bill return';

  @override
  String get syncEntityCustomerPayment => 'Customer payment';

  @override
  String get syncEntityPurchase => 'Purchase';

  @override
  String get syncEntitySupplierPayment => 'Supplier payment';

  @override
  String get syncEntityExpense => 'Expense';

  @override
  String get syncEntityStockAdjustment => 'Stock adjustment';

  @override
  String get syncIssuesDeviceOnly =>
      'Sync issues are available on Android and Windows.';

  @override
  String monthShort(String month) {
    String _temp0 = intl.Intl.selectLogic(month, {
      '1': 'Jan',
      '2': 'Feb',
      '3': 'Mar',
      '4': 'Apr',
      '5': 'May',
      '6': 'Jun',
      '7': 'Jul',
      '8': 'Aug',
      '9': 'Sep',
      '10': 'Oct',
      '11': 'Nov',
      '12': 'Dec',
      'other': '',
    });
    return '$_temp0';
  }

  @override
  String get timeAm => 'AM';

  @override
  String get timePm => 'PM';

  @override
  String relativeToday(String time) {
    return 'Today, $time';
  }

  @override
  String relativeYesterday(String time) {
    return 'Yesterday, $time';
  }

  @override
  String relativeTomorrow(String time) {
    return 'Tomorrow, $time';
  }

  @override
  String dateWithTime(String date, String time) {
    return '$date, $time';
  }

  @override
  String get paymentCash => 'Cash';

  @override
  String get paymentDigital => 'Digital';

  @override
  String get paymentUdhaar => 'Udhaar';

  @override
  String get paymentSplit => 'Split';

  @override
  String get paymentNone => 'No payment';

  @override
  String get unitKg => 'kg';

  @override
  String get unitGram => 'g';

  @override
  String get unitLiter => 'L';

  @override
  String get unitMilliliter => 'ml';

  @override
  String measureQuantity(String amount, String unit) {
    return '$amount $unit';
  }

  @override
  String unitPrice(String price, String unit) {
    return '$price/$unit';
  }

  @override
  String get posNewSaleHeading => 'New Sale';

  @override
  String posTodaySummary(String amount, String bills) {
    return 'Today: $amount  •  $bills bills';
  }

  @override
  String get posSearchHint => 'Search product or scan barcode';

  @override
  String get posCategoryAll => 'All';

  @override
  String get posNoProducts => 'No local products found.';

  @override
  String get posNoBarcodeMatch => 'No product matches that barcode.';

  @override
  String get posPricesChangedTitle =>
      'Prices changed since these items were added. Check the total before taking payment.';

  @override
  String posPriceChangeLine(String product, String oldPrice, String newPrice) {
    return '$product: was $oldPrice, now $newPrice';
  }

  @override
  String posCatalogTruncated(String shown, String total) {
    return 'Showing the first $shown of $total products (A–Z). Later products cannot be found or scanned here. Archive products you no longer sell.';
  }

  @override
  String posCustomersTruncated(String shown, String total) {
    return 'Only the first $shown of $total customers (A–Z) can be picked here. Ask the owner to deactivate customers who no longer buy on Udhaar.';
  }

  @override
  String get posAdd => 'Add';

  @override
  String get posUpdate => 'Update';

  @override
  String posStock(String stock) {
    return 'Stock $stock';
  }

  @override
  String posStockLow(String stock) {
    return 'Stock $stock • Low';
  }

  @override
  String posFromPrice(String price) {
    return 'From $price';
  }

  @override
  String posPackSizes(String count) {
    return '$count pack sizes';
  }

  @override
  String posPackSizesLow(String count) {
    return '$count pack sizes • Low';
  }

  @override
  String posPackOne(String count) {
    return '$count pack';
  }

  @override
  String posPackMany(String count) {
    return '$count packs';
  }

  @override
  String get posStockNotTracked => 'Stock not tracked';

  @override
  String get posNoBarcode => 'No barcode';

  @override
  String get posLowStock => 'Low stock';

  @override
  String posPriceAndStock(String price, String stock) {
    return '$price • Stock $stock';
  }

  @override
  String posLastSaleSaved(String amount, String time) {
    return 'Last sale saved on this device: $amount at $time';
  }

  @override
  String get posViewReprint => 'View / Reprint';

  @override
  String get posDismiss => 'Dismiss';

  @override
  String get posReceiptUnavailable =>
      'The receipt could not be opened. Find it in Bills.';

  @override
  String get posLogOut => 'Log out';

  @override
  String get posOpenFailed =>
      'The local POS could not be opened. Check this device’s local storage and try again.';

  @override
  String get posCurrentBill => 'Current Bill';

  @override
  String get posOpenCurrentBill => 'Open Current Bill';

  @override
  String posCurrentBillSummary(String count, String amount) {
    return 'Current Bill • $count • $amount';
  }

  @override
  String posItemCount(String count) {
    return '$count items';
  }

  @override
  String get posEmptyBill => 'Tap a product to begin a sale.';

  @override
  String get posSubtotal => 'Subtotal';

  @override
  String get posDiscount => 'Discount';

  @override
  String get posTotal => 'Total';

  @override
  String posPay(String amount) {
    return 'Pay $amount';
  }

  @override
  String get posCompleting => 'Completing…';

  @override
  String get posHoldBill => 'Hold Bill';

  @override
  String payTitle(String amount) {
    return 'Payment • $amount';
  }

  @override
  String get payCashReceived => 'Cash received';

  @override
  String get payDigitalNote =>
      'Digital payment will be recorded without a gateway.';

  @override
  String get payCashAmount => 'Cash amount';

  @override
  String get payDigitalAmount => 'Digital amount';

  @override
  String get payUdhaarAmount => 'Udhaar amount';

  @override
  String payChange(String amount) {
    return 'Change: $amount';
  }

  @override
  String get payComplete => 'Complete Sale';

  @override
  String get payUdhaarCustomer => 'Udhaar customer';

  @override
  String payExistingBalance(String amount) {
    return 'Existing balance: $amount';
  }

  @override
  String payThisSaleUdhaar(String amount) {
    return 'This sale on Udhaar: $amount';
  }

  @override
  String payNewBalance(String amount) {
    return 'New balance: $amount';
  }

  @override
  String payCreditLimit(String amount) {
    return 'Credit limit: $amount';
  }

  @override
  String get payCreditLimitExceeded =>
      'Credit limit exceeded. Ask the owner to increase the limit.';

  @override
  String get saleCompleted => 'Sale completed';

  @override
  String get saleSavedOpenFromBills =>
      'The sale is saved. Open its receipt from Bills.';

  @override
  String get saleSavedSynced => 'Saved on this tablet • Synced';

  @override
  String get saleSavedWaiting => 'Saved on this tablet • Waiting to sync';

  @override
  String get saleViewReceipt => 'View receipt';

  @override
  String get saleNew => 'New sale';

  @override
  String get saleCheckoutConflict =>
      'This sale was already saved with different details. Nothing new was recorded.';

  @override
  String get saleFailed => 'Sale could not be completed. Nothing was charged.';

  @override
  String saleErrorOther(String message) {
    return '$message';
  }

  @override
  String get saleErrCartEmpty => 'Cart must not be empty';

  @override
  String get saleErrDiscountNegative => 'Discount cannot be negative';

  @override
  String get saleErrDiscountTooHigh => 'Discount exceeds line value';

  @override
  String get saleErrInsufficientStock => 'Insufficient stock';

  @override
  String get saleErrProductName => 'Product requires a display name';

  @override
  String get saleErrTotalNegative => 'Sale total cannot be negative';

  @override
  String get saleErrShopMissing => 'Shop does not exist';

  @override
  String get saleErrCashierInactive => 'Cashier is not active for this shop';

  @override
  String get saleErrCreditCustomerInactive =>
      'Credit customer is not active for this shop';

  @override
  String get saleErrCreditNeedsCustomer => 'Credit payment requires a customer';

  @override
  String get saleErrCreditLimit => 'Customer credit limit exceeded';

  @override
  String get saleErrDeviceInactive => 'Device is not active for this shop';

  @override
  String get saleErrMeasuredUnit => 'Measured product requires kg or liter';

  @override
  String get saleErrPaymentPositive =>
      'Payment amounts must be greater than zero';

  @override
  String get saleErrPaymentTotal => 'Payment total must equal sale total';

  @override
  String get saleErrWholeUnits => 'Piece products are sold in whole units';

  @override
  String get saleErrProductInactive => 'Product is not active for this shop';

  @override
  String get saleErrPriceNegative => 'Product prices cannot be negative';

  @override
  String get saleErrQuantityPositive => 'Quantities must be greater than zero';

  @override
  String get payErrInvalid => 'Enter a valid payment.';

  @override
  String get payErrTotal => 'Payment total must equal the sale total.';

  @override
  String get payErrUdhaarCustomer => 'Select a customer for Udhaar.';

  @override
  String get payErrCashShort => 'Cash received is less than the total.';

  @override
  String get measureErrInvalid => 'Enter a valid quantity.';

  @override
  String get measureErrZero => 'Quantity must be more than zero.';

  @override
  String get measureErrTooLarge => 'Quantity is too large.';

  @override
  String measureAvailable(String quantity) {
    return 'Available $quantity';
  }

  @override
  String measureInBill(String quantity) {
    return 'In bill: $quantity';
  }

  @override
  String get measureCustomQuantity => 'Custom quantity';

  @override
  String get measureQuantityLabel => 'Quantity';

  @override
  String get measureTotalNone => 'Total —';

  @override
  String measureTotalFor(String amount, String quantity) {
    return 'Total $amount for $quantity';
  }

  @override
  String measureOnlyInStock(String available) {
    return 'Only $available in stock.';
  }

  @override
  String measureOnlyAvailable(String available) {
    return 'Only $available available.';
  }

  @override
  String get receiptTitle => 'Receipt';

  @override
  String get receiptPrint => 'Print / Reprint';

  @override
  String get receiptPrinterMissing =>
      'No receipt printer is configured. You can retry from Sales.';

  @override
  String receiptDateCashier(String dateTime, String cashier) {
    return '$dateTime • $cashier';
  }

  @override
  String receiptCustomer(String name) {
    return 'Customer: $name';
  }

  @override
  String receiptLine(String quantity, String name, String amount) {
    return '$quantity × $name  $amount';
  }

  @override
  String receiptAtPrice(String price) {
    return '@ $price';
  }

  @override
  String receiptEach(String price) {
    return '$price each';
  }

  @override
  String receiptSubtotal(String amount) {
    return 'Subtotal $amount';
  }

  @override
  String receiptDiscount(String amount) {
    return 'Discount $amount';
  }

  @override
  String receiptTotal(String amount) {
    return 'Total $amount';
  }

  @override
  String receiptReturned(String amount) {
    return 'Returned $amount';
  }

  @override
  String receiptNet(String amount) {
    return 'Net $amount';
  }

  @override
  String receiptPayment(String method, String amount) {
    return '$method: $amount';
  }

  @override
  String receiptReceived(String amount) {
    return 'Received $amount';
  }

  @override
  String receiptChange(String amount) {
    return 'Change $amount';
  }

  @override
  String get categoryHousehold => 'Household';

  @override
  String get categoryStaples => 'Staples';

  @override
  String get categoryDairy => 'Dairy';

  @override
  String get categoryCookingEssentials => 'Cooking Essentials';

  @override
  String get categoryBeverages => 'Beverages';

  @override
  String get categorySnacks => 'Snacks';

  @override
  String posPreviewTitle(String shopName) {
    return '$shopName • POS preview';
  }

  @override
  String get posPreviewAuthenticated => 'Cashier authentication successful';

  @override
  String posPreviewSignedIn(String cashierName) {
    return '$cashierName is signed in.';
  }

  @override
  String get posPreviewNote =>
      'The offline POS database is available on Android and Windows. Chrome remains an auth and onboarding preview target.';

  @override
  String get posPreviewEnd => 'End preview session';

  @override
  String get commonLoading => 'Loading…';

  @override
  String get commonTryAgain => 'Try again';

  @override
  String get commonOptional => 'Optional';

  @override
  String get commonSaving => 'Saving…';

  @override
  String get commonEdit => 'Edit';

  @override
  String get commonSearch => 'Search';

  @override
  String get commonSearching => 'Searching…';

  @override
  String get commonRefresh => 'Refresh';

  @override
  String unitName(String key, String english) {
    String _temp0 = intl.Intl.selectLogic(key, {'other': '$english'});
    return '$_temp0';
  }

  @override
  String get productsTitle => 'Products';

  @override
  String get productsTabMine => 'My Products';

  @override
  String get productsTabAdd => 'Add Product';

  @override
  String get productsOpenFailed => 'Could not open products. Please try again.';

  @override
  String get productsSaved => 'Product saved to My Products.';

  @override
  String get productsSearchLabel => 'Search name or barcode';

  @override
  String get productsCategoryLabel => 'Category';

  @override
  String get productsAllCategories => 'All categories';

  @override
  String get productsUncategorized => 'Uncategorized';

  @override
  String get productsNoMatch => 'No products match this filter.';

  @override
  String get productsLoadMore => 'Load more';

  @override
  String get productsImageNotUpdated =>
      'Product saved. The image could not be updated on this tablet.';

  @override
  String get productsImageNotSaved =>
      'Product created. The image could not be saved on this tablet.';

  @override
  String productsSaleAndPurchase(String sale, String purchase) {
    return 'Sale $sale • Purchase $purchase';
  }

  @override
  String get productsInactive => 'Inactive';

  @override
  String get productsSearchMasterCatalog => 'Search Master Catalog';

  @override
  String get productsCatalogQueryLabel => 'Product name, brand, or barcode';

  @override
  String get productsCatalogSearchFailed =>
      'Catalog search failed. Check internet and try again.';

  @override
  String get productsOpenEdit => 'Open / edit';

  @override
  String get productsCreateCustom => 'Create Custom Product';

  @override
  String get productsAddToShop => 'Add to My Shop';

  @override
  String get productsLowStockThreshold => 'Low-stock threshold';

  @override
  String get fieldPurchasePrice => 'Purchase price';

  @override
  String fieldPurchasePricePer(String unit) {
    return 'Purchase price per $unit';
  }

  @override
  String get fieldSalePrice => 'Sale price';

  @override
  String fieldSalePricePer(String unit) {
    return 'Sale price per $unit';
  }

  @override
  String get fieldOpeningStock => 'Opening stock';

  @override
  String fieldOpeningStockIn(String unit) {
    return 'Opening stock ($unit)';
  }

  @override
  String get fieldLowStockAlert => 'Low-stock alert at';

  @override
  String fieldLowStockAlertIn(String unit) {
    return 'Low-stock alert at ($unit)';
  }

  @override
  String get fieldBarcode => 'Barcode';

  @override
  String get fieldPackSize => 'Pack size';

  @override
  String get fieldPurchaseCost => 'Purchase cost';

  @override
  String get customSubtitle => 'For items that are not in the master catalog.';

  @override
  String get customCreate => 'Create Product';

  @override
  String get customCreating => 'Creating…';

  @override
  String get customProductDetails => 'Product details';

  @override
  String get sellingPiece => 'Single Piece';

  @override
  String get sellingLoose => 'Loose / Measured';

  @override
  String get sellingPackaged => 'Packaged Variants';

  @override
  String get customFamilyName => 'Product family name *';

  @override
  String get customProductName => 'Product name *';

  @override
  String get customFamilyHint => 'e.g. Tapal Danedar';

  @override
  String get customPackSizes => 'Pack sizes';

  @override
  String get customCategoryRequired => 'Category *';

  @override
  String get customUnitRequired => 'Unit *';

  @override
  String get measureWeightKg => 'Weight (kg)';

  @override
  String get measureVolumeL => 'Volume (L)';

  @override
  String get customPackLabel => 'Pack size / label';

  @override
  String get customPackLabelHint => 'e.g. 500 g';

  @override
  String get customPricingStock => 'Pricing & stock';

  @override
  String get customQuickQuantities => 'Quick quantities';

  @override
  String get customAllowCustom => 'Allow custom quantity';

  @override
  String get customAllowCustomHint =>
      'Cashier may type any amount, not only quick quantities.';

  @override
  String get imageSection => 'Product image';

  @override
  String get imageChoose => 'Choose product image';

  @override
  String get imageChange => 'Change';

  @override
  String get imageChangeSemantics => 'Change product image';

  @override
  String get imagePreviewSemantics => 'Product image preview';

  @override
  String get imageFormats => 'Optional · JPG, PNG or WebP';

  @override
  String get editTitle => 'Edit product';

  @override
  String get editLooseWeight => 'Loose product · sold by weight (kg)';

  @override
  String get editLooseVolume => 'Loose product · sold by volume (L)';

  @override
  String get editAvailability => 'Availability';

  @override
  String get editActive => 'Active';

  @override
  String get editActiveHint => 'Inactive products are hidden from sale.';

  @override
  String get dupTitle => 'This product may already exist';

  @override
  String get dupAlreadyHas => 'Your shop already has:';

  @override
  String get dupSameBarcode => '(same barcode)';

  @override
  String dupMore(String count) {
    return 'and $count more';
  }

  @override
  String get dupExplain =>
      'Creating it again makes a separate product with its own stock. Go back to edit, or create it anyway.';

  @override
  String get dupGoBack => 'Go back';

  @override
  String get dupCreateAnyway => 'Create anyway';

  @override
  String packRowTitle(String number) {
    return 'Pack size $number';
  }

  @override
  String get packRowSaved => 'Saved';

  @override
  String get packRemove => 'Remove pack size';

  @override
  String get packSizeHint => 'e.g. 250 g';

  @override
  String get packOpeningStock => 'Opening stock (packs)';

  @override
  String get packLowStock => 'Low-stock alert (packs)';

  @override
  String get packAdd => 'Add pack size';

  @override
  String presetFull(String max) {
    return 'Quick quantities full ($max)';
  }

  @override
  String get presetAdd => 'Add quick quantity';

  @override
  String get inventoryLoadFailed => 'Inventory could not be loaded.';

  @override
  String get inventoryTabCurrent => 'Current Stock';

  @override
  String get inventoryTabHistory => 'Movement History';

  @override
  String get inventorySearchLabel => 'Search product or barcode';

  @override
  String get inventoryFilterLow => 'Low';

  @override
  String get inventoryFilterOut => 'Out';

  @override
  String get inventoryNoMovements => 'No stock movements yet.';

  @override
  String get inventoryAdjustSaved => 'Stock adjustment saved locally.';

  @override
  String get inventoryAdjustFailed =>
      'Stock adjustment could not be saved. Check the quantity and try again.';

  @override
  String inventoryAdjustTitle(String name) {
    return 'Adjust $name';
  }

  @override
  String get inventoryReason => 'Reason';

  @override
  String get inventoryManualCorrection => 'Manual correction (+ / -)';

  @override
  String get inventoryQuantitySigned => 'Quantity (+ / -)';

  @override
  String get inventoryReasonNote => 'Reason / note *';

  @override
  String get inventorySaveAdjustment => 'Save Adjustment';

  @override
  String get inventoryOutOfStock => 'Out of stock';

  @override
  String get inventoryInStock => 'in stock';

  @override
  String get inventoryAdjust => 'Adjust';

  @override
  String get movementOpening => 'Opening stock';

  @override
  String get movementPurchase => 'Purchase';

  @override
  String get movementSale => 'Sale';

  @override
  String get movementVoid => 'Void';

  @override
  String get movementReturn => 'Return';

  @override
  String get movementDamage => 'Damaged / wastage';

  @override
  String get movementAdjustment => 'Adjustment';

  @override
  String get movementCorrection => 'Stock correction';

  @override
  String get inventoryWebOnly =>
      'Inventory management is available on Windows and Android.';

  @override
  String get productsWebOnly =>
      'Product management uses the native Drift catalog. Open Dukaan Pro on Windows or Android.';

  @override
  String get prodErrAlreadyInShop => 'This product is already in your shop';

  @override
  String get prodErrNameRequired => 'Product name is required';

  @override
  String get prodErrCategoryRequired => 'Category is required';

  @override
  String get prodErrFamilyNameRequired => 'Product family name is required';

  @override
  String get prodErrNoPackSize => 'Add at least one pack size';

  @override
  String get prodErrPackLabel => 'Every pack needs a size label';

  @override
  String prodErrPackTwice(String label) {
    return 'Pack size $label is listed twice';
  }

  @override
  String prodErrBarcodeUsed(String barcode) {
    return 'Barcode $barcode is already used in this shop';
  }

  @override
  String prodErrPackSalePrice(String label) {
    return 'Enter a sale price for $label';
  }

  @override
  String get prodErrPricesNegative => 'Prices cannot be negative';

  @override
  String prodErrWholePacks(String label) {
    return 'Stock for $label must be whole packs';
  }

  @override
  String get prodErrLooseUnit =>
      'Loose products are sold by weight (kg) or volume (L)';

  @override
  String prodErrPresetCount(String max) {
    return 'Use at most $max quick quantities';
  }

  @override
  String prodErrPresetCountDot(String max) {
    return 'Use at most $max quick quantities.';
  }

  @override
  String get prodErrPresetsInvalid => 'Quick quantities are not valid';

  @override
  String get prodErrStockNegative => 'Stock values cannot be negative';

  @override
  String get prodErrValues => 'Enter valid non-negative values.';

  @override
  String get prodErrRequiredFields =>
      'Complete all required fields with valid values.';

  @override
  String prodErrPackRow(String label) {
    return 'Pack $label: enter a sale price and whole-pack stock.';
  }

  @override
  String prodErrFamilyIncomplete(String label, String reason, String count) {
    return 'Pack $label was not created: $reason. $count size(s) already saved; press Create again to finish without duplicating them.';
  }

  @override
  String get prodErrNotSaved => 'it could not be saved';

  @override
  String get prodErrSaveFailed =>
      'Could not save the product. Please try again.';

  @override
  String get prodErrCreateFailed =>
      'Could not create the product. Please try again.';

  @override
  String get prodErrUpdateFailed => 'Could not update product.';

  @override
  String get prodErrImageOpen => 'Could not open that image. Try another.';

  @override
  String get prodErrImageEmpty => 'The selected file is empty.';

  @override
  String get prodErrImageTooLarge => 'The selected image is too large.';

  @override
  String get prodErrImageFormat => 'Choose a JPG, PNG or WebP product image.';

  @override
  String get presetErrDuplicate =>
      'That quick quantity is already in the list.';

  @override
  String get presetErrKeepOne => 'Keep at least one quick quantity.';

  @override
  String get inventoryErrInvalid => 'Enter a valid quantity and reason.';

  @override
  String get billsLoadFailed => 'Sales could not be loaded. Please try again.';

  @override
  String get billsNoMatch => 'No sales match these filters.';

  @override
  String get billsSearchLabel => 'Bill #, customer name or phone';

  @override
  String get billsCashier => 'Cashier';

  @override
  String get billsAllCashiers => 'All cashiers';

  @override
  String get billsToday => 'Today';

  @override
  String get billsYesterday => 'Yesterday';

  @override
  String get billsThisWeek => 'This Week';

  @override
  String get billsCustomDates => 'Custom dates';

  @override
  String get billsCustom => 'Custom';

  @override
  String get billsAllPayments => 'All payments';

  @override
  String get billsTodaySales => 'Today\'s sales';

  @override
  String billsCountOne(String count) {
    return '$count bill';
  }

  @override
  String billsCountMany(String count) {
    return '$count bills';
  }

  @override
  String saleStatus(String key, String english) {
    String _temp0 = intl.Intl.selectLogic(key, {'other': '$english'});
    return '$_temp0';
  }

  @override
  String get billWaitingToSync => 'Waiting to sync';

  @override
  String billCashier(String name) {
    return 'Cashier: $name';
  }

  @override
  String get billReturned => 'Returned';

  @override
  String get billNet => 'Net';

  @override
  String billPaidBy(String method) {
    return 'Paid by $method';
  }

  @override
  String billReturnLine(String dateTime, String reason, String amount) {
    return 'Return: $dateTime • $reason • $amount';
  }

  @override
  String billVoidReason(String reason) {
    return 'Void reason: $reason';
  }

  @override
  String get billVoid => 'Void';

  @override
  String get billReturnItems => 'Return items';

  @override
  String get salesOpenFailed => 'Sales could not be opened.';

  @override
  String get returnSaved => 'Return saved locally.';

  @override
  String get returnFailed =>
      'Return could not be saved. Check quantities and try again.';

  @override
  String returnLineLabel(String name, String quantity) {
    return '$name (sold $quantity)';
  }

  @override
  String get returnRefundMethod => 'Refund method';

  @override
  String get returnUdhaarAdjustment => 'Udhaar adjustment';

  @override
  String get returnSave => 'Save Return';

  @override
  String get commonReasonRequired => 'Reason *';

  @override
  String get voidTitle => 'Void sale';

  @override
  String get voidConfirm => 'Void Sale';

  @override
  String get voidSaved => 'Sale void recorded locally.';

  @override
  String get voidRefused =>
      'Void is allowed only for an owner within 15 minutes and before any return.';

  @override
  String get salesWebTitle => 'Sales';

  @override
  String get salesWebOnly =>
      'Sales management is available on Windows and Android.';

  @override
  String get khataSearchLabel => 'Search customer name or phone';

  @override
  String khataLoadFailed(String error) {
    return 'Could not load Khata: $error';
  }

  @override
  String get khataNoCustomers => 'No customers found.';

  @override
  String get khataNoPhone => 'No phone';

  @override
  String get khataBalanceClear => 'Clear';

  @override
  String khataDue(String amount) {
    return '$amount due';
  }

  @override
  String get khataReceivePayment => 'Receive Payment';

  @override
  String get khataBalance => 'Balance';

  @override
  String get khataCreditLimit => 'Credit limit';

  @override
  String get khataNotSet => 'Not set';

  @override
  String get khataCreditSales => 'Credit sales';

  @override
  String get khataPayments => 'Payments';

  @override
  String get khataStatement => 'Statement';

  @override
  String get khataNoEntries => 'No ledger entries yet.';

  @override
  String khataRunningBalance(String amount) {
    return 'Balance $amount';
  }

  @override
  String get ledgerSale => 'Sale';

  @override
  String get ledgerPayment => 'Payment';

  @override
  String get ledgerOpeningBalance => 'Opening balance';

  @override
  String get ledgerReturnAdjustment => 'Return adjustment';

  @override
  String get ledgerManualAdjustment => 'Manual adjustment';

  @override
  String paymentStored(String key, String english) {
    String _temp0 = intl.Intl.selectLogic(key, {'other': '$english'});
    return '$_temp0';
  }

  @override
  String get khataPaymentSaved => 'Payment saved locally and queued for sync.';

  @override
  String get khataPaymentFailed =>
      'Payment could not be recorded. Nothing was changed.';

  @override
  String get khataAmount => 'Amount';

  @override
  String get khataReferenceOptional => 'Reference (optional)';

  @override
  String get khataNoteOptional => 'Note (optional)';

  @override
  String get khataRecordPayment => 'Record Payment';

  @override
  String get customersTitle => 'Customers / Khata';

  @override
  String get customersAdd => 'Add customer';

  @override
  String get customersEdit => 'Edit customer';

  @override
  String customersOpenFailed(String error) {
    return 'Could not open customers: $error';
  }

  @override
  String get customersSearchLabel => 'Search name or phone';

  @override
  String get customersEmpty => 'No customers yet. Add the first customer.';

  @override
  String get customersSaved => 'Customer saved.';

  @override
  String get customersSaveFailed => 'Customer could not be saved.';

  @override
  String get customerName => 'Name *';

  @override
  String get customerPhone => 'Phone';

  @override
  String get customerAddress => 'Address';

  @override
  String get customerNotes => 'Notes';

  @override
  String get customerCreditLimitOptional => 'Credit limit (optional)';

  @override
  String get customersWebOnly =>
      'Customer offline management is available on Android and Windows.';

  @override
  String get khataErrAmountZero => 'Enter an amount greater than zero.';

  @override
  String khataErrExceeds(String amount) {
    return 'Payment cannot exceed $amount.';
  }

  @override
  String get customersErrRequired =>
      'Name and a valid credit limit are required.';

  @override
  String get customersRefreshWarning =>
      'Customers could not be refreshed. Showing available offline data.';

  @override
  String get purchasesTabSuppliers => 'Suppliers';

  @override
  String get purchasesTabPurchases => 'Purchases';

  @override
  String get suppliersAdd => 'Add supplier';

  @override
  String get suppliersEdit => 'Edit supplier';

  @override
  String get purchasesNew => 'New purchase';

  @override
  String get purchasesNewTitle => 'New Purchase';

  @override
  String get suppliersSearch => 'Search supplier name or phone';

  @override
  String get purchasesSearch => 'Search supplier or invoice';

  @override
  String get suppliersEmpty => 'No suppliers yet.';

  @override
  String get purchasesEmpty => 'No purchases yet.';

  @override
  String suppliersPayable(String amount) {
    return '$amount payable';
  }

  @override
  String purchaseRowDetails(String date, String reference, String count) {
    return '$date • $reference • $count items';
  }

  @override
  String get purchasesNoReference => 'No reference';

  @override
  String get purchaseStatusPaid => 'Paid';

  @override
  String get purchaseStatusPartial => 'Partial';

  @override
  String get purchaseStatusCredit => 'Credit';

  @override
  String get suppliersSaveFailed => 'Supplier could not be saved.';

  @override
  String get purchasesSaved => 'Purchase saved locally.';

  @override
  String get supplierContactPerson => 'Contact person';

  @override
  String get purchaseSupplierRequired => 'Supplier *';

  @override
  String get purchaseInvoiceReference => 'Invoice/reference';

  @override
  String get purchaseDate => 'Purchase date';

  @override
  String get purchaseAmountPaid => 'Amount paid';

  @override
  String get purchaseSave => 'Save Purchase';

  @override
  String purchaseLineQtyCost(String quantity, String cost) {
    return 'Qty $quantity @ $cost';
  }

  @override
  String get purchaseProductFallback => 'Product';

  @override
  String get purchaseItemTitle => 'Purchase item';

  @override
  String get purchaseUnitCost => 'Unit cost';

  @override
  String supplierPayableHeading(String amount) {
    return 'Payable $amount';
  }

  @override
  String supplierTotals(String purchases, String payments) {
    return 'Purchases $purchases • Payments $payments';
  }

  @override
  String get supplierPaymentTitle => 'Supplier Payment';

  @override
  String get commonReference => 'Reference';

  @override
  String get commonNote => 'Note';

  @override
  String get supplierPaymentRecord => 'Record';

  @override
  String purchaseTotals(String total, String paid, String due) {
    return 'Total $total • Paid $paid • Due $due';
  }

  @override
  String get purchasesErrSelection =>
      'Select supplier/items and enter a valid payment.';

  @override
  String get expensesAddCategory => 'Add category';

  @override
  String get expensesAdd => 'Add Expense';

  @override
  String get expensesThisMonth => 'This month';

  @override
  String get expensesSearch => 'Search description/category';

  @override
  String get expensesAnyDate => 'Any date';

  @override
  String get expensesEmpty => 'No expenses found.';

  @override
  String expensesReferenceLine(String reference) {
    return 'Reference: $reference';
  }

  @override
  String get expensesCustomCategory => 'Custom category';

  @override
  String get expensesCategoryName => 'Name';

  @override
  String get expensesCategoryFailed => 'Category could not be created.';

  @override
  String get expensesSaved => 'Expense saved locally.';

  @override
  String get expenseDescriptionRequired => 'Description *';

  @override
  String get expenseAmountRequired => 'Amount *';

  @override
  String get expenseDate => 'Expense date';

  @override
  String get expensesErrRequired => 'Complete all required fields.';

  @override
  String get expenseCatRent => 'Rent';

  @override
  String get expenseCatElectricity => 'Electricity';

  @override
  String get expenseCatGas => 'Gas';

  @override
  String get expenseCatInternet => 'Internet';

  @override
  String get expenseCatSalary => 'Salary';

  @override
  String get expenseCatTransport => 'Transport';

  @override
  String get expenseCatDelivery => 'Delivery';

  @override
  String get expenseCatMaintenance => 'Maintenance';

  @override
  String get expenseCatFoodTea => 'Food/Tea';

  @override
  String get expenseCatPackaging => 'Packaging';

  @override
  String get expenseCatMiscellaneous => 'Miscellaneous';

  @override
  String dashTitle(String shop) {
    return '$shop • Dashboard';
  }

  @override
  String get dashReportFailed => 'Could not calculate this report.';

  @override
  String reportPreset(String key, String english) {
    String _temp0 = intl.Intl.selectLogic(key, {'other': '$english'});
    return '$_temp0';
  }

  @override
  String get dashCachedNote =>
      'Cached device data • pending operations may not be reflected on other devices.';

  @override
  String dashPartialReturns(String count) {
    return '$count partially returned sale(s) are excluded. Profit is provisional until returns accounting is implemented.';
  }

  @override
  String get dashNetSalesCard => 'Net Sales';

  @override
  String get dashGrossProfit => 'Gross Profit';

  @override
  String get dashNetProfit => 'Net Profit';

  @override
  String get dashCustomerUdhaar => 'Customer Udhaar';

  @override
  String get dashSupplierPayable => 'Supplier Payable';

  @override
  String get dashLowStockCard => 'Low Stock';

  @override
  String get dashSales => 'Sales';

  @override
  String get dashGrossSales => 'Gross sales';

  @override
  String get dashReturnsVoids => 'Returns / voids';

  @override
  String get dashNetSales => 'Net sales';

  @override
  String get dashAverageBill => 'Average bill';

  @override
  String get dashUdhaarCreated => 'Udhaar created';

  @override
  String get dashPeriodPurchases => 'Period purchases';

  @override
  String get dashCreditCreated => 'Credit created';

  @override
  String get dashTransactions => 'Transactions';

  @override
  String get dashSalesVsPurchases => 'Sales vs Purchases';

  @override
  String get dashTopSales => 'Top products by sales';

  @override
  String get dashTopQuantity => 'Top products by quantity';

  @override
  String get dashTopProfit => 'Highest gross profit products';

  @override
  String get dashExpensesByCategory => 'Expenses by category';

  @override
  String get dashExpensesByMethod => 'Expenses by payment method';

  @override
  String get dashTopDebtors => 'Top customer debtors';

  @override
  String get dashTopSupplierPayable => 'Top supplier payable';

  @override
  String get dashLowStockList => 'Low stock (current / threshold)';

  @override
  String get dashNoData => 'No data';

  @override
  String dashMissingCost(String count) {
    return '$count sale lines excluded from profit because cost snapshots were invalid.';
  }

  @override
  String get dashCashierPerformance => 'Cashier performance';

  @override
  String dashCashierLine(
    String bills,
    String cash,
    String digital,
    String udhaar,
  ) {
    return '$bills bills • Cash $cash • Digital $digital • Udhaar $udhaar';
  }

  @override
  String get dashNoActivity => 'No period activity';

  @override
  String get settingsOfflineUnavailable =>
      'Settings are unavailable offline until the first sync.';

  @override
  String get settingsShowingCached => 'Showing cached settings.';

  @override
  String get settingsErrRequired =>
      'Enter a shop name and a non-negative stock threshold.';

  @override
  String get settingsSaveFailed =>
      'Could not save settings. Check your connection.';

  @override
  String get settingsSaved => 'Settings saved.';

  @override
  String get settingsSubscription => 'Subscription';

  @override
  String get settingsShopDetails => 'Shop details';

  @override
  String get settingsShopName => 'Shop name';

  @override
  String get settingsCurrency => 'Currency';

  @override
  String get settingsTimeZone => 'Time zone';

  @override
  String get settingsTimeZoneValue => 'Pakistan (Asia/Karachi)';

  @override
  String get settingsStock => 'Stock';

  @override
  String get settingsAllowNegative => 'Allow selling below zero stock';

  @override
  String get settingsDefaultLowStock => 'Default low-stock alert level';

  @override
  String get settingsReceiptFooter => 'Receipt footer';

  @override
  String get settingsPaperWidth => 'Paper width';

  @override
  String get settingsShowPhone => 'Show phone on receipt';

  @override
  String get settingsShowAddress => 'Show address on receipt';

  @override
  String get settingsNotifications => 'Notifications';

  @override
  String get settingsOwnerAlerts => 'Owner alerts';

  @override
  String get settingsAlertsHint =>
      'Alerts are not available yet. Your choice is saved for when they are.';

  @override
  String get settingsSave => 'Save settings';

  @override
  String get settingsDevices => 'Registered devices';

  @override
  String get settingsCashiers => 'Cashiers';

  @override
  String get settingsCheckingSubscription => 'Checking subscription…';

  @override
  String get subStateTrial => 'Trial active';

  @override
  String get subStateExpiringSoon => 'Expires soon';

  @override
  String get subStateOfflineGrace => 'Offline grace';

  @override
  String get subStateVerify => 'Online verification required';

  @override
  String get subStateExpired => 'Expired';

  @override
  String get subCanRecord => 'This tablet can record sales';

  @override
  String get subNeedsRenewal => 'Verification or renewal needed';

  @override
  String get subPlan => 'Plan';

  @override
  String get subUnavailable => 'Unavailable';

  @override
  String get subPeriodEnds => 'Current period ends';

  @override
  String get subOfflineUntil => 'Works offline until';

  @override
  String get subLastChecked => 'Last checked online';

  @override
  String get subNotYet => 'Not yet';

  @override
  String get subRenewUnavailable =>
      'Online renewal is not available in the app yet.';

  @override
  String get subRenew => 'Renew subscription';

  @override
  String deviceThisDevice(String name) {
    return '$name (this device)';
  }

  @override
  String deviceRegistered(String type, String date) {
    return '$type • Registered $date';
  }

  @override
  String get deviceAndroidTablet => 'Android tablet';

  @override
  String get deviceWindows => 'Windows computer';

  @override
  String get deviceMobile => 'Mobile';

  @override
  String get settingsSyncHint =>
      'Sync status for this tablet is shown at the top of the sales screen.';

  @override
  String get settingsLanguageHint =>
      'Saved on this device only. Changing it keeps you signed in.';

  @override
  String get cashierCreate => 'Create cashier';

  @override
  String get cashierDisabled => 'Disabled';

  @override
  String get cashierName => 'Cashier name';

  @override
  String get cashierNumericPin => 'Numeric PIN';

  @override
  String get cashierConfirmPin => 'Confirm PIN';

  @override
  String get purchasesErrSaveFailed =>
      'Could not save the purchase. Please try again.';

  @override
  String get expensesErrSaveFailed =>
      'Could not save the expense. Please try again.';

  @override
  String get cashierErrName => 'Enter the cashier name.';

  @override
  String get cashierErrPin => 'PIN must contain 4 to 8 digits.';

  @override
  String get cashierErrPinMismatch => 'PINs do not match.';

  @override
  String get cashierErrCreate =>
      'Could not create the cashier. Please try again.';

  @override
  String get cashierErrUpdate =>
      'Could not update the cashier. Please try again.';

  @override
  String get supplierPaymentSaved => 'Supplier payment saved locally.';

  @override
  String get supplierPaymentFailed =>
      'Supplier payment could not be recorded. Nothing was changed.';

  @override
  String get authOwnerSignIn => 'Owner sign in';

  @override
  String get authCreateOwnerAccount => 'Create owner account';

  @override
  String get authFullName => 'Full name';

  @override
  String get authEmail => 'Email';

  @override
  String get authPassword => 'Password';

  @override
  String get authPleaseWait => 'Please wait…';

  @override
  String get authSignUp => 'Sign up';

  @override
  String get authSignIn => 'Sign in';

  @override
  String get authHaveAccount => 'Have an account? Sign in';

  @override
  String get authErrWrongCredentials => 'Wrong email or password.';

  @override
  String get authErrNoConnection =>
      'No connection to the server. Check your internet and try again.';

  @override
  String get authErrSessionExpired =>
      'Your session expired. Please sign in again.';

  @override
  String get authErrSignInDetails =>
      'Could not sign in. Please check your details and try again.';

  @override
  String get authErrSignInConnection =>
      'Could not sign in. Check your connection and try again.';

  @override
  String get onboardLoadFailedTitle => 'Bootstrap failed';

  @override
  String get onboardLoadFailed =>
      'Could not load your shop. Check your connection and try again.';

  @override
  String get onboardCreateShopTitle => 'Create your shop';

  @override
  String get onboardShopPhone => 'Phone';

  @override
  String get onboardShopAddress => 'Address';

  @override
  String get onboardCreatingShop => 'Creating shop…';

  @override
  String get onboardCreateShop => 'Create shop';

  @override
  String get onboardErrCreateShop =>
      'Could not create your shop. Please try again.';

  @override
  String get deviceName => 'Device name';

  @override
  String get deviceRegistering => 'Registering…';

  @override
  String get deviceRegister => 'Register this device';

  @override
  String get deviceRevoked => 'Device is revoked.';

  @override
  String get deviceActive => 'Device active. Local sales foundation is ready.';

  @override
  String get deviceErrCheck =>
      'Could not check this device registration. Check your connection.';

  @override
  String get deviceErrRegister =>
      'Could not register this device. Check your connection.';

  @override
  String get deviceErrCashierNeedsOwner =>
      'Unlock owner mode once to set up cashier mode on this device.';

  @override
  String get deviceErrCashierSetup =>
      'Could not set up cashier mode on this device. Check your connection.';

  @override
  String get deviceErrSecureOwner =>
      'Could not secure owner mode on this device. Try again.';

  @override
  String get deviceOpenFailed => 'This device could not be opened. Try again.';

  @override
  String get deviceOwnerRemovalFailed =>
      'Owner mode could not be closed safely on this device, so cashier mode was not opened. Restart the app and try again.';

  @override
  String get deviceWarnSetupOnce =>
      'This device must be set up for cashier mode once. Ask the owner to sign in.';

  @override
  String get deviceWarnOfflineExpired =>
      'The offline cashier session expired. Connect to the internet and sign in again.';

  @override
  String get deviceWarnMismatch =>
      'Offline cashier access is unavailable because this shop or device no longer matches. Connect to the internet and sign in again.';

  @override
  String cashierLoginHeading(String shopName) {
    return 'Dukaan Pro — $shopName';
  }

  @override
  String get cashierLoadFailed => 'Could not load cashiers. Please try again.';

  @override
  String get cashierNoneCreated => 'No cashier has been created yet.';

  @override
  String get cashierNoneActive => 'No active cashier is available.';

  @override
  String get cashierAskOwner => 'Ask the owner to sign in and add a cashier.';

  @override
  String get cashierCreateFirst => 'Create first cashier';

  @override
  String get cashierManage => 'Manage cashiers';

  @override
  String get cashierHideSetup => 'Hide cashier setup';

  @override
  String get cashierSelect => 'Select cashier';

  @override
  String get cashierPin => 'PIN';

  @override
  String get cashierSigningIn => 'Signing in…';

  @override
  String get cashierStartShift => 'Start Shift / Login';

  @override
  String get cashierErrPinFormat => 'Enter the cashier’s 4 to 8 digit PIN.';

  @override
  String get cashierAuthenticated =>
      'Cashier authenticated. Offline billing remains available until local expiry.';

  @override
  String get cashierLoginFailed => 'Login failed or temporarily locked.';

  @override
  String get ownerAccessRequired => 'Owner access required';

  @override
  String get ownerLockedAskOwner =>
      'Owner mode is locked on this device. Ask the owner to unlock it.';

  @override
  String get ownerLockedEnterPassword =>
      'Owner mode is locked. Enter the owner password.';

  @override
  String get ownerPassword => 'Owner password';

  @override
  String get ownerChecking => 'Checking…';

  @override
  String get ownerUnlock => 'Unlock owner mode';

  @override
  String get ownerErrWrongPassword => 'Wrong owner password.';

  @override
  String get ownerErrCheckPassword =>
      'Could not check the password. Check your connection.';

  @override
  String get subMsgVerificationRequired =>
      'Online subscription verification is required.';

  @override
  String get subMsgProofInvalid =>
      'Stored subscription proof is invalid. Verify online.';

  @override
  String get subMsgClockChanged =>
      'Device time changed significantly. Connect online to verify.';

  @override
  String get subMsgNeedsRenewal =>
      'Shop subscription needs renewal. Please contact the owner.';

  @override
  String get subMsgGrace =>
      'Grace period active. Online verification is needed.';

  @override
  String get subMsgEndingSoon => 'Subscription ending soon.';

  @override
  String get subMsgVerified => 'Subscription verified.';

  @override
  String get syncReasonInvalid =>
      'The cloud rejected this record as invalid or out of date.';

  @override
  String get syncReasonOtherVersion =>
      'A different version of this record is already in the cloud.';

  @override
  String get syncReasonConflict =>
      'This change conflicts with the cloud and cannot be applied.';

  @override
  String get syncReasonDeviceNotAuthorised =>
      'This device or cashier is no longer authorised.';

  @override
  String get syncReasonSessionNotAuthorised =>
      'This device or session is not authorised to sync.';

  @override
  String get syncReasonSessionExpired => 'The sign-in session expired.';

  @override
  String get syncReasonSessionMissing => 'The sign-in session is missing.';

  @override
  String get syncReasonOldVersion =>
      'This record was saved by an older app version and cannot be sent safely.';

  @override
  String get syncReasonOffline =>
      'No connection to the cloud. It will retry automatically.';

  @override
  String get syncReasonTemporary =>
      'The cloud is temporarily unavailable. It will retry automatically.';

  @override
  String get syncReasonRejected => 'The cloud could not accept this record.';

  @override
  String get syncReasonParent =>
      'An earlier record it depends on needs attention.';

  @override
  String syncReasonFlagged(String rules) {
    return 'Saved in the cloud, but it broke a shop rule ($rules). Please review it.';
  }

  @override
  String get syncFlagCreditLimit => 'customer credit limit exceeded';

  @override
  String get expensesWebOnly =>
      'Offline expense management is available on Android and Windows.';

  @override
  String get purchasesWebOnly =>
      'Purchasing is available on Android and Windows.';

  @override
  String dashboardWebTitle(String shopName) {
    return '$shopName Dashboard';
  }

  @override
  String get dashboardWebOnly =>
      'Offline owner reports are available on Android and Windows.';

  @override
  String saleErrNotEnoughStock(String product, String available) {
    return 'Not enough stock for $product. Available: $available.';
  }

  @override
  String saleErrStockBelowZero(String product, String stock) {
    return 'Stock for $product is below zero ($stock). Correct the stock in Inventory before selling it.';
  }

  @override
  String get inventoryErrQuantityMissing =>
      'Enter a quantity, for example 20, +20 or -5.';

  @override
  String get inventoryErrQuantityFormat =>
      'Enter a number such as 20, +20, -5 or 2.5 (up to 3 decimals).';

  @override
  String get inventoryErrQuantityZero => 'Quantity cannot be zero.';

  @override
  String get inventoryErrQuantitySign =>
      'Enter this quantity without a minus sign. To remove stock, choose Manual correction or Damaged / wastage.';

  @override
  String get inventoryErrWholeUnits =>
      'This product is counted in whole units. Enter a whole number.';

  @override
  String get inventoryErrReasonRequired =>
      'Enter a reason for this adjustment.';

  @override
  String get inventoryErrWouldGoNegative =>
      'This adjustment would make stock negative.';

  @override
  String get inventorySaving => 'Saving…';

  @override
  String get editFamilyShared =>
      'This is one pack size. Its name and category are shared by every size and cannot be changed here yet.';

  @override
  String get editUnitLocked =>
      'The unit is fixed once the product has stock or sales.';

  @override
  String get editStockSection => 'Stock';

  @override
  String get editStockHint =>
      'Stock changes only through Adjust stock, so every change is recorded.';

  @override
  String get editAdjustStock => 'Adjust stock';

  @override
  String get editArchive => 'Archive Product';

  @override
  String archiveTitle(String name) {
    return 'Archive $name?';
  }

  @override
  String get archiveChecking => 'Checking where this product is used…';

  @override
  String archiveHistoryCounts(
    String bills,
    String purchases,
    String returns,
    String movements,
  ) {
    return 'Bill lines: $bills · Purchase lines: $purchases · Returns: $returns · Stock movements: $movements';
  }

  @override
  String get archiveHistoryExplain =>
      'This product has sales or stock history. Archiving hides it from new sales; old bills, stock history and reports keep it. You can restore it at any time.';

  @override
  String get archiveUnusedExplain =>
      'This product has no sales or stock history. Archiving hides it from new sales. You can restore it at any time.';

  @override
  String get archiveConfirm => 'Archive Product';

  @override
  String get archiveWorking => 'Archiving…';

  @override
  String archiveDone(String name) {
    return '$name archived. It is no longer sold; its history is kept.';
  }

  @override
  String get archiveFailed =>
      'Could not archive the product. Check your connection and try again.';

  @override
  String get restoreAction => 'Restore';

  @override
  String restoreDone(String name) {
    return '$name restored and available for sale.';
  }

  @override
  String get restoreFailed =>
      'Could not restore the product. Check your connection and try again.';

  @override
  String get productsStatusLabel => 'Show';

  @override
  String get productsStatusAll => 'All products';

  @override
  String get productsStatusActive => 'For sale';

  @override
  String get productsStatusArchived => 'Archived';

  @override
  String get productUrduNameAction => 'Urdu name';

  @override
  String productUrduNameTitle(String name) {
    return 'Urdu name for $name';
  }

  @override
  String get productUrduNameHint =>
      'Shown only when the app is in Urdu. The English product name is not changed.';

  @override
  String get productUrduNameAutoOff =>
      'Automatic translation is off until the translation models are downloaded in Settings. You can enter the Urdu name yourself.';

  @override
  String get productUrduNameRemove => 'Remove Urdu name';

  @override
  String get productUrduNameSaved => 'Urdu name saved';

  @override
  String get offlineTranslationHeading => 'Offline Urdu Translation';

  @override
  String get offlineTranslationUnsupported =>
      'Automatic Urdu product names work on Android tablets only. Urdu names entered by hand still work.';

  @override
  String get offlineTranslationChecking => 'Checking translation models…';

  @override
  String get offlineTranslationNotDownloaded =>
      'Models not downloaded. Download required to show product names in Urdu automatically.';

  @override
  String get offlineTranslationSize =>
      'One-time download of about 60 MB (English and Urdu models, about 30 MB each) over Wi-Fi. After that, product names are translated on this tablet without internet.';

  @override
  String get offlineTranslationDownload => 'Download Translation Models';

  @override
  String get offlineTranslationDownloading =>
      'Downloading translation models… You can keep using the app.';

  @override
  String get offlineTranslationReady =>
      'Ready for offline translation. Product names are translated on this tablet without internet.';

  @override
  String get offlineTranslationFailed =>
      'Download failed. Check the Wi-Fi connection and retry.';

  @override
  String get offlineTranslationRetry => 'Retry';

  @override
  String get offlineTranslationUseMobileData => 'Download using mobile data';

  @override
  String get offlineTranslationConfirmTitle => 'Download translation models?';

  @override
  String get offlineTranslationConfirmDownload => 'Download';

  @override
  String get offlineTranslationMachineNote =>
      'Machine translations can be wrong. Correct any name with the Urdu name button in Products.';

  @override
  String get activationContactSupport =>
      'Contact Dokan Pro Support for Activation';

  @override
  String get activationSupportNote =>
      'New shops and owner accounts are created by Dokan Pro Support.';

  @override
  String get authForgotPassword => 'Forgot password?';

  @override
  String get authResetSent =>
      'If this email has an account, a password reset link has been sent.';

  @override
  String get authResetNeedsEmail => 'Enter your email first.';

  @override
  String get activationNoShopTitle => 'No shop on this account';

  @override
  String get activationNoShopBody =>
      'This account is not linked to a shop yet. Contact Dokan Pro Support for Activation.';

  @override
  String get activationShopPending =>
      'This shop is waiting for activation by Dokan Pro Support.';

  @override
  String get activationShopSuspended =>
      'This shop is suspended. Billing stops once the offline grace ends. Contact Dokan Pro Support.';

  @override
  String get activationShopActive => 'Shop active';

  @override
  String activationValidUntil(String date) {
    return 'Subscription valid until $date';
  }

  @override
  String activationExpiredOn(String date) {
    return 'Subscription ended on $date. Contact Dokan Pro Support to renew.';
  }

  @override
  String get deviceApprovalPending =>
      'Device replacement requires admin approval. This shop already uses its device slots (1 mobile and 1 tablet), so this new registration is waiting. Contact Dokan Pro Support and give them the device code below.';

  @override
  String deviceApprovalCode(String code) {
    return 'Device code: $code';
  }

  @override
  String get deviceApprovalCheckAgain => 'Check again';

  @override
  String get deviceApprovalRejected =>
      'This device was not approved. Contact Dokan Pro Support.';

  @override
  String get subMsgShopNotActive =>
      'This shop is not active. Contact Dokan Pro Support.';

  @override
  String get subMsgDeviceNotApproved =>
      'This device is not approved. Contact Dokan Pro Support.';

  @override
  String get subStateBlocked => 'Blocked';

  @override
  String get updateTitle => 'Dokan Pro update available';

  @override
  String get updateRequiredTitle => 'Dokan Pro update required';

  @override
  String updateInstalledVersion(String version) {
    return 'Installed version: $version';
  }

  @override
  String updateNewVersion(String version) {
    return 'New version: $version';
  }

  @override
  String updateDownloadSize(String size) {
    return 'Download size: $size';
  }

  @override
  String get updateWhatsNew => 'What\'s new';

  @override
  String get updateDataSafe =>
      'The app is updated in place: sales, Udhaar, products and settings stay on this device.';

  @override
  String get updateRequiredNote =>
      'This version is no longer supported. Please update soon. Billing and your records stay available until then.';

  @override
  String get updateNow => 'Update now';

  @override
  String get updateLater => 'Later';

  @override
  String get updateContinue => 'Continue for now';

  @override
  String get updateCancel => 'Cancel download';

  @override
  String get updateRetry => 'Try again';

  @override
  String get updateClose => 'Close';

  @override
  String updateDownloading(String percent) {
    return 'Downloading… $percent%';
  }

  @override
  String get updateVerifying => 'Checking the downloaded file…';

  @override
  String get updateInstalling =>
      'Confirm the installation in the Android window. Dokan Pro restarts as the new version.';

  @override
  String get updatePermissionTitle => 'Allow Dokan Pro to install updates';

  @override
  String get updatePermissionBody =>
      'Android needs your permission once. Tap Open settings, turn on \"Allow from this source\", come back and tap Update now.';

  @override
  String get updateOpenSettings => 'Open settings';

  @override
  String get updateCheckNow => 'Check for updates';

  @override
  String get updateChecking => 'Checking for updates…';

  @override
  String get updateUpToDate => 'Dokan Pro is up to date.';

  @override
  String get updateErrOffline =>
      'Could not check for updates. Check the internet connection and try again.';

  @override
  String get updateErrManifest =>
      'The update information could not be verified, so nothing was changed.';

  @override
  String get updateErrDownload =>
      'The download did not finish. Check the internet and try again.';

  @override
  String get updateErrCorrupt =>
      'The downloaded file failed the safety check and was deleted. Try again.';

  @override
  String get updateErrPackage =>
      'This file is not a valid Dokan Pro update and was not installed.';

  @override
  String get updateErrSigner =>
      'This update is not signed by Dokan Pro and was not installed. Contact Dokan Pro Support.';

  @override
  String get updateErrInstall =>
      'Android could not install the update. The current app and its data are unchanged.';

  @override
  String get updateInstallCancelled =>
      'Installation cancelled. You can update later.';

  @override
  String get productsNameInShop => 'Name in your shop';

  @override
  String get productsCatalogShowMore => 'Show more';

  @override
  String get productsAddedNameNotSaved =>
      'Product added, but its new name was not saved. Change it from My Products.';
}
