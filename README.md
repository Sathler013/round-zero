# Round Zero

Aplicação de treino e organização de times de CS2 em Next.js App Router, TypeScript estrito, Supabase Auth/PostgreSQL/Storage. Interface em português do Brasil e inglês dos EUA, com visual próprio baseado na referência fornecida. A marca está em `src/lib/config.ts`; os tokens visuais estão em `src/app/globals.css`.

**Entrega sem publicação.** Não foi criado projeto remoto, conta externa ou cadastro público. `/` e `/demonstracao` exibem uma demonstração identificada, fictícia e somente leitura. `/app` usa exclusivamente dados de uma sessão real do Supabase. Sem configuração, o aplicativo encaminha para a entrada e informa o que falta; não simula login nem grava dados do produto no navegador.

## O que está implementado

- Cadastro com confirmação, login, reenvio neutro, recuperação/redefinição, renovação de cookies e saída. Sessão verificada no servidor e proteção em cada API.
- Espaço solo separado de múltiplos times, onboarding, seletor de time, convites individuais com hash, expiração, revogação e aceite transacional. Administração de papéis, remoção, saída e transferência de propriedade.
- Funções de jogo por mapa/lado independentes do papel de acesso. Catálogo extensível de mapas.
- Sessões, exercícios/checklists, edição, status, duplicação limpa de sessão/semana, reagendamento, cancelamento/arquivo, resultados, dificuldades, metas com unidade e confirmação de presença.
- Disponibilidade informativa individual e bloqueios explícitos de agenda. Sessões coletivas podem reservar horário pela mesma regra das scrims.
- Playbook por mapa/lado, posições, utilitárias, funções, chamadas, plano B, referência HTTPS e status/arquivo.
- Biblioteca curada com modelo AWPer e cópia para uma nova sessão privada.
- Mural público separado de informações privadas; propostas, contrapropostas e versões históricas; aceites idempotentes, reserva atômica dos dois times, consumo da vaga, remarcação, recusa, retirada, expiração, cancelamento e notificações.
- Sala compartilhada apenas entre membros ativos dos participantes, instruções privadas de servidor, relatos de placar separados e resultado compartilhado somente por acordo. Convite privado para revanche.
- Bucket privado, metadados autorizados, upload TUS em partes com progresso/pausa/retomada, validação de conclusão no servidor, download autenticado transmitido por streaming, link externo HTTPS e exclusão autorizada.
- Revisão privada vinculada opcionalmente à scrim/demo e conversão idempotente em treino do mesmo espaço.
- Taxa de acerto definida como soma dos acertos / soma das tentativas, amostra, minutos e comparação semanal/mensal entre intervalos equivalentes. Sem tentativas não gera taxa zero.
- RLS, grants mínimos, RPCs, trilha de auditoria, recibos de idempotência, migrações, seed curado, testes e CI.

O relatório de execução está em [docs/VALIDACAO.md](docs/VALIDACAO.md). Código implementado não equivale a uma integração remota já configurada: os testes HTTP de Auth/Storage e as jornadas automatizadas completas ainda dependem do ambiente indicado abaixo.

## Requisitos

- Node.js 22 ou 24; a entrega foi verificada com Node 24.
- npm e o `package-lock.json` incluído. Use `npm ci` para reproduzir as versões.
- Para o Supabase local completo: Docker em execução e Supabase CLI 3.2.0, já fixado nas dependências de desenvolvimento.
- Navegador Chromium instalado pelo Playwright para as jornadas automatizadas.
- O teste SQL sem Docker usa PostgreSQL 18.6 nativo descartável, obtido pela dependência `embedded-postgres`. Ele verifica SQL/RLS/transações; não substitui GoTrue, PostgREST ou Storage HTTP. O Supabase local/CI usa PostgreSQL 17.

## Iniciar apenas a interface de demonstração

```bash
npm ci
npm run dev
```

Abra `http://localhost:3000`. Navegue pela demonstração, inclusive `?lang=en-US`. Os botões que exigem gravação encaminham para o fluxo de conta real. A imagem de referência não está embutida como interface ou fundo.

## Inicializar a aplicação completa localmente

Os comandos desta seção são **exclusivamente para um banco local descartável**. Nunca execute reset contra um banco compartilhado.

```bash
npm ci
npx supabase start
npx supabase db reset
npm run local:env
npm run dev
```

O CLI v3 usa destino local por padrão para `db reset`; não acrescente `--remote`. `npm run local:env` lê o status local e cria `.env.local` ignorado pelo Git, sem imprimir credenciais. Ele recusa endpoints hospedados e habilita cadastro apenas neste ambiente local.

