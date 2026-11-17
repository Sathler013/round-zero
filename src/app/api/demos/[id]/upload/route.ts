import {authorizeDemo,upstreamHeaders,storageBase} from '../../../../../lib/file-access';
import {storageAdmin} from '../../../../../lib/supabase/admin';
import {json,noStore,sameOrigin} from '../../../../../lib/http';
export const runtime='nodejs';
const chunkLimit=6*1024*1024;
const tusHeaders={'Tus-Resumable':'1.0.0',...noStore};
async function transfer(request:Request,params:Promise<{id:string}>,method:'POST'|'HEAD'|'PATCH'|'DELETE'){
 if(method!=='HEAD'&&!sameOrigin(request))return json({error:'Invalid origin'},403);
 try{
 const {id}=await params;const {db,demo}=await authorizeDemo(id,true);if(demo.kind!=='file'||demo.state!=='pending')return json({error:'Upload indisponível / Upload unavailable'},409);
 const touched=await db.rpc('touch_demo_upload',{p_id:id});if(touched.error)throw touched.error;
 const admin=storageAdmin();const base=storageBase();
 const existing=(await admin.from('demo_transfers').select('*').eq('demo_id',id).maybeSingle()).data;
 if(method==='POST'&&!existing){
  if(Number(request.headers.get('upload-length'))!==demo.expected_bytes)return json({error:'Tamanho inválido / Invalid size'},400);
  const lock=await admin.from('demo_transfers').insert({demo_id:id,upload_path:''});if(lock.error)return new Response(null,{status:409,headers:tusHeaders});
  const metadata={bucketName:'demos',objectName:demo.object_key!,contentType:'application/octet-stream',cacheControl:'0'};
  const upstream=await fetch(base+'/storage/v1/upload/resumable',{method:'POST',headers:{...upstreamHeaders(),'Tus-Resumable':'1.0.0','Upload-Length':String(demo.expected_bytes),'Upload-Metadata':Object.entries(metadata).map(([k,v])=>k+' '+Buffer.from(v).toString('base64')).join(','),'x-upsert':'false'},cache:'no-store',redirect:'error'});
  const location=upstream.headers.get('location');
  if(upstream.status!==201||!location){await admin.from('demo_transfers').delete().eq('demo_id',id);return json({error:'Não foi possível iniciar o upload / Could not start upload'},502);}
  const remote=new URL(location,base);if(remote.origin!==new URL(base).origin||!remote.pathname.startsWith('/storage/v1/upload/resumable/'))throw new Error('INVALID_UPLOAD_LOCATION');
  const upload_path=remote.pathname+remote.search;const saved=await admin.from('demo_transfers').update({upload_path}).eq('demo_id',id);if(saved.error)throw saved.error;
  return new Response(null,{status:201,headers:{...tusHeaders,Location:`/api/demos/${id}/upload`,'Upload-Offset':'0'}});
 }
 if(!existing){return new Response(null,{status:404,headers:tusHeaders});}
 if(!existing.upload_path)return new Response(null,{status:409,headers:tusHeaders});
 const remote=new URL(existing.upload_path,base);if(remote.origin!==new URL(base).origin||!remote.pathname.startsWith('/storage/v1/upload/resumable/'))throw new Error('INVALID_UPLOAD_LOCATION');
 if(method==='POST')return new Response(null,{status:201,headers:{...tusHeaders,Location:`/api/demos/${id}/upload`}});
 const headers:Record<string,string>={...upstreamHeaders(),'Tus-Resumable':'1.0.0'};
 if(method==='PATCH'){
  const offset=request.headers.get('upload-offset');const length=Number(request.headers.get('content-length')||0);
  if(!offset||!/^\d+$/.test(offset)||Number(offset)>demo.expected_bytes!||length>chunkLimit)return json({error:'Parte de upload inválida / Invalid upload chunk'},400);
  headers['Upload-Offset']=offset;headers['Content-Type']='application/offset+octet-stream';
 }
 let bytes=0;
 const body=method==='PATCH'?request.body?.pipeThrough(new TransformStream<Uint8Array,Uint8Array>({transform(chunk,controller){bytes+=chunk.byteLength;if(bytes>chunkLimit)throw new Error('CHUNK_TOO_LARGE');controller.enqueue(chunk);}})):undefined;
 const upstream=await fetch(remote,{method,headers,body,duplex:'half',cache:'no-store',redirect:'error'} as RequestInit&{duplex:'half'});
 const out=new Headers(tusHeaders);for(const h of ['upload-offset','upload-length','upload-expires']){const v=upstream.headers.get(h);if(v)out.set(h,v);}
 if(method==='DELETE'&&upstream.ok)await admin.from('demo_transfers').delete().eq('demo_id',id);
 return new Response(null,{status:upstream.status,headers:out});
 }catch{return json({error:'Upload interrompido ou acesso revogado. Tente novamente. / Upload interrupted or access revoked. Try again.'},409);}
}
export const POST=(r:Request,c:{params:Promise<{id:string}>})=>transfer(r,c.params,'POST');
export const HEAD=(r:Request,c:{params:Promise<{id:string}>})=>transfer(r,c.params,'HEAD');
export const PATCH=(r:Request,c:{params:Promise<{id:string}>})=>transfer(r,c.params,'PATCH');
export const DELETE=(r:Request,c:{params:Promise<{id:string}>})=>transfer(r,c.params,'DELETE');
export async function OPTIONS(){return new Response(null,{headers:{...tusHeaders,'Tus-Version':'1.0.0','Tus-Extension':'creation,termination','Tus-Max-Size':'524288000'}});}
