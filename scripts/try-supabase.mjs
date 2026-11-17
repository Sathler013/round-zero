import {spawn} from 'node:child_process';
const child=spawn('node_modules/.bin/supabase',['start','--runtime','native','--stack','round-zero-qa','--eager','--output-format','json'],{env:{...process.env,SUPABASE_EXPERIMENTAL_STACK:'1'},stdio:['ignore','pipe','pipe']});
let out='',err='';child.stdout.on('data',b=>out+=b);child.stderr.on('data',b=>{err+=b;});
child.on('close',code=>{
 if(code===0){console.log('Local Supabase native stack started.');}
 else{console.log('Native Supabase unavailable. Exit',code);console.log((err+"\n"+out).slice(-5000).replace(/(?:eyJ)[A-Za-z0-9._-]+/g,'[redacted-local-token]').replace(/sb_(?:secret|publishable)_[A-Za-z0-9_-]+/g,'[redacted-local-key]'));}
 process.exitCode=code??1;
});
