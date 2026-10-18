// Security tests for the admin-create-owner and issue-entitlement Edge
// Functions. Run through tool/edge_functions/run_local.sh, which serves both
// functions against the disposable R1 HTTP stack (local only).
import { test, before } from 'node:test'
import assert from 'node:assert/strict'
import { createPublicKey, verify, randomUUID, createHmac } from 'node:crypto'

const env = (k) => { const v = process.env[k]; if (!v) throw new Error(`${k} not set`); return v }
const BASE = env('R1_HTTP_URL'), ANON = env('R1_HTTP_ANON_KEY'), SERVICE = env('EDGE_SERVICE_ROLE_KEY')
const ADMIN_FN = env('EDGE_ADMIN_URL'), ENT_FN = env('EDGE_ENTITLEMENT_URL')
const PUBLIC_KEY = createPublicKey({ key: JSON.parse(env('EDGE_PUBLIC_JWK')), format: 'jwk' })
const run = randomUUID().slice(0, 8)
const PASSWORD = 'Edge-test-pass-123'

async function call(url, { body, token, headers = {}, method = 'POST' } = {}) {
  const h = { 'Content-Type': 'application/json', apikey: ANON, ...headers }
  if (token !== undefined) h.Authorization = `Bearer ${token}`
  const res = await fetch(url, { method, headers: h, body: body === undefined ? undefined : JSON.stringify(body) })
  const text = await res.text()
  // No response, success or refusal, may ever carry the service-role key.
  assert.ok(!text.includes(SERVICE), `service-role key leaked by ${url}`)
  let json = null; try { json = JSON.parse(text) } catch { /* plain text */ }
  return { status: res.status, json, text }
}
async function signUp(email) {
  const r = await call(`${BASE}/auth/v1/signup`, { body: { email, password: PASSWORD } })
  assert.equal(r.status, 200, r.text); assert.ok(r.json.access_token, 'local stack must auto-confirm')
  return { token: r.json.access_token, id: r.json.user.id, email }
}
async function signIn(email, password) {
  return call(`${BASE}/auth/v1/token?grant_type=password`, { body: { email, password } })
}
async function rpc(name, params, token, headers) {
  return call(`${BASE}/rest/v1/rpc/${name}`, { body: params, token, headers })
}
async function ok(name, params, token) {
  const r = await rpc(name, params, token); assert.ok(r.status < 300, `${name}: ${r.status} ${r.text}`); return r.json
}
// RFC 6238 TOTP (SHA-1, 30 s, 6 digits), as authenticator apps compute it.
function totp(secretBase32, at = Date.now()) {
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567'
  let bits = ''
  for (const c of secretBase32.replace(/=+$/, '').toUpperCase()) bits += alphabet.indexOf(c).toString(2).padStart(5, '0')
  const key = Buffer.from(bits.match(/.{8}/g).map((b) => parseInt(b, 2)))
  const counter = Buffer.alloc(8); counter.writeBigUInt64BE(BigInt(Math.floor(at / 30000)))
  const h = createHmac('sha1', key).update(counter).digest()
  const o = h[h.length - 1] & 0xf
  return String((h.readUInt32BE(o) & 0x7fffffff) % 1000000).padStart(6, '0')
}
// Enrols and verifies a TOTP factor through GoTrue; returns the AAL2 token.
async function elevate(session) {
  const f = await call(`${BASE}/auth/v1/factors`, { body: { factor_type: 'totp', friendly_name: `t-${randomUUID()}` }, token: session.token })
  assert.equal(f.status, 200, f.text)
  const c = await call(`${BASE}/auth/v1/factors/${f.json.id}/challenge`, { body: {}, token: session.token })
  assert.equal(c.status, 200, c.text)
  const v = await call(`${BASE}/auth/v1/factors/${f.json.id}/verify`, { body: { challenge_id: c.json.id, code: totp(f.json.totp.secret) }, token: session.token })
  assert.equal(v.status, 200, v.text)
  assert.equal(claims(v.json.access_token).aal, 'aal2')
  return v.json.access_token
}
const claims = (jwt) => JSON.parse(Buffer.from(jwt.split('.')[1], 'base64url').toString())
const canonical = (v) => Array.isArray(v) ? `[${v.map(canonical).join(',')}]`
  : v && typeof v === 'object' ? `{${Object.keys(v).sort().map((k) => `${JSON.stringify(k)}:${canonical(v[k])}`).join(',')}}`
  : JSON.stringify(v)
