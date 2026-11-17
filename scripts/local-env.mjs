import {execFileSync} from 'node:child_process';
import {writeFile} from 'node:fs/promises';
// Only local status. Credentials are never printed or committed.
const stdout=execFileSync('node_modules/.bin/supabase',['status','-o','env'],{encoding:'utf8',stdio:['ignore','pipe','inherit']});
const entries=Object.fromEntries(stdout.split('\n').filter(l=>/^[A-Z_]+=/.test(l)).map(l=>{const i=l.indexOf('=');return [l.slice(0,i),l.slice(i+1).replace(/^"|"$/g,'')];}));
const url=entries.API_URL??entries.SUPABASE_URL;const publishable=entries.ANON_KEY??entries.PUBLISHABLE_KEY;const service=entries.SERVICE_ROLE_KEY??entries.SECRET_KEY;
if(!url||!publishable||!service)throw new Error('Local Supabase status did not return the required URL and keys.');
if(!['localhost','127.0.0.1'].includes(new URL(url).hostname))throw new Error('Refusing to configure a non-local endpoint.');
const content={NEXT_PUBLIC_SUPABASE_URL:url,NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY:publishable,SUPABASE_SERVICE_ROLE_KEY:service,SITE_URL:'http://localhost:3000',PUBLIC_SIGNUP_ENABLED:'true',TEST_SUPABASE_URL:url,TEST_SUPABASE_ANON_KEY:publishable,TEST_SUPABASE_SERVICE_ROLE_KEY:service};
await writeFile('.env.local',Object.entries(content).map(([k,v])=>`${k}=${v}`).join('\n')+'\n',{mode:0o600});
console.log('Local environment configured. Credentials were not printed.');
