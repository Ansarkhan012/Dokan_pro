# Dukaan Pro — Stage 2 Localization Plan (English + Urdu)

Status: **Phase 2A, discovery and design only.** No application code,
dependency, font or asset has been added. Phase 2B starts only after approval.

Date: 2026-10-12 · Branch: `r1/sync-reliability` (Stage 1B and keyboard-focus
work are still uncommitted and are preserved).

Companion file: [`docs/stage2/string_inventory.md`](docs/stage2/string_inventory.md)
holds the complete inventory: every candidate string with its file and line.

---

## 0. Decisions needed before Phase 2B

| # | Decision | Recommendation |
| --- | --- | --- |
| D1 | Localization mechanism | Flutter `gen-l10n` with ARB files; add `flutter_localizations` (SDK) and `intl` (version pinned by the SDK) |
| D2 | Urdu font | **Noto Nastaliq Urdu** (SIL OFL 1.1), bundled. Download from the official Noto repository after approval. Hold a 1-day visual spike against Noto Naskh Arabic on the Tab A9+ (§6). |
| D3 | Digits | **Western digits 0–9 everywhere** (money, quantities, stock, dates, barcodes, phone numbers) in both languages |
| D4 | Currency | Keep `Rs` in both languages, always rendered as an LTR island (§5.3) |
| D5 | Glossary | Approve §8, then have one Karachi shopkeeper review the Urdu ARB before release |
| D6 | Seeded category and expense-category names | Translate **display only**, by their fixed seeded ids. Shop-created names are shown as entered. |
| D7 | Charts | Owner dashboard bar chart stays LTR (time axis left to right) in both languages |
| D8 | Urdu search normalisation | Optional and **not** in scope by default. Folding ی/ي, ک/ك, ہ/ه in search would change search logic, so it needs separate approval. |
| D9 | Diff hygiene | Commit (with approval) the Stage 1B fixes and the keyboard-focus work **before** Batch 2 touches `pos_workspace.dart`, so localization diffs stay reviewable |

---

## 1. Current architecture (verified)

| Area | Finding |
| --- | --- |
| Localization | **None.** No `flutter_localizations`, `intl`, `l10n.yaml`, ARB or `Localizations` usage. Every string is a hard-coded English literal. |
| App root | `lib/app/dukaan_pro_app.dart`: a single `MaterialApp` with `home:` switching to `AuthGate`. There are no named routes; screens use `Navigator.push`/`MaterialPageRoute` (12 call sites) and in-place state. |
| Theme | `ThemeData(colorSchemeSeed: 0xff176b52)` with the default font. No `fonts:` in `pubspec.yaml`. 36 explicit `fontSize`/`fontFamily` settings. |
| Navigation | POS shell (`pos_workspace.dart`): custom `_PosSidebar` (Sale, Products, Bills, Khata) plus a top bar. Owner area: menu in `auth_gate.dart` plus screens. Two `TabBar`s (Products, Inventory). |
| Settings | `lib/features/settings/owner_settings_screen.dart` (shop profile, cashiers, subscription). There is no device-preference section yet. |
| Device preferences | `SharedPreferences` is already used (`preferences_device_id_store.dart`) and is excluded from Android backup. |
| Formatting | `lib/core/format/display_format.dart`: English month names, AM/PM, "Today/Yesterday", `paymentMethodLabel`. `formatPkr` is defined in **two** places (`pos_state.dart:241`, `pos_workspace.dart:1823`). `measure_format.dart`: kg/g/L/ml labels. |
| Error text | Domain exceptions carry English messages that are shown directly (e.g. `SaleValidationException('Insufficient stock')`, `ProductValidationException`, `ProductImageException`, `EntitlementState.message`). Sync failure **reasons are persisted** to the `sync_operations` row in English. |
| RTL readiness | 19 `EdgeInsets.only(left/right)`/`fromLTRB`, 8 `Alignment.*Left/Right`, 3 `Positioned`, 3 directional icons (`arrow_back`, `arrow_forward` ×2), 1 explicit `TextDirection.ltr` (dashboard chart painter). There are no `TextAlign.left/right`. |
| Tests | 272 `find.text`/`find.textContaining` assertions on English text. They stay valid because English remains the default. |

