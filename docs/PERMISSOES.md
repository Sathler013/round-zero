# Matriz de permissões

As políticas consultam associações ativas no banco em cada requisição. Função no jogo não concede acesso administrativo. `owner/captain` administram; `coach/igl` operam. Moderador é atribuído apenas por administração do banco, nunca pelo perfil.

| Recurso / operação | Anônimo | Titular solo | Membro ativo | Coach / IGL | Dono / capitão | Adversário | Ex-membro | Moderador |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Modelos curados / ler | Sim | Sim | Sim | Sim | Sim | Sim | Sim | Sim |
| Diretório e mural público / ler | Sim | Sim | Sim | Sim | Sim | Sim | Sim | Sim |
| Registros solo / ler e escrever | Não | Próprios | Próprios | Próprios | Próprios | Próprios | Próprios | Próprios |
| Treino, playbook, metas, revisões e demos do time / ler | Não | Não | Sim | Sim | Sim | Não | Não | Não |
| Estrutura coletiva, metas, playbook e revisão / escrever | Não | Não | Não | Sim | Sim | Não | Não | Não |
| Resultado de exercício e presença / escrever | Não | Próprios | Próprio atribuído | Sim | Sim | Não | Não | Não |
| Membros e convites / administrar | Não | Não | Não | Não | Sim | Não | Não | Não |
| Propriedade / transferir | Não | Não | Não | Não | Apenas dono | Não | Não | Não |
| Vaga e negociação / operar | Não | Não | Não | Próprio time | Próprio time | Outro time autorizado | Não | Não |
| Sala e instruções / ler | Não | Não | Time participante | Time participante | Time participante | Time participante | Não | Não |
| Sala, placar, cancelar / escrever | Não | Não | Não | Time participante | Time participante | Representante | Não | Não |
| Arquivos privados / upload e apagar | Não | Próprios | Não | Próprio time | Próprio time | Não | Não | Não |
| Notificações / ler e marcar | Não | Próprias | Próprias | Próprias | Próprias | Próprias | Próprias | Próprias |
| Denunciar anúncio | Não | Sim | Sim | Sim | Sim | Sim | Sim | Sim |
| Moderação de anúncio / decidir | Não | Não | Não | Não | Não | Não | Não | Sim |

RLS protege leitura; RPCs controlam escrita. Chaves de escopo e relações são imutáveis ou verificadas por constraints/triggers. Não existem grants de escrita direta nas tabelas do domínio. Bucket privado sem acesso direto de usuário; as rotas de arquivo verificam os metadados sob RLS antes de usar a chave de serviço restrita ao servidor.
