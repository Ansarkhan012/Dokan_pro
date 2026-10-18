# SEC-2: local database encryption — assessment and migration plan

Status: **plan only; nothing in this document is implemented.** Date 2026-10-13.
Related: SEC-1, fixed in this pass (the database and its companion files are
excluded from Android backup and device transfer).

## 1. Current state (verified)

| Item | Finding |
| --- | --- |
| File | `Context.getFilesDir()/dukaan_pro.sqlite` (`AppDatabase.open`, `lib/database/app_database.dart:48-55`; `path_provider_android` maps the app-support directory to `getFilesDir()`) |
| Engine | `sqlite3` 3.x with the default build (plain SQLite); `NativeDatabase.createInBackground`, no `setup:` callback, no `PRAGMA key` |
| Contents | Customers (names, phones, addresses), Udhaar ledger, sales, payments, the unsynced outbox (full JSON payloads), audit log |
| Secrets elsewhere | Owner session, device credential, cashier session, owner lock and entitlement are already in `flutter_secure_storage` (Android Keystore-backed) |
| Backup | Excluded since SEC-1 (`backup_rules.xml`, `data_extraction_rules.xml`) |
| Pilot build | **Debug, debuggable** APK. With USB debugging enabled on an unlocked tablet, `adb shell run-as com.dukaanpro.dukaan_pro` reads the database directly. A release build (non-debuggable) closes that path; release signing is already wired in `android/app/build.gradle.kts` |

## 2. Threats encryption addresses, and those it does not

| Threat | Encryption at rest helps? |
| --- | --- |
| Lost or stolen tablet, file copied via `run-as` (debug build) or a rooted device | **Yes**: the key is in the Keystore and is not exportable |
| Backup or device-transfer copy | Already closed by SEC-1 |
| Someone using the unlocked app | No: that is an app-access problem (owner lock, cashier PIN, FLAG_SECURE) |
| Malware with root on the tablet while the app runs | No: the key is usable in process |

**Cheapest first step:** ship the pilot as a **release** build (non-debuggable) once the signing keystore is approved. That removes the easiest extraction path even before encryption.

## 3. Recommended design

1. **Cipher library:** SQLite3 Multiple Ciphers (`sqlite3mc`) through the `sqlite3` package's build hook (`hooks: user_defines: sqlite3: source: sqlite3mc` in `pubspec.yaml`). It is maintained alongside `sqlite3`/Drift, supports `PRAGMA key`/`rekey`, and its default cipher is ChaCha20-Poly1305. SQLCipher via `sqlcipher_flutter_libs` is the alternative, but it ties the app to the legacy `sqlite3` 2.x path.
2. **Key:**
   - a random 256-bit key generated on first launch of the encrypting version;
   - stored in `flutter_secure_storage`, which is Keystore-wrapped and already excluded from backup (`sharedpref` domain);
   - never derived from a PIN or password, so offline cashier switching keeps working;
   - never sent to the server.
3. **Open path:** `NativeDatabase.createInBackground(file, isolateSetup: …, setup: (db) => db.execute("PRAGMA key = \"x'<hex>'\""))`, then `select count(*) from sqlite_master` to fail fast on a wrong key.
4. **Verification:** an instrumented test that the file header is not `SQLite format 3\0` and that a wrong key fails to open.

## 4. Data-preserving migration (plaintext → encrypted)

Run once, at startup, before any screen opens the database. Each step is resumable.

1. If a key exists and the file opens with it: done.
2. If no key exists and the file is plaintext:
   1. Generate the key and store it, then read it back to confirm it persisted.
   2. Copy `dukaan_pro.sqlite` to `dukaan_pro.sqlite.pre-encryption`. The SEC-1 rules exclude `dukaan_pro.sqlite*` — **add that exact name to both rule files with this change**, because SEC-1 excludes four exact names, not a wildcard.
   3. Open the plaintext copy and `ATTACH 'dukaan_pro.sqlite.enc' AS enc KEY …`. Export every table into `enc`, and set `PRAGMA user_version` to the Drift schema version. Alternatively, `PRAGMA rekey` the plaintext file in place; sqlite3mc supports this, but not in WAL mode.
   4. Verify the encrypted file:
      - `PRAGMA integrity_check` is `ok`;
      - row counts are equal for every table;
      - `sync_operations` rows that are not `synced` are equal by id.
   5. Atomically rename `.enc` over `dukaan_pro.sqlite` and delete the `-journal`.
   6. Delete `.pre-encryption` only after the app has opened the encrypted file successfully once.
3. If the key exists but the plaintext file is still present (crash mid-migration), resume from step 2.4.
4. **Downgrade:** a pre-encryption APK cannot read the encrypted file. A rollback after encryption requires a full sync followed by clearing app data. Write this into the rollback procedure before rollout.

## 5. Key loss and recovery

| Situation | Effect | Recovery |
| --- | --- | --- |
| App data cleared or app uninstalled | Key and database are both gone | Same as today: sign in and pull from the cloud. Unsynced operations are lost (see §6) |
| Keystore entry lost while the file remains (rare OEM or OS-upgrade defect; also possible if the user removes the screen lock) | Database unreadable | Rename the file to `dukaan_pro.sqlite.unreadable` (kept, not deleted), start a fresh database, pull from the cloud, and show the owner how many outbox rows were pending at the last successful open. The app persists that count in secure storage at each sync |
| Lost or stolen tablet | Data unreadable without the device's Keystore | The owner deactivates the device. Its credential stops working immediately (`dukaan_private.request_device` requires an active device) |

**Key escrow** (a server-held copy of each device key, released to the shop
owner) would make case 2 recoverable. It also makes the server a decryption
oracle for every tablet. Not recommended for the pilot; revisit only if case 2
is observed.

## 6. Unsynced transactions on a lost or broken device (applies now, after SEC-1)

- Sales, returns, voids, Khata payments and other changes committed while offline exist **only on that tablet** until they upload.
- Since SEC-1 they are also **not** in Google backup. Before SEC-1, a backup copy existed, but a restore onto another tablet could not upload them without manual recovery (the device credential is excluded from backup).
- If the tablet is lost, stolen or dead before it syncs, those transactions are lost to the business. Stock, Udhaar and the day's cash must then be reconciled by hand from paper receipts.
- **Controls for the pilot:**
  - the sync chip must show *Synced* before closing the shop, before handing the tablet over, and before any app update or uninstall;
  - background retry runs every 2 minutes while online and on app resume;
  - the owner deactivates a lost device from another device, so it can no longer upload or read shop data.

## 7. Effort and order

1. Release build for the pilot (signing keystore approval): about 0.5 day.
2. sqlite3mc integration, key handling, open path and instrumented tests: about 2 days.
3. Migration with verification and resume, plus upgrade tests from v13 plaintext fixtures: about 2 days.
4. Staged rollout: one tablet, 3 days of normal trade, then the rest.
