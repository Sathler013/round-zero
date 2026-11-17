-- Curated public content. No fake accounts or production metrics.
insert into public.maps(id,name) values
('10000000-0000-4000-8000-000000000001','Mirage'),
('10000000-0000-4000-8000-000000000002','Ancient'),
('10000000-0000-4000-8000-000000000003','Inferno'),
('10000000-0000-4000-8000-000000000004','Nuke'),
('10000000-0000-4000-8000-000000000005','Anubis'),
('10000000-0000-4000-8000-000000000006','Dust II'),
('10000000-0000-4000-8000-000000000007','Train') on conflict do nothing;
insert into public.library_templates(id,title,description,category,game_role,minutes,goal,checklist) values
('20000000-0000-4000-8000-000000000001','AWP + flash no meio','Duas pessoas. Sincronize a flash do suporte com a abertura da AWP. Registre somente tentativas completas.','awp','AWPer',30,'Acertar 8 de 10 execuções com flash coordenada','["Definir chamada de abertura","Repetir 10 execuções","Rever a posição após o disparo"]'),
('20000000-0000-4000-8000-000000000002','Primeiro contato, segundo jogador','Treine abertura e troca sem espaçamento excessivo.','posicionamento','Entry',25,'Conseguir troca em até 2 segundos em 8 de 10 tentativas','["Combinar distância","Executar 10 entradas","Registrar as trocas"]'),
('20000000-0000-4000-8000-000000000003','Utilitárias com propósito','Escolha três granadas e explique o espaço criado por cada uma.','comunicacao','Suporte',20,'Executar corretamente 9 de 10 utilitárias','["Escolher três granadas","Praticar sem adversário","Validar o timing em dupla"]'),
('20000000-0000-4000-8000-000000000004','Leitura de rotação','Revise cinco rounds, pause antes da rotação e registre sua hipótese.','leitura','IGL',40,'Justificar a decisão com duas informações em 4 de 5 rounds','["Escolher cinco rounds","Registrar hipótese antes de continuar","Comparar hipótese e informação disponível"]'),
('20000000-0000-4000-8000-000000000005','Mira: precisão antes de velocidade','Série curta de tiros isolados. Conte acertos e tentativas com o mesmo critério.','mira','Rifler',15,'Acertar 80 de 100 tiros isolados','["Aquecimento de 5 minutos","Executar a série","Anotar tentativas e acertos"]'),
('20000000-0000-4000-8000-000000000006','Timing de lurker','Compare o avanço do lurker com a pressão do grupo.','decisao','Lurker',30,'Sincronizar 8 de 10 avanços com a chamada do time','["Definir gatilho de avanço","Executar 10 rounds","Rever comunicação"]') on conflict do nothing;