---

## 2. String inventory (summary)

Static scan of `lib/` (generated tables excluded): **920 occurrences in 67
files**. The full list is in [`docs/stage2/string_inventory.md`](docs/stage2/string_inventory.md).

| Category | Files | Occurrences | Treatment |
| --- | ---: | ---: | --- |
| A. Widget UI text | 36 | 759 | Move to ARB |
| B. Domain, service and policy messages shown to users | 20 | 111 | Keep the English source (logs and tests). Map to ARB at the UI boundary by type, code or constant. |
| C. Formatting helpers | 2 | 29 | Make locale-aware (`formatDisplayDate(…, l10n)`, etc.) |
| D. Internal, SQL or never shown | 9 | 21 | **Do not translate** |

After removing duplicates (Save, Cancel, Retry, Cash…), expect about
**550–600 ARB keys**.

### By screen

| Screen / area | Main files | ≈ strings | Batch |
| --- | --- | ---: | --- |
| Shared shell, nav, chips, formatting | `core/ui/pos_ui.dart`, `pos_workspace.dart` (top bar, sidebar), `features/sync/sync_attention_*`, `core/format/*` | 60 | 1 |
| Cashier sale and checkout | `pos_workspace.dart`, `measured_quantity_picker.dart`, `pack_selector.dart`, `pos_state.dart`, `pos_runtime_*`, `receipts/receipt_view.dart` | 130 | 2 |
| Products and stock | `product_management_native.dart`, `custom_product_dialog.dart`, `edit_product_dialog.dart`, `pack_family_editor.dart`, `measure_preset_editor.dart`, `product_management_service.dart`/`_models.dart`, `inventory_management_native.dart`, `product_image_processing.dart` | 200 | 3 |
| Bills, returns, voids | `sales_history.dart`, `sales_management_native.dart`, `local_sale_service.dart` (validation messages), `bill_reference.dart` | 110 | 4 |
| Udhaar / Khata / customers | `customer_khata_view.dart`, `customer_management_native.dart` | 65 | 4 |
| Owner dashboard and reports | `owner_dashboard_native.dart`, `report_models.dart` | 45 | 5 |
| Purchases and suppliers | `purchase_management_native.dart` | 69 | 5 |
| Expenses | `expense_management_native.dart` | 36 | 5 |
| Settings | `owner_settings_screen.dart` | 59 | 5 |
| Auth, onboarding, device, cashier login | `auth_gate.dart`, `cashier_login_panel.dart`, `owner_cashier_setup_panel.dart`, `owner_access.dart`, `cashier_resume_gate_native.dart`, `dukaan_pro_app.dart`, `auth_session_controller.dart`, `device_mode.dart`, `core/errors/safe_error_message.dart` | 105 | 6 |
| Sync and subscription messages | `sync/sync_failure.dart`, `sync_queue_repository.dart`, `sync_health.dart`, `subscription/entitlement_policy.dart`, `entitlement.dart` | 55 | 6 |
| Web-only placeholders | `*_web.dart` (12 files) | 20 | with their feature batch |

---

## 3. Server and database text versus static UI text

