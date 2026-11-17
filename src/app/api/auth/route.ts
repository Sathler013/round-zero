import {z} from 'zod';
import {serverClient} from '../../../lib/supabase/server';
import {configured,siteUrl} from '../../../lib/config';
import {internalNext} from '../../../lib/domain';
import {json,sameOrigin} from '../../../lib/http';
const schema=z.object({mode:z.enum(['login','signup','recover','resend','reset','logout']),email:z.string().email().max(254).optional(),password:z.string().min(10).max(128).optional(),name:z.string().min(1).max(60).optional(),next:z.string().optional()});
export async function POST(request:Request){
 if(!sameOrigin(request))return json({error:'Origem inválida.'},403);
 if(!configured())return json({error:'A conexão com o Supabase ainda não foi configurada neste ambiente.'},503);
 const parsed=schema.safeParse(await request.json().catch(()=>null));if(!parsed.success)return json({error:'Confira os campos. A senha deve ter pelo menos 10 caracteres.'},400);
 const p=parsed.data;const db=await serverClient();const next=internalNext(p.next);
 if(p.mode==='logout'){await db.auth.signOut();return json({redirect:'/entrar'});}
 if(p.mode==='reset'){
  const {data}=await db.auth.getUser();if(!data.user)return json({error:'Link inválido ou sessão expirada. Solicite um novo link.'},401);
  if(!p.password)return json({error:'Informe sua nova senha.'},400);
  const {error}=await db.auth.updateUser({password:p.password});return error?json({error:'Não foi possível atualizar a senha. Use uma senha diferente e tente novamente.'},400):json({redirect:'/app'});
 }
 if(!p.email)return json({error:'Informe um e-mail válido.'},400);
 if(p.mode==='login'){
  if(!p.password)return json({error:'Informe a senha.'},400);
  const {error}=await db.auth.signInWithPassword({email:p.email,password:p.password});
  if(error)return json({error:error.code==='over_request_rate_limit'?'Muitas tentativas. Aguarde antes de tentar novamente.':'Não foi possível entrar. Confira e-mail, senha e confirmação de e-mail.'},400);
  return json({redirect:next});
 }
 const emailRedirectTo=siteUrl()+'/auth/confirm?next='+encodeURIComponent(next);
 if(p.mode==='signup'){
  if(process.env.PUBLIC_SIGNUP_ENABLED!=='true')return json({error:'Os cadastros estão fechados neste ambiente.'},403);
  if(!p.password||!p.name)return json({error:'Preencha nome e senha.'},400);
  await db.auth.signUp({email:p.email,password:p.password,options:{data:{display_name:p.name},emailRedirectTo}});
 }else if(p.mode==='recover'){
  await db.auth.resetPasswordForEmail(p.email,{redirectTo:siteUrl()+'/auth/callback?next=/redefinir-senha'});
 }else{
  await db.auth.resend({type:'signup',email:p.email,options:{emailRedirectTo}});
 }
 return json({message:'Se a solicitação puder ser atendida, você receberá um e-mail com os próximos passos. Aguarde alguns minutos antes de reenviar.'});
}
