import {authorizeDemo,upstreamHeaders,storageBase} from '../../../../../lib/file-access';
import {json,noStore} from '../../../../../lib/http';
export const runtime='nodejs';
export async function GET(request:Request,{params}:{params:Promise<{id:string}>}){
 try{
 const {demo}=await authorizeDemo((await params).id);if(demo.kind!=='file'||demo.state!=='ready'||!demo.object_key)return json({error:'Arquivo indisponível / File unavailable'},404);
 const headers:Record<string,string>={...upstreamHeaders()};const range=request.headers.get('range');if(range&&/^bytes=\d*-\d*$/.test(range))headers.Range=range;
 const upstream=await fetch(`${storageBase()}/storage/v1/object/authenticated/demos/${demo.object_key.split('/').map(encodeURIComponent).join('/')}`,{headers,cache:'no-store',redirect:'error'});
 if(!upstream.ok)return json({error:'Arquivo indisponível. Tente novamente. / File unavailable. Try again.'},upstream.status===404?404:502);
 const out=new Headers(noStore);out.set('Content-Type','application/octet-stream');out.set('Content-Disposition',`attachment; filename="demo.dem"; filename*=UTF-8''${encodeURIComponent(demo.name)}`);out.set('X-Content-Type-Options','nosniff');
 for(const h of ['content-length','content-range','accept-ranges']){const v=upstream.headers.get(h);if(v)out.set(h,v);}
 return new Response(upstream.body,{status:upstream.status,headers:out});
 }catch{return json({error:'Arquivo indisponível ou acesso revogado / File unavailable or access revoked'},404);}
}
