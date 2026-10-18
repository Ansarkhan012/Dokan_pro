# Android release signing

Release builds never use the debug key. Provide these values as environment
variables or private Gradle properties (for example in the user-level
`~/.gradle/gradle.properties`, never in this repository):

- `DUKAAN_KEYSTORE_PATH`
- `DUKAAN_KEYSTORE_PASSWORD`
- `DUKAAN_KEY_ALIAS`
- `DUKAAN_KEY_PASSWORD`

`flutter build apk --release` fails clearly when any value is missing. Keep the
keystore and its passwords in the deployment secret store and back up the
keystore securely; losing it prevents signing upgrades to the same Android app.

## Pilot release key (created 2026-10-13)

| Item | Value |
| --- | --- |
| Keystore | `C:\Users\ansar\.dukaan\signing\dukaan-release.jks` (PKCS12, RSA 4096, valid until 2054). Outside the repository; the folder is readable only by its owner |
| Passwords | `C:\Users\ansar\.dukaan\signing\dukaan-release.properties`, in the four `DUKAAN_*` names above. Never printed or committed |
| Alias | `dukaan-release` |
| Certificate SHA-256 | `8ac9097e64db69bee9676741853e6b72b0d3dbf7b33f421e898cf6febad0441b` |
| Rotation lineage | `C:\Users\ansar\.dukaan\signing\debug-to-release.lineage` (debug key → release key) |

**Back up `dukaan-release.jks` and `dukaan-release.properties` together to the
secret store before the first release install.** After a tablet runs a build
signed with this key, only this key can ever update the app without wiping
its data.

## Moving installed debug-signed pilots to release (data preserved)

Pilot tablets run debug builds signed with the developer machine's debug key
(certificate SHA-256 `3c0612…efd7b3`). Android accepts an update only from the
same signer, or from a new signer that carries a signed proof of rotation
(APK Signature Scheme v3, Android 9 and later). An APK signed only with the
new key is **refused** (`INSTALL_FAILED_UPDATE_INCOMPATIBLE`). Uninstalling
instead would delete the database, including unsynced sales. So the first
release must carry the lineage:

```powershell
# 1. Build (Gradle signs with the release key only).
flutter build apk --release --dart-define-from-file="C:\Users\ansar\.dukaan\pilot_defines.json"
# 2. Re-sign: v2 with the debug key (Android 7-8.1), v3 with the release key
#    plus the debug-to-release lineage (Android 9+).
java -jar <build-tools>\lib\apksigner.jar sign `
  --ks %USERPROFILE%\.android\debug.keystore --ks-key-alias androiddebugkey --ks-pass env:DEBUG_KS_PASS --key-pass env:DEBUG_KS_PASS `
  --next-signer --ks %DUKAAN_KEYSTORE_PATH% --ks-key-alias %DUKAAN_KEY_ALIAS% --ks-pass env:DUKAAN_KEYSTORE_PASSWORD --key-pass env:DUKAAN_KEY_PASSWORD `
  --lineage C:\Users\ansar\.dukaan\signing\debug-to-release.lineage --rotation-min-sdk-version 28 `
  --out dukaan-release.apk build\app\outputs\flutter-apk\app-release.apk
# 3. Check: v3 signer is the release key; lineage lists the debug key first.
java -jar <build-tools>\lib\apksigner.jar lineage --in dukaan-release.apk --print-certs
```

`DEBUG_KS_PASS` is the Android SDK's standard debug-keystore password. The
lineage gives the debug key *installed data* (data is kept) but not
*rollback* (a debug-signed APK can no longer replace the release app).

Verified on 2026-10-13 on an Android 15 (API 35) emulator, booted read-only
so the AVD was left unchanged:

| Step | Result |
| --- | --- |
| Debug pilot (2026-10-13) installed with `adb install -r` | Success; first install time unchanged (2026-09-20) |
| Release APK signed **only** with the new key | **Refused**: `INSTALL_FAILED_UPDATE_INCOMPATIBLE`; app and its files untouched |
| Release APK with the lineage | **Success**. Same UID, same first install time (an update, so Android keeps `/data/data`); `DEBUGGABLE` flag gone; `run-as` refused; signature v3 with the debug key as past signer |
| Launch | Starts and renders Owner sign in; no fatal exception |
| Debug APK again (rollback) | Refused: `INSTALL_FAILED_UPDATE_INCOMPATIBLE` |
| Later release signed with the new key only | Accepted |

**Not proven on the emulator:** that files written by the debug build are
readable by the release build. `run-as` is impossible once the app is not
debuggable, and the Play-image emulator cannot be rooted. Android keeps the
data directory on every successful update of the same package and UID, which
is what was observed. Confirm on the tablet before uninstalling anything:
after the update, the pending sales and Bills from before the update must
still be there.

**If `adb install -r` of the release APK fails on a tablet, do not uninstall
the app.** The installed app and its unsynced data are untouched by a failed
install. Stop, keep the debug build in use, and investigate.

**Later releases:** once the rotated build is installed, an APK signed with
the release key alone (the plain Gradle output) is accepted. Keep signing with
the lineage anyway: it costs nothing and covers any tablet still on a
debug-signed build.
