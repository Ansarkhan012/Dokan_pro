# Platform administration, licensing and the two-device rule

Migrations: `supabase/migrations/202610140001_platform_admin_licensing.sql`,
`202610150001_audit_owner_login_creation.sql` (audits owner logins created by
`admin-create-owner`), `202610160001_platform_admin_mfa.sql` (admin access needs AAL2). Edge Function security tests: `tool/edge_functions/run_local.sh`.
Rollout: `docs/security-phase1-rollout.md`.
Edge Functions: `supabase/functions/issue-entitlement` (updated),
`supabase/functions/admin-create-owner` (new).
Admin panel: `lib/admin/` (separate entry point, not part of the shop APK).

## Who can do what

| Action | Anonymous | Cashier (device credential) | Shop owner | Platform admin |
|---|---|---|---|---|
| Create a shop | no | no | no | `admin_create_shop` |
| Assign owner | no | no | no | `admin_assign_owner` |
| Activate / suspend | no | no | no | `admin_set_shop_status` |
| Renew subscription | no | no | no | `admin_renew_subscription` |
| Register a device | no | no | own shop; beyond the limit it is **pending** | — |
| Approve / reject / replace / revoke device | no | no | no | `admin_*_device` |
| Read entitlement claims | no | own device only | own shop's devices | — |
| Audit log | no | no | no | `admin_list_audit` |

The admin role is a row in `dukaan_private.platform_admins` (keyed by
auth user id, not email; schema not exposed by PostgREST; no client grant).
`create_owner_shop` has no execute grant and raises if reached.

## Bootstrapping the first platform admin (operator, SQL editor)

1. Create the admin's login in Supabase Auth (Dashboard → Authentication →
   Add user), with a strong, unique password and an email used for nothing
   else.
2. In the SQL editor:

   ```sql
   insert into dukaan_private.platform_admins(user_id, note)
   select id, 'Dokan Pro owner' from auth.users where email = '<admin email>';
   ```

3. **Enrol MFA (mandatory, migration 202610160001).** Start the admin panel
   and sign in with the password. The panel shows *Set up two-step
   verification* with a setup key. In Google/Microsoft Authenticator choose
   *Add account → Enter a setup key* (time-based), then type the 6-digit code
   into the panel. Only then do the admin pages open. Every later sign-in
   asks for a current code.
4. **Verify AAL2.** In the panel the shop list loads (it is refused below
   AAL2). Optional SQL Editor check of the factor (no secrets shown):
   ```sql
   select f.factor_type, f.status, f.created_at
     from auth.mfa_factors f join auth.users u on u.id = f.user_id
    where u.email = '<admin email>';   -- expect totp / verified
   ```
   A password-only session gets `platform_admin_access() = 'mfa_required'`
   and every admin RPC and `admin-create-owner` refuse it (42501 / 403).

To remove an admin: `update dukaan_private.platform_admins set is_active = false where user_id = ...`.

### MFA rules

* Every privileged path checks `public.is_platform_admin()`, which requires a
  listed, active admin **and** a JWT with `aal = 'aal2'`: all `admin_*` RPCs,
  `admin_record_owner_login_created` and the `admin-create-owner` Edge
  Function. No bypass code, role or service-role path exists for clients.
* Owners and cashiers are unaffected: nothing else reads the AAL.
* Supabase Auth (TOTP) must stay enabled on the project (on by default for
  hosted projects; locally `[auth.mfa.totp]` in `config.toml`).

### Lost authenticator (recovery)

No backup codes exist; recovery is an operator action, never done from the
panel:

1. Confirm the request out of band (the admin in person or by a known phone
   number). If the account might be compromised, first set
   `platform_admins.is_active = false` for it.
2. Dashboard → Authentication → Users → the admin → remove the MFA factor
   (or SQL Editor:
   `delete from auth.mfa_factors where user_id = (select id from auth.users where email = '<admin email>');`).
   Also reset the password if it may be known to anyone else.
3. The admin signs in again: the panel returns to *Set up two-step
   verification*; enrol a new authenticator (step 3 above). Re-enable
   `is_active` if it was switched off.
4. Note the reset (who, when, why) in the operator log. Admin actions taken
   afterwards are in `admin_list_audit` as usual.

Keep a second platform admin enrolled where possible so one lost phone never
leaves the platform without an administrator.

## Running the admin panel

```bash
flutter run -d windows -t lib/admin/admin_main.dart --dart-define=SUPABASE_URL=<url> --dart-define=SUPABASE_ANON_KEY=<anon key>
```

Only the public anon key is used. The session is kept in memory (sign in on
every launch, password then authenticator code). A non-admin account is
signed out immediately; an admin without a verified authenticator only sees
the enrolment screen. Every action is re-authorised by the database (AAL2)
anyway.

