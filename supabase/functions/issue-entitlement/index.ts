// The RSA private JWK is supplied with `supabase secrets set ENTITLEMENT_PRIVATE_JWK=...`.
// It is never stored in PostgreSQL or returned to Flutter.
//
// Callers: the owner (Authorization: owner JWT) or cashier mode (anon key plus
// the x-dukaan-device credential). entitlement_claims decides; this function
// only forwards the caller's own credentials and signs what it returns.
// Refusals carry a stable `code` (DPL01 shop not active, DPL02 device not
// approved, DPL03 no subscription, DENIED otherwise) so the app can record a
// revocation instead of treating it as an outage.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const canonical=(v:unknown):string=>Array.isArray(v)?`[${v.map(canonical).join(',')}]`:v&&typeof v==='object'?`{${Object.keys(v as object).sort().map(k=>`${JSON.stringify(k)}:${canonical((v as Record<string,unknown>)[k])}`).join(',')}}`:JSON.stringify(v)
const b64=(b:ArrayBuffer)=>btoa(String.fromCharCode(...new Uint8Array(b))).replaceAll('+','-').replaceAll('/','_').replace(/=+$/,'')
const refusalCode=(message:string)=>/DPL0[0-9]/.exec(message)?.[0]??'DENIED'

Deno.serve(async(req)=>{
  const auth=req.headers.get('Authorization'); if(!auth) return new Response('authentication required',{status:401})
  let body:{shop_id?:unknown,device_id?:unknown}
  try { body=await req.json() } catch { return Response.json({error:'invalid request',code:'INVALID'},{status:400}) }
  const headers:Record<string,string>={Authorization:auth}
  const device=req.headers.get('x-dukaan-device'); if(device) headers['x-dukaan-device']=device
  const client=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_ANON_KEY')!,{global:{headers},auth:{persistSession:false}})
  const {data,error}=await client.rpc('entitlement_claims',{p_shop_id:body.shop_id,p_device_id:body.device_id})
  if(error) return Response.json({error:'entitlement refused',code:refusalCode(error.message??'')},{status:403})
  try {
    const key=await crypto.subtle.importKey('jwk',JSON.parse(Deno.env.get('ENTITLEMENT_PRIVATE_JWK')!),{name:'RSASSA-PKCS1-v1_5',hash:'SHA-256'},false,['sign'])
    const signature=await crypto.subtle.sign('RSASSA-PKCS1-v1_5',key,new TextEncoder().encode(canonical(data)))
    return Response.json({payload:data,signature:b64(signature),algorithm:'RS256',key_id:Deno.env.get('ENTITLEMENT_KEY_ID')??'dev-1'})
  } catch { return Response.json({error:'signing unavailable',code:'UNAVAILABLE'},{status:503}) }
})
