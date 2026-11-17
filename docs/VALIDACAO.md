# Relatório de validação — 17/11/2026

## Resultado confirmado nesta entrega

| Verificação | Resultado | Evidência / limite |
| --- | --- | --- |
| `npm run typecheck` | Passou | TypeScript estrito, incluindo rotas, formulários e tipos do banco. |
| `npm run lint` | Passou | ESLint com zero avisos. |
| `npm test` | Passou | 31 testes de integridade de fonte, redirects, agregação ponderada, datas/fusos, fronteiras de intervalos e entradas. |
| `npm run test:db` | Passou | 21 cenários contra PostgreSQL nativo 18.6 descartável; nove migrações aplicadas em banco limpo. |
| `npm run build` | Passou | Build Next.js de produção, compilação e geração de rotas. |
| Inspeção visual do painel desktop | Realizada | Painel Round Zero aberto em Chrome na primeira etapa; identidade visual, navegação e troca PT/EN conferidas. |
| CI | Configurado, não executado | Workflow entregue. Nenhuma execução remota foi disparada. |
| Produção | Não configurada e não publicada | Nenhuma conta, projeto remoto, SMTP real ou cadastro público foi criado. |

## Banco: cenários executados

1. Criação atômica do time e associação do dono.
2. Convite com destinatário correto e rejeição de reutilização.
3. Rejeição de convite expirado, revogado e e-mail não verificado.
4. Bloqueio de autopromoção e escrita direta por jogador.
5. Isolamento solo/time e entre times.
6. Cópia de sessão sem resultados, presença ou checklists concluídos.
7. Rejeição de resultado impossível e responsável de outro time.
8. Papel de acesso independente da função de jogo IGL.
9. Aceite apenas pelo destinatário da versão vigente, com repetição idempotente.
10. Adversário lê a sala, mas não a revisão, demo ou treino privado de origem.
11. Remarcação conflitante mantém ambas as reservas originais.
12. Reservas adjacentes são permitidas; sessões bloqueantes usam a mesma exclusão.
13. Remoção corta a próxima leitura usando a mesma identidade.
14. Cancelamento idempotente libera os horários e mantém histórico.
15. Dois aceites simultâneos: um vence, sem reserva/notificação parcial.
16. Recibos impedem duplicar criação e rejeitam payload alterado na mesma chave.
17. Uma vaga é consumida uma vez; remarcação bem-sucedida move os dois horários; revanche privada fica invisível a terceiro time.
18. Checklist só é editado no escopo original.
19. Limpeza não alcança upload retomado recentemente; reivindicação é restrita ao serviço.
20. Bucket é privado; usuário não chama finalização privilegiada nem lê recursos internos de upload/convites.
21. Dono precisa transferir propriedade antes de sair.

O harness usa fixtures mínimas dos esquemas Auth/Storage e claims para exercitar as políticas e funções **reais** do produto. Isso prova as regras SQL, mas não prova GoTrue, PostgREST, Mailpit, TUS ou Storage HTTP. Nenhum fixture desse harness participa do runtime da aplicação.

## Não verificado e como executar