Workflow: **New shop** (optionally creates the owner's login with a
temporary password through `admin-create-owner`) → shop starts **pending** →
**Activate** after payment → **Renew** (plan + months; extends from the later
of today or the current end) → devices appear as the owner registers them.

## Two-device rule

* At most one approved **mobile**, one approved **tablet**, two in total.
* The slot is held while `approval_status = 'approved'`, even if the owner
  switches the device off; switching off and registering another device does
  **not** free a slot. Replacement = admin approves the new device and picks
  the old one under "Replace" (old device revoked, its credential deleted,
  its cashier sessions ended, its entitlements marked revoked).
* Classification: the app sends `mobile` when the Android screen's shortest
  side is < 600 dp, `androidTablet` otherwise. The server stores it at first
  registration and the owner can never change it (column grant + trigger).
  A modified app can mislabel a device, so the **hard** guarantee is the
  total of two; the per-type limit is best effort and the admin can correct
  it (`admin_set_device_form_factor`, or the Slot field when approving).
* A copied device identifier maps to the same device row, never a new slot.

## Updates, reinstalls and replacement (support workflow)

* **In-place APK update** (same package, signed with the same key or the
  rotated release key with lineage, `docs/release-signing.md`): Android keeps
  the app's data, so the device identity (`dukaan_pro.app_device_id.v1` in app
  preferences), the login and the local database are unchanged. Same
  registration, nothing to approve. The identity is never derived from the app
  version.
* **Uninstall/reinstall or "Clear data"**: Android deletes the identity (it is
  also excluded from backups, so it is never cloned). The app registers a
  **new** device. If the shop's slots are taken, the server stores it as
  `pending`; it gets no credential, no cashier login and no entitlement. The
  app shows *"Device replacement requires admin approval"* (English/Urdu) and a
  **device code** (first 8 characters of the registration id) plus *Check
  again*.
* **Never uninstall to "fix" an update.** A failed update leaves the app and
  its unsynced sales intact; uninstalling deletes them.

Replacing a reinstalled device (admin panel → shop → Devices):

1. Ask the owner for the code shown on the device. Find the `pending` row
   with that code. Never approve a code you cannot match to a person.
2. Pick the registration it replaces: the same physical device's previous
   row (the approved one whose activity stopped at the reinstall).
3. If the shop holds more approved registrations than its slots (legacy
   shops, e.g. four old "Android tablet" rows), first **Revoke** the obsolete
   ones one at a time with a note. Approving fails with DPL04 until they fit;
   the panel says so and changes nothing.
4. **Approve** the pending row with *Replace* = the previous row. The old row
   is revoked in the same transaction (credential deleted, cashier sessions
   ended); all its sales stay.
5. Owner taps *Check again* (no restart). The device is active; it fetches a
   fresh entitlement on that reconnect.

Every step is in the audit log (`device.approval_requested`, `device.revoked`,
`device.replaced`).

## Online / offline policy

| Situation | Device online (reconnect) | Device offline |
|---|---|---|
| Active, subscription valid | entitlement refreshed | billing allowed until `valid_until`, warning grace until `offline_grace_until` |
| Subscription expired, not renewed | new token has past `valid_until` → grace → blocked | same, by signed dates |
| Shop suspended / pending | issuance refused (DPL01); app records the refusal → billing **blocked** | billing continues until the cached token's grace ends |
| Device revoked / pending / rejected | refused (DPL02) → blocked; credential and cashier sessions already dead | until the cached token's grace ends |
| Renewal / reactivation | next refresh clears the block | — |

Sales made offline under a valid entitlement still upload after suspension;
suspension never discards financial records.

## Existing shops (compatibility)

* All existing shops are set `active`.
* Existing active devices become `approved` and `legacy_grandfathered`
  (kept even if a shop has more than two); inactive ones become `revoked`.
  A shop over the limit keeps working; new devices then wait for approval.
* Old APKs keep working: `register_shop_device` has the same signature
  (extra result columns are ignored).
* Old APKs that still offer "Create owner account / Create shop" will get an
  error on shop creation (by design).

## Production deployment (requires approval — not done)

Authoritative order and STOP list: `docs/security-phase1-deploy-runbook.md`.

1. Apply the four migrations (`supabase db push --linked`, after `--dry-run`).
2. `supabase functions deploy issue-entitlement` (forwards the device
   credential, returns refusal codes) and `supabase functions deploy admin-create-owner`.
3. Bootstrap the first platform admin (above, including TOTP enrolment).
4. Verify on production: Ali_shop still `active`, its devices `approved`,
   owner login and cashier billing unchanged.
5. Only then, separately approved: Dashboard → Authentication → disable
   "Allow new users to sign up".
6. Release the APK with the new sign-in screen and device classification.

`supabase/dev/r1_local_platform_admin.sql` is for disposable local test
stacks only and must never be applied to a hosted project.