| Source | Examples | Rule |
| --- | --- | --- |
| Shopkeeper-entered | product names, pack labels, customer, supplier and cashier names, shop name, address, receipt footer, return/void reasons, expense notes | **Never translated.** Shown exactly as entered, with automatic text direction (§5.2). |
| Seeded reference data with fixed ids | product categories (`seed.sql`: Household, Staples, Dairy, Cooking Essentials, Beverages, Snacks), default expense categories (`ensure_default_expense_categories`: Rent, Electricity, Gas, Internet, Salary, Transport, Delivery, Maintenance, Food/Tea, Packaging, Miscellaneous, with deterministic ids) | Display-only translation by **id** (D6). Rows whose id is not in the map are shown as stored. The hosted ids still need checking with a read-only query, run only with your approval. |
| Stored enum names | `cash`, `digital`, `credit`, `piece`, `measured`, `kg`, `liter`, `completed`, `voided`, sync statuses, error classes | Never translated in storage or payloads. Labels are produced at display time from the enum. |
| Persisted English messages | `sync_operations.error_message`, sync `reason` strings, `customer credit limit exceeded` | Never shown raw in Urdu. The UI derives text from the stable **code / error class / flag** (`sync_failure.dart` codes, `DPV01`-style SQLSTATEs). The English text stays in the database for diagnostics. |
| Server / Supabase errors | `AuthException`, `PostgrestException` messages, RPC `raise exception` text | Mapped by code or known pattern (`safe_error_message.dart`) to localized text, with a localized generic fallback. Raw server text is never shown in Urdu. |
| Identifiers | barcodes, bill references (`B-…`), invoice numbers, UUIDs, device ids, email, phone | Never translated. Always rendered LTR. |
| Domain exception messages | `SaleValidationException`, `ProductValidationException`, `CustomerValidationException`… | English text stays unchanged (tests assert it). The UI maps type plus message constant to an ARB key. Unknown messages fall back to a localized generic message. |

---

## 4. Technical approach (gen-l10n)

- `pubspec.yaml`: `flutter_localizations: {sdk: flutter}`, `intl: any` (pinned
  by the SDK) and `flutter: generate: true`.
- `l10n.yaml`: `arb-dir: lib/l10n`, `template-arb-file: app_en.arb`,
  `output-localization-file: app_localizations.dart`, `nullable-getter: false`,
  `untranslated-messages-file: build/l10n_untranslated.txt`. On Flutter 3.44,
  output is generated into `lib/l10n` (no synthetic package).
- `lib/l10n/app_en.arb` (template, with an `@key` description for every key)
  and `lib/l10n/app_ur.arb`.
- Keys are grouped by prefix: `common*`, `nav*`, `sale*`, `checkout*`,
  `product*`, `stock*`, `bill*`, `return*`, `void*`, `khata*`, `purchase*`,
  `expense*`, `report*`, `settings*`, `auth*`, `sync*`, `sub*`, `error*`.
- Plurals and placeholders use ICU (`{count, plural, one{…} other{…}}`). Urdu
  uses the `one`/`other` plural categories. Typed placeholders mean money and
  quantities are passed **pre-formatted as strings**, never formatted by
  `intl` (D3, D4).
- `MaterialApp`: `localizationsDelegates: AppLocalizations.localizationsDelegates`
  (includes `GlobalMaterialLocalizations`, `GlobalWidgetsLocalizations`,
  `GlobalCupertinoLocalizations`), `supportedLocales: [en, ur]`, and
  `locale:` from the controller (§7). This gives Material widgets (date picker,
  text selection menu, back tooltip) Urdu text and RTL automatically.
- Access via `context.l10n` (a small extension). Domain and service code never
  imports `AppLocalizations`.
- Guards: a test that fails on new hard-coded user-visible literals in `lib/`
  (with an allowlist for category D), and a test that every `app_en.arb` key
  exists in `app_ur.arb` with identical placeholders.

---

## 5. RTL behaviour

### 5.1 Layout

