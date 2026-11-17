import {createClient} from '@supabase/supabase-js';
import {existsSync} from 'node:fs';
if(existsSync('.env.local'))process.loadEnvFile('.env.local');
const url=process.env.NEXT_PUBLIC_SUPABASE_URL,key=process.env.SUPABASE_SERVICE_ROLE_KEY;
if(!url||!key)throw new Error('Storage server configuration is required.');
const apply=process.argv.includes('--apply');const cutoff=new Date(Date.now()-48*3600000).toISOString();
const db=createClient(url,key,{auth:{persistSession:false}});
const {data,error}=await db.from('demos').select('id,object_key').eq('kind','file').in('state',['pending','failed']).lt('created_at',cutoff).lt('activity_at',cutoff).limit(100);
if(error)throw new Error('Could not inspect stale uploads.');
console.log(`${data.length} stale upload(s), mode=${apply?'apply':'dry-run'}. No filenames or private URLs are logged.`);
if(apply)for(const d of data){
 // A completed object may be waiting for a lost finalize response. Preserve it.
 const object=await db.storage.from('demos').info(d.object_key);if(!object.error&&object.data)continue;
 const claimed=await db.rpc('claim_stale_upload',{p_id:d.id,p_before:cutoff});
 if(claimed.error||!claimed.data)continue;
 // Completed objects are preserved; the provider expires incomplete TUS resources.

}