Se preferir, copie `.env.example` para `.env.local` e preencha os valores localmente. Nunca envie chaves privadas no chat, commit ou arquivo publicado. A chave de serviço só é usada no broker de arquivos e nas ferramentas de manutenção/teste; operações normais usam a identidade do usuário.

Endpoints locais configurados:

| Serviço | Endereço |
| --- | --- |
| Aplicação | http://localhost:3000 |
| Supabase API | http://127.0.0.1:54321 |
| PostgreSQL | localhost:54322 |
| Studio | http://localhost:54323 |
| Mailpit, caixa de e-mail de teste | http://localhost:54324 |

No CLI atual, a caixa de teste usa `[local_smtp]`, e os templates ficam em `supabase/templates`. Os e-mails locais não são entregues a pessoas reais. Abra o Mailpit, confirme a conta e continue o fluxo. O convite é preservado pelo destino validado de confirmação; abra o link usando a conta com o e-mail exato convidado.

Em Linux sem Docker, o CLI oferece runtime nativo experimental:

```bash
SUPABASE_EXPERIMENTAL_STACK=1 npx supabase start --runtime native --stack round-zero-dev --eager
```

Ele exige acesso aos arquivos oficiais de `supabase/slim-services` ou ao host S3 de distribuição e suporte local a processos do banco. Não muda a aplicação para uma implementação fictícia. Neste ambiente, o download desses serviços foi bloqueado por resolução de rede; por isso não houve validação HTTP completa.

## Testes e build

```bash
npm run typecheck
npm run lint
npm test
npm run test:db
npm run build
```

`test:db` cria um cluster PostgreSQL temporário, aplica todas as migrações em ordem e remove o cluster no final. Os usuários e claims usados ali são fixtures SQL para verificar as políticas reais, não um substituto de Auth para o aplicativo.

Com Supabase local, `.env.local` criado e banco descartável:

```bash
npx supabase test db
npm run test:integration
npx playwright install chromium
npm run build
npm start
```

Em outro terminal:

```bash
RUN_AUTH_E2E=1 PLAYWRIGHT_BASE_URL=http://localhost:3000 npm run test:e2e
```

O runner de integração recusa URLs remotas e falha explicitamente sem as variáveis `TEST_SUPABASE_*`. O teste Auth no navegador é marcado não executado quando `RUN_AUTH_E2E` não está habilitado. Para considerar o aceite completo, rode-o com `RUN_AUTH_E2E=1`; um relatório só de testes públicos não prova cadastro, sincronização ou arquivos.

As jornadas incluem cadastro/caixa de e-mail/verificação, login, sincronização em outro contexto mobile, upload/download privado, saída e recuperação de senha. Os testes SQL verificam concorrência, não sobreposição, atomicidade, versões, remarcação, convites e isolamento. A suíte HTTP verifica a resposta da Data API e do Storage para dono, membro, adversário e conta de fora. Não verifica só botões escondidos.

O workflow `.github/workflows/ci.yml` instala dependências, roda lógica, SQL, build, inicia Supabase descartável, aplica migrações, executa pgTAP, integrações HTTP e jornadas desktop/mobile. Não faz deploy. A definição está entregue, mas não foi executada em um provedor de CI nesta sessão.

## Ambientes e configuração de produção

Use projetos Supabase distintos para desenvolvimento, homologação e produção, com URLs e credenciais específicas. Não reaproveite um banco de teste como produção.

Antes de qualquer publicação autorizada:

1. Execute as suites no ambiente de homologação. Revise o relatório e os limites do plano contratado.
2. Configure `SITE_URL` com a origem HTTPS real; `NEXT_PUBLIC_SUPABASE_URL` e a chave pública com os valores do ambiente; guarde `SUPABASE_SERVICE_ROLE_KEY` apenas no gerenciador de segredos do servidor.
3. Configure no Auth a Site URL e os callbacks específicos `/auth/confirm`, `/auth/callback` e `/redefinir-senha`. Não use redirecionamentos de domínio aberto. O servidor só aceita destinos internos conhecidos.
4. Copie os templates de confirmação e recuperação. O template de confirmação utiliza `RedirectTo`, preservando o fluxo de convite depois do cadastro.
5. Configure SMTP real, domínio/remetente e limites/intervalos no provedor. Verifique confirmação, recuperação, links expirados e reenvio neutro. Mantenha signup desabilitado no próprio Supabase e `PUBLIC_SIGNUP_ENABLED=false` até a abertura ser autorizada. A flag da interface não substitui o controle do servidor Auth.
6. Aplique novas migrações pelo fluxo de migração do projeto de destino, com backup anterior. Não use reset remoto nem reescreva migrações aplicadas.
7. Confirme bucket `demos` privado e sem políticas de acesso direto para `anon`/`authenticated`. Não adicione política `SELECT` de Storage: ela permitiria gerar URLs assinadas reutilizáveis e quebraria a revogação por solicitação.
8. Verifique a capacidade real de arquivos: desenvolvimento foi configurado para 500 MiB, com partes de 6 MiB. Planos/proxies com limite menor precisam de ajuste conjunto do bucket, constraint de metadados, validação `demo.create`, configuração central e limite do proxy. Não suponha que o limite local vale para qualquer plano remoto.
9. A hospedagem deve suportar Node, SSR/cookies, streaming de download e corpos de upload de pelo menos 6 MiB. Um export estático não executa esta aplicação. Se a plataforma limitar o corpo a menos de 6 MiB, adapte o broker ou escolha uma hospedagem compatível antes de habilitar demos.
10. Confirme `Cache-Control: private, no-store` em sessão, páginas privadas, sala e arquivos; desative cache compartilhado do proxy nessas rotas. Valide a CSP com o domínio final.

