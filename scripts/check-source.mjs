import ts from 'typescript';
import {existsSync,readFileSync,readdirSync} from 'node:fs';
import {resolve,relative,sep,dirname} from 'node:path';
import {fileURLToPath} from 'node:url';

const projectRoot=fileURLToPath(new URL('../',import.meta.url));
const critical=['package.json','tsconfig.json','src/lib/supabase/server.ts','src/lib/supabase/admin.ts','src/lib/database.types.ts'];
function exactPath(root,file){
 const rel=relative(root,file);if(rel.startsWith('..'+sep)||rel==='..')return false;
 let current=root;for(const part of rel.split(sep)){if(!existsSync(current)||!readdirSync(current).includes(part))return false;current=resolve(current,part);}return true;
}
export function checkSource(root=projectRoot,{required=critical}={}){
 root=resolve(root);const issues=[];const files=[];let imports=0;
 for(const file of required)if(!existsSync(resolve(root,file))||!exactPath(root,resolve(root,file)))issues.push(`Arquivo obrigatório ausente ou com maiúsculas diferentes: ${file}`);
 const configPath=resolve(root,'tsconfig.json');if(!existsSync(configPath))return {files:0,imports,issues};
 const config=ts.readConfigFile(configPath,ts.sys.readFile);if(config.error){issues.push('Não foi possível ler tsconfig.json.');return {files:0,imports,issues};}
 const parsed=ts.parseJsonConfigFileContent(config.config,ts.sys,root);
 for(const error of parsed.errors.filter(e=>e.code!==18003))issues.push(ts.flattenDiagnosticMessageText(error.messageText,' '));
 const sourceRoot=resolve(root,'src');if(!existsSync(sourceRoot)){issues.push('Pasta src ausente. Envie o projeto inteiro.');return {files:0,imports,issues};}
 function walk(dir){for(const entry of readdirSync(dir,{withFileTypes:true})){const file=resolve(dir,entry.name);if(entry.isDirectory())walk(file);else if(/\.tsx?$/.test(entry.name))files.push(file);}}
 walk(sourceRoot);
 for(const file of files){const info=ts.preProcessFile(readFileSync(file,'utf8'),true,true);
  for(const entry of info.importedFiles){const name=entry.fileName;if(!name.startsWith('@/')&&!name.startsWith('.'))continue;imports++;
   const direct=name.startsWith('.')?resolve(dirname(file),name):null;
   if(direct&&ts.sys.fileExists(direct)){if(!exactPath(root,direct))issues.push(`${relative(root,file)}: maiúsculas diferentes no import ${name}`);continue;}
   const found=ts.resolveModuleName(name,file,parsed.options,ts.sys).resolvedModule;
   if(!found||!existsSync(found.resolvedFileName)||!exactPath(root,found.resolvedFileName))issues.push(`${relative(root,file).split(sep).join('/')}: módulo local não encontrado ou com maiúsculas diferentes: ${name}`);
  }
 }
 return {files:files.length,imports,issues};
}
if(process.argv[1]&&resolve(process.argv[1])===fileURLToPath(import.meta.url)){
 const result=checkSource();
 if(result.issues.length){console.error('SOURCE_INCOMPLETE: o código recebido pelo build está incompleto ou tem caminhos inválidos.');for(const issue of result.issues)console.error(' - '+issue);console.error('Use como raiz a pasta que contém package.json, tsconfig.json e src. Envie todos os arquivos do pacote.');process.exitCode=1;}
 else console.log(`Source OK: ${result.files} arquivos e ${result.imports} imports locais verificados.`);
}
