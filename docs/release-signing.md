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