Não foi registrada/publicada uma instância Sites, porque o pedido não autoriza produção. O código Next.js pode ser executado em um servidor Node compatível; publicar em um runtime diferente exige um adaptador verificado e nova autorização. Não foi substituído por Vinext/Worker ou por um site estático para contornar essa condição.

## Modelo de privacidade e permissões

Veja [docs/PERMISSOES.md](docs/PERMISSOES.md), [docs/ARQUITETURA.md](docs/ARQUITETURA.md) e [docs/RPCS.md](docs/RPCS.md).

- O espaço selecionado na URL é preferência de navegação. Associação ativa no banco decide acesso.
- Jogador não altera o próprio papel. Função de jogo IGL não equivale ao papel operacional `igl`.
- O dono transfere propriedade antes de sair. Convites armazenam apenas SHA-256 do token aleatório; o link é retornado uma única vez ao criador.
- Revisões e demos pertencem ao time ou titular solo; não são compartilhadas por associação à scrim.
- A tabela pública de times e os anúncios públicos não carregam IP, senha, e-mail, notas, revisões ou elenco privado.
- Moderadores só administram denúncias/anúncios. A função de moderador é atribuída por administração controlada do banco em `private.moderators`; não concede leitura de táticas ou arquivos.
- Arquivos já baixados não podem ser revogados. A proteção corta a próxima solicitação, incluindo as próximas partes de um upload.

## Dados, métricas e datas

Todos os instantes são `timestamptz`. Os formulários exibem o fuso escolhido; o padrão é `America/Sao_Paulo`; semanas começam na segunda-feira. Datas locais inexistentes por transição de fuso são rejeitadas.

Reservas são intervalos `[início,fim)`; 20h–21h e 21h–22h são adjacentes e permitidos. A restrição GiST no banco vale para scrims, bloqueios explícitos e treino coletivo bloqueante. Disponibilidade individual é informativa.

Nas métricas de treino, o período usa a data do registro de execução, com filtros por sessão/mapa/lado. A comparação usa o mesmo intervalo decorrido no período anterior; meses com menos dias limitam a janela comparável. A interface mostra amostra e consulta uma janela de até 200 sessões/2.000 resultados por espaço. Não existe rating inventado. O painel usa o planejamento da semana para os cards de agenda e as amostras registradas correspondentes.

Duplicar cria sessões pendentes, resultados ausentes, presença ausente e tarefas desmarcadas. Reagendar não conclui nada. Uma scrim confirmada só é marcada jogada quando os relatos canônicos dos dois times coincidem.

## Arquivos e manutenção

O cliente TUS fala com `/api/demos/[id]/upload`. O servidor resolve o recurso de upload a partir do identificador autorizado; não aceita URL/prefixo arbitrário do cliente. Cada POST/HEAD/PATCH revalida sessão e autorização. O objeto só fica `ready` depois da consulta de tamanho ao Storage. O download em `/api/demos/[id]/download` transmite o objeto sem URL permanente ou assinada no navegador.

Para inspecionar uploads pendentes/falhos com mais de 48 horas:

```bash
node scripts/cleanup-uploads.mjs
```

O padrão é simulação. `--apply` reivindica apenas registros sem atividade recente, limpa os metadados de transferência e conserva o registro como falho para nova tentativa. Execute somente por operador autorizado, com retenção acordada. Nenhum objeto concluído é apagado por esse script. Uploads TUS incompletos dependem da expiração do serviço de Storage. Não há job remoto automaticamente instalado.

Recibos de mutação impedem duplicação em novas tentativas do mesmo formulário; o payload deve permanecer igual para a mesma chave. Não limpe recibos enquanto houver retries em aberto. Convites não persistem o token no recibo: uma resposta perdida exige criar um novo convite e revogar o anterior, sem reutilizar o token.

