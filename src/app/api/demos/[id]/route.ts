import {authorizeDemo} from '../../../../lib/file-access';
import {storageAdmin} from '../../../../lib/supabase/admin';
import {json,sameOrigin} from '../../../../lib/http';
export const runtime='nodejs';
export async function POST(request:Request,{params}:{params:Promise<{id:string}>}){
 if(!sameOrigin(request))return json({error:'Invalid origin'},403);
 try{
 const {id}=await params;const {demo}=await authorizeDemo(id,true);if(demo.kind!=='file'||!demo.object_key)return json({error:'Arquivo inválido / Invalid file'},400);
 const admin=storageAdmin();const {data,error}=await admin.storage.from('demos').info(demo.object_key);
 if(error||!data||data.size!==demo.expected_bytes)return json({error:'O envio ainda não foi confirmado ou tem tamanho incorreto. Tente novamente. / Upload not confirmed or incorrect size. Retry.'},409);
 const finalized=await admin.rpc('mark_demo_uploaded',{p_id:id,p_bytes:data.size});if(finalized.error)throw finalized.error;
 await admin.from('demo_transfers').delete().eq('demo_id',id);return json({ready:true});
 }catch{return json({error:'Não foi possível confirmar o arquivo / Could not confirm file'},409);}
}
export async function DELETE(request:Request,{params}:{params:Promise<{id:string}>}){
 if(!sameOrigin(request))return json({error:'Invalid origin'},403);
 try{
 const {id}=await params;const {db,demo}=await authorizeDemo(id,true);
 if(demo.object_key){const {error}=await storageAdmin().storage.from('demos').remove([demo.object_key]);if(error)throw error;}
 const {error}=await db.rpc('delete_demo_metadata',{p_id:id});if(error)throw error;return json({deleted:true});
 }catch{return json({error:'Não foi possível excluir. Seu registro foi preservado para nova tentativa. / Could not delete. Your record is preserved for retry.'},409);}
}