| Element | Required Urdu behaviour | Change |
| --- | --- | --- |
| App direction | `ur`: RTL, from `MaterialApp` locale | none (automatic) |
| POS sidebar (`_PosSidebar`) | Moves to the **right**; the selected indicator sits on the inner edge | Already inside a `Row`, so it mirrors automatically. Check its indicator padding. |
| Current Bill panel | Moves to the **left**. The product grid flows right to left. | `Row` and `GridView` mirror automatically |
| Paddings and margins | Mirror | Convert the 19 `EdgeInsets.only(left/right)`/`fromLTRB` to `EdgeInsetsDirectional`, unless they are symmetric |
| Alignment | Mirror | 8 `Alignment.centerLeft/Right` → `AlignmentDirectional.centerStart/End` |
| `Positioned` (3) | Mirror | `PositionedDirectional` |
| Back arrow | Points right | `cashier_resume_gate_native.dart:340` `Icons.arrow_back` → `BackButtonIcon` or `Icons.adaptive.arrow_back`. `AppBar` back buttons mirror automatically. |
| Forward / "go" arrows | Point left | `product_management_native.dart:244` and `sales_history.dart:618` `Icons.arrow_forward`: mirror via `Directionality`-aware icon |
| Non-directional icons | Unchanged | Cart, receipt, print, search, barcode and lock icons are **not** mirrored |
| Tabs | Order right to left, swipe direction mirrored | automatic |
| Dialogs and forms | Title, fields and actions right-aligned; the primary action on the **left** end | automatic with `OverflowBar`/`actions`. Verify `PosFormDialog` (`pos_ui.dart:249` `Alignment.centerRight` → `AlignmentDirectional.centerEnd`). |
| Tables and lists | Name column on the right; amounts at the end (left) | Use `start`/`end` alignment. Amount cells use LTR islands. |
| Snackbars and banners | RTL text | automatic |
| Charts | Stay LTR (D7) | Keep `TextDirection.ltr` in `owner_dashboard_native.dart:291` and wrap the chart in `Directionality(ltr)` |

### 5.2 Text input and mixed content

- **Numeric fields** (prices, quantities, cash received, discount, stock, PIN,
  phone, barcode): `textDirection: TextDirection.ltr`, `textAlign: end` and a
  shared `AsciiDigitsFormatter` that maps Urdu (۰–۹, U+06F0–U+06F9) and Arabic
  (٠–٩, U+0660–U+0669) digits and `٫` to ASCII **before** the existing
  parsers. Parsing logic (`parseMeasureInput`, money parsing) is unchanged.
- **Free text** (product, customer and supplier names, reasons, notes): the
  direction follows the first strong character (an `AutoDirection` helper on
  `TextField`), so English names stay LTR inside the Urdu UI and Urdu names
  stay RTL inside the English UI.
- **Email, password and URLs**: always LTR.
- **Mixed strings**: placeholders such as `{name}`, `{amount}` and `{barcode}`
  are wrapped in Unicode isolates (FSI/LRI … PDI) by a single helper, so
  `"Barcode 8964000123 is already used"` and `"Rs 1,025.00"` never reorder
  inside Urdu sentences.

### 5.3 Money, quantities and dates

- `formatPkr` output is unchanged (`Rs 350.00`, `-Rs 50.00`). In Urdu it is
  wrapped in an LRI…PDI isolate, so the minus sign and `Rs` stay on the
  correct side. **No calculation changes.**
- Quantities: `2.5 kg` / `750 ml` become `2.5 کلو` / `750 ملی لیٹر`. The number
  stays Western and LTR-isolated, and the unit label comes from ARB. The stored
  `measure_unit_snapshot` is unchanged.
- Dates: Gregorian calendar, Western digits, Urdu month names from ARB (e.g. `5 اکتوبر 2026`)
  and `صبح`/`شام` for AM/PM. Relative words come from ARB: `آج`,
  `گزشتہ کل` (yesterday), `آئندہ کل` (tomorrow). Plain `کل` is ambiguous,
  so it is avoided.

---

## 6. Urdu font

**Recommendation: Noto Nastaliq Urdu**, licensed under the **SIL Open Font
License 1.1**, which allows bundling, embedding and redistribution inside a
commercial app.

- **Why:** Nastaliq is what Karachi shopkeepers read every day (signboards,
  newspapers, Urdu apps). Naskh is readable but feels "Arabic".
- **Known cost:** Nastaliq needs about 1.6–1.9× line height. Tight areas such as
  status pills, 64 px product cards, sidebar labels and button rows can clip.
  Mitigation: an Urdu-specific `TextTheme` with explicit `height`, `StrutStyle`
  on dense widgets, and overflow tests (§10).
- **Alternative:** **Noto Naskh Arabic** (also OFL 1.1) is more compact. The
  visual spike decides whether the dense POS grid and bill panel use Naskh
  while the rest uses Nastaliq. Default: Nastaliq everywhere unless the spike
  shows clipping that cannot be fixed.
