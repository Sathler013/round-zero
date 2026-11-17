import {execFileSync} from 'node:child_process';
import {writeFile} from 'node:fs/promises';
const generated=execFileSync('node_modules/.bin/supabase',['gen','types','typescript'],{encoding:'utf8',stdio:['ignore','pipe','inherit']});
if(!generated.includes('export type Database'))throw new Error('No database types returned; existing file preserved.');
await writeFile('src/lib/database.types.ts',generated+"\nexport type Row<T extends keyof Database['public']['Tables']> = Database['public']['Tables'][T]['Row'];\n");
