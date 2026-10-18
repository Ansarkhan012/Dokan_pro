// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Urdu (`ur`).
class AppLocalizationsUr extends AppLocalizations {
  AppLocalizationsUr([String locale = 'ur']) : super(locale);

  @override
  String get languageMenuTooltip => 'زبان';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageUrdu => 'اردو';

  @override
  String get urduFontHeading => 'اردو فونٹ';

  @override
  String get urduFontNastaliq => 'نستعلیق';

  @override
  String get urduFontNaskh => 'نسخ';

  @override
  String get commonCancel => 'رہنے دیں';

  @override
  String get commonSave => 'محفوظ کریں';

  @override
  String get commonClose => 'بند کریں';

  @override
  String get commonRetry => 'دوبارہ کوشش کریں';

  @override
  String get commonSignOut => 'لاگ آؤٹ';

  @override
  String get commonClear => 'صاف کریں';

  @override
  String get commonRemove => 'ہٹائیں';

  @override
  String get commonRequiredHint => '* لازمی';

  @override
  String get commonLocalDataUnavailable => 'اس ڈیوائس کا ڈیٹا نہیں کھل سکا۔';

  @override
  String get navSale => 'فروخت';

  @override
  String get navProducts => 'آئٹمز';

  @override
  String get navBills => 'بل';

  @override
  String get navKhata => 'کھاتہ';

  @override
  String get navBackToCashierLogin => 'کیشیئر لاگ اِن پر واپس جائیں';

  @override
  String get ownerNavDashboard => 'مالک کا خلاصہ';

  @override
  String get ownerNavSettings => 'سیٹنگز';

  @override
  String get ownerNavSalesReturns => 'فروخت اور واپسی';

  @override
  String get ownerNavInventory => 'اسٹاک';

  @override
  String get ownerNavProducts => 'آئٹمز کا انتظام';

  @override
  String get ownerNavCustomers => 'گاہک / کھاتہ';

  @override
  String get ownerNavPurchases => 'سپلائر اور خریداری';

  @override
  String get ownerNavExpenses => 'اخراجات';

  @override
  String get syncIssuesTitle => 'سنک کے مسائل';

  @override
  String get syncStatusSynced => 'آن لائن محفوظ';

  @override
  String get syncStatusPending => 'اپ لوڈ باقی';

  @override
  String get syncStatusSyncing => 'اپ لوڈ ہو رہا ہے';

  @override
  String get syncStatusOffline => 'آف لائن';

  @override
  String get syncStatusNeedsAttention => 'توجہ درکار';

  @override
  String get syncStatusNeedsAttentionHint =>
      'کچھ ریکارڈ آن لائن محفوظ نہیں ہو سکے۔ مالک انہیں دیکھ سکتا ہے۔';

  @override
  String get syncNoIssues => 'سنک کا کوئی مسئلہ نہیں۔';

  @override
  String get syncNothingDeleted =>
      'یہاں سے کچھ بھی ڈیلیٹ نہیں ہوا۔ ریکارڈ سنک ہونے تک اسی ڈیوائس پر محفوظ رہتے ہیں۔';

  @override
  String get syncReasonFallback => 'یہ ریکارڈ سنک نہیں ہو سکا۔';

  @override
  String syncAttentionDetails(
    String code,
    String state,
    String time,
    String attempts,
  ) {
    return 'کوڈ: $code • $state • $time • کوششیں: $attempts';
  }

  @override
  String get syncStateFlagged => 'سنک ہو گیا، نشان زد';

  @override
  String get syncStateWaitingAuthorisation => 'اجازت کا انتظار';

  @override
  String get syncAcknowledge => 'دیکھ لیا';

  @override
  String syncEntitySale(String reference) {
    return 'فروخت • $reference';
  }

  @override
  String get syncEntityVoid => 'بل منسوخی';

  @override
  String get syncEntityReturn => 'بل واپسی';

  @override
  String get syncEntityCustomerPayment => 'گاہک کی ادائیگی';

  @override
  String get syncEntityPurchase => 'خریداری';

  @override
  String get syncEntitySupplierPayment => 'سپلائر کو ادائیگی';

  @override
  String get syncEntityExpense => 'خرچہ';

  @override
  String get syncEntityStockAdjustment => 'اسٹاک درستگی';

  @override
  String get syncIssuesDeviceOnly =>
      'سنک کے مسائل اینڈرائیڈ اور ونڈوز پر دیکھے جا سکتے ہیں۔';