- **Avoid:** Jameel Noori Nastaleeq and other "freely downloadable" Urdu fonts
  with no clear redistribution licence.
- **Licence handling:**
  1. Download only from the official Noto release, after approval. Record
     the version, URL and SHA-256 in `assets/fonts/README.md`.
  2. Bundle the unmodified font files and the full `OFL.txt` under
     `assets/fonts/noto_nastaliq_urdu/`.
  3. Register the licence at startup with `LicenseRegistry.addLicense`, so it
     appears in Flutter's licences page (owner Settings → About → Licences).
  4. Do not rename or modify the font. If it is ever subset, check the
     Reserved Font Name clause in the shipped `OFL.txt` first.
  5. Measure the APK size impact before merging.
- **Usage:** applied only for the `ur` locale (`fontFamily` with a fallback),
  so English rendering is unchanged.

---

## 7. Locale persistence and switching

- **Scope:** a device-level UI preference. **No change to the shop data model,
  SQLite, Supabase or sync.**
- **Storage:** `SharedPreferences` key `ui_locale` holds `en` or `ur`. A missing
  key means **English**, so existing users see no change until they choose
  Urdu. The key is excluded from backup already (sharedpref rule), so after a
  restore to a new device the app starts in English.
- **Startup:** read the preference in `main()` before `runApp`, so there is no
  English-to-Urdu flash. If the read fails, use English.
- **Controller:** a `LocaleController` (`ValueNotifier<Locale>`) above
  `MaterialApp`. Switching only rebuilds `MaterialApp` with a new `locale`.
  The `Navigator`, `AuthGate` state, POS cart, open dialogs and the owner or
  cashier session are **kept**: no restart and no logout.
- **Where to switch:** a language toggle (`English | اردو`) in
  - the pre-login screens (owner sign-in and cashier login),
  - the POS top bar overflow menu (available to cashiers; it changes only the
    UI language),
  - Owner Settings → Device.
- **Offline:** everything is bundled (ARB-generated code and fonts), so both
  languages work fully offline.

---

## 8. Translation glossary (draft for native review)

Tone: plain, spoken Karachi shop Urdu. Use English loanwords where shopkeepers
actually say them (Stock, Bill, Cash, Barcode). No formal or literary words.

| English | Urdu | Notes |
| --- | --- | --- |
| Sale (screen) / New sale | فروخت / نئی فروخت | |
| Products | آئٹمز | Alternative: سامان. Decide in review. |
| Product | آئٹم | |
| Bill / Bills | بل | Urdu plural is the same word |
| Receipt | رسید | |
| Khata | کھاتہ | |
| Udhaar | ادھار | Payment method label for stored `credit` |
| Cash | کیش | Alternative: نقد |
| Digital | ڈیجیٹل | JazzCash / Easypaisa / bank |
| Split payment | مختلف ادائیگی | Review |
| Payment | ادائیگی | |
| Subtotal | ذیلی ٹوٹل | |
| Total | ٹوٹل | Alternative: کل رقم |
| Discount | رعایت | Alternative: ڈسکاؤنٹ |
| Cash received | وصول رقم | |
| Change (to give back) | واپس دیں | Avoids بقایا, which also means "balance" |
| Balance (Udhaar owed) | باقی | e.g. باقی ادھار |
| Credit limit | ادھار کی حد | |
| Customer | گاہک | |
| Supplier | سپلائر | |
| Purchase | خریداری | |
| Expense | خرچہ | |
| Stock / Low stock / Out of stock | اسٹاک / اسٹاک کم ہے / اسٹاک ختم | |
| Opening stock | ابتدائی اسٹاک | |
| Stock adjustment | اسٹاک درستگی | |
| Return | واپسی | |
| Refund | رقم واپسی | |
| Void (bill) | بل منسوخ کریں | "Cancel" is رہنے دیں, kept distinct |
| Cancel (dialog) | رہنے دیں | Alternative: منسوخ (not used, to avoid clashing with Void) |
| Save / Confirm / Retry | محفوظ کریں / تصدیق کریں / دوبارہ کوشش کریں | |
| Add / Edit / Remove | شامل کریں / ترمیم / ہٹائیں | |
| Search | تلاش | |
| Category | کیٹیگری | |
| Price / Sale price / Purchase price | قیمت / قیمتِ فروخت / قیمتِ خرید | |
| Quantity | مقدار | |
| Piece (unit) | عدد | Alternative: پیس |
| kg / g / L / ml | کلو / گرام / لیٹر / ملی لیٹر | Labels only. Numbers stay Western. |
| Pack size | پیک سائز | |
| Barcode | بارکوڈ | |
| Print / Reprint | پرنٹ / دوبارہ پرنٹ | |
| Owner / Cashier | مالک / کیشیئر | |
| Shop | دکان | |
| Device | ڈیوائس | |
| Sign in / Sign out | لاگ اِن / لاگ آؤٹ | |
| PIN | پن | |
| Settings | سیٹنگز | |
| Reports / Dashboard | رپورٹس / خلاصہ | |
| Today / Yesterday / Tomorrow | آج / گزشتہ کل / آئندہ کل | |
| Offline | آف لائن | |
| Synced / Pending upload / Needs attention | محفوظ (آن لائن) / اپ لوڈ باقی / توجہ درکار | Sync chip |
| Subscription | سبسکرپشن | |

