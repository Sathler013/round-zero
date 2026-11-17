# Contratos das RPCs

As assinaturas abaixo são geradas por introspecção do esquema. O contrato de payload JSON e limites de entrada está em `src/lib/commands.ts`; constraints e transições residem nas migrações. Todas as funções privilegiadas qualificam nomes, fixam `search_path` vazio e restringem EXECUTE. O acesso nunca depende somente da rota.

| RPC | Parâmetros | Retorno | Autorização / comportamento |
| --- | --- | --- | --- |
| `accept_invite` | `{ p_token: string }` | `string` | Sessão com e-mail confirmado igual ao destinatário; uso único e transacional. |
| `accept_proposal` | `{ p_negotiation: string; p_version: number; p_team: string }` | `string` | Só representante do destinatário da versão exata; duas reservas atômicas. |
| `add_map` | `{ p_team: string; p_name: string }` | `string` | Titular do escopo ou papel operacional/administrativo exigido na implementação SQL; vínculos e estados são revalidados no banco. |
| `can_manage_demo` | `{ p_id: string }` | `boolean` | Consulta restrita à identidade atual; não transfere propriedade. |
| `cancel_scrim` | `{ p_scrim: string; p_team: string }` | `undefined` | Representante; libera duas reservas e mantém histórico. |
| `claim_stale_upload` | `{ p_id: string; p_before: string }` | `boolean` | Somente service_role; lock e atividade recente protegem uploads retomados. |
| `close_scrim_post` | `{ p_post: string }` | `undefined` | Titular do escopo ou papel operacional/administrativo exigido na implementação SQL; vínculos e estados são revalidados no banco. |
| `create_demo` | `{ p_data: Json }` | `string` | Titular do escopo ou papel operacional/administrativo exigido na implementação SQL; vínculos e estados são revalidados no banco. |
| `create_invite` | `{ p_team: string; p_email: string; p_role?: string }` | `string` | Dono/capitão; retorna token uma vez, armazena somente hash. |
| `create_team` | `{ p_name: string; p_slug: string; p_timezone?: string }` | `string` | Usuário autenticado; cria time, dono e diretório público juntos. |
| `delete_demo_metadata` | `{ p_id: string }` | `undefined` | Titular do escopo ou papel operacional/administrativo exigido na implementação SQL; vínculos e estados são revalidados no banco. |
| `duplicate_week` | `{ p_team: string; p_from: string; p_to: string }` | `number` | Titular/operador; semanas começam na segunda no fuso do espaço. |
| `execute_command` | `{ p_key: string; p_command: string; p_data: Json }` | `Json` | Autenticação + chave de idempotência + validações da RPC de domínio. |
| `fail_demo` | `{ p_id: string }` | `undefined` | Titular do escopo ou papel operacional/administrativo exigido na implementação SQL; vínculos e estados são revalidados no banco. |
| `invite_rematch` | `{ p_scrim: string; p_team: string; p_start: string; p_end: string }` | `string` | Representante participante; convite privado sujeito a aceite de versão. |
| `list_invites` | `{ p_team: string }` | `Json[]` | Somente dono/capitão; nunca retorna hash ou token. |
| `manage_block` | `{ p_team: string; p_id: string; p_title: string; p_start: string; p_end: string; p_active: boolean }` | `string` | Titular do escopo ou papel operacional/administrativo exigido na implementação SQL; vínculos e estados são revalidados no banco. |
| `manage_member` | `{ p_team: string; p_user: string; p_action: string; p_role?: string }` | `undefined` | Administração ativa; dono transfere propriedade antes de sair. |
| `manage_training` | `{ p_action: string; p_data: Json }` | `string` | Titular solo ou operador do time; copiar zera execução e presença. |
| `mark_demo_uploaded` | `{ p_id: string; p_bytes: number }` | `undefined` | Somente service_role, após confirmação de tamanho pelo broker. |
| `mark_notifications_read` | `Record<string, never>` | `undefined` | Somente notificações da própria identidade. |
| `moderate_post` | `{ p_report: string; p_remove: boolean }` | `undefined` | Moderador atribuído fora do perfil; ação auditada. |
| `propose_reschedule` | `{ p_scrim: string; p_team: string; p_start: string; p_end: string; p_maps: (string)[] }` | `number` | Representante participante; não libera horário original. |
| `propose_scrim` | `{ p_data: Json }` | `string` | Representante; bloqueia time próprio, duplicidade, spam e versão obsoleta. |
| `publish_scrim` | `{ p_data: Json }` | `string` | Titular do escopo ou papel operacional/administrativo exigido na implementação SQL; vínculos e estados são revalidados no banco. |
| `record_training` | `{ p_session: string; p_attempts: number; p_hits: number; p_minutes: number; p_difficulty: string; p_notes: string }` | `undefined` | Titular, operador ou responsável atribuído; acertos não superam tentativas. |
| `report_post` | `{ p_post: string; p_reason: string }` | `undefined` | Autenticado; limite por dia e uma denúncia por anúncio. |
| `report_score` | `{ p_scrim: string; p_team: string; p_scores: Json }` | `boolean` | Representante; só compartilha resultado por relatos canônicos iguais. |
| `resolve_proposal` | `{ p_negotiation: string; p_version: number; p_team: string; p_action: string }` | `undefined` | Titular do escopo ou papel operacional/administrativo exigido na implementação SQL; vínculos e estados são revalidados no banco. |
| `resolve_reschedule` | `{ p_scrim: string; p_version: number; p_team: string; p_accept: boolean }` | `undefined` | Outro representante; conflito mantém ambas as reservas originais. |
| `respond_attendance` | `{ p_session: string; p_response: string }` | `undefined` | Titular ou membro ativo; registra somente a própria presença. |
| `retry_demo` | `{ p_id: string }` | `undefined` | Titular do escopo ou papel operacional/administrativo exigido na implementação SQL; vínculos e estados são revalidados no banco. |
| `review_to_training` | `{ p_review: string; p_start: string; p_minutes: number }` | `string` | Titular/operador; preserva escopo e retorna tarefa existente na repetição. |
| `revoke_invite` | `{ p_id: string }` | `undefined` | Dono/capitão; revoga convite ainda não usado. |
| `save_availability` | `{ p_team: string; p_start: string; p_end: string; p_kind: string }` | `string` | Titular do escopo ou papel operacional/administrativo exigido na implementação SQL; vínculos e estados são revalidados no banco. |
| `save_goal` | `{ p_data: Json }` | `string` | Titular do escopo ou papel operacional/administrativo exigido na implementação SQL; vínculos e estados são revalidados no banco. |
| `save_play` | `{ p_data: Json }` | `string` | Titular do escopo ou papel operacional/administrativo exigido na implementação SQL; vínculos e estados são revalidados no banco. |
| `save_review` | `{ p_data: Json }` | `string` | Titular do escopo ou papel operacional/administrativo exigido na implementação SQL; vínculos e estados são revalidados no banco. |
| `save_room` | `{ p_scrim: string; p_team: string; p_address: string; p_password: string; p_instructions: string }` | `undefined` | Representante participante; endereço/senha nunca são dados públicos. |
| `save_task` | `{ p_session: string; p_id: string; p_label: string; p_position: number; p_delete: boolean }` | `string` | Titular/operador; tarefa permanece na sessão original. |
| `set_game_role` | `{ p_team: string; p_user: string; p_map: string; p_side: string; p_role: string }` | `undefined` | Titular do escopo ou papel operacional/administrativo exigido na implementação SQL; vínculos e estados são revalidados no banco. |
| `toggle_task` | `{ p_task: string; p_done: boolean }` | `undefined` | Titular/operador ou responsável ativo atribuído. |
| `touch_demo_upload` | `{ p_id: string }` | `undefined` | Titular/operador; arquivo pendente e lock compartilhado com limpeza. |
| `update_profile` | `{ p_name: string; p_locale: string; p_timezone: string }` | `undefined` | Somente titular; valida idioma e fuso. |

Erros estáveis incluem `AUTH_REQUIRED`, `FORBIDDEN`, `STALE_VERSION`, `SCHEDULE_CONFLICT`, `INVALID_INVITE`, `INVALID_TRANSITION`, `RATE_LIMIT`, `SCOPE_MISMATCH` e `IDEMPOTENCY_CONFLICT`. A API traduz mensagens sem incluir tokens, instruções de servidor ou notas privadas.

Leituras comuns usam Data API com RLS. Upload/download usam o broker autenticado e não retornam URLs assinadas. Os estados e transições estão em [ARQUITETURA.md](ARQUITETURA.md).
