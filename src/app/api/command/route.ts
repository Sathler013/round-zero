import {z} from 'zod';
import {verifiedClient} from '../../../lib/supabase/server';
import {parseCommand} from '../../../lib/commands';
import {message} from '../../../lib/domain';
import {json,sameOrigin} from '../../../lib/http';
import type {Json} from '../../../lib/database.types';
const envelope=z.object({command:z.string().max(50),data:z.unknown(),key:z.string().uuid(),locale:z.enum(['pt-BR','en-US']).default('pt-BR')});
export async function POST(request:Request){
 if(!sameOrigin(request))return json({error:'Origem inválida / Invalid origin'},403);
 if(Number(request.headers.get('content-length')||0)>100000)return json({error:'Dados muito grandes / Payload too large'},413);
 const parsed=envelope.safeParse(await request.json().catch(()=>null));if(!parsed.success)return json({error:'Dados inválidos / Invalid input'},400);
 const p=parsed.data;const payload=parseCommand(p.command,p.data);
 if(!payload?.success)return json({error:p.locale==='en-US'?'Check the highlighted fields.':'Confira os campos destacados.',fields:payload?.error.flatten().fieldErrors??{}},400);
 try{
  const {db}=await verifiedClient();
  const {data,error}=await db.rpc('execute_command',{p_key:p.key,p_command:p.command,p_data:payload.data as Json});
  if(error)return json({error:message(error,p.locale)},error.message.includes('AUTH_REQUIRED')?401:409);
  return json({data});
 }catch(error){return json({error:message(error,p.locale)},401);}
}
