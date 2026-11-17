import {spawn} from 'node:child_process';
// Accept the managed preview launcher's host/port flags while running real Next.js.
const input=process.argv.slice(2),args=['dev'];
for(let i=0;i<input.length;i++){if(input[i]==='--strictPort')continue;args.push(input[i]==='--host'?'--hostname':input[i]);}
if(!args.includes('--hostname'))args.push('--hostname','0.0.0.0');
const child=spawn(process.execPath,['node_modules/next/dist/bin/next',...args],{stdio:'inherit',env:process.env});
for(const signal of ['SIGINT','SIGTERM'])process.on(signal,()=>child.kill(signal));
child.on('exit',code=>{process.exitCode=code??1;});
