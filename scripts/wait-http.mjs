const target=process.argv[2];if(!target)throw new Error('URL required');
let ready=false;for(let i=0;i<40;i++){try{const r=await fetch(target);if(r.ok){ready=true;break;}}catch{}await new Promise(r=>setTimeout(r,500));}
if(!ready)throw new Error('Application did not become ready.');