| Verificação pendente | Motivo observado | Comando e pré-requisito |
| --- | --- | --- |
| pgTAP no stack Supabase | Stack completo não iniciou neste ambiente. | Com Docker e Supabase local: `npx supabase start`, `npx supabase db reset`, `npx supabase test db`. Reset apenas em banco local descartável. |
| Data API e Storage reais | Sem projeto de teste autorizado acessível; o runtime nativo não conseguiu baixar serviços oficiais por erro de resolução de rede. | Inicializar stack local, `npm run local:env`, `npm run test:integration`. A suíte recusa endpoints remotos. |
| Jornadas Playwright públicas desktop/mobile | As 14 tentativas iniciais falharam na infraestrutura: Chromium não pôde criar o socket Unix (`Operation not permitted`); o runner também não alcançou o processo de preview em seu namespace. | Runner com IPC do Chromium: `npx playwright install chromium`; com aplicação servindo, `PLAYWRIGHT_BASE_URL=http://localhost:3000 npm run test:e2e`. |
| Cadastro/verificação/login/saída/recuperação e sincronização em outro dispositivo | Serviços reais e caixa de teste indisponíveis. Esses testes não foram substituídos por mocks. | Stack Supabase + Mailpit + `.env.local`; `npm run build`, `npm start`; `RUN_AUTH_E2E=1 PLAYWRIGHT_BASE_URL=http://localhost:3000 npm run test:e2e`. |
| Upload, retomada, broker, download e revogação por HTTP | Depende do mesmo stack e da chave de serviço restrita ao servidor. | As suítes de integração e navegador acima. Validar também um `.dem` grande, perda de conexão, retomada, cancelamento e limite do proxy. |
| Responsividade e acessibilidade integral | CSS responsivo, foco, semântica e testes foram implementados; não houve confirmação automatizada mobile nesta sessão. | Projetos `desktop` e `mobile` do Playwright e revisão manual por teclado/leitor de tela. |

O teste de Auth do Playwright fica explicitamente não executado sem `RUN_AUTH_E2E=1`. Não considere apenas os testes públicos como prova da jornada completa.

Na retomada, a prévia compartilhada estava aberta em outro projeto do usuário. Ela não foi usada como evidência do Round Zero nem substituída para concluir esta entrega.

## Correções verificadas

Um teste de criação de demo encontrou acesso a `NEW.source_review_id` em um gatilho também usado por uma tabela sem esse campo. A migração 007 separa os ramos por tipo de registro; o cenário completo voltou a passar. A limpeza de uploads ganhou atividade e lock na migração 009, com teste de regressão para retomada recente. O botão de mutação renova a chave quando o payload muda, mantendo a mesma chave somente em retry do conteúdo idêntico.

## GitHub e entrega

A conexão reconheceu a conta `Sathler013`, mas a listagem e a busca do Round Zero retornaram zero repositórios acessíveis. Não houve push, PR ou criação de repositório remoto. O pacote contém código, lockfile, migrações, seed curado, testes e documentação para execução local. O arquivo de configuração de exemplo não contém segredos.

## Condição para liberar produção

A implementação está entregue para revisão e configuração; o aceite ponta a ponta permanece pendente das verificações acima. Antes de publicar: homologação separada, suites completas, SMTP/callbacks verificados, limite real de Storage/proxy conciliado, backup/restauração testados e autorização de publicação. Não há promessa de zero bugs ou de produção já configurada.

## Revisão do erro de módulo no deploy

A captura recebida mostrou falha no import `@/lib/supabase/server`. O arquivo e o alias existiam no ZIP anterior, e seu build local também passou com Webpack; portanto a causa específica do checkout remoto não foi confirmada pela captura. A revisão remove a dependência do alias nos 107 imports internos que o usavam e adiciona uma checagem anterior à compilação para detectar fonte ausente ou nome com maiúsculas diferentes.

Foram adicionados cinco testes: arquivo Supabase ausente (a classe de falha relatada), resolução relativa sem alias, diferença de maiúsculas, import de CSS e integridade do projeto entregue. Total de testes de unidade nesta revisão: 31. As limitações de Auth/Storage HTTP e das jornadas completas no navegador continuam as mesmas; nenhuma política foi reduzida para corrigir a compilação.

Validação adicional do pacote revisado: o ZIP candidato foi extraído em outra pasta, recebeu `npm ci --prefer-offline` e passou em `npm run build` (Turbopack) e `npm run build -- --webpack`. A checagem anterior ao build passou nos dois casos. O arquivo `src/lib/supabase/server.ts` da extração foi comparado byte a byte com a fonte original. Isso valida o pacote entregue, sem afirmar que o deploy remoto já foi atualizado.
