// Creates a shop owner's login for the private admin panel.
//
// Public sign-up is disabled, so owner accounts are created here, with the
// service-role key that the Edge runtime injects (SUPABASE_SERVICE_ROLE_KEY).
// That key never leaves the server. The caller must be a platform admin; this
// is checked by calling public.is_platform_admin() with the caller's own JWT,
// so the decision is the database's, never a client flag. Since migration
// 202610160001 that check also requires the JWT's aal claim to be 'aal2'
// (verified TOTP); a password-only admin session is refused here too.
// Linking the account to a shop is a separate, audited RPC
// (admin_assign_owner); the account creation itself is audited by
// admin_record_owner_login_created.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const json=(body:unknown,status=200)=>Response.json(body,{status,headers:cors})
const cors={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization, x-client-info, apikey, content-type'}

Deno.serve(async(req)=>{
  if(req.method==='OPTIONS') return new Response('ok',{headers:cors})
  const auth=req.headers.get('Authorization'); if(!auth) return json({error:'authentication required'},401)
  const url=Deno.env.get('SUPABASE_URL')!
  const caller=createClient(url,Deno.env.get('SUPABASE_ANON_KEY')!,{global:{headers:{Authorization:auth}},auth:{persistSession:false}})
  const {data:isAdmin,error:roleError}=await caller.rpc('is_platform_admin')
  if(roleError||isAdmin!==true) return json({error:'platform administrator with verified MFA required'},403)

  let body:{email?:unknown,password?:unknown,full_name?:unknown}
  try { body=await req.json() } catch { return json({error:'invalid request'},400) }
  const email=typeof body.email==='string'?body.email.trim().toLowerCase():''
  const password=typeof body.password==='string'?body.password:''
  const fullName=typeof body.full_name==='string'?body.full_name.trim():''
  if(!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) return json({error:'valid email required'},400)
  if(password.length<10) return json({error:'temporary password must have at least 10 characters'},400)

  const service=createClient(url,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,{auth:{persistSession:false,autoRefreshToken:false}})
  const {data,error}=await service.auth.admin.createUser({email,password,email_confirm:true,user_metadata:{full_name:fullName}})
  if(error) return json({error:error.message.includes('already')?'an account with this email already exists':'could not create account'},409)
  // Audited with the admin's own JWT, so the actor is the real caller.
  const {error:auditError}=await caller.rpc('admin_record_owner_login_created',{p_user_id:data.user?.id})
  if(auditError) return json({error:'account created but audit failed',user_id:data.user?.id},500)
  return json({user_id:data.user?.id,email})
})
