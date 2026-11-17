# Plano de implementação

1. Preparar Next.js estrito, identidade visual, autenticação SSR, matriz de acesso e migrações por domínio.
2. Conectar espaços solo/time, elenco e convites, treino, metas, presença e playbook.
3. Implementar mural, versões de proposta, reservas transacionais, sala, remarcação, placares e notificações.
4. Implementar arquivos privados, revisão → treino e métricas com amostra; revisar mobile/acessibilidade.
5. Executar verificações, documentar limitações reais, configurar CI e empacotar o código sem publicar.

## Decisões

- Next.js App Router em Node; sem trocar a arquitetura por outro runtime. Nenhum deploy é autorizado nesta entrega.
- Supabase é a fonte de verdade. A demonstração pública é explicitamente fictícia, somente leitura e separada de `/app`.
- Toda mutação de domínio passa por RPC validada no banco. O servidor usa a identidade do usuário para as operações comuns.
- Bucket sem políticas de leitura/escrita para usuários: o broker verifica sessão e associação a cada operação. Downloads são transmitidos sem URL assinada; uploads TUS são encaminhados em partes após autorização, sem expor credencial administrativa.
- Reservas ativas usam intervalos `[início,fim)`, restrição GiST por time e bloqueios em ordem estável. Aceite e remarcação são atômicos.
- O placar só é compartilhado quando os dois relatos são iguais. Confirmada e jogada são estados diferentes.
- Arquivos e revisão pertencem ao escopo que os criou, nunca automaticamente aos participantes da scrim.
- Idioma é preferência de apresentação; datas são UTC no banco e interpretadas no fuso explícito do espaço.

## Estado da entrega

- Etapas 1–4 implementadas no código e nas nove migrações.
- Etapa 5: typecheck, lint, 31 testes de lógica e integridade, 21 cenários SQL e build passaram.
- CI e suites reais entregues; Auth/Storage HTTP, pgTAP no Supabase e jornadas completas desktop/mobile permanecem não verificados por limites do ambiente. Ver `docs/VALIDACAO.md`.
- Código empacotado para revisão, sem publicação. GitHub reconheceu a conta, mas não retornou repositório acessível para envio.