Seeded names (display-only, by id): Household گھریلو اشیاء · Staples
راشن · Dairy دودھ اور ڈیری · Cooking Essentials کھانا پکانے کا سامان ·
Beverages مشروبات · Snacks اسنیکس · Rent کرایہ · Electricity بجلی ·
Gas گیس · Internet انٹرنیٹ · Salary تنخواہ · Transport ٹرانسپورٹ ·
Delivery ڈیلیوری · Maintenance مرمت · Food/Tea کھانا / چائے ·
Packaging پیکنگ · Miscellaneous متفرق.

**Review process:** I draft `app_ur.arb` with an English `@description` for
every key. One Karachi shopkeeper reviews it from a printed or tablet
walkthrough (each screen with Urdu next to English). Changes go back into the
ARB. The glossary in this file is the source of truth for consistency.

---

## 9. Risks

| # | Risk | Impact | Mitigation and test |
| --- | --- | --- | --- |
| R1 | **Barcode scanning.** The hardware scanner sends keystrokes. RTL does not affect key events, but an **Urdu physical-keyboard layout** set in Android would remap the scanner's keys. | Scans add the wrong product, or none | Barcode handling stays ASCII and LTR, with no digit conversion on the scan path. Widget test: a scan in `ur` adds the product. Tablet check: scan with the Urdu UI and with the Gboard Urdu soft keyboard active. Document "physical keyboard layout = English (US)". |
| R2 | **Keyboard focus** (uncommitted `pos-search`/`pos-hardware-scan` work) | Regressions while editing `pos_workspace.dart` | D9: commit it first. Batch 2 changes only strings and directional widgets, and reruns `pos_search_focus_test.dart` and `keyboard_overlay_test.dart` in both locales. |
| R3 | **Product search** with Urdu names: letter variants (ی/ي, ک/ك, ہ/ه) and zero-width joiners | A typed name is not found | Default: no logic change. D8 offers optional search-only normalisation. The test suite records current behaviour. |
| R4 | **Numeric fields** receiving Urdu or Arabic digits from the Urdu soft keyboard | Parsing fails ("Enter a valid amount") | `AsciiDigitsFormatter` on every numeric field. Tests for ۲٫۵ → 2.5 and ۱۲۵۰ → 1250. |
| R5 | **Money and minus signs** reordering in RTL | "Rs 50.00-" or a misread amount | LTR isolates. Tests compare rendered strings in `ur`. Calculations are untouched. |
| R6 | **Receipts**: mixed Urdu labels with English product names; future thermal printing cannot print Urdu glyphs | On-screen layout; print later | The on-screen receipt follows the UI language with LTR amount columns. Printing remains English or raster per the Stage 1 printer plan. Receipt language may become its own setting later. |
| R7 | **Nastaliq height** causing overflow and clipping | Broken POS layout on the tablet or phone | Urdu `TextTheme` heights, `StrutStyle` and overflow tests at text scale 1.0 and 1.3 on phone and tablet sizes |
| R8 | **Persisted English messages** (sync reasons, entitlement messages) | English text inside the Urdu UI | Map by code or state. Raw text is shown only in the "details" area for support. |
| R9 | **Category names** on hosted data may differ from `seed.sql` | Some categories untranslated | Translate by id only. Unknown ids are shown as stored. |
| R10 | **Test coupling** (272 English finders) | Accidental breakage | English stays the default. The existing suite must stay green unchanged. Urdu tests are added alongside. |
| R11 | **`ur` Material and Cupertino support** for date pickers and text selection | English fragments | Use `GlobalMaterialLocalizations` (which supports `ur`) and verify the date picker in Urdu |
| R12 | **Scope creep and diff size** (~600 keys across 67 files) | Review fatigue | Seven batches, each green before the next, each a separate commit after approval |

