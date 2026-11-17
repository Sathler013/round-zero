import Link from 'next/link';
import {notFound} from 'next/navigation';
import {Brand,TacticMap} from '../../../components/brand';
import {AuthForm} from '../../../components/auth-form';
import {configured,tr,type Locale} from '../../../lib/config';
import {internalNext} from '../../../lib/domain';
export const dynamic='force-dynamic';
export default async function AuthPage({params,searchParams}:{params:Promise<{authpage:string}>;searchParams:Promise<Record<string,string|undefined>>}){
 const {authpage}=await params;const search=await searchParams;const modes={entrar:'login',cadastro:'signup','recuperar-senha':'recover','redefinir-senha':'reset'} as const;
 if(!(authpage in modes))notFound();const mode=modes[authpage as keyof typeof modes];const locale:Locale=search.lang==='en-US'?'en-US':'pt-BR';
 return <div className="auth-page" lang={locale}><aside className="auth-art"><Link href="/"><Brand/></Link><TacticMap/><div><p className="eyebrow">TRAIN WITH PURPOSE</p><h1>{tr(locale,'O próximo round','The next round')}<br/><span>{tr(locale,'começa aqui.','starts here.')}</span></h1><p>{tr(locale,'Encontre adversários, alinhe seu time e transforme cada revisão no seu próximo treino.','Find opponents, align your team and turn every review into your next training session.')}</p></div><div className="auth-art-bottom"><span>CS2 WORKSPACE</span><span>PREPARE. PLAY. IMPROVE.</span></div></aside><main className="auth-content"><AuthForm mode={mode} locale={locale} ready={configured()} signup={process.env.PUBLIC_SIGNUP_ENABLED==='true'} next={internalNext(search.next)} initialError={search.erro?tr(locale,search.erro==='link-expirado'?'Este link é inválido ou expirou. Solicite um novo.':'Sua sessão expirou. Entre novamente.',search.erro==='link-expirado'?'This link is invalid or expired. Request a new one.':'Your session expired. Sign in again.'):undefined}/></main></div>;
}
