'use client';
export default function ErrorPage({reset}:{error:Error;reset:()=>void}){return <main className="auth-content" style={{minHeight:'80vh'}}><h1>Vamos tentar de novo.</h1><p className="notice error">Não foi possível consultar seus dados. / Could not load your data.</p><button className="button primary" onClick={reset}>Tentar novamente / Retry</button></main>;}