---

## 10. Implementation batches (Phase 2B, after approval)

Every batch:
- changes only presentation (no business, sync, security, money or stock logic);
- keeps the full suite green in English;
- adds Urdu tests;
- runs `flutter analyze`;
- stops for review.

| Batch | Scope | Key files | Acceptance |
| --- | --- | --- | --- |
| **0. Foundation and switcher** | Dependencies, `l10n.yaml`, ARB scaffold, `context.l10n`, `LocaleController` and preference, `MaterialApp` delegates, font assets and licence (after D2), helpers (`AsciiDigitsFormatter`, `ltrIsolate`, `AutoDirection`), the hard-coded-string guard test (allowlist starts with every current file and shrinks per batch), the ARB parity test, and the language toggle on sign-in and in the POS menu | `pubspec.yaml`, `l10n.yaml`, `lib/l10n/*`, `lib/main.dart`, `lib/app/dukaan_pro_app.dart`, new `lib/core/l10n/*` | English is unchanged by default. Switching keeps the session and cart. The choice persists across restart. Offline works. |
| **1. Shared navigation and common widgets** | Sidebar, top bar, sync chip, status pills, `PosFormDialog`, common buttons, locale-aware `display_format`/`measure_format` | `core/ui/pos_ui.dart`, `pos_workspace.dart` (shell only), `features/sync/*`, `core/format/*` | The sidebar mirrors. Dates and units show in Urdu with Western digits. No overflow at phone or tablet size. |
| **2. Cashier sale and checkout** | Grid, search, cart, measured picker, pack selector, payment dialog (Cash, Digital, Udhaar, Split), change, sale-validation error mapping, receipt dialog and on-screen receipt | `pos_workspace.dart`, `measured_quantity_picker.dart`, `pack_selector.dart`, `receipt_view.dart`, `pos_state.dart` (validation text) | Full sales in Urdu (PIECE, 2.5 kg, 500 ml, pack). Totals are identical to English. Scanning and focus tests pass in both locales. Urdu-digit input works. |
| **3. Products and stock** | Product list and tabs, create/edit/family dialogs, image picker messages, measure presets, inventory tabs and adjustments | `features/products/*`, `features/inventory/*`, `product_image_processing.dart` (message mapping) | Product names are shown as entered. Barcode fields are LTR. Validation messages are in Urdu. |
| **4. Bills, returns and Udhaar** | Bills list and detail, reprint, return and void dialogs, Khata view, customers, credit limit and payments | `sales_history.dart`, `sales_management_native.dart`, `customer_khata_view.dart`, `customer_management_native.dart` | Bill references are LTR. Return and void flows work in Urdu. Balances are identical to English. |
| **5. Owner dashboard, reports, settings, purchases, expenses** | Dashboard tiles and chart labels, reports, settings (including the Device → Language section), purchases and suppliers, expenses and seeded expense-category names | `owner_dashboard_native.dart`, `owner_settings_screen.dart`, `purchase_management_native.dart`, `expense_management_native.dart` | The chart stays LTR. Seeded names are translated by id. Date pickers are in Urdu. |
| **6. Auth, onboarding, dialogs and errors** | Owner sign-in and shop creation, device registration, cashier login and PIN, owner unlock, resume gate, sync-attention dialog, subscription banners, `safe_error_message`, sync failure code mapping | `app/*`, `core/errors/*`, `sync/sync_failure.dart` (code → key map lives in the UI layer), `subscription/entitlement_policy.dart` (state → key) | No raw English or server text in the Urdu UI. The guard test allowlist contains only category D. |