const entitlement = (body, token, headers) => call(ENT_FN, { body, token, headers })
const createOwner = (body, token, headers) => call(ADMIN_FN, { body, token, headers })

let admin, ownerA, ownerB, shopA, shopB, shopPending, mobileA, tabletA, extraA, deviceB, cashierA
const device = async (owner, shop, type, name) =>
  (await ok('register_shop_device', { p_shop_id: shop, p_device_name: name, p_device_type: type, p_device_identifier: randomUUID() }, owner.token))[0]

before(async () => {
  admin = await signUp(`admin-${run}@r1-admin.test`)
  admin.aal1 = admin.token
  admin.token = await elevate(admin)
  ownerA = await signUp(`owner-a-${run}@edge.test`)
  ownerB = await signUp(`owner-b-${run}@edge.test`)
  shopA = await ok('admin_create_shop', { p_name: `A ${run}`, p_phone: '', p_address: '', p_owner_email: ownerA.email }, admin.token)
  shopB = await ok('admin_create_shop', { p_name: `B ${run}`, p_phone: '', p_address: '', p_owner_email: ownerB.email }, admin.token)
  shopPending = await ok('admin_create_shop', { p_name: `P ${run}`, p_phone: '', p_address: '', p_owner_email: ownerB.email }, admin.token)
  for (const s of [shopA, shopB]) await ok('admin_set_shop_status', { p_shop_id: s, p_status: 'active', p_note: 'edge test' }, admin.token)
  mobileA = await device(ownerA, shopA, 'mobile', 'A phone')
  tabletA = await device(ownerA, shopA, 'androidTablet', 'A tablet')
  extraA = await device(ownerA, shopA, 'mobile', 'A third')
  deviceB = await device(ownerB, shopB, 'mobile', 'B phone')
  assert.deepEqual([mobileA.approval_status, tabletA.approval_status, extraA.approval_status], ['approved', 'approved', 'pending'])
  const secret = await ok('issue_device_credential', { p_shop_id: shopA, p_device_id: mobileA.device_id }, ownerA.token)
  cashierA = { 'x-dukaan-device': `${mobileA.device_id}.${secret}` }
})

// ---------------------------------------------------------------- admin-create-owner
test('admin-create-owner: no Authorization header is 401', async () => {
  const r = await createOwner({ email: `x-${run}@edge.test`, password: PASSWORD })
  assert.equal(r.status, 401)
})

test('admin-create-owner: anon, forged, owner, cashier and service-role callers are refused', async () => {
  const body = { email: `nobody-${run}@edge.test`, password: PASSWORD }
  const forged = admin.token.split('.').slice(0, 2).join('.') + '.AAAA'
  for (const [label, token, headers] of [
    ['anon key', ANON], ['forged JWT', forged], ['owner', ownerA.token], ['cashier device', ANON, cashierA],
    ['service-role key as bearer', SERVICE],
  ]) {
    const r = await createOwner(body, token, headers)
    assert.equal(r.status, 403, `${label}: ${r.status} ${r.text}`)
  }
  // Supplying another identity in the body changes nothing.
  const r = await createOwner({ ...body, user_id: admin.id, admin_id: admin.id, is_platform_admin: true }, ownerA.token)
  assert.equal(r.status, 403)
  assert.equal((await signIn(body.email, PASSWORD)).status, 400, 'no account may have been created')
})

