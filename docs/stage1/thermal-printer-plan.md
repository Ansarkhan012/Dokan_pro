# Thermal receipt printing: integration plan

Status: **PLAN ONLY — not implemented.** Today the app has a transport-neutral
`ReceiptModel`, an on-screen `ReceiptView`, a `ReceiptPrinter` interface and
only `UnavailableReceiptPrinter`, which always answers "No receipt printer is
configured". `ReceiptPaperWidth.mm58/mm80` exists but does not change any
layout. No Bluetooth/USB plugin or Android permission is present.

## 1. Scope for the pilot

- ESC/POS printers only, 58 mm (32 columns, Font A) and 80 mm (48 columns).
- Transports: Bluetooth Classic SPP (most common in Pakistani shops) first,
  USB (Android USB host) second. No network printers in the pilot.
- Printing is never part of the sale transaction (already guaranteed by the
  committer: the sale is committed before the receipt is built).

## 2. Architecture

```
ReceiptModel ──► EscPosReceiptEncoder(width) ──► Uint8List
                                                 │
                       ReceiptTransport (bt | usb) ◄─ PrinterSettings (secure prefs)
                                                 │
                    EscPosReceiptPrinter implements ReceiptPrinter
```

- `EscPosReceiptEncoder`: pure Dart, unit-tested byte-for-byte. Init
  (`ESC @`), code page, bold/double-height shop name, left/right column
  alignment computed in columns (not pixels), quantity formatting via the
  existing `formatLineQuantity`, unit price line, Subtotal / Discount (only
  when stored discount > 0) / Total / Returned / Net, payments, received /
  change, footer, feed + partial cut (`GS V 66 0`) when supported.
- Long product names wrap at the column width; amounts stay right-aligned.
- `ReceiptTransport`: `connect`, `write(bytes)`, `disconnect`, typed errors
  (`notPaired`, `permissionDenied`, `timeout`, `outOfPaper` where reported).
- Plugin candidates (evaluate licence + maintenance before choosing):
  a Bluetooth Classic SPP plugin and an Android USB serial/host plugin. Write
  thin adapters so the encoder and retry logic stay plugin-independent.

## 3. Urdu

ESC/POS printer fonts do not shape Urdu/Arabic script. Urdu text must be
rendered to a monochrome raster image in Flutter (`dart:ui` PictureRecorder
with an embedded Nastaliq/Naskh font) and sent with `GS v 0`. Plan: Latin-only
receipt in the pilot; Urdu raster as a follow-up after hardware testing.
Product names containing Urdu would otherwise print as `?`; the encoder must
detect non-Latin characters and fall back to raster lines.

## 4. Android permissions (Flutter default target SDK, Tab A9+ on Android 14)

- Bluetooth: `BLUETOOTH_CONNECT` (runtime, Android 12+); `BLUETOOTH_SCAN`
  with `android:usesPermissionFlags="neverForLocation"` only if in-app
  discovery is offered (otherwise list bonded devices only);
  legacy `BLUETOOTH` / `BLUETOOTH_ADMIN` with `android:maxSdkVersion="30"`.
- USB: `<uses-feature android:name="android.hardware.usb.host" android:required="false"/>`,
  a `USB_DEVICE_ATTACHED` intent filter with a device filter, and a runtime
  `UsbManager.requestPermission` per device.
- Request at the moment the owner opens Printer settings, never at checkout.
- These are AndroidManifest changes and need approval.

## 5. Connection, failure and retry

- Owner chooses the printer once in Settings (paired Bluetooth list or
  attached USB device) plus paper width; stored per device.
- Print: connect (5 s timeout) → write in ≤512-byte chunks → short drain delay
  → disconnect (Bluetooth SPP printers often allow one client only).
- One automatic retry on connect timeout; then a clear message with a
  **Retry** button. The sale is already saved; reprint is always available
  from Bills (existing flow). Never mark a receipt "printed" unless the
  write completed.
- Do not auto-print twice: a print attempt id per tap prevents a double tap
  from printing two copies.

## 6. Tests

- Automated: encoder golden byte tests for 58/80 mm, wrapping, discount line
  present/absent, loose units (2.5 kg, 750 ml), pack labels, returned/voided
  receipts; fake transport tests for timeout, retry, disconnect mid-write.
- Physical (required before any claim of compatibility), on the Tab A9+:
  1. Pair printer in Android settings; select it in app; test page.
  2. Print a PIECE, a loose kg, a loose ml and a pack-variant sale on 58 mm and 80 mm.
  3. Verify Rs alignment, wrapping of a long name, discount and payments lines.
  4. Printer off → error message → turn on → Retry prints exactly once.
  5. Out of paper mid-print → message → reload → reprint from Bills.
  6. Bluetooth toggled off during print; app backgrounded during print.
  7. 20 consecutive receipts: no dropped bytes or garbled lines.
  8. USB printer: attach, permission prompt, print, detach mid-print.
  9. Record printer make/model/firmware for each passed test.

## 7. Estimate

Encoder + settings + Bluetooth transport + tests: ~3–4 days; USB +
Urdu raster: +2–3 days; physical test cycle: 1 day per printer model.