**Estimate:** Batch 0 ~1 day (plus the font spike), Batches 1–6 ~1–1.5 days
each, native review ~1 day, tablet verification ~0.5 day.

---

## 11. Testing strategy

**Automated (Flutter)**
1. The existing suite (299 tests plus the R1 layers) stays green with **no
   edits**, which proves English is the unchanged default.
2. ARB parity: identical key sets and placeholders in `en` and `ur`. The
   `untranslated-messages-file` must be empty.
3. Hard-coded string guard: no new user-visible literals outside the allowlist.
4. Per batch: widget tests that pump the screen in `ur` at **phone 360×800**
   and **tablet 1280×800 (Tab A9+ landscape)** and **800×1280**, at text scale
   1.0 and 1.3. Each asserts `takeException() == null` (no overflow),
   `Directionality.of == rtl`, the sidebar on the right, and key Urdu labels
   present.
5. Behaviour:
   - switching language with a non-empty cart keeps the cart and session;
   - the preference persists across a simulated restart;
   - English is the default with no preference;
   - money and quantity strings have identical digits in both locales;
   - Urdu-digit input parses correctly;
   - a barcode scan adds the product in `ur`;
   - the focus tests pass in `ur`.
6. Formatting unit tests for Urdu dates, relative days, units, payment labels
   and the bidi isolation of amounts.
7. Optional golden tests for the POS screen, receipt and Khata in both locales,
   on Windows only to avoid platform font drift.

**Manual (tablet and phone)**
- Tab A9+ (landscape and portrait) and one phone or emulator: every screen in
  Urdu.
- Hardware barcode scanner with the Urdu UI.
- Gboard Urdu keyboard on numeric fields.
- Language switch mid-sale.
- Restart.
- Offline.
- Receipt readability.
- Native-speaker review sheet.

---

## 12. Acceptance criteria (Stage 2 complete)

1. Existing users start in English. Urdu appears only after they choose it,
   and the choice persists per device.
2. Switching language does not restart the app, log out, clear the cart or
   close the current screen.
3. All user-visible static text in the migrated screens comes from ARB. The
   guard test passes with only category D allowlisted.
4. Urdu uses full RTL: mirrored navigation, alignment and directional icons.
   Non-directional icons and charts are unchanged.
5. Product, customer, supplier, cashier and shop names, barcodes, references,
   IDs, stored enum values and API payloads are never translated.
6. Money, quantities, stock, sync, security and subscription logic are
   unchanged. The existing tests pass unmodified, and totals are identical in
   both languages.
7. Western digits are used everywhere. Urdu or Arabic digits typed into
   numeric fields are accepted.
8. Barcode scanning and keyboard-focus behaviour are identical in both
   languages.
9. There is no overflow or clipping at phone and tablet sizes at text scale 1.0
   and 1.3.
10. The app works fully offline in both languages.
11. The bundled Urdu font's OFL licence ships with the app and is visible on the
    licences page.
12. A native Karachi shopkeeper has reviewed the Urdu text, and the glossary is
    applied consistently.

---

## 13. Out of scope for Stage 2

- Database encryption (SEC-2)
- Thermal printing (PRN-1)
- Cross-device images (IMG-1/2)
- Supabase or schema changes
- Translating shop data
- Urdu search normalisation (D8, unless approved)
- Receipt-language setting