## Backup, atualização e reversão

- Antes de alterar produção: backup consistente do PostgreSQL e cópia independente dos objetos do bucket, com manifesto de IDs/tamanhos e retenção privada; backup do banco não inclui automaticamente os bytes do Storage.
- Use backups/PITR compatíveis com o plano, confirme a retenção e faça um teste de restauração em ambiente separado antes da primeira alteração real.
- Mudanças de esquema são novas migrações aditivas. Registre a versão do app e a migração aplicada. Nunca apague dados antigos para fazer um build passar.
- Rollback de interface: volte ao commit anterior compatível com o esquema. Para banco, prefira migração corretiva; só restaure backup com janela de manutenção e plano para alterações ocorridas depois do backup.
- Segredos ficam no ambiente de destino. Rotacione-os se forem expostos; nunca os adicione ao ZIP ou ao Git.

## Solução de problemas

| Sintoma | Verificação / ação |
| --- | --- |
| Login mostra falta de configuração | Confira as duas variáveis públicas e reinicie o servidor após editar `.env.local`. |
| Cadastro fechado | Habilite somente no ambiente autorizado, tanto na aplicação como no servidor Auth. |
| Link volta para domínio errado | Confira `SITE_URL`, Site URL/allowlist do Auth e templates. Gere um link novo. |
| Sessão expirada | Entre novamente; as operações verificam o usuário no Auth e a associação atual no banco. |
| Convite indisponível | Use o e-mail verificado exato, confira expiração/revogação e peça um novo link. |
| Proposta mudou | Atualize, compare o histórico e aceite o número da versão vigente. |
| Conflito de horário | Nenhuma reserva parcial é mantida. Escolha outro intervalo; o original de uma remarcação falha permanece ativo. |
| Upload pausado/falhou | Selecione o mesmo arquivo para retomar; confira limites do plano/proxy e presença da chave de serviço no servidor. |
| Envio chegou a 100%, mas não ficou pronto | Use “Verificar arquivo enviado”; a conclusão depende da confirmação do Storage. |
| Acesso direto a Storage é negado até ao dono | Comportamento esperado: use o broker autenticado, nunca política de leitura direta ou URL assinada. |
| Chromium falha com `socket() ... Operation not permitted` | Rode o Playwright em um runner com suporte a IPC do Chromium; não desabilite políticas de acesso do produto para contornar isso. |
| Runtime nativo Supabase não baixa serviços | É necessário acesso aos hosts oficiais de distribuição ou Docker funcional. O teste SQL nativo continua disponível, sem provar Auth/Storage HTTP. |

## Organização

`src/app`: rotas SSR, callbacks e APIs; `src/components`: navegação, formulários e módulos; `src/lib`: configuração, domínio, validação, tipos gerados e clientes Supabase; `supabase/migrations`: domínios e correções incrementais; `supabase/tests`: pgTAP; `scripts`: banco descartável, geração de tipos e manutenção; `tests`: unidade, HTTP e navegador; `docs`: contratos, acesso e validação.

Não estão nesta versão ranking geral, chat aberto, análise automática ou player de `.dem`, IA, hospedagem de servidor de jogo, integrações Steam/FACEIT/Discord e aplicativo nativo.

## Correção de resolução de módulos no deploy

Se o log mostrar `Can't resolve '@/lib/supabase/server'`, o arquivo esperado é `src/lib/supabase/server.ts`. Ele está incluído no pacote e exporta `serverClient` e `verifiedClient`.

Esta revisão usa imports relativos em todo o código interno, incluindo a rota `/api/command`, para que esses módulos não dependam do alias `@/` no ambiente que recebeu os arquivos. As operações continuam exigindo sessão real, RLS e permissões do banco.

Antes da compilação, `npm run build` executa automaticamente `npm run check:source`. A checagem confere os arquivos obrigatórios, 159 imports locais e diferenças entre maiúsculas/minúsculas. Caso uma cópia esteja incompleta, o build para com o nome do arquivo ausente.

| Conteúdo na raiz do repositório | Root Directory do deploy |
| --- | --- |
| `package.json`, `tsconfig.json` e `src/` diretamente na raiz | Raiz do repositório |
| Esses três itens estão dentro de `round-zero/` | `round-zero` |

Use `npm ci` para instalar e `npm run build` para compilar. Envie o conteúdo completo do pacote; copiar somente `src/app` não inclui os clientes Supabase nem os demais módulos. Se já houver um projeto remoto, confira se `src/lib/supabase/server.ts` consta no commit efetivamente usado pelo deploy. A captura isolada não permite confirmar qual arquivo/configuração faltava nesse checkout remoto.