test('admin-create-owner: a platform admin creates an ordinary, audited owner login', async () => {
  const email = `new-owner-${run}@edge.test`
  const r = await createOwner({ email, password: PASSWORD, full_name: 'New Owner',
    app_metadata: { role: 'admin' }, role: 'service_role', is_platform_admin: true }, admin.token)
  assert.equal(r.status, 200, r.text)
  assert.deepEqual(Object.keys(r.json).sort(), ['email', 'user_id'])
  assert.ok(!r.text.includes(PASSWORD), 'password must not be echoed')

  const login = await signIn(email, PASSWORD)
  assert.equal(login.status, 200, login.text)
  assert.equal(login.json.user.id, r.json.user_id)
  assert.equal(await ok('is_platform_admin', {}, login.json.access_token), false, 'created account must not be an admin')
  assert.ok(!('role' in (login.json.user.app_metadata ?? {})))
  assert.equal((await rpc('admin_list_shops', {}, login.json.access_token)).status, 403)

  const audit = await ok('admin_list_audit', { p_shop_id: null, p_limit: 50 }, admin.token)
  const row = audit.find((a) => a.action === 'owner.login_created' && a.details.owner_user_id === r.json.user_id)
  assert.ok(row, 'owner login creation must be audited')
  assert.equal(row.actor_user_id, admin.id); assert.equal(row.actor_kind, 'platform_admin')

  const again = await createOwner({ email, password: PASSWORD }, admin.token)
  assert.equal(again.status, 409)
})

test('admin-create-owner: input is validated', async () => {
  assert.equal((await createOwner({ email: 'not-an-email', password: PASSWORD }, admin.token)).status, 400)
  assert.equal((await createOwner({ email: `short-${run}@edge.test`, password: 'short' }, admin.token)).status, 400)
})

test('audit RPC cannot be driven by non-admins or used to relabel admins', async () => {
  assert.equal((await rpc('admin_record_owner_login_created', { p_user_id: ownerA.id }, ownerA.token)).status, 403)
  assert.equal((await rpc('admin_record_owner_login_created', { p_user_id: ownerA.id }, ANON)).status, 401)
  assert.notEqual((await rpc('admin_record_owner_login_created', { p_user_id: admin.id }, admin.token)).status, 204)
})

test('platform-admin RPCs refuse owners and cashiers server-side', async () => {
  for (const [name, params] of [
    ['admin_list_shops', {}], ['admin_set_shop_status', { p_shop_id: shopB, p_status: 'suspended', p_note: '' }],
    ['admin_approve_device', { p_device_id: extraA.device_id, p_replace_device_id: mobileA.device_id, p_form_factor: null }],
    ['admin_create_shop', { p_name: 'x', p_phone: '', p_address: '', p_owner_email: ownerA.email }],
  ]) {
    const asOwner = await rpc(name, params, ownerA.token)
    assert.ok([401, 403].includes(asOwner.status), `${name} as owner: ${asOwner.status}`)
    const asCashier = await rpc(name, params, ANON, cashierA)
    assert.ok([401, 403, 404].includes(asCashier.status), `${name} as cashier: ${asCashier.status}`)
  }
  assert.equal((await rpc('create_owner_shop', { p_name: 'self', p_phone: '', p_address: '' }, ownerA.token)).status >= 400, true)
})

// ---------------------------------------------------------------- admin MFA (AAL2)
test('MFA: a listed admin with a password-only (aal1) session is refused everywhere', async () => {
  assert.equal(claims(admin.aal1).aal, 'aal1')
  assert.equal(await ok('platform_admin_access', {}, admin.aal1), 'mfa_required')
  assert.equal(await ok('is_platform_admin', {}, admin.aal1), false)
  for (const [name, params] of [
    ['admin_list_shops', {}], ['admin_create_shop', { p_name: 'aal1', p_phone: '', p_address: '', p_owner_email: '' }],
    ['admin_set_shop_status', { p_shop_id: shopB, p_status: 'suspended', p_note: '' }],
    ['admin_renew_subscription', { p_shop_id: shopB, p_plan_id: 'pro_monthly', p_months: 1 }],
    ['admin_assign_owner', { p_shop_id: shopB, p_owner_email: ownerA.email }],
    ['admin_revoke_device', { p_device_id: deviceB.device_id, p_note: '' }],
    ['admin_set_device_form_factor', { p_device_id: deviceB.device_id, p_form_factor: 'tablet' }],
  ]) assert.equal((await rpc(name, params, admin.aal1)).status, 403, name)
  const email = `aal1-${run}@edge.test`
  assert.equal((await createOwner({ email, password: PASSWORD }, admin.aal1)).status, 403)
  assert.equal((await signIn(email, PASSWORD)).status, 400, 'no account may have been created')
  assert.equal(await ok('platform_admin_access', {}, admin.token), 'granted')
})

