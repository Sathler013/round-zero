import {test,expect,type APIRequestContext} from '@playwright/test';
import {createClient} from '@supabase/supabase-js';
import {randomUUID} from 'node:crypto';
const enabled=process.env.RUN_AUTH_E2E==='1';
const email=`journey-${randomUUID()}@example.test`;const password='Local-journey-'+randomUUID();const nextPassword='New-local-'+randomUUID();
async function mailLink(request:APIRequestContext,subject:string){
 const mailpit=process.env.TEST_MAILPIT_URL??'http://127.0.0.1:54324';let messageId='';
 await expect.poll(async()=>{const r=await request.get(mailpit+'/api/v1/search?query='+encodeURIComponent('to:'+email+' subject:'+subject));const data=await r.json();messageId=data.messages?.[0]?.ID??'';return Boolean(messageId);},{timeout:20000}).toBe(true);
 const detail=await(await request.get(mailpit+'/api/v1/message/'+messageId)).json();const match=String(detail.HTML??detail.Text).match(/href="([^"]+)"/);if(!match)throw new Error('No confirmation link in local test email.');return match[1].replaceAll('&amp;','&');
}
test.describe('real Supabase + email + browser journeys',()=>{
 test.skip(!enabled,'NOT VERIFIED: RUN_AUTH_E2E=1 requires a disposable Supabase stack, Mailpit and configured Next server.');
 test('signup, verification, cross-device data, private file, logout and password recovery',async({page,context,browser,request,baseURL})=>{
  if(!process.env.TEST_SUPABASE_URL||!['localhost','127.0.0.1'].includes(new URL(process.env.TEST_SUPABASE_URL).hostname))throw new Error('Local disposable stack required.');
  const admin=createClient(process.env.TEST_SUPABASE_URL,process.env.TEST_SUPABASE_SERVICE_ROLE_KEY!,{auth:{persistSession:false}});
  let userId='';let fileKey='';
  try{
   await page.goto('/cadastro');await page.getByLabel('Como podemos te chamar?').fill('Journey player');await page.getByLabel('E-mail',{exact:true}).fill(email);await page.getByLabel('Senha',{exact:true}).fill(password);await page.getByRole('button',{name:'Criar minha conta'}).click();await expect(page.getByRole('status')).toContainText('receberá um e-mail');
   const confirmation=new URL(await mailLink(request,'Confirme'));await page.goto(baseURL+confirmation.pathname+confirmation.search);await expect(page).toHaveURL(/\/app$/);
   await expect(page.getByRole('link',{name:'Treinar solo',exact:true})).toBeVisible();
   userId=(await admin.auth.admin.listUsers()).data.users.find(u=>u.email===email)?.id??'';expect(userId).not.toBe('');
   await page.goto('/app/treinos');await page.getByRole('button',{name:'Nova sessão',exact:true}).click();const dialog=page.getByRole('dialog');await dialog.getByLabel('Nome da sessão').fill('Treino salvo na nuvem');await dialog.getByLabel('Meta e critério de execução').fill('8 de 10 acertos');await dialog.getByRole('button',{name:'Criar sessão',exact:true}).click();await expect(dialog.getByRole('status')).toContainText('Salvo');await dialog.getByRole('button',{name:'Fechar',exact:true}).last().click();
   const second=await browser.newContext({viewport:{width:390,height:844}});const other=await second.newPage();await other.goto(baseURL+'/entrar');await other.getByLabel('E-mail',{exact:true}).fill(email);await other.getByLabel('Senha',{exact:true}).fill(password);await other.getByRole('button',{name:'Entrar no meu espaço'}).click();await expect(other).toHaveURL(/\/app$/);await other.goto(baseURL+'/app/treinos');await expect(other.getByRole('heading',{name:'Treino salvo na nuvem'})).toBeVisible();expect(await other.evaluate(()=>document.documentElement.scrollWidth<=window.innerWidth)).toBe(true);await second.close();
   await page.goto('/app/demos');await page.getByLabel('Selecionar demo').setInputFiles({name:'journey.dem',mimeType:'application/octet-stream',buffer:Buffer.from('HL2DEMO\0')});await page.getByRole('button',{name:'Enviar demo',exact:true}).click();await expect(page.getByText('Demo pronta para revisão.',{exact:true})).toBeVisible({timeout:30000});
   const metadata=await admin.from('demos').select('*').eq('owner_id',userId).eq('name','journey.dem').single();expect(metadata.error).toBeNull();fileKey=metadata.data.object_key;
   const download=await context.request.get('/api/demos/'+metadata.data.id+'/download');expect(download.status()).toBe(200);expect((await download.body()).byteLength).toBe(8);expect(download.headers()['cache-control']).toContain('no-store');
   await page.goto('/app/configuracoes');await page.getByRole('button',{name:'Sair da conta'}).click();await expect(page).toHaveURL(/\/entrar/);await page.goto('/app');await expect(page).toHaveURL(/\/entrar/);
   await page.goto('/recuperar-senha');await page.getByLabel('E-mail',{exact:true}).fill(email);await page.getByRole('button',{name:'Enviar instruções'}).click();await expect(page.getByRole('status')).toBeVisible();const recovery=new URL(await mailLink(request,'Redefinir'));await page.goto(baseURL+recovery.pathname+recovery.search);await expect(page).toHaveURL(/\/redefinir-senha/);await page.getByLabel('Senha',{exact:true}).fill(nextPassword);await page.getByRole('button',{name:'Salvar nova senha'}).click();await expect(page).toHaveURL(/\/app$/);
  }finally{
   if(fileKey)await admin.storage.from('demos').remove([fileKey]);
   if(userId){await admin.from('demos').delete().eq('owner_id',userId);const sessions=await admin.from('training_sessions').select('id').eq('owner_id',userId);if(sessions.data?.length)await admin.from('training_tasks').delete().in('session_id',sessions.data.map(s=>s.id));await admin.from('training_sessions').delete().eq('owner_id',userId);await admin.auth.admin.deleteUser(userId);}
  }
 });
});
