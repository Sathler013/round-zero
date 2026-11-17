import {describe,it,expect} from 'vitest';
import {mkdtempSync,mkdirSync,writeFileSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {createRequire} from 'node:module';
const require=createRequire(import.meta.url);
// The same build preflight is evaluated against fixtures, including the reported import.
const {checkSource}=require('../../scripts/check-source.mjs') as {checkSource:(root?:string,options?:{required?:string[]})=>{files:number;imports:number;issues:string[]}};
function fixture(run:(root:string)=>void){const root=mkdtempSync(join(tmpdir(),'rz-source-'));try{mkdirSync(join(root,'src/app'),{recursive:true});writeFileSync(join(root,'tsconfig.json'),JSON.stringify({compilerOptions:{moduleResolution:'bundler',module:'esnext',paths:{'@/*':['./src/*']}}}));run(root);}finally{rmSync(root,{recursive:true,force:true});}}
describe('source package regression',()=>{
 it('detects the missing Supabase module before Next compilation',()=>fixture(root=>{
  writeFileSync(join(root,'src/app/route.ts'),"import {verifiedClient} from '@/lib/supabase/server'; export {verifiedClient};");
  const result=checkSource(root,{required:['src/lib/supabase/server.ts']});expect(result.issues.some(s=>s.includes('src/lib/supabase/server.ts'))).toBe(true);expect(result.issues.some(s=>s.includes('@/lib/supabase/server'))).toBe(true);
 }));
 it('resolves a relative server import without an alias definition',()=>fixture(root=>{
  writeFileSync(join(root,'tsconfig.json'),JSON.stringify({compilerOptions:{moduleResolution:'bundler',module:'esnext'}}));mkdirSync(join(root,'src/lib/supabase'),{recursive:true});writeFileSync(join(root,'src/lib/supabase/server.ts'),'export const verifiedClient=()=>true;');writeFileSync(join(root,'src/app/route.ts'),"import {verifiedClient} from '../lib/supabase/server'; export {verifiedClient};");
  expect(checkSource(root,{required:['src/lib/supabase/server.ts']}).issues).toEqual([]);
 }));
 it('rejects case differences that break Linux deployment',()=>fixture(root=>{
  mkdirSync(join(root,'src/lib/supabase'),{recursive:true});writeFileSync(join(root,'src/lib/supabase/Server.ts'),'export const server=true;');writeFileSync(join(root,'src/app/route.ts'),"import {server} from '../lib/supabase/server'; export {server};");
  expect(checkSource(root,{required:['src/lib/supabase/server.ts']}).issues.length).toBeGreaterThan(0);
 }));
 it('accepts stylesheet imports handled by Next rather than TypeScript',()=>fixture(root=>{
  writeFileSync(join(root,'src/app/globals.css'),'body { margin: 0; }');writeFileSync(join(root,'src/app/layout.tsx'),"import './globals.css'; export default function Layout() { return null; }");
  expect(checkSource(root,{required:[]}).issues).toEqual([]);
 }));
 it('finds every internal module in the delivered project',()=>{const result=checkSource();expect(result.files).toBeGreaterThan(30);expect(result.imports).toBeGreaterThan(100);expect(result.issues).toEqual([]);});
});