test('MFA: a wrong code does not elevate the session', async () => {
  const other = await signUp(`admin2-${run}@r1-admin.test`)
  const f = await call(`${BASE}/auth/v1/factors`, { body: { factor_type: 'totp', friendly_name: 'wrong' }, token: other.token })
  const c = await call(`${BASE}/auth/v1/factors/${f.json.id}/challenge`, { body: {}, token: other.token })
  const good = totp(f.json.totp.secret)
  const bad = String((Number(good) + 1) % 1000000).padStart(6, '0')
  const v = await call(`${BASE}/auth/v1/factors/${f.json.id}/verify`, { body: { challenge_id: c.json.id, code: bad }, token: other.token })
  assert.ok(v.status >= 400 && v.status < 500, v.text); assert.ok(!v.json?.access_token)
  assert.equal(await ok('platform_admin_access', {}, other.token), 'mfa_required')
  assert.equal((await rpc('admin_list_shops', {}, other.token)).status, 403)
})

test('MFA: an owner with a verified authenticator is still not an admin', async () => {
  const owner = await signUp(`mfa-owner-${run}@edge.test`)
  const aal2 = await elevate(owner)
  assert.equal(await ok('platform_admin_access', {}, aal2), 'none')
  assert.equal((await rpc('admin_list_shops', {}, aal2)).status, 403)
  assert.equal((await createOwner({ email: `via-owner-${run}@edge.test`, password: PASSWORD }, aal2)).status, 403)
})

test('MFA: a forged aal2 claim is refused', async () => {
  const [h, , sig] = admin.aal1.split('.')
  const payload = Buffer.from(JSON.stringify({ ...claims(admin.aal1), aal: 'aal2' })).toString('base64url')
  const forged = `${h}.${payload}.${sig}`
  assert.equal((await rpc('admin_list_shops', {}, forged)).status, 401)
  assert.equal((await rpc('platform_admin_access', {}, forged)).status, 401)
  assert.equal((await createOwner({ email: `forged-${run}@edge.test`, password: PASSWORD }, forged)).status, 403)
  const unsigned = `${Buffer.from('{"alg":"none","typ":"JWT"}').toString('base64url')}.${payload}.`
  assert.equal((await rpc('admin_list_shops', {}, unsigned)).status, 401)
})

// ---------------------------------------------------------------- issue-entitlement
const verified = (r) => {
  assert.equal(r.status, 200, r.text)
  assert.ok(verify('sha256', Buffer.from(canonical(r.json.payload)), PUBLIC_KEY, Buffer.from(r.json.signature, 'base64url')), 'bad signature')
  assert.deepEqual(Object.keys(r.json).sort(), ['algorithm', 'key_id', 'payload', 'signature'])
  return r.json.payload
}
const refused = (r, code) => { assert.equal(r.status, 403, r.text); if (code) assert.equal(r.json.code, code) }

test('issue-entitlement: unauthenticated callers are refused', async () => {
  assert.equal((await entitlement({ shop_id: shopA, device_id: mobileA.device_id })).status, 401)
  refused(await entitlement({ shop_id: shopA, device_id: mobileA.device_id }, ANON))
  refused(await entitlement({ shop_id: shopA, device_id: mobileA.device_id }, ANON,
    { 'x-dukaan-device': `${mobileA.device_id}.${'0'.repeat(64)}` }), 'DENIED')
})