  @override
  String monthShort(String month) {
    String _temp0 = intl.Intl.selectLogic(month, {
      '1': 'جنوری',
      '2': 'فروری',
      '3': 'مارچ',
      '4': 'اپریل',
      '5': 'مئی',
      '6': 'جون',
      '7': 'جولائی',
      '8': 'اگست',
      '9': 'ستمبر',
      '10': 'اکتوبر',
      '11': 'نومبر',
      '12': 'دسمبر',
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
    return 'آج، $time';
  }

  @override
  String relativeYesterday(String time) {
    return 'گزشتہ کل، $time';
  }

  @override
  String relativeTomorrow(String time) {
    return 'آئندہ کل، $time';
  }

  @override
  String dateWithTime(String date, String time) {
    return '$date، $time';
  }

  @override
  String get paymentCash => 'کیش';

  @override
  String get paymentDigital => 'ڈیجیٹل';

  @override
  String get paymentUdhaar => 'ادھار';

  @override
  String get paymentSplit => 'مختلف ادائیگی';

  @override
  String get paymentNone => 'کوئی ادائیگی نہیں';

  @override
  String get unitKg => 'کلو';

  @override
  String get unitGram => 'گرام';

  @override
  String get unitLiter => 'لیٹر';

  @override
  String get unitMilliliter => 'ملی لیٹر';

  @override
  String measureQuantity(String amount, String unit) {
    return '$amount $unit';
  }

  @override
  String unitPrice(String price, String unit) {
    return '$price فی $unit';
  }

  @override
  String get posNewSaleHeading => 'نئی فروخت';

  @override
  String posTodaySummary(String amount, String bills) {
    return 'آج: $amount  •  $bills بل';
  }

  @override
  String get posSearchHint => 'آئٹم تلاش کریں یا بارکوڈ اسکین کریں';

  @override
  String get posCategoryAll => 'سب';

  @override
  String get posNoProducts => 'کوئی آئٹم نہیں ملا۔';

  @override
  String get posNoBarcodeMatch => 'اس بارکوڈ کا کوئی آئٹم نہیں ملا۔';

  @override
  String get posPricesChangedTitle =>
      'یہ آئٹم شامل کرنے کے بعد قیمتیں بدل گئی ہیں۔ رقم لینے سے پہلے ٹوٹل چیک کریں۔';

  @override
  String posPriceChangeLine(String product, String oldPrice, String newPrice) {
    return '$product: پہلے $oldPrice، اب $newPrice';
  }

  @override
  String posCatalogTruncated(String shown, String total) {
    return '$total میں سے پہلے $shown آئٹم (حروفِ تہجی کے لحاظ سے) دکھائے جا رہے ہیں۔ باقی آئٹم یہاں تلاش یا اسکین نہیں ہو سکتے۔ جو آئٹم اب نہیں بکتے انہیں آرکائیو کریں۔';
  }

  @override
  String posCustomersTruncated(String shown, String total) {
    return 'یہاں $total میں سے صرف پہلے $shown گاہک (حروفِ تہجی کے لحاظ سے) منتخب ہو سکتے ہیں۔ جو گاہک اب ادھار نہیں لیتے، مالک انہیں غیر فعال کر دے۔';
  }

  @override
  String get posAdd => 'شامل کریں';

  @override
  String get posUpdate => 'تبدیل کریں';

  @override
  String posStock(String stock) {
    return 'اسٹاک $stock';
  }

  @override
  String posStockLow(String stock) {
    return 'اسٹاک $stock • کم';
  }

  @override
  String posFromPrice(String price) {
    return '$price سے شروع';
  }

  @override
  String posPackSizes(String count) {
    return 'پیک سائز: $count';
  }

  @override
  String posPackSizesLow(String count) {
    return 'پیک سائز: $count • کم';
  }

  @override
  String posPackOne(String count) {
    return '$count پیک';
  }

  @override
  String posPackMany(String count) {
    return '$count پیک';
  }

  @override
  String get posStockNotTracked => 'اسٹاک ٹریک نہیں ہوتا';

  @override
  String get posNoBarcode => 'بارکوڈ نہیں';

  @override
  String get posLowStock => 'اسٹاک کم ہے';

  @override
  String posPriceAndStock(String price, String stock) {
    return '$price • اسٹاک $stock';
  }

  @override
  String posLastSaleSaved(String amount, String time) {
    return 'اس ڈیوائس پر آخری محفوظ فروخت: $amount، وقت $time';
  }

  @override
  String get posViewReprint => 'دیکھیں / دوبارہ پرنٹ';

  @override
  String get posDismiss => 'بند کریں';

  @override
  String get posReceiptUnavailable => 'رسید نہیں کھل سکی۔ اسے بل میں دیکھیں۔';

  @override
  String get posLogOut => 'لاگ آؤٹ';

  @override
  String get posOpenFailed =>
      'یہ POS نہیں کھل سکا۔ ڈیوائس کی اسٹوریج دیکھیں اور دوبارہ کوشش کریں۔';

  @override
  String get posCurrentBill => 'موجودہ بل';

  @override
  String get posOpenCurrentBill => 'موجودہ بل کھولیں';

  @override
  String posCurrentBillSummary(String count, String amount) {
    return 'موجودہ بل • $count • $amount';
  }

  @override
  String posItemCount(String count) {
    return '$count آئٹمز';
  }

  @override
  String get posEmptyBill => 'فروخت شروع کرنے کے لیے کوئی آئٹم دبائیں۔';

  @override
  String get posSubtotal => 'ذیلی ٹوٹل';

  @override
  String get posDiscount => 'رعایت';

  @override
  String get posTotal => 'ٹوٹل';

  @override
  String posPay(String amount) {
    return 'ادائیگی $amount';
  }

  @override
  String get posCompleting => 'مکمل ہو رہی ہے…';

  @override
  String get posHoldBill => 'بل روکیں';

  @override
  String payTitle(String amount) {
    return 'ادائیگی • $amount';
  }

  @override
  String get payCashReceived => 'وصول رقم';

  @override
  String get payDigitalNote => 'ڈیجیٹل ادائیگی بغیر کسی گیٹ وے کے درج ہو گی۔';

  @override
  String get payCashAmount => 'کیش رقم';

  @override
  String get payDigitalAmount => 'ڈیجیٹل رقم';

  @override
  String get payUdhaarAmount => 'ادھار رقم';

  @override
  String payChange(String amount) {
    return 'واپس دیں: $amount';
  }

  @override
  String get payComplete => 'فروخت مکمل کریں';

  @override
  String get payUdhaarCustomer => 'ادھار والا گاہک';

  @override
  String payExistingBalance(String amount) {
    return 'پچھلا باقی: $amount';
  }

  @override
  String payThisSaleUdhaar(String amount) {
    return 'اس فروخت کا ادھار: $amount';
  }

  @override
  String payNewBalance(String amount) {
    return 'نیا باقی: $amount';
  }

  @override
  String payCreditLimit(String amount) {
    return 'ادھار کی حد: $amount';
  }

  @override
  String get payCreditLimitExceeded =>
      'ادھار کی حد سے زیادہ ہے۔ حد بڑھانے کے لیے مالک سے کہیں۔';

  @override
  String get saleCompleted => 'فروخت مکمل';

  @override
  String get saleSavedOpenFromBills =>
      'فروخت محفوظ ہو گئی۔ اس کی رسید بل میں دیکھیں۔';

  @override
  String get saleSavedSynced => 'اس ٹیبلٹ پر محفوظ • آن لائن محفوظ';

  @override
  String get saleSavedWaiting => 'اس ٹیبلٹ پر محفوظ • اپ لوڈ باقی';

  @override
  String get saleViewReceipt => 'رسید دیکھیں';

  @override
  String get saleNew => 'نئی فروخت';

  @override
  String get saleCheckoutConflict =>
      'یہ فروخت پہلے ہی مختلف تفصیلات کے ساتھ محفوظ ہو چکی ہے۔ کچھ نیا درج نہیں ہوا۔';

  @override
  String get saleFailed => 'فروخت مکمل نہیں ہو سکی۔ کوئی رقم وصول نہیں ہوئی۔';

  @override
  String saleErrorOther(String message) {
    return 'فروخت مکمل نہیں ہو سکی: $message';
  }

  @override
  String get saleErrCartEmpty => 'بل میں کوئی آئٹم نہیں۔';

  @override
  String get saleErrDiscountNegative => 'رعایت منفی نہیں ہو سکتی۔';

  @override
  String get saleErrDiscountTooHigh => 'رعایت آئٹم کی قیمت سے زیادہ ہے۔';

  @override
  String get saleErrInsufficientStock => 'اسٹاک کافی نہیں۔';

  @override
  String get saleErrProductName => 'آئٹم کا نام ضروری ہے۔';

  @override
  String get saleErrTotalNegative => 'بل کا ٹوٹل منفی نہیں ہو سکتا۔';

  @override
  String get saleErrShopMissing => 'یہ دکان موجود نہیں۔';

  @override
  String get saleErrCashierInactive => 'یہ کیشیئر اس دکان کے لیے فعال نہیں۔';

  @override
  String get saleErrCreditCustomerInactive =>
      'ادھار والا گاہک اس دکان میں فعال نہیں۔';

  @override
  String get saleErrCreditNeedsCustomer => 'ادھار کے لیے گاہک منتخب کریں۔';

  @override
  String get saleErrCreditLimit => 'گاہک کی ادھار کی حد پوری ہو چکی ہے۔';

  @override
  String get saleErrDeviceInactive => 'یہ ڈیوائس اس دکان کے لیے فعال نہیں۔';

  @override
  String get saleErrMeasuredUnit =>
      'وزن یا مقدار والے آئٹم کے لیے کلو یا لیٹر ضروری ہے۔';

  @override
  String get saleErrPaymentPositive =>
      'ادائیگی کی رقم صفر سے زیادہ ہونی چاہیے۔';

  @override
  String get saleErrPaymentTotal =>
      'ادائیگی کا ٹوٹل بل کے ٹوٹل کے برابر ہونا چاہیے۔';

  @override
  String get saleErrWholeUnits => 'عدد والے آئٹم پورے عدد میں ہی بکتے ہیں۔';

  @override
  String get saleErrProductInactive => 'یہ آئٹم اس دکان میں فعال نہیں۔';

  @override
  String get saleErrPriceNegative => 'آئٹم کی قیمت منفی نہیں ہو سکتی۔';

  @override
  String get saleErrQuantityPositive => 'مقدار صفر سے زیادہ ہونی چاہیے۔';

  @override
  String get payErrInvalid => 'درست ادائیگی درج کریں۔';

  @override
  String get payErrTotal => 'ادائیگی کا ٹوٹل بل کے ٹوٹل کے برابر ہونا چاہیے۔';

  @override
  String get payErrUdhaarCustomer => 'ادھار کے لیے گاہک منتخب کریں۔';

  @override
  String get payErrCashShort => 'وصول رقم ٹوٹل سے کم ہے۔';

  @override
  String get measureErrInvalid => 'درست مقدار درج کریں۔';

  @override
  String get measureErrZero => 'مقدار صفر سے زیادہ ہونی چاہیے۔';

  @override
  String get measureErrTooLarge => 'مقدار بہت زیادہ ہے۔';

  @override
  String measureAvailable(String quantity) {
    return 'دستیاب $quantity';
  }

  @override
  String measureInBill(String quantity) {
    return 'بل میں: $quantity';
  }

  @override
  String get measureCustomQuantity => 'اپنی مقدار';

  @override
  String get measureQuantityLabel => 'مقدار';

  @override
  String get measureTotalNone => 'ٹوٹل —';

  @override
  String measureTotalFor(String amount, String quantity) {
    return '$quantity کا ٹوٹل $amount';
  }

  @override
  String measureOnlyInStock(String available) {
    return 'اسٹاک میں صرف $available ہے۔';
  }

  @override
  String measureOnlyAvailable(String available) {
    return 'صرف $available دستیاب ہے۔';
  }

  @override
  String get receiptTitle => 'رسید';

  @override
  String get receiptPrint => 'پرنٹ / دوبارہ پرنٹ';

  @override
  String get receiptPrinterMissing =>
      'کوئی رسید پرنٹر سیٹ نہیں۔ آپ \"فروخت اور واپسی\" سے دوبارہ کوشش کر سکتے ہیں۔';

  @override
  String receiptDateCashier(String dateTime, String cashier) {
    return '$dateTime • $cashier';
  }

  @override
  String receiptCustomer(String name) {
    return 'گاہک: $name';
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
    return '$price فی عدد';
  }

  @override
  String receiptSubtotal(String amount) {
    return 'ذیلی ٹوٹل $amount';
  }

  @override
  String receiptDiscount(String amount) {
    return 'رعایت $amount';
  }

  @override
  String receiptTotal(String amount) {
    return 'ٹوٹل $amount';
  }

  @override
  String receiptReturned(String amount) {
    return 'واپس شدہ $amount';
  }

  @override
  String receiptNet(String amount) {
    return 'خالص $amount';
  }

  @override
  String receiptPayment(String method, String amount) {
    return '$method: $amount';
  }

  @override
  String receiptReceived(String amount) {
    return 'وصول $amount';
  }

  @override
  String receiptChange(String amount) {
    return 'واپس دیں $amount';
  }

  @override
  String get categoryHousehold => 'گھریلو اشیاء';

  @override
  String get categoryStaples => 'راشن';

  @override
  String get categoryDairy => 'دودھ اور ڈیری';

  @override
  String get categoryCookingEssentials => 'کھانا پکانے کا سامان';

  @override
  String get categoryBeverages => 'مشروبات';

  @override
  String get categorySnacks => 'اسنیکس';

  @override
  String posPreviewTitle(String shopName) {
    return '$shopName • POS پیش منظر';
  }

  @override
  String get posPreviewAuthenticated => 'کیشیئر کی تصدیق ہو گئی';

  @override
  String posPreviewSignedIn(String cashierName) {
    return '$cashierName لاگ اِن ہیں۔';
  }

  @override
  String get posPreviewNote =>
      'آف لائن POS ڈیٹا بیس اینڈرائیڈ اور ونڈوز پر دستیاب ہے۔ کروم صرف لاگ اِن اور ابتدائی سیٹ اپ کے پیش منظر کے لیے ہے۔';

  @override
  String get posPreviewEnd => 'پیش منظر ختم کریں';

  @override
  String get commonLoading => 'لوڈ ہو رہا ہے…';

  @override
  String get commonTryAgain => 'دوبارہ کوشش کریں';

  @override
  String get commonOptional => 'اختیاری';

  @override
  String get commonSaving => 'محفوظ ہو رہا ہے…';

  @override
  String get commonEdit => 'ترمیم';

  @override
  String get commonSearch => 'تلاش کریں';

  @override
  String get commonSearching => 'تلاش ہو رہی ہے…';

  @override
  String get commonRefresh => 'تازہ کریں';

  @override
  String unitName(String key, String english) {
    String _temp0 = intl.Intl.selectLogic(key, {
      'piece': 'عدد',
      'pack': 'پیک',
      'kg': 'کلو',
      'gram': 'گرام',
      'liter': 'لیٹر',
      'bottle': 'بوتل',
      'carton': 'کارٹن',
      'dozen': 'درجن',
      'bag': 'تھیلا',
      'other': '$english',
    });
    return '$_temp0';
  }

  @override
  String get productsTitle => 'آئٹمز';

  @override
  String get productsTabMine => 'میرے آئٹمز';

  @override
  String get productsTabAdd => 'آئٹم شامل کریں';

  @override
  String get productsOpenFailed => 'آئٹمز نہیں کھل سکے۔ دوبارہ کوشش کریں۔';

  @override
  String get productsSaved => 'آئٹم \"میرے آئٹمز\" میں محفوظ ہو گیا۔';

  @override
  String get productsSearchLabel => 'نام یا بارکوڈ سے تلاش کریں';

  @override
  String get productsCategoryLabel => 'کیٹیگری';

  @override
  String get productsAllCategories => 'تمام کیٹیگریز';

  @override
  String get productsUncategorized => 'بغیر کیٹیگری';

  @override
  String get productsNoMatch => 'اس فلٹر کے مطابق کوئی آئٹم نہیں۔';

  @override
  String get productsLoadMore => 'مزید دکھائیں';

  @override
  String get productsImageNotUpdated =>
      'آئٹم محفوظ ہو گیا، لیکن اس ٹیبلٹ پر تصویر اپ ڈیٹ نہیں ہو سکی۔';

  @override
  String get productsImageNotSaved =>
      'آئٹم بن گیا، لیکن اس ٹیبلٹ پر تصویر محفوظ نہیں ہو سکی۔';

  @override
  String productsSaleAndPurchase(String sale, String purchase) {
    return 'فروخت $sale • خرید $purchase';
  }

  @override
  String get productsInactive => 'غیر فعال';

  @override
  String get productsSearchMasterCatalog => 'ماسٹر کیٹلاگ میں تلاش کریں';

  @override
  String get productsCatalogQueryLabel => 'آئٹم کا نام، برانڈ یا بارکوڈ';

  @override
  String get productsCatalogSearchFailed =>
      'کیٹلاگ میں تلاش نہیں ہو سکی۔ انٹرنیٹ دیکھ کر دوبارہ کوشش کریں۔';

  @override
  String get productsOpenEdit => 'کھولیں / ترمیم';

  @override
  String get productsCreateCustom => 'اپنا آئٹم بنائیں';

  @override
  String get productsAddToShop => 'میری دکان میں شامل کریں';

  @override
  String get productsLowStockThreshold => 'کم اسٹاک کی حد';

  @override
  String get fieldPurchasePrice => 'قیمتِ خرید';

  @override
  String fieldPurchasePricePer(String unit) {
    return 'قیمتِ خرید فی $unit';
  }

  @override
  String get fieldSalePrice => 'قیمتِ فروخت';

  @override
  String fieldSalePricePer(String unit) {
    return 'قیمتِ فروخت فی $unit';
  }

  @override
  String get fieldOpeningStock => 'ابتدائی اسٹاک';

  @override
  String fieldOpeningStockIn(String unit) {
    return 'ابتدائی اسٹاک ($unit)';
  }

  @override
  String get fieldLowStockAlert => 'کم اسٹاک کا الرٹ';

  @override
  String fieldLowStockAlertIn(String unit) {
    return 'کم اسٹاک کا الرٹ ($unit)';
  }

  @override
  String get fieldBarcode => 'بارکوڈ';

  @override
  String get fieldPackSize => 'پیک سائز';

  @override
  String get fieldPurchaseCost => 'قیمتِ خرید';

  @override
  String get customSubtitle => 'ان آئٹمز کے لیے جو ماسٹر کیٹلاگ میں نہیں۔';

  @override
  String get customCreate => 'آئٹم بنائیں';

  @override
  String get customCreating => 'بن رہا ہے…';

  @override
  String get customProductDetails => 'آئٹم کی تفصیل';

  @override
  String get sellingPiece => 'ایک عدد';

  @override
  String get sellingLoose => 'کھلا / تول کر';

  @override
  String get sellingPackaged => 'پیک سائز والے';

  @override
  String get customFamilyName => 'آئٹم فیملی کا نام *';

  @override
  String get customProductName => 'آئٹم کا نام *';

  @override
  String get customFamilyHint => 'مثلاً Tapal Danedar';

  @override
  String get customPackSizes => 'پیک سائز';

  @override
  String get customCategoryRequired => 'کیٹیگری *';

  @override
  String get customUnitRequired => 'اکائی *';

  @override
  String get measureWeightKg => 'وزن (کلو)';

  @override
  String get measureVolumeL => 'مقدار (لیٹر)';

  @override
  String get customPackLabel => 'پیک سائز / لیبل';

  @override
  String get customPackLabelHint => 'مثلاً 500 گرام';

  @override
  String get customPricingStock => 'قیمت اور اسٹاک';

  @override
  String get customQuickQuantities => 'فوری مقداریں';

  @override
  String get customAllowCustom => 'اپنی مقدار کی اجازت';

  @override
  String get customAllowCustomHint =>
      'کیشیئر کوئی بھی مقدار لکھ سکتا ہے، صرف فوری مقداریں نہیں۔';

  @override
  String get imageSection => 'آئٹم کی تصویر';

  @override
  String get imageChoose => 'آئٹم کی تصویر منتخب کریں';

  @override
  String get imageChange => 'بدلیں';

  @override
  String get imageChangeSemantics => 'آئٹم کی تصویر بدلیں';

  @override
  String get imagePreviewSemantics => 'آئٹم کی تصویر کا پیش منظر';

  @override
  String get imageFormats => 'اختیاری · JPG، PNG یا WebP';

  @override
  String get editTitle => 'آئٹم میں ترمیم';

  @override
  String get editLooseWeight => 'کھلا آئٹم · وزن سے (کلو)';

  @override
  String get editLooseVolume => 'کھلا آئٹم · مقدار سے (لیٹر)';

  @override
  String get editAvailability => 'دستیابی';

  @override
  String get editActive => 'فعال';

  @override
  String get editActiveHint => 'غیر فعال آئٹمز فروخت میں نظر نہیں آتے۔';

  @override
  String get dupTitle => 'یہ آئٹم شاید پہلے سے موجود ہے';

  @override
  String get dupAlreadyHas => 'آپ کی دکان میں پہلے سے ہے:';

  @override
  String get dupSameBarcode => '(وہی بارکوڈ)';

  @override
  String dupMore(String count) {
    return 'اور $count مزید';
  }

  @override
  String get dupExplain =>
      'دوبارہ بنانے سے الگ آئٹم بنے گا جس کا اپنا اسٹاک ہو گا۔ ترمیم کے لیے واپس جائیں یا پھر بھی بنا لیں۔';

  @override
  String get dupGoBack => 'واپس جائیں';

  @override
  String get dupCreateAnyway => 'پھر بھی بنائیں';

  @override
  String packRowTitle(String number) {
    return 'پیک سائز $number';
  }

  @override
  String get packRowSaved => 'محفوظ';

  @override
  String get packRemove => 'پیک سائز ہٹائیں';

  @override
  String get packSizeHint => 'مثلاً 250 گرام';

  @override
  String get packOpeningStock => 'ابتدائی اسٹاک (پیک)';

  @override
  String get packLowStock => 'کم اسٹاک الرٹ (پیک)';

  @override
  String get packAdd => 'پیک سائز شامل کریں';

  @override
  String presetFull(String max) {
    return 'فوری مقداریں پوری ($max)';
  }

  @override
  String get presetAdd => 'فوری مقدار شامل کریں';

  @override
  String get inventoryLoadFailed => 'اسٹاک لوڈ نہیں ہو سکا۔';

  @override
  String get inventoryTabCurrent => 'موجودہ اسٹاک';

  @override
  String get inventoryTabHistory => 'اسٹاک کی آمد و رفت';

  @override
  String get inventorySearchLabel => 'آئٹم یا بارکوڈ تلاش کریں';

  @override
  String get inventoryFilterLow => 'کم';

  @override
  String get inventoryFilterOut => 'ختم';

  @override
  String get inventoryNoMovements => 'ابھی تک اسٹاک میں کوئی تبدیلی نہیں۔';

  @override
  String get inventoryAdjustSaved => 'اسٹاک درستگی اس ڈیوائس پر محفوظ ہو گئی۔';

  @override
  String get inventoryAdjustFailed =>
      'اسٹاک درستگی محفوظ نہیں ہو سکی۔ مقدار دیکھ کر دوبارہ کوشش کریں۔';

  @override
  String inventoryAdjustTitle(String name) {
    return '$name کا اسٹاک درست کریں';
  }

  @override
  String get inventoryReason => 'وجہ';

  @override
  String get inventoryManualCorrection => 'دستی درستگی (+ / -)';

  @override
  String get inventoryQuantitySigned => 'مقدار (+ / -)';

  @override
  String get inventoryReasonNote => 'وجہ / نوٹ *';

  @override
  String get inventorySaveAdjustment => 'درستگی محفوظ کریں';

  @override
  String get inventoryOutOfStock => 'اسٹاک ختم';

  @override
  String get inventoryInStock => 'اسٹاک میں';

  @override
  String get inventoryAdjust => 'درست کریں';

  @override
  String get movementOpening => 'ابتدائی اسٹاک';

  @override
  String get movementPurchase => 'خریداری';

  @override
  String get movementSale => 'فروخت';

  @override
  String get movementVoid => 'بل منسوخی';

  @override
  String get movementReturn => 'واپسی';

  @override
  String get movementDamage => 'خراب / ضائع';

  @override
  String get movementAdjustment => 'درستگی';

  @override
  String get movementCorrection => 'اسٹاک کی تصحیح';

  @override
  String get inventoryWebOnly =>
      'اسٹاک کا انتظام ونڈوز اور اینڈرائیڈ پر دستیاب ہے۔';

  @override
  String get productsWebOnly =>
      'آئٹمز کا انتظام ڈیوائس کے کیٹلاگ سے ہوتا ہے۔ Dukaan Pro ونڈوز یا اینڈرائیڈ پر کھولیں۔';

  @override
  String get prodErrAlreadyInShop => 'یہ آئٹم پہلے سے آپ کی دکان میں ہے';

  @override
  String get prodErrNameRequired => 'آئٹم کا نام لازمی ہے';

  @override
  String get prodErrCategoryRequired => 'کیٹیگری لازمی ہے';

  @override
  String get prodErrFamilyNameRequired => 'آئٹم فیملی کا نام لازمی ہے';

  @override
  String get prodErrNoPackSize => 'کم از کم ایک پیک سائز شامل کریں';

  @override
  String get prodErrPackLabel => 'ہر پیک کا سائز لکھیں';

  @override
  String prodErrPackTwice(String label) {
    return 'پیک سائز $label دو بار لکھا گیا ہے';
  }

  @override
  String prodErrBarcodeUsed(String barcode) {
    return 'بارکوڈ $barcode اس دکان میں پہلے سے استعمال ہو رہا ہے';
  }

  @override
  String prodErrPackSalePrice(String label) {
    return '$label کی قیمتِ فروخت درج کریں';
  }

  @override
  String get prodErrPricesNegative => 'قیمت منفی نہیں ہو سکتی';

  @override
  String prodErrWholePacks(String label) {
    return '$label کا اسٹاک پورے پیک میں ہونا چاہیے';
  }

  @override
  String get prodErrLooseUnit =>
      'کھلے آئٹم وزن (کلو) یا مقدار (لیٹر) سے بکتے ہیں';

  @override
  String prodErrPresetCount(String max) {
    return 'زیادہ سے زیادہ $max فوری مقداریں رکھیں';
  }

  @override
  String prodErrPresetCountDot(String max) {
    return 'زیادہ سے زیادہ $max فوری مقداریں رکھیں۔';
  }

  @override
  String get prodErrPresetsInvalid => 'فوری مقداریں درست نہیں';

  @override
  String get prodErrStockNegative => 'اسٹاک منفی نہیں ہو سکتا';

  @override
  String get prodErrValues => 'درست (منفی کے بغیر) قیمتیں درج کریں۔';

  @override
  String get prodErrRequiredFields =>
      'تمام لازمی خانے درست معلومات سے پُر کریں۔';

  @override
  String prodErrPackRow(String label) {
    return 'پیک $label: قیمتِ فروخت اور پورے پیک میں اسٹاک درج کریں۔';
  }

  @override
  String prodErrFamilyIncomplete(String label, String reason, String count) {
    return 'پیک $label نہیں بن سکا: $reason۔ $count سائز پہلے ہی محفوظ ہو چکے؛ دوبارہ \"آئٹم بنائیں\" دبائیں، یہ دوبارہ نہیں بنیں گے۔';
  }

  @override
  String get prodErrNotSaved => 'یہ محفوظ نہیں ہو سکا';

  @override
  String get prodErrSaveFailed => 'آئٹم محفوظ نہیں ہو سکا۔ دوبارہ کوشش کریں۔';

  @override
  String get prodErrCreateFailed => 'آئٹم نہیں بن سکا۔ دوبارہ کوشش کریں۔';

  @override
  String get prodErrUpdateFailed => 'آئٹم اپ ڈیٹ نہیں ہو سکا۔';

  @override
  String get prodErrImageOpen => 'یہ تصویر نہیں کھل سکی۔ کوئی اور منتخب کریں۔';

  @override
  String get prodErrImageEmpty => 'منتخب فائل خالی ہے۔';

  @override
  String get prodErrImageTooLarge => 'منتخب تصویر بہت بڑی ہے۔';

  @override
  String get prodErrImageFormat => 'JPG، PNG یا WebP تصویر منتخب کریں۔';

  @override
  String get presetErrDuplicate => 'یہ فوری مقدار پہلے سے فہرست میں ہے۔';

  @override
  String get presetErrKeepOne => 'کم از کم ایک فوری مقدار رکھیں۔';

  @override
  String get inventoryErrInvalid => 'درست مقدار اور وجہ درج کریں۔';

  @override
  String get billsLoadFailed => 'فروخت لوڈ نہیں ہو سکی۔ دوبارہ کوشش کریں۔';

  @override
  String get billsNoMatch => 'ان فلٹرز کے مطابق کوئی فروخت نہیں۔';

  @override
  String get billsSearchLabel => 'بل نمبر، گاہک کا نام یا فون';

  @override
  String get billsCashier => 'کیشیئر';

  @override
  String get billsAllCashiers => 'تمام کیشیئر';

  @override
  String get billsToday => 'آج';

  @override
  String get billsYesterday => 'گزشتہ کل';

  @override
  String get billsThisWeek => 'اس ہفتے';

  @override
  String get billsCustomDates => 'اپنی تاریخیں';

  @override
  String get billsCustom => 'منتخب تاریخیں';

  @override
  String get billsAllPayments => 'تمام ادائیگیاں';

  @override
  String get billsTodaySales => 'آج کی فروخت';

  @override
  String billsCountOne(String count) {
    return '$count بل';
  }

  @override
  String billsCountMany(String count) {
    return '$count بل';
  }

  @override
  String saleStatus(String key, String english) {
    String _temp0 = intl.Intl.selectLogic(key, {
      'Completed': 'مکمل',
      'Voided': 'منسوخ',
      'FullyReturned': 'مکمل واپس',
      'PartiallyReturned': 'جزوی واپس',
      'other': '$english',
    });
    return '$_temp0';
  }

  @override
  String get billWaitingToSync => 'اپ لوڈ باقی';

  @override
  String billCashier(String name) {
    return 'کیشیئر: $name';
  }

  @override
  String get billReturned => 'واپس شدہ';

  @override
  String get billNet => 'خالص';

  @override
  String billPaidBy(String method) {
    return '$method سے ادائیگی';
  }

  @override
  String billReturnLine(String dateTime, String reason, String amount) {
    return 'واپسی: $dateTime • $reason • $amount';
  }

  @override
  String billVoidReason(String reason) {
    return 'منسوخی کی وجہ: $reason';
  }

  @override
  String get billVoid => 'بل منسوخ کریں';

  @override
  String get billReturnItems => 'آئٹمز واپس لیں';

  @override
  String get salesOpenFailed => 'فروخت نہیں کھل سکی۔';

  @override
  String get returnSaved => 'واپسی اس ڈیوائس پر محفوظ ہو گئی۔';

  @override
  String get returnFailed =>
      'واپسی محفوظ نہیں ہو سکی۔ مقدار دیکھ کر دوبارہ کوشش کریں۔';

  @override
  String returnLineLabel(String name, String quantity) {
    return '$name (فروخت: $quantity)';
  }

  @override
  String get returnRefundMethod => 'رقم واپسی کا طریقہ';

  @override
  String get returnUdhaarAdjustment => 'ادھار میں کٹوتی';

  @override
  String get returnSave => 'واپسی محفوظ کریں';

  @override
  String get commonReasonRequired => 'وجہ *';

  @override
  String get voidTitle => 'بل منسوخ کریں';

  @override
  String get voidConfirm => 'بل منسوخ کریں';

  @override
  String get voidSaved => 'بل کی منسوخی اس ڈیوائس پر محفوظ ہو گئی۔';

  @override
  String get voidRefused =>
      'بل صرف مالک، 15 منٹ کے اندر اور کسی واپسی سے پہلے منسوخ کر سکتا ہے۔';

  @override
  String get salesWebTitle => 'فروخت';

  @override
  String get salesWebOnly =>
      'فروخت کا انتظام ونڈوز اور اینڈرائیڈ پر دستیاب ہے۔';

  @override
  String get khataSearchLabel => 'گاہک کا نام یا فون تلاش کریں';

  @override
  String khataLoadFailed(String error) {
    return 'کھاتہ لوڈ نہیں ہو سکا: $error';
  }

  @override
  String get khataNoCustomers => 'کوئی گاہک نہیں ملا۔';

  @override
  String get khataNoPhone => 'فون نہیں';

  @override
  String get khataBalanceClear => 'حساب صاف';

  @override
  String khataDue(String amount) {
    return '$amount باقی';
  }

  @override
  String get khataReceivePayment => 'ادائیگی وصول کریں';

  @override
  String get khataBalance => 'باقی';

  @override
  String get khataCreditLimit => 'ادھار کی حد';

  @override
  String get khataNotSet => 'مقرر نہیں';

  @override
  String get khataCreditSales => 'ادھار فروخت';

  @override
  String get khataPayments => 'ادائیگیاں';

  @override
  String get khataStatement => 'کھاتے کی تفصیل';

  @override
  String get khataNoEntries => 'ابھی کھاتے میں کوئی اندراج نہیں۔';

  @override
  String khataRunningBalance(String amount) {
    return 'باقی $amount';
  }

  @override
  String get ledgerSale => 'فروخت';

  @override
  String get ledgerPayment => 'ادائیگی';

  @override
  String get ledgerOpeningBalance => 'ابتدائی باقی';

  @override
  String get ledgerReturnAdjustment => 'واپسی کی کٹوتی';

  @override
  String get ledgerManualAdjustment => 'دستی درستگی';

  @override
  String paymentStored(String key, String english) {
    String _temp0 = intl.Intl.selectLogic(key, {
      'cash': 'کیش',
      'digital': 'ڈیجیٹل',
      'credit': 'ادھار',
      'other': '$english',
    });
    return '$_temp0';
  }

  @override
  String get khataPaymentSaved =>
      'ادائیگی اس ڈیوائس پر محفوظ ہو گئی اور سنک کے لیے قطار میں ہے۔';

  @override
  String get khataPaymentFailed =>
      'ادائیگی درج نہیں ہو سکی۔ کچھ تبدیل نہیں ہوا۔';

  @override
  String get khataAmount => 'رقم';

  @override
  String get khataReferenceOptional => 'حوالہ (اختیاری)';

  @override
  String get khataNoteOptional => 'نوٹ (اختیاری)';

  @override
  String get khataRecordPayment => 'ادائیگی درج کریں';

  @override
  String get customersTitle => 'گاہک / کھاتہ';

  @override
  String get customersAdd => 'گاہک شامل کریں';

  @override
  String get customersEdit => 'گاہک میں ترمیم';

  @override
  String customersOpenFailed(String error) {
    return 'گاہک نہیں کھل سکے: $error';
  }

  @override
  String get customersSearchLabel => 'نام یا فون تلاش کریں';

  @override
  String get customersEmpty => 'ابھی کوئی گاہک نہیں۔ پہلا گاہک شامل کریں۔';

  @override
  String get customersSaved => 'گاہک محفوظ ہو گیا۔';

  @override
  String get customersSaveFailed => 'گاہک محفوظ نہیں ہو سکا۔';

  @override
  String get customerName => 'نام *';

  @override
  String get customerPhone => 'فون';

  @override
  String get customerAddress => 'پتہ';

  @override
  String get customerNotes => 'نوٹس';

  @override
  String get customerCreditLimitOptional => 'ادھار کی حد (اختیاری)';

  @override
  String get customersWebOnly =>
      'گاہکوں کا آف لائن انتظام اینڈرائیڈ اور ونڈوز پر دستیاب ہے۔';

  @override
  String get khataErrAmountZero => 'صفر سے زیادہ رقم درج کریں۔';

  @override
  String khataErrExceeds(String amount) {
    return 'ادائیگی $amount سے زیادہ نہیں ہو سکتی۔';
  }

  @override
  String get customersErrRequired => 'نام اور درست ادھار کی حد ضروری ہے۔';

  @override
  String get customersRefreshWarning =>
      'گاہکوں کی تازہ معلومات نہیں آ سکیں۔ آف لائن ڈیٹا دکھایا جا رہا ہے۔';

  @override
  String get purchasesTabSuppliers => 'سپلائر';

  @override
  String get purchasesTabPurchases => 'خریداری';

  @override
  String get suppliersAdd => 'سپلائر شامل کریں';

  @override
  String get suppliersEdit => 'سپلائر میں ترمیم';

  @override
  String get purchasesNew => 'نئی خریداری';

  @override
  String get purchasesNewTitle => 'نئی خریداری';

  @override
  String get suppliersSearch => 'سپلائر کا نام یا فون تلاش کریں';

  @override
  String get purchasesSearch => 'سپلائر یا بل نمبر تلاش کریں';

  @override
  String get suppliersEmpty => 'ابھی کوئی سپلائر نہیں۔';

  @override
  String get purchasesEmpty => 'ابھی کوئی خریداری نہیں۔';

  @override
  String suppliersPayable(String amount) {
    return '$amount دینا باقی';
  }

  @override
  String purchaseRowDetails(String date, String reference, String count) {
    return '$date • $reference • $count آئٹمز';
  }

  @override
  String get purchasesNoReference => 'کوئی حوالہ نہیں';

  @override
  String get purchaseStatusPaid => 'ادا شدہ';

  @override
  String get purchaseStatusPartial => 'جزوی';

  @override
  String get purchaseStatusCredit => 'ادھار';

  @override
  String get suppliersSaveFailed => 'سپلائر محفوظ نہیں ہو سکا۔';

  @override
  String get purchasesSaved => 'خریداری اس ڈیوائس پر محفوظ ہو گئی۔';

  @override
  String get supplierContactPerson => 'رابطہ شخص';

  @override
  String get purchaseSupplierRequired => 'سپلائر *';

  @override
  String get purchaseInvoiceReference => 'بل نمبر / حوالہ';

  @override
  String get purchaseDate => 'خریداری کی تاریخ';

  @override
  String get purchaseAmountPaid => 'ادا شدہ رقم';

  @override
  String get purchaseSave => 'خریداری محفوظ کریں';

  @override
  String purchaseLineQtyCost(String quantity, String cost) {
    return 'مقدار $quantity @ $cost';
  }

  @override
  String get purchaseProductFallback => 'آئٹم';

  @override
  String get purchaseItemTitle => 'خریدا گیا آئٹم';

  @override
  String get purchaseUnitCost => 'فی عدد قیمتِ خرید';

  @override
  String supplierPayableHeading(String amount) {
    return 'دینا باقی: $amount';
  }

  @override
  String supplierTotals(String purchases, String payments) {
    return 'خریداری $purchases • ادائیگیاں $payments';
  }

  @override
  String get supplierPaymentTitle => 'سپلائر کو ادائیگی';

  @override
  String get commonReference => 'حوالہ';

  @override
  String get commonNote => 'نوٹ';

  @override
  String get supplierPaymentRecord => 'درج کریں';

  @override
  String purchaseTotals(String total, String paid, String due) {
    return 'ٹوٹل $total • ادا شدہ $paid • باقی $due';
  }

  @override
  String get purchasesErrSelection =>
      'سپلائر اور آئٹمز منتخب کریں اور درست ادائیگی درج کریں۔';

  @override
  String get expensesAddCategory => 'کیٹیگری شامل کریں';

  @override
  String get expensesAdd => 'خرچہ شامل کریں';

  @override
  String get expensesThisMonth => 'اس مہینے';

  @override
  String get expensesSearch => 'تفصیل یا کیٹیگری تلاش کریں';

  @override
  String get expensesAnyDate => 'کوئی بھی تاریخ';

  @override
  String get expensesEmpty => 'کوئی خرچہ نہیں ملا۔';

  @override
  String expensesReferenceLine(String reference) {
    return 'حوالہ: $reference';
  }

  @override
  String get expensesCustomCategory => 'نئی کیٹیگری';

  @override
  String get expensesCategoryName => 'نام';

  @override
  String get expensesCategoryFailed => 'کیٹیگری نہیں بن سکی۔';

  @override
  String get expensesSaved => 'خرچہ اس ڈیوائس پر محفوظ ہو گیا۔';

  @override
  String get expenseDescriptionRequired => 'تفصیل *';

  @override
  String get expenseAmountRequired => 'رقم *';

  @override
  String get expenseDate => 'خرچے کی تاریخ';

  @override
  String get expensesErrRequired => 'تمام لازمی خانے پُر کریں۔';

  @override
  String get expenseCatRent => 'کرایہ';

  @override
  String get expenseCatElectricity => 'بجلی';

  @override
  String get expenseCatGas => 'گیس';

  @override
  String get expenseCatInternet => 'انٹرنیٹ';

  @override
  String get expenseCatSalary => 'تنخواہ';

  @override
  String get expenseCatTransport => 'ٹرانسپورٹ';

  @override
  String get expenseCatDelivery => 'ڈیلیوری';

  @override
  String get expenseCatMaintenance => 'مرمت';

  @override
  String get expenseCatFoodTea => 'کھانا / چائے';

  @override
  String get expenseCatPackaging => 'پیکنگ';

  @override
  String get expenseCatMiscellaneous => 'متفرق';

  @override
  String dashTitle(String shop) {
    return '$shop • خلاصہ';
  }

  @override
  String get dashReportFailed => 'یہ رپورٹ نہیں بن سکی۔';

  @override
  String reportPreset(String key, String english) {
    String _temp0 = intl.Intl.selectLogic(key, {
      'today': 'آج',
      'week': 'یہ ہفتہ',
      'month': 'یہ مہینہ',
      'year': 'یہ سال',
      'custom': 'منتخب تاریخیں',
      'other': '$english',
    });
    return '$_temp0';
  }

  @override
  String get dashCachedNote =>
      'اس ڈیوائس کا محفوظ ڈیٹا • زیرِ التوا اندراجات دوسری ڈیوائسز پر شاید نظر نہ آئیں۔';

  @override
  String dashPartialReturns(String count) {
    return '$count جزوی واپس فروخت شامل نہیں۔ واپسی کا حساب آنے تک منافع عارضی ہے۔';
  }

  @override
  String get dashNetSalesCard => 'خالص فروخت';

  @override
  String get dashGrossProfit => 'مجموعی منافع';

  @override
  String get dashNetProfit => 'خالص منافع';

  @override
  String get dashCustomerUdhaar => 'گاہکوں کا ادھار';

  @override
  String get dashSupplierPayable => 'سپلائرز کو دینا';

  @override
  String get dashLowStockCard => 'کم اسٹاک';

  @override
  String get dashSales => 'فروخت';

  @override
  String get dashGrossSales => 'کل فروخت';

  @override
  String get dashReturnsVoids => 'واپسی / منسوخی';

  @override
  String get dashNetSales => 'خالص فروخت';

  @override
  String get dashAverageBill => 'اوسط بل';

  @override
  String get dashUdhaarCreated => 'نیا ادھار';

  @override
  String get dashPeriodPurchases => 'اس مدت کی خریداری';

  @override
  String get dashCreditCreated => 'نیا سپلائر ادھار';

  @override
  String get dashTransactions => 'لین دین';

  @override
  String get dashSalesVsPurchases => 'فروخت بمقابلہ خریداری';

  @override
  String get dashTopSales => 'سب سے زیادہ فروخت والے آئٹمز';

  @override
  String get dashTopQuantity => 'سب سے زیادہ تعداد میں بکنے والے آئٹمز';

  @override
  String get dashTopProfit => 'سب سے زیادہ منافع والے آئٹمز';

  @override
  String get dashExpensesByCategory => 'کیٹیگری کے لحاظ سے اخراجات';

  @override
  String get dashExpensesByMethod => 'ادائیگی کے طریقے کے لحاظ سے اخراجات';

  @override
  String get dashTopDebtors => 'سب سے زیادہ ادھار والے گاہک';

  @override
  String get dashTopSupplierPayable => 'سب سے زیادہ دینا (سپلائر)';

  @override
  String get dashLowStockList => 'کم اسٹاک (موجودہ / حد)';

  @override
  String get dashNoData => 'کوئی ڈیٹا نہیں';

  @override
  String dashMissingCost(String count) {
    return '$count فروخت کی لائنیں منافع سے خارج ہیں کیونکہ ان کی قیمتِ خرید درست نہیں تھی۔';
  }

  @override
  String get dashCashierPerformance => 'کیشیئرز کی کارکردگی';

  @override
  String dashCashierLine(
    String bills,
    String cash,
    String digital,
    String udhaar,
  ) {
    return '$bills بل • کیش $cash • ڈیجیٹل $digital • ادھار $udhaar';
  }

  @override
  String get dashNoActivity => 'اس مدت میں کوئی سرگرمی نہیں';

  @override
  String get settingsOfflineUnavailable =>
      'پہلی سنک تک سیٹنگز آف لائن دستیاب نہیں۔';

  @override
  String get settingsShowingCached => 'محفوظ شدہ سیٹنگز دکھائی جا رہی ہیں۔';

  @override
  String get settingsErrRequired =>
      'دکان کا نام اور درست (منفی کے بغیر) اسٹاک حد درج کریں۔';

  @override
  String get settingsSaveFailed => 'سیٹنگز محفوظ نہیں ہو سکیں۔ انٹرنیٹ دیکھیں۔';

  @override
  String get settingsSaved => 'سیٹنگز محفوظ ہو گئیں۔';

  @override
  String get settingsSubscription => 'سبسکرپشن';

  @override
  String get settingsShopDetails => 'دکان کی تفصیل';

  @override
  String get settingsShopName => 'دکان کا نام';

  @override
  String get settingsCurrency => 'کرنسی';

  @override
  String get settingsTimeZone => 'ٹائم زون';

  @override
  String get settingsTimeZoneValue => 'پاکستان (Asia/Karachi)';

  @override
  String get settingsStock => 'اسٹاک';

  @override
  String get settingsAllowNegative =>
      'اسٹاک صفر سے کم ہونے پر بھی فروخت کی اجازت';

  @override
  String get settingsDefaultLowStock => 'کم اسٹاک الرٹ کی عمومی حد';

  @override
  String get settingsReceiptFooter => 'رسید کا آخری پیغام';

  @override
  String get settingsPaperWidth => 'کاغذ کی چوڑائی';

  @override
  String get settingsShowPhone => 'رسید پر فون دکھائیں';

  @override
  String get settingsShowAddress => 'رسید پر پتہ دکھائیں';

  @override
  String get settingsNotifications => 'اطلاعات';

  @override
  String get settingsOwnerAlerts => 'مالک کے الرٹس';

  @override
  String get settingsAlertsHint =>
      'الرٹس ابھی دستیاب نہیں۔ آپ کی پسند محفوظ ہے۔';

  @override
  String get settingsSave => 'سیٹنگز محفوظ کریں';

  @override
  String get settingsDevices => 'رجسٹرڈ ڈیوائسز';

  @override
  String get settingsCashiers => 'کیشیئرز';

  @override
  String get settingsCheckingSubscription => 'سبسکرپشن چیک ہو رہی ہے…';

  @override
  String get subStateTrial => 'ٹرائل جاری';

  @override
  String get subStateExpiringSoon => 'جلد ختم ہو رہی ہے';

  @override
  String get subStateOfflineGrace => 'آف لائن مہلت';

  @override
  String get subStateVerify => 'آن لائن تصدیق ضروری';

  @override
  String get subStateExpired => 'ختم ہو چکی';

  @override
  String get subCanRecord => 'یہ ٹیبلٹ فروخت درج کر سکتا ہے';

  @override
  String get subNeedsRenewal => 'تصدیق یا تجدید ضروری';

  @override
  String get subPlan => 'پلان';

  @override
  String get subUnavailable => 'دستیاب نہیں';

  @override
  String get subPeriodEnds => 'موجودہ مدت ختم';

  @override
  String get subOfflineUntil => 'آف لائن کام کرے گا';

  @override
  String get subLastChecked => 'آخری آن لائن تصدیق';

  @override
  String get subNotYet => 'ابھی نہیں';

  @override
  String get subRenewUnavailable => 'ایپ میں آن لائن تجدید ابھی دستیاب نہیں۔';

  @override
  String get subRenew => 'سبسکرپشن کی تجدید';

  @override
  String deviceThisDevice(String name) {
    return '$name (یہ ڈیوائس)';
  }

  @override
  String deviceRegistered(String type, String date) {
    return '$type • رجسٹریشن $date';
  }

  @override
  String get deviceAndroidTablet => 'اینڈرائیڈ ٹیبلٹ';

  @override
  String get deviceWindows => 'ونڈوز کمپیوٹر';

  @override
  String get deviceMobile => 'موبائل';

  @override
  String get settingsSyncHint =>
      'اس ٹیبلٹ کی سنک کی صورتحال فروخت کی اسکرین کے اوپر نظر آتی ہے۔';

  @override
  String get settingsLanguageHint =>
      'صرف اس ڈیوائس پر محفوظ۔ زبان بدلنے سے لاگ آؤٹ نہیں ہوتا۔';

  @override
  String get cashierCreate => 'کیشیئر بنائیں';

  @override
  String get cashierDisabled => 'بند';

  @override
  String get cashierName => 'کیشیئر کا نام';

  @override
  String get cashierNumericPin => 'ہندسوں والا پن';

  @override
  String get cashierConfirmPin => 'پن دوبارہ';

  @override
  String get purchasesErrSaveFailed =>
      'خریداری محفوظ نہیں ہو سکی۔ دوبارہ کوشش کریں۔';

  @override
  String get expensesErrSaveFailed =>
      'خرچہ محفوظ نہیں ہو سکا۔ دوبارہ کوشش کریں۔';

  @override
  String get cashierErrName => 'کیشیئر کا نام درج کریں۔';

  @override
  String get cashierErrPin => 'پن میں 4 سے 8 ہندسے ہونے چاہئیں۔';

  @override
  String get cashierErrPinMismatch => 'دونوں پن ایک جیسے نہیں۔';

  @override
  String get cashierErrCreate => 'کیشیئر نہیں بن سکا۔ دوبارہ کوشش کریں۔';

  @override
  String get cashierErrUpdate => 'کیشیئر اپ ڈیٹ نہیں ہو سکا۔ دوبارہ کوشش کریں۔';

  @override
  String get supplierPaymentSaved =>
      'سپلائر کو ادائیگی اس ڈیوائس پر محفوظ ہو گئی۔';

  @override
  String get supplierPaymentFailed =>
      'سپلائر کو ادائیگی درج نہیں ہو سکی۔ کچھ تبدیل نہیں ہوا۔';

  @override
  String get authOwnerSignIn => 'مالک کا لاگ اِن';

  @override
  String get authCreateOwnerAccount => 'مالک کا اکاؤنٹ بنائیں';

  @override
  String get authFullName => 'پورا نام';

  @override
  String get authEmail => 'ای میل';

  @override
  String get authPassword => 'پاس ورڈ';

  @override
  String get authPleaseWait => 'انتظار کریں…';

  @override
  String get authSignUp => 'اکاؤنٹ بنائیں';

  @override
  String get authSignIn => 'لاگ اِن';

  @override
  String get authHaveAccount => 'اکاؤنٹ پہلے سے ہے؟ لاگ اِن کریں';

  @override
  String get authErrWrongCredentials => 'ای میل یا پاس ورڈ غلط ہے۔';

  @override
  String get authErrNoConnection =>
      'سرور سے رابطہ نہیں ہو سکا۔ انٹرنیٹ چیک کر کے دوبارہ کوشش کریں۔';

  @override
  String get authErrSessionExpired =>
      'آپ کا سیشن ختم ہو گیا۔ دوبارہ لاگ اِن کریں۔';

  @override
  String get authErrSignInDetails =>
      'لاگ اِن نہیں ہو سکا۔ اپنی معلومات چیک کر کے دوبارہ کوشش کریں۔';

  @override
  String get authErrSignInConnection =>
      'لاگ اِن نہیں ہو سکا۔ انٹرنیٹ چیک کر کے دوبارہ کوشش کریں۔';

  @override
  String get onboardLoadFailedTitle => 'دکان نہیں کھل سکی';

  @override
  String get onboardLoadFailed =>
      'آپ کی دکان لوڈ نہیں ہو سکی۔ انٹرنیٹ چیک کر کے دوبارہ کوشش کریں۔';

  @override
  String get onboardCreateShopTitle => 'اپنی دکان بنائیں';

  @override
  String get onboardShopPhone => 'فون';

  @override
  String get onboardShopAddress => 'پتہ';

  @override
  String get onboardCreatingShop => 'دکان بن رہی ہے…';

  @override
  String get onboardCreateShop => 'دکان بنائیں';

  @override
  String get onboardErrCreateShop =>
      'آپ کی دکان نہیں بن سکی۔ دوبارہ کوشش کریں۔';

  @override
  String get deviceName => 'ڈیوائس کا نام';

  @override
  String get deviceRegistering => 'رجسٹر ہو رہی ہے…';

  @override
  String get deviceRegister => 'یہ ڈیوائس رجسٹر کریں';

  @override
  String get deviceRevoked => 'یہ ڈیوائس بند کر دی گئی ہے۔';

  @override
  String get deviceActive =>
      'ڈیوائس فعال ہے۔ اس ڈیوائس پر فروخت کے لیے سب تیار ہے۔';

  @override
  String get deviceErrCheck =>
      'اس ڈیوائس کی رجسٹریشن چیک نہیں ہو سکی۔ انٹرنیٹ چیک کریں۔';

  @override
  String get deviceErrRegister =>
      'یہ ڈیوائس رجسٹر نہیں ہو سکی۔ انٹرنیٹ چیک کریں۔';

  @override
  String get deviceErrCashierNeedsOwner =>
      'اس ڈیوائس پر کیشیئر موڈ کے لیے ایک بار مالک موڈ کھولیں۔';

  @override
  String get deviceErrCashierSetup =>
      'اس ڈیوائس پر کیشیئر موڈ سیٹ نہیں ہو سکا۔ انٹرنیٹ چیک کریں۔';

  @override
  String get deviceErrSecureOwner =>
      'اس ڈیوائس پر مالک موڈ محفوظ نہیں ہو سکا۔ دوبارہ کوشش کریں۔';

  @override
  String get deviceOpenFailed => 'یہ ڈیوائس نہیں کھل سکی۔ دوبارہ کوشش کریں۔';

  @override
  String get deviceOwnerRemovalFailed =>
      'اس ڈیوائس پر مالک موڈ محفوظ طریقے سے بند نہیں ہو سکا، اس لیے کیشیئر موڈ نہیں کھولا گیا۔ ایپ دوبارہ شروع کر کے کوشش کریں۔';

  @override
  String get deviceWarnSetupOnce =>
      'اس ڈیوائس کو ایک بار کیشیئر موڈ کے لیے سیٹ کرنا ضروری ہے۔ مالک سے لاگ اِن کرنے کو کہیں۔';

  @override
  String get deviceWarnOfflineExpired =>
      'آف لائن کیشیئر سیشن ختم ہو گیا۔ انٹرنیٹ سے جڑ کر دوبارہ لاگ اِن کریں۔';

  @override
  String get deviceWarnMismatch =>
      'آف لائن کیشیئر رسائی دستیاب نہیں کیونکہ یہ دکان یا ڈیوائس اب میل نہیں کھاتی۔ انٹرنیٹ سے جڑ کر دوبارہ لاگ اِن کریں۔';

  @override
  String cashierLoginHeading(String shopName) {
    return 'Dukaan Pro — $shopName';
  }

  @override
  String get cashierLoadFailed => 'کیشیئرز لوڈ نہیں ہو سکے۔ دوبارہ کوشش کریں۔';

  @override
  String get cashierNoneCreated => 'ابھی کوئی کیشیئر نہیں بنایا گیا۔';

  @override
  String get cashierNoneActive => 'کوئی فعال کیشیئر موجود نہیں۔';

  @override
  String get cashierAskOwner =>
      'مالک سے لاگ اِن کر کے کیشیئر شامل کرنے کو کہیں۔';

  @override
  String get cashierCreateFirst => 'پہلا کیشیئر بنائیں';

  @override
  String get cashierManage => 'کیشیئرز کا انتظام';

  @override
  String get cashierHideSetup => 'کیشیئر سیٹ اپ چھپائیں';

  @override
  String get cashierSelect => 'کیشیئر منتخب کریں';

  @override
  String get cashierPin => 'پن';

  @override
  String get cashierSigningIn => 'لاگ اِن ہو رہا ہے…';

  @override
  String get cashierStartShift => 'شفٹ شروع کریں / لاگ اِن';

  @override
  String get cashierErrPinFormat => 'کیشیئر کا 4 سے 8 ہندسوں کا پن درج کریں۔';

  @override
  String get cashierAuthenticated =>
      'کیشیئر کی تصدیق ہو گئی۔ مقررہ مدت تک آف لائن بلنگ دستیاب رہے گی۔';

  @override
  String get cashierLoginFailed =>
      'لاگ اِن نہیں ہو سکا یا عارضی طور پر بند ہے۔';

  @override
  String get ownerAccessRequired => 'مالک کی اجازت ضروری ہے';

  @override
  String get ownerLockedAskOwner =>
      'اس ڈیوائس پر مالک موڈ بند ہے۔ مالک سے اسے کھولنے کو کہیں۔';

  @override
  String get ownerLockedEnterPassword =>
      'مالک موڈ بند ہے۔ مالک کا پاس ورڈ درج کریں۔';

  @override
  String get ownerPassword => 'مالک کا پاس ورڈ';

  @override
  String get ownerChecking => 'چیک ہو رہا ہے…';

  @override
  String get ownerUnlock => 'مالک موڈ کھولیں';

  @override
  String get ownerErrWrongPassword => 'مالک کا پاس ورڈ غلط ہے۔';

  @override
  String get ownerErrCheckPassword =>
      'پاس ورڈ چیک نہیں ہو سکا۔ انٹرنیٹ چیک کریں۔';

  @override
  String get subMsgVerificationRequired =>
      'سبسکرپشن کی آن لائن تصدیق ضروری ہے۔';

  @override
  String get subMsgProofInvalid =>
      'محفوظ سبسکرپشن ثبوت درست نہیں۔ آن لائن تصدیق کریں۔';

  @override
  String get subMsgClockChanged =>
      'ڈیوائس کا وقت بہت بدل گیا ہے۔ تصدیق کے لیے انٹرنیٹ سے جڑیں۔';

  @override
  String get subMsgNeedsRenewal =>
      'دکان کی سبسکرپشن کی تجدید ضروری ہے۔ مالک سے رابطہ کریں۔';

  @override
  String get subMsgGrace => 'مہلت کی مدت جاری ہے۔ آن لائن تصدیق ضروری ہے۔';

  @override
  String get subMsgEndingSoon => 'سبسکرپشن جلد ختم ہو رہی ہے۔';

  @override
  String get subMsgVerified => 'سبسکرپشن کی تصدیق ہو گئی۔';

  @override
  String get syncReasonInvalid =>
      'کلاؤڈ نے اس ریکارڈ کو غلط یا پرانا سمجھ کر مسترد کر دیا۔';

  @override
  String get syncReasonOtherVersion =>
      'اس ریکارڈ کا ایک مختلف ورژن پہلے سے کلاؤڈ میں موجود ہے۔';

  @override
  String get syncReasonConflict =>
      'یہ تبدیلی کلاؤڈ سے ٹکراتی ہے اور لاگو نہیں ہو سکتی۔';

  @override
  String get syncReasonDeviceNotAuthorised =>
      'اس ڈیوائس یا کیشیئر کو اب اجازت نہیں۔';

  @override
  String get syncReasonSessionNotAuthorised =>
      'اس ڈیوائس یا سیشن کو سنک کی اجازت نہیں۔';

  @override
  String get syncReasonSessionExpired => 'لاگ اِن سیشن ختم ہو گیا۔';

  @override
  String get syncReasonSessionMissing => 'لاگ اِن سیشن موجود نہیں۔';

  @override
  String get syncReasonOldVersion =>
      'یہ ریکارڈ ایپ کے پرانے ورژن نے محفوظ کیا تھا اور محفوظ طریقے سے بھیجا نہیں جا سکتا۔';

  @override
  String get syncReasonOffline =>
      'کلاؤڈ سے رابطہ نہیں۔ یہ خود دوبارہ کوشش کرے گا۔';

  @override
  String get syncReasonTemporary =>
      'کلاؤڈ عارضی طور پر دستیاب نہیں۔ یہ خود دوبارہ کوشش کرے گا۔';

  @override
  String get syncReasonRejected => 'کلاؤڈ یہ ریکارڈ قبول نہیں کر سکا۔';

  @override
  String get syncReasonParent =>
      'اس سے پہلے کا ایک متعلقہ ریکارڈ توجہ چاہتا ہے۔';

  @override
  String syncReasonFlagged(String rules) {
    return 'کلاؤڈ میں محفوظ ہو گیا، لیکن دکان کا ایک اصول ٹوٹا ($rules)۔ براہ کرم اسے دیکھ لیں۔';
  }

  @override
  String get syncFlagCreditLimit => 'گاہک کی ادھار حد سے زیادہ';

  @override
  String get expensesWebOnly =>
      'آف لائن خرچوں کا انتظام Android اور Windows پر دستیاب ہے۔';

  @override
  String get purchasesWebOnly => 'خریداری Android اور Windows پر دستیاب ہے۔';

  @override
  String dashboardWebTitle(String shopName) {
    return '$shopName خلاصہ';
  }

  @override
  String get dashboardWebOnly =>
      'مالک کی آف لائن رپورٹس Android اور Windows پر دستیاب ہیں۔';

  @override
  String saleErrNotEnoughStock(String product, String available) {
    return '$product کا اسٹاک کافی نہیں۔ دستیاب: $available۔';
  }

  @override
  String saleErrStockBelowZero(String product, String stock) {
    return '$product کا اسٹاک صفر سے کم ہے ($stock)۔ فروخت سے پہلے انوینٹری میں اسٹاک درست کریں۔';
  }

  @override
  String get inventoryErrQuantityMissing =>
      'مقدار درج کریں، مثلاً 20، ‎+20 یا ‎-5۔';

  @override
  String get inventoryErrQuantityFormat =>
      '20، ‎+20، ‎-5 یا 2.5 جیسا عدد درج کریں (زیادہ سے زیادہ 3 اعشاریہ)۔';

  @override
  String get inventoryErrQuantityZero => 'مقدار صفر نہیں ہو سکتی۔';

  @override
  String get inventoryErrQuantitySign =>
      'یہ مقدار منفی نشان کے بغیر درج کریں۔ اسٹاک کم کرنے کے لیے دستی درستگی یا خراب / ضائع منتخب کریں۔';

  @override
  String get inventoryErrWholeUnits =>
      'یہ آئٹم پورے عدد میں گنا جاتا ہے۔ پورا عدد درج کریں۔';

  @override
  String get inventoryErrReasonRequired => 'اس درستگی کی وجہ درج کریں۔';

  @override
  String get inventoryErrWouldGoNegative =>
      'اس درستگی سے اسٹاک منفی ہو جائے گا۔';

  @override
  String get inventorySaving => 'محفوظ ہو رہا ہے…';

  @override
  String get editFamilyShared =>
      'یہ ایک پیک سائز ہے۔ اس کا نام اور کیٹیگری ہر سائز کے لیے ایک ہی ہیں اور ابھی یہاں تبدیل نہیں ہو سکتے۔';

  @override
  String get editUnitLocked => 'اسٹاک یا فروخت کے بعد یونٹ تبدیل نہیں ہو سکتا۔';

  @override
  String get editStockSection => 'اسٹاک';

  @override
  String get editStockHint =>
      'اسٹاک صرف \"اسٹاک درست کریں\" سے بدلتا ہے، تاکہ ہر تبدیلی کا ریکارڈ رہے۔';

  @override
  String get editAdjustStock => 'اسٹاک درست کریں';

  @override
  String get editArchive => 'آئٹم آرکائیو کریں';

  @override
  String archiveTitle(String name) {
    return '$name آرکائیو کریں؟';
  }

  @override
  String get archiveChecking =>
      'دیکھا جا رہا ہے کہ یہ آئٹم کہاں استعمال ہوا ہے…';

  @override
  String archiveHistoryCounts(
    String bills,
    String purchases,
    String returns,
    String movements,
  ) {
    return 'بل کی لائنیں: $bills · خریداری کی لائنیں: $purchases · واپسیاں: $returns · اسٹاک تبدیلیاں: $movements';
  }

  @override
  String get archiveHistoryExplain =>
      'اس آئٹم کی فروخت یا اسٹاک کا ریکارڈ موجود ہے۔ آرکائیو کرنے سے یہ نئی فروخت میں نظر نہیں آئے گا؛ پرانے بل، اسٹاک ریکارڈ اور رپورٹس میں یہ موجود رہے گا۔ آپ اسے کسی بھی وقت بحال کر سکتے ہیں۔';

  @override
  String get archiveUnusedExplain =>
      'اس آئٹم کی کوئی فروخت یا اسٹاک ریکارڈ نہیں۔ آرکائیو کرنے سے یہ نئی فروخت میں نظر نہیں آئے گا۔ آپ اسے کسی بھی وقت بحال کر سکتے ہیں۔';

  @override
  String get archiveConfirm => 'آئٹم آرکائیو کریں';

  @override
  String get archiveWorking => 'آرکائیو ہو رہا ہے…';

  @override
  String archiveDone(String name) {
    return '$name آرکائیو ہو گیا۔ یہ اب فروخت نہیں ہو گا؛ اس کا ریکارڈ محفوظ ہے۔';
  }

  @override
  String get archiveFailed =>
      'آئٹم آرکائیو نہیں ہو سکا۔ انٹرنیٹ چیک کر کے دوبارہ کوشش کریں۔';

  @override
  String get restoreAction => 'بحال کریں';

  @override
  String restoreDone(String name) {
    return '$name بحال ہو گیا اور فروخت کے لیے دستیاب ہے۔';
  }

  @override
  String get restoreFailed =>
      'آئٹم بحال نہیں ہو سکا۔ انٹرنیٹ چیک کر کے دوبارہ کوشش کریں۔';

  @override
  String get productsStatusLabel => 'دکھائیں';

  @override
  String get productsStatusAll => 'تمام آئٹمز';

  @override
  String get productsStatusActive => 'فروخت کے لیے';

  @override
  String get productsStatusArchived => 'آرکائیو شدہ';

  @override
  String get productUrduNameAction => 'اردو نام';

  @override
  String productUrduNameTitle(String name) {
    return '$name کا اردو نام';
  }

  @override
  String get productUrduNameHint =>
      'یہ نام صرف اردو زبان میں دکھایا جائے گا۔ انگریزی نام تبدیل نہیں ہوگا۔';

  @override
  String get productUrduNameAutoOff =>
      'سیٹنگز میں ترجمے کے ماڈل ڈاؤن لوڈ ہونے تک خودکار ترجمہ بند ہے۔ آپ اردو نام خود لکھ سکتے ہیں۔';

  @override
  String get productUrduNameRemove => 'اردو نام ہٹائیں';

  @override
  String get productUrduNameSaved => 'اردو نام محفوظ ہو گیا';

  @override
  String get offlineTranslationHeading => 'آف لائن اردو ترجمہ';

  @override
  String get offlineTranslationUnsupported =>
      'خودکار اردو نام صرف اینڈرائیڈ ٹیبلٹ پر کام کرتے ہیں۔ ہاتھ سے لکھے اردو نام پھر بھی کام کرتے ہیں۔';

  @override
  String get offlineTranslationChecking => 'ترجمے کے ماڈل چیک ہو رہے ہیں…';

  @override
  String get offlineTranslationNotDownloaded =>
      'ماڈل ڈاؤن لوڈ نہیں ہوئے۔ پروڈکٹ کے نام خودکار طور پر اردو میں دکھانے کے لیے ڈاؤن لوڈ ضروری ہے۔';

  @override
  String get offlineTranslationSize =>
      'وائی فائی پر ایک بار تقریباً 60 MB کا ڈاؤن لوڈ (انگریزی اور اردو ماڈل، ہر ایک تقریباً 30 MB)۔ اس کے بعد پروڈکٹ کے نام اسی ٹیبلٹ پر انٹرنیٹ کے بغیر ترجمہ ہوں گے۔';

  @override
  String get offlineTranslationDownload => 'ترجمے کے ماڈل ڈاؤن لوڈ کریں';

  @override
  String get offlineTranslationDownloading =>
      'ترجمے کے ماڈل ڈاؤن لوڈ ہو رہے ہیں… آپ ایپ استعمال کرتے رہیں۔';

  @override
  String get offlineTranslationReady =>
      'آف لائن ترجمے کے لیے تیار۔ پروڈکٹ کے نام اسی ٹیبلٹ پر انٹرنیٹ کے بغیر ترجمہ ہوتے ہیں۔';

  @override
  String get offlineTranslationFailed =>
      'ڈاؤن لوڈ ناکام۔ وائی فائی کنکشن چیک کر کے دوبارہ کوشش کریں۔';

  @override
  String get offlineTranslationRetry => 'دوبارہ کوشش کریں';

  @override
  String get offlineTranslationUseMobileData => 'موبائل ڈیٹا سے ڈاؤن لوڈ کریں';

  @override
  String get offlineTranslationConfirmTitle => 'ترجمے کے ماڈل ڈاؤن لوڈ کریں؟';

  @override
  String get offlineTranslationConfirmDownload => 'ڈاؤن لوڈ کریں';

  @override
  String get offlineTranslationMachineNote =>
      'مشینی ترجمہ غلط بھی ہو سکتا ہے۔ کسی بھی نام کو پروڈکٹس میں اردو نام کے بٹن سے درست کریں۔';

  @override
  String get activationContactSupport =>
      'ایکٹیویشن کے لیے دکان پرو سپورٹ سے رابطہ کریں';

  @override
  String get activationSupportNote =>
      'نئی دکانیں اور مالک کے اکاؤنٹ دکان پرو سپورٹ بناتی ہے۔';

  @override
  String get authForgotPassword => 'پاس ورڈ بھول گئے؟';

  @override
  String get authResetSent =>
      'اگر اس ای میل کا اکاؤنٹ موجود ہے تو پاس ورڈ بدلنے کا لنک بھیج دیا گیا ہے۔';

  @override
  String get authResetNeedsEmail => 'پہلے اپنی ای میل لکھیں۔';

  @override
  String get activationNoShopTitle => 'اس اکاؤنٹ پر کوئی دکان نہیں';

  @override
  String get activationNoShopBody =>
      'یہ اکاؤنٹ ابھی کسی دکان سے منسلک نہیں۔ ایکٹیویشن کے لیے دکان پرو سپورٹ سے رابطہ کریں۔';

  @override
  String get activationShopPending =>
      'یہ دکان دکان پرو سپورٹ کی طرف سے ایکٹیویشن کی منتظر ہے۔';

  @override
  String get activationShopSuspended =>
      'یہ دکان معطل ہے۔ آف لائن مہلت ختم ہوتے ہی بلنگ رک جائے گی۔ دکان پرو سپورٹ سے رابطہ کریں۔';

  @override
  String get activationShopActive => 'دکان فعال ہے';

  @override
  String activationValidUntil(String date) {
    return 'سبسکرپشن $date تک درست ہے';
  }

  @override
  String activationExpiredOn(String date) {
    return 'سبسکرپشن $date کو ختم ہو گئی۔ تجدید کے لیے دکان پرو سپورٹ سے رابطہ کریں۔';
  }

  @override
  String get deviceApprovalPending =>
      'ڈیوائس بدلنے کے لیے ایڈمن کی منظوری ضروری ہے۔ اس دکان کی ڈیوائس جگہیں (ایک موبائل اور ایک ٹیبلٹ) پہلے سے استعمال میں ہیں، اس لیے یہ نئی رجسٹریشن منظوری کی منتظر ہے۔ دکان پرو سپورٹ سے رابطہ کریں اور نیچے دیا گیا ڈیوائس کوڈ بتائیں۔';

  @override
  String deviceApprovalCode(String code) {
    return 'ڈیوائس کوڈ: $code';
  }

  @override
  String get deviceApprovalCheckAgain => 'دوبارہ چیک کریں';

  @override
  String get deviceApprovalRejected =>
      'یہ ڈیوائس منظور نہیں ہوئی۔ دکان پرو سپورٹ سے رابطہ کریں۔';

  @override
  String get subMsgShopNotActive =>
      'یہ دکان فعال نہیں۔ دکان پرو سپورٹ سے رابطہ کریں۔';

  @override
  String get subMsgDeviceNotApproved =>
      'یہ ڈیوائس منظور شدہ نہیں۔ دکان پرو سپورٹ سے رابطہ کریں۔';

  @override
  String get subStateBlocked => 'بند';

  @override
  String get updateTitle => 'دکان پرو کا نیا ورژن دستیاب ہے';

  @override
  String get updateRequiredTitle => 'دکان پرو کی اپ ڈیٹ ضروری ہے';

  @override
  String updateInstalledVersion(String version) {
    return 'موجودہ ورژن: $version';
  }

  @override
  String updateNewVersion(String version) {
    return 'نیا ورژن: $version';
  }

  @override
  String updateDownloadSize(String size) {
    return 'ڈاؤن لوڈ سائز: $size';
  }

  @override
  String get updateWhatsNew => 'اس ورژن میں نیا کیا ہے';

  @override
  String get updateDataSafe =>
      'ایپ اپنی جگہ اپ ڈیٹ ہوتی ہے: فروخت، اُدھار، اشیاء اور سیٹنگز اسی ڈیوائس پر محفوظ رہتی ہیں۔';

  @override
  String get updateRequiredNote =>
      'یہ ورژن اب سپورٹ نہیں ہوتا۔ جلد اپ ڈیٹ کریں۔ تب تک بلنگ اور آپ کا ریکارڈ دستیاب رہے گا۔';

  @override
  String get updateNow => 'ابھی اپ ڈیٹ کریں';

  @override
  String get updateLater => 'بعد میں';

  @override
  String get updateContinue => 'ابھی جاری رکھیں';

  @override
  String get updateCancel => 'ڈاؤن لوڈ منسوخ کریں';

  @override
  String get updateRetry => 'دوبارہ کوشش کریں';

  @override
  String get updateClose => 'بند کریں';

  @override
  String updateDownloading(String percent) {
    return 'ڈاؤن لوڈ ہو رہا ہے… $percent%';
  }

  @override
  String get updateVerifying => 'ڈاؤن لوڈ کی گئی فائل کی جانچ ہو رہی ہے…';

  @override
  String get updateInstalling =>
      'اینڈرائیڈ کی ونڈو میں انسٹالیشن کی تصدیق کریں۔ دکان پرو نئے ورژن کے ساتھ دوبارہ کھلے گی۔';

  @override
  String get updatePermissionTitle =>
      'دکان پرو کو اپ ڈیٹ انسٹال کرنے کی اجازت دیں';

  @override
  String get updatePermissionBody =>
      'اینڈرائیڈ کو ایک بار آپ کی اجازت درکار ہے۔ سیٹنگز کھولیں، \"Allow from this source\" آن کریں، واپس آئیں اور \"ابھی اپ ڈیٹ کریں\" دبائیں۔';

  @override
  String get updateOpenSettings => 'سیٹنگز کھولیں';

  @override
  String get updateCheckNow => 'اپ ڈیٹ چیک کریں';

  @override
  String get updateChecking => 'اپ ڈیٹ چیک ہو رہی ہے…';

  @override
  String get updateUpToDate => 'دکان پرو تازہ ترین ورژن پر ہے۔';

  @override
  String get updateErrOffline =>
      'اپ ڈیٹ چیک نہیں ہو سکی۔ انٹرنیٹ کنکشن دیکھ کر دوبارہ کوشش کریں۔';

  @override
  String get updateErrManifest =>
      'اپ ڈیٹ کی معلومات کی تصدیق نہیں ہو سکی، اس لیے کچھ تبدیل نہیں ہوا۔';

  @override
  String get updateErrDownload =>
      'ڈاؤن لوڈ مکمل نہیں ہوا۔ انٹرنیٹ دیکھ کر دوبارہ کوشش کریں۔';

  @override
  String get updateErrCorrupt =>
      'ڈاؤن لوڈ کی گئی فائل حفاظتی جانچ میں ناکام ہوئی اور حذف کر دی گئی۔ دوبارہ کوشش کریں۔';

  @override
  String get updateErrPackage =>
      'یہ فائل دکان پرو کی درست اپ ڈیٹ نہیں، اس لیے انسٹال نہیں کی گئی۔';

  @override
  String get updateErrSigner =>
      'یہ اپ ڈیٹ دکان پرو کی دستخط شدہ نہیں، اس لیے انسٹال نہیں کی گئی۔ دکان پرو سپورٹ سے رابطہ کریں۔';

  @override
  String get updateErrInstall =>
      'اینڈرائیڈ اپ ڈیٹ انسٹال نہیں کر سکا۔ موجودہ ایپ اور اس کا ڈیٹا تبدیل نہیں ہوا۔';

  @override
  String get updateInstallCancelled =>
      'انسٹالیشن منسوخ کر دی گئی۔ آپ بعد میں اپ ڈیٹ کر سکتے ہیں۔';

  @override
  String get productsNameInShop => 'آپ کی دکان میں نام';

  @override
  String get productsCatalogShowMore => 'مزید دکھائیں';

  @override
  String get productsAddedNameNotSaved =>
      'آئٹم شامل ہو گیا، لیکن نیا نام محفوظ نہیں ہو سکا۔ میرے آئٹمز سے تبدیل کریں۔';
}
