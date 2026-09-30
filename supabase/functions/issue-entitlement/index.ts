// The RSA private JWK is supplied with `supabase secrets set ENTITLEMENT_PRIVATE_JWK=...`.
// It is never stored in PostgreSQL or returned to Flutter.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const canonical=(v:unknown):string=>Array.isArray(v)?`[${v.map(canonical).join(',')}]`:v&&typeof v==='object'?`{${Object.keys(v as object).sort().map(k=>`${JSON.stringify(k)}:${canonical((v as Record<string,unknown>)[k])}`).join(',')}}`:JSON.stringify(v)
const b64=(b:ArrayBuffer)=>btoa(String.fromCharCode(...new Uint8Array(b))).replaceAll('+','-').replaceAll('/','_').replace(/=+$/,'')

Deno.serve(async(req)=>{
  try {
    const auth=req.headers.get('Authorization'); if(!auth) return new Response('authentication required',{status:401})
    const {shop_id,device_id}=await req.json()
    const client=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_ANON_KEY')!,{global:{headers:{Authorization:auth}}})
    const {data,error}=await client.rpc('entitlement_claims',{p_shop_id:shop_id,p_device_id:device_id}); if(error) throw error
    const key=await crypto.subtle.importKey('jwk',JSON.parse(Deno.env.get('ENTITLEMENT_PRIVATE_JWK')!),{name:'RSASSA-PKCS1-v1_5',hash:'SHA-256'},false,['sign'])
    const signature=await crypto.subtle.sign('RSASSA-PKCS1-v1_5',key,new TextEncoder().encode(canonical(data)))
    return Response.json({payload:data,signature:b64(signature),algorithm:'RS256',key_id:Deno.env.get('ENTITLEMENT_KEY_ID')??'dev-1'})
  } catch(e) { return Response.json({error:String(e)},{status:403}) }
})