test('issue-entitlement: the owner gets a signed entitlement for an approved device of their shop', async () => {
  const p = verified(await entitlement({ shop_id: shopA, device_id: mobileA.device_id }, ownerA.token))
  assert.equal(p.shop_id, shopA); assert.equal(p.device_id, mobileA.device_id)
})

test('issue-entitlement: the authorised cashier device gets its own entitlement only', async () => {
  const p = verified(await entitlement({ shop_id: shopA, device_id: mobileA.device_id }, ANON, cashierA))
  assert.equal(p.device_id, mobileA.device_id)
  refused(await entitlement({ shop_id: shopA, device_id: tabletA.device_id }, ANON, cashierA))
  refused(await entitlement({ shop_id: shopB, device_id: deviceB.device_id }, ANON, cashierA))
})

test('issue-entitlement: no cross-shop impersonation by IDs', async () => {
  refused(await entitlement({ shop_id: shopA, device_id: mobileA.device_id }, ownerB.token))
  refused(await entitlement({ shop_id: shopA, device_id: deviceB.device_id }, ownerA.token), 'DPL02')
  refused(await entitlement({ shop_id: shopB, device_id: deviceB.device_id }, ownerA.token))
  refused(await entitlement({ shop_id: shopA, device_id: mobileA.device_id }, admin.token), 'DENIED')
  refused(await entitlement({ shop_id: shopA, device_id: mobileA.device_id }, SERVICE), 'DENIED')
})

test('issue-entitlement: pending device and unsold shop are refused', async () => {
  refused(await entitlement({ shop_id: shopA, device_id: extraA.device_id }, ownerA.token), 'DPL02')
  const pendingDevice = await device(ownerB, shopPending, 'mobile', 'P phone')
  refused(await entitlement({ shop_id: shopPending, device_id: pendingDevice.device_id }, ownerB.token), 'DPL01')
})

test('issue-entitlement: revoked device and suspended shop get no fresh entitlement', async () => {
  await ok('admin_revoke_device', { p_device_id: tabletA.device_id, p_note: 'edge test' }, admin.token)
  refused(await entitlement({ shop_id: shopA, device_id: tabletA.device_id }, ownerA.token), 'DPL02')

  await ok('admin_set_shop_status', { p_shop_id: shopA, p_status: 'suspended', p_note: 'edge test' }, admin.token)
  refused(await entitlement({ shop_id: shopA, device_id: mobileA.device_id }, ownerA.token), 'DPL01')
  refused(await entitlement({ shop_id: shopA, device_id: mobileA.device_id }, ANON, cashierA))
  const audit = await ok('admin_list_audit', { p_shop_id: shopA, p_limit: 50 }, admin.token)
  for (const action of ['shop.suspended', 'device.revoked', 'shop.created', 'shop.owner_assigned'])
    assert.ok(audit.some((a) => a.action === action && a.actor_user_id === admin.id), `${action} audited`)

  await ok('admin_set_shop_status', { p_shop_id: shopA, p_status: 'active', p_note: 'edge test' }, admin.token)
  verified(await entitlement({ shop_id: shopA, device_id: mobileA.device_id }, ownerA.token))
})

test('device replacement is audited and frees exactly one slot', async () => {
  await ok('admin_approve_device', { p_device_id: extraA.device_id, p_replace_device_id: mobileA.device_id, p_form_factor: null }, admin.token)
  refused(await entitlement({ shop_id: shopA, device_id: mobileA.device_id }, ownerA.token), 'DPL02')
  refused(await entitlement({ shop_id: shopA, device_id: mobileA.device_id }, ANON, cashierA))
  verified(await entitlement({ shop_id: shopA, device_id: extraA.device_id }, ownerA.token))
  const audit = await ok('admin_list_audit', { p_shop_id: shopA, p_limit: 50 }, admin.token)
  assert.ok(audit.some((a) => a.action === 'device.replaced' && a.details.replaced_device_id === mobileA.device_id))
})
