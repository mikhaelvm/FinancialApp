# Trackr — iOS

Finanças pessoais com SwiftUI, SwiftData, Charts, App Intents, notificações locais e WidgetKit. O armazenamento é **local**, sem CloudKit, servidor ou assinatura de sincronização. O projeto usa XcodeGen e compila no GitHub Actions, sem depender de um Mac local.

## Versão 2.1.0 — Google Drive

- Em Dados e backup, conecte o Google Drive para enviar e restaurar backups.
- Backup manual e automático opcional, agrupado após alterações. Só envia quando os registros mudam.
- Área privada no Drive, com cinco versões. Desconectar ou redefinir o app mantém os backups remotos.
- Configuração necessária: siga [docs/GOOGLE_DRIVE.md](docs/GOOGLE_DRIVE.md) para criar seu Client ID OAuth. Sem ele, o app compila com a conexão desabilitada.
- Segundo plano depende do iOS. Com proteção de acesso, envia somente durante uma sessão desbloqueada no app.

### Identidade Trackr


- Nome, código, pastas, targets, URLs (`trackr://`), widgets, controles, Atalhos e workflow renomeados para Trackr.
- Bundle principal `com.mikhael.trackr`; App Group `group.com.mikhael.trackr`.
- Azul do sistema como destaque padrão. As demais opções de personalização permanecem.
- Nova logo vetorial no Icon Composer, com fundo opaco e sem vidro, reflexo, sombra ou refração extras. Sem PNG com máscara/arredondamento pré-renderizados.
- O workflow gera `Trackr.xcodeproj` e disponibiliza `Trackr.ipa`.

### Levar os dados da instalação anterior

A mudança do bundle ID cria outra identidade e outro armazenamento no iPhone. Exporte um backup JSON no app antigo antes de instalar; no Trackr, use Dados e backup → Importar backup. Os registros financeiros usam o mesmo formato de backup. Preferências e autorização de notificações precisam ser configuradas novamente. O certificado e o perfil de assinatura precisam aceitar os novos identificadores do app e da extensão (e o App Group, quando utilizado). Não envie chaves privadas para o repositório.

### Funcionalidades


- Agenda permite dispensar contas agendadas e faturas por vencimento, sem pagamento ou débito. Arraste ou mantenha pressionado para dispensar; a seção Dispensados permite reativar. Dispensas são locais, incluídas no backup JSON e removidas na redefinição. Compras, limite e histórico das faturas não são alterados. Recorrências automáticas devem ser pausadas em Recorrentes.

- Quatro abas: Resumo, Extrato, Cartões e Pagamentos. Agenda e Recorrentes ficam juntas em Pagamentos, com um seletor; links e lembretes anteriores continuam funcionando.
- Entrada monetária em centavos com formatação automática: digitar 123456 mostra 1.234,56, sem precisar inserir vírgula.
- Compras do cartão em seção própria, com todas as compras ou apenas a fatura selecionada. O detalhe mostra parcelas e permite excluir a compra inteira.
- Extrato e Resumo também exibem compras do cartão, sem descontar novamente o saldo da conta.
- Exclusão de cartão vermelha, com confirmação, disponível ao arrastar e no formulário de edição. Pagamentos realizados são preservados no Extrato; recorrências vinculadas são pausadas.
- Excluir uma compra recalcula as faturas e mantém o saldo realizado: pagamentos que excedam as cobranças restantes são preservados como despesas na conta.
- Planejamento sem seta duplicada e previsão de faturas alinhada como na tela do cartão.
- Redefinição exige apenas confirmação no alerta, sem digitar APAGAR.

- Resumo com Ajustes à esquerda e ações de ocultar valores/novo lançamento à direita.
- Check do teclado fecha tanto o título quanto o valor do lançamento. O formulário do cartão também oferece conclusão para nome e limite, com R$ sempre visível.
- Faturas por mês em linhas de texto e valor, com inicial maiúscula e gráfico compartilhado. Sem gráfico vazio quando todos os valores são zero. O comprometimento de limite fica em uma seção recolhível, com uma única explicação.
- Limite do cartão em uma superfície nativa, mostrando disponível, total e em uso uma vez cada. Categorias respondem ao toque em toda a linha.
- A prévia do seletor de apps só é ocultada quando o bloqueio de acesso está ativado; desativar a proteção mantém o conteúdo visível.

- Bloqueio opcional por Face ID/Touch ID com alternativa pelo código do aparelho, autenticação para ativar/desativar e nova exigência após ir para segundo plano.
- Proteção opaca acima dos modais na prévia do seletor de apps. Widgets e notificações ficam discretos com o bloqueio ativo; consultas financeiras dos App Intents respeitam a sessão.
- Ações de Despesa/Receita/Agendar maiores, com fundos, bordas e símbolos destacados; adaptação para fontes de acessibilidade.
- Listas e formulários com superfícies, cabeçalhos, espaçamento e ações de navegação compartilhados. Tab inicial e título usam Resumo.
- Filtros no Extrato por natureza, período e categoria; opção Repetir lançamento abre uma nova cópia para revisar antes de salvar.
- Evolução de entradas/saídas em seis meses e comparação de saídas até o mesmo dia do mês anterior. Compras no cartão não duplicam seus pagamentos de faturas nos totais da conta.
- Nome interno e tradução do bundle corrigidos para Trackr; o botão oficial do Atalhos continua sendo utilizado.

- Resumo com Ajustes à esquerda e atalhos de ocultação e novo lançamento à direita; título grande que se recolhe ao rolar.
- Nomes das categorias em cor primária do sistema (branco no modo escuro e preto no claro), preservando símbolos coloridos.
- Botões de navegação dos modais usam X para cancelar e check para salvar/concluir, com rótulos de acessibilidade para VoiceOver.

- Ícone nativo do Icon Composer em **todos os builds SDK 26+**, com fundo contínuo, escala original e sem refratividade, sombra ou reflexos extras. Os PNGs com acabamento pré-renderizado não são mais usados como ícone.
- Interface baseada em listas agrupadas, cores semânticas, fontes do sistema e superfícies discretas. Resumo, cartões, recorrências e Agenda seguem Light/Dark Mode e Dynamic Type.
- Novo lançamento começa com um seletor **Despesa / Receita**, valor em destaque e ações coerentes com a modalidade.
- Orçamento mensal, meta de reserva, relatórios por mês e categorias com símbolos/cores personalizáveis.
- Aparência automática/clara/escura, seis cores de destaque e opção para ocultar valores no resumo e listas. Essas preferências também aparecem nos Ajustes do iOS.
- Backup completo em JSON pelo app Arquivos, restauração aditiva e exportação de transações em CSV.
- Importação local de OFX/CSV/PDF direto pelo seletor de arquivos, com revisão, categorias e detecção de duplicados. PDF inclui extração de texto e OCR local; movimentos de PDF começam desmarcados.
- Widgets informativos pequenos, médios e grandes com saldo, entradas, saídas, faturas, orçamento e próximos pagamentos; resumos na Tela Bloqueada. Compartilham somente um resumo local via App Groups, sem mover o banco SwiftData.
- Quatro controles da Central de Controle (iOS 18+): nova despesa, nova receita, resumo e Agenda.
- Paleta com amostras individuais e atualização imediata da cor; exclusão de agendamentos dentro da edição e menu de exclusão em Pagos.
- Redefinição completa dos dados e preferências com confirmação; categorias e gráficos usam os símbolos e cores escolhidos.
- Atalhos/Siri e lembretes de faturas, recorrências e contas agendadas continuam disponíveis.

O bundle identifier passa a ser `com.mikhael.trackr`. O projeto, scheme, target e módulo agora se chamam `Trackr`. Os seis modelos persistidos e o schema V2 continuam com os mesmos campos; use o backup JSON para transferir os dados entre as duas identidades.

## Enviar e instalar

```powershell
git status
git add .
git commit -m "Refina Trackr e adiciona widgets, backup e importacao bancaria"
git push
```

Push em `main`/`master` inicia **Actions → Build Trackr IPA**. Também há **Run workflow**. Ao concluir, baixe **Artifacts → Trackr.ipa**, baixe o arquivo diretamente e assine/instale pelo seu fluxo habitual.

O IPA contém `Trackr.app` e `PlugIns/TrackrWidgets.appex`. O instalador precisa preservar e assinar também a extensão para que os widgets apareçam. Widgets informativos precisam do App Group autorizado nos perfis de assinatura dos dois targets (veja abaixo). Não usam iCloud. A assinatura de dispositivo continua sendo uma etapa externa ao pipeline unsigned. [Execução em dispositivo — Apple](https://help.apple.com/xcode/mac/current/en.lproj/dev5a825a1ca.html).

Para manter os registros, atualize a instalação existente com a mesma identidade e não desinstale antes. Faça um backup pelo Trackr antes de trocar de instalação ou aparelho.

## Backup local: exportar e restaurar

Abra **Resumo → engrenagem → Dados, backup e extratos**:

1. **Exportar backup completo** abre o seletor nativo do app Arquivos. Escolha uma pasta que você controle.
2. O JSON inclui categorias, cartões, compras e parcelas, pagamentos de faturas, recorrências, contas agendadas e IDs usados para impedir importações repetidas.
3. **Importar backup** permite selecionar o JSON, mostra a quantidade de registros e pede confirmação antes de adicionar dados.
4. Registros ausentes são adicionados; registros já existentes com o mesmo ID são preservados. Uma segunda restauração do mesmo arquivo não duplica os dados.
5. Categorias iniciais com o mesmo nome são associadas às categorias locais, remapeando referências. Em um banco sem registros financeiros, cores e símbolos do backup também são restaurados.

O app mostra a data do último backup exportado com sucesso. Não há backup automático nem sincronização. Aparência, orçamento e permissões do aparelho são preferências locais e não são substituídos na restauração. O JSON é legível e não possui criptografia por senha própria; sua proteção depende do local escolhido no app Arquivos.

**Exportar transações em CSV** produz uma planilha para análise; ela não substitui o backup completo. Descrições são escapadas para não virarem fórmulas, e os valores monetários mantêm seus sinais. O CSV lista lançamentos de conta e parcelas de cartão, com categoria, cartão, número de parcela e vencimento; pagamentos de faturas estão preservados no backup JSON.

## Importar extratos bancários

Abra **Extrato → menu de ações → Importar extrato**, ou **Ajustes → Dados, backup e extratos → Importar extrato bancário**.

O botão abre imediatamente o seletor de arquivos do iOS. Não há seleção de banco/conta: ela não alterava o reconhecimento de colunas. Os cabeçalhos conhecidos de **Itaú, Caixa, Bradesco, Banco do Brasil, Mercado Pago e Inter** continuam reconhecidos automaticamente. São aceitos:

- **OFX de conta** no padrão SGML ou XML: data, valor assinado, descrição e FITID. O identificador de conta do arquivo participa da detecção de duplicados. O saldo inicial/final não vira receita.
- **PDF** com texto selecionável ou páginas digitalizadas via PDFKit/Vision. Até 50 páginas/15 MB, sem senha. Cada linha precisa permitir reconhecer data, descrição e valor; layouts com colunas fora de ordem podem ser recusados.
- **CSV** separado por ponto e vírgula, vírgula ou tabulação, com campos entre aspas, quebras de linha e codificações UTF-8, UTF-16 e Windows-1252.
- Colunas usuais de Data/Histórico/Lançamento/Descrição, Valor com sinal, D/C, Débito/Crédito separados e identificadores de transação.
- No Mercado Pago, o mapeamento prefere impacto líquido em conta (`SETTLEMENT_NET_AMOUNT`, `TRANSACTION_NET_AMOUNT` ou colunas líquidas de débito/crédito), em vez do valor bruto.

Os bancos podem mudar cabeçalhos e formatos conforme conta, canal e tipo de relatório. Por isso, o CSV tem um **mapeamento de colunas visível e ajustável**; os testes incluem exemplos representativos dos seis bancos, sem prometer reconhecimento de todo layout proprietário. Para a exportação, procure OFX ou CSV no app/site do banco; a disponibilidade pode variar por canal.

### Revisão antes de salvar

1. Toque em **Importar extrato** e escolha o arquivo no app Arquivos.
2. O processamento acontece em segundo plano, **no aparelho**, sem enviar dados a serviços externos.
3. No CSV, confira as colunas e use **Analisar colunas selecionadas** depois de qualquer ajuste. Não selecione a coluna Saldo como valor.
4. Confira os totais de receitas/despesas e os lançamentos individuais. Você pode mudar natureza e categoria e desmarcar itens. Em PDF, todos começam desmarcados e permitem corrigir data, descrição e valor; a seleção em lote não inclui PDFs. Valores sem sinal não determinam a natureza com segurança: confirme Receita/Despesa individualmente.
5. Possíveis duplicados começam desmarcados. Se forem movimentos realmente distintos, use **É outro movimento: importar como novo** explicitamente.
6. Somente **Confirmar importação** altera o banco e o saldo.

O app sugere categorias por palavras-chave, sempre editáveis na revisão. Importações anteriores são reconhecidas por FITID/identificadores e impressões digitais estáveis. Movimentos manuais semelhantes e pagamentos de faturas já registrados podem ser apontados como possíveis duplicados. CSV/PDF sem identificador e contas diferentes com movimentos iguais são inerentemente menos precisos; a prévia e a opção de inclusão explícita permitem resolver casos ambíguos.

Linhas inválidas são apresentadas separadamente e não viram movimentos. Lançamentos futuros não entram como realizados. Após importar, os movimentos ficam no Extrato com o selo **Extrato bancário** e podem ser editados ou excluídos.

O importador trabalha em BRL e com extratos de **conta**. XLS/XLSX e faturas de cartão não são aceitos. PDF não é um padrão bancário estruturado: OCR pode errar números e sinais, e não há garantia de reconhecer todo layout. Se a prévia estiver incompleta ou incorreta, prefira OFX/CSV. O app não busca saldos online nem acessa senhas bancárias. Para evitar duplicar pagamentos já registrados, confira os itens sinalizados antes de confirmar.

Referências dos formatos: [relatórios Mercado Pago](https://www.mercadopago.com.br/developers/pt/docs/qr-code/additional-content/reports/account-money/how-to-use), [exportação Bradesco](https://www.institucional.bradesco.com.br/simulador_bradesco_net_empresa/conteudo/perfil_corporate/extrato/pagfor_autorizacao.asp), [extratos Caixa](https://govconta.caixa.gov.br/sigovstatic/tour/servicos/serv_extrato02.htm).

## Fluxo financeiro

- **Saldo efetivo:** receitas na conta − despesas na conta − pagamentos de faturas.
- **Saldo projetado:** saldo efetivo − faturas pendentes até o fim do mês (inclusive atrasadas) − recorrências futuras na conta − contas agendadas pendentes.
- O app começa com zero. Registre uma receita para informar o saldo inicial, se necessário; o importador não presume esse saldo.
- O orçamento usa despesas na conta e parcelas por vencimento, incluindo previsões de assinaturas, sem contar o pagamento da fatura como uma segunda despesa por categoria.
- A meta de reserva acompanha o saldo em relação ao valor escolhido e não movimenta dinheiro.

Compras antes do fechamento entram no ciclo daquele mês; compras no dia ou após o fechamento vão ao seguinte. Se o vencimento for anterior ou igual ao dia de fechamento, ele fica no mês seguinte. Dias inexistentes usam o último dia do mês. Alterar o cartão preserva datas de parcelas já lançadas.

R$ 1.200,00 em 10x gera dez parcelas de R$ 120,00. R$ 100,00 em 3x gera 33,34 + 33,33 + 33,33. Todos os valores persistidos usam centavos inteiros. O valor total compromete o limite; o pagamento registrado libera o limite e diminui o saldo da conta.

Assinaturas e contas recorrentes têm ciclos semanal/mensal/anual. O dia original é preservado através de meses curtos. Pausar interrompe lançamentos/alertas futuros no Trackr, sem cancelar o serviço externo; retomar inicia nova agenda hoje. O app atualiza cobranças vencidas ao abrir/voltar ao primeiro plano. Contas avulsas só viram despesa ao marcar como pagas na Agenda.

## Sistema e personalização

- **Widgets:** adicione Trackr pela galeria. Pequeno mostra saldo e faturas; médio acrescenta entradas e saídas; grande mostra orçamento e próximos pagamentos. Respeitam ocultação de valores e sinalizam o horário do resumo. Usam uma cópia agregada dos dados; não abrem o banco SwiftData. A atualização depende do orçamento de execução do WidgetKit e não é em tempo real.
- **Central de Controle:** no iOS 18+, pressione a Central de Controle → Adicionar um Controle → Trackr. As ações abrem o app na tela correspondente, sem registrar dinheiro automaticamente. Os intents estão nos dois targets, conforme exigência do OpenIntent.
- **Ajustes do iOS:** em Apps → Trackr estão aparência, cor e ocultação de valores. Orçamentos, categorias e arquivos ficam nos Ajustes dentro do app.
- **Atalhos/Siri:** consultar resumo, registrar despesa/receita, agendar conta, abrir Agenda, buscar e abrir lançamentos. Consultas financeiras e gravações exigem autenticação. Frases: “Qual é meu saldo no Trackr?”, “Registrar gasto no Trackr” e “Agendar conta no Trackr”.
- **Siri AI:** builds com SDK 27 habilitam o schema oficial `system.searchInApp`, que pesquisa o Extrato. Ações financeiras seguem via App Shortcuts, pois a Apple não oferece um domínio financeiro equivalente.
- **Alertas:** configure horário e antecedência nos Ajustes do Trackr. Depois de agendados, funcionam com o app fechado. Mantemos os 60 alertas mais próximos dentro de 60 dias; abra o app periodicamente para renovar a fila. Pagamentos/edições/pausas removem ou atualizam alertas obsoletos. Foco e permissões do iOS influenciam a apresentação.

Referências: [WidgetKit](https://developer.apple.com/documentation/widgetkit), [Settings bundle](https://developer.apple.com/documentation/foundation/building-a-settings-bundle-for-your-app), [Siri searchInApp](https://developer.apple.com/documentation/appintents/appschema/systemintent/searchinapp).

## Bloqueio por Face ID / Touch ID

Abra **Ajustes → Privacidade e segurança → Bloquear com Face ID/Touch ID**. A opção permanece desligada até uma autenticação bem-sucedida. Desativar também pede autenticação. É necessário configurar o código do aparelho; o iOS oferece esse código como alternativa quando a biometria não está disponível.

O Trackr bloqueia no início de uma nova sessão e após ir para segundo plano. Abrir notificações, widgets, links e controles não evita a proteção. Com o bloqueio ativado, a prévia no seletor de apps é coberta por uma janela opaca da cena, acima inclusive de formulários e alertas; os campos em edição permanecem montados. Cancelar a autenticação mantém o bloqueio e permite tentar novamente pelo botão, sem repetir prompts em ciclo. Solicitações antigas não podem liberar a sessão após ela ter sido bloqueada novamente.

Com a opção ativa, novos resumos compartilhados dos widgets não contêm valores nem descrições financeiras, e notificações usam título Trackr e texto genérico. A atualização de widgets segue os prazos do sistema. Atalhos que consultam ou alteram dados e consultas de entidades recusam acesso enquanto a sessão está bloqueada; abra/desbloqueie o Trackr antes de executá-los. As ações que apenas abrem telas continuam encaminhando à interface protegida.

Este recurso controla o acesso à interface e às ações do app. Não adiciona criptografia própria ao banco ou senha aos backups JSON exportados. As permissões de biometria e o código são gerenciados pelo iOS; o Trackr não recebe dados biométricos nem armazena o código. A redefinição completa do app desliga a preferência de bloqueio.

Referências: [LocalAuthentication — Apple](https://developer.apple.com/documentation/localauthentication/logging-a-user-into-your-app-with-face-id-or-touch-id), [biometria ou código do aparelho](https://developer.apple.com/documentation/localauthentication/lapolicy/deviceownerauthentication), [ShortcutsLink nativo](https://developer.apple.com/documentation/appintents/shortcutslink).

## Filtros, repetição e evolução

- No **Extrato**, combine natureza, período, categoria e busca. Pagamentos de faturas seguem o período e a busca e aparecem em despesas/todos; não possuem categoria de despesa e são ocultados quando uma categoria é selecionada. **Limpar filtros** restaura a visão completa.
- Mantenha um lançamento pressionado e escolha **Repetir lançamento**. A cópia usa a data de hoje e abre para revisão; só salvar cria um registro. Identificadores bancários, vínculos de assinaturas e parcelas não são transferidos para o novo lançamento à vista.
- Em **Resumo → Planejamento**, toque na comparação de saídas para abrir **Evolução da conta**. Também há acesso nos Relatórios. O gráfico usa apenas entradas/saídas registradas e pagamentos efetivamente realizados, até hoje, sem incluir compras no cartão duas vezes.
- A comparação no Resumo usa o dia atual como corte nos dois meses (limitado ao último dia quando o mês anterior é mais curto). Sem saídas no período anterior, não inventa uma porcentagem. A opção de ocultação também protege os gráficos e comparações.

## App Groups e assinatura dos widgets

O identificador padrão é `group.com.mikhael.trackr`, configurado em `TRACKR_APP_GROUP` no `project.yml`, nos dois Info.plist e em `Shared/Trackr.entitlements`. O grupo deve ser registrado/autorizado para a sua equipe e incluído nos perfis do app e da extensão. Se o identificador não estiver disponível para sua equipe, altere **TRACKR_APP_GROUP** e registre outro grupo. Isso não altera o bundle identifier nem o banco principal.

O pipeline continua gerando um IPA **unsigned**. Ele não cria perfis, não registra grupos e não concede permissões de assinatura. Ao reassinar, preserve a extensão, use o mesmo grupo autorizado nos dois targets e mantenha o valor **TrackrAppGroup** dos dois Info.plist coerente com o grupo provisionado. Alguns instaladores removem/recriam entitlements e não oferecem App Groups em contas gratuitas. Sem autorização, o app continua local e funcional; o widget mostra uma orientação, nunca um saldo inventado. Consulte a disponibilidade da capability na sua conta antes de depender do dashboard fora do app. Nenhum dado vai para iCloud.

Referências: [App Groups — Apple](https://support.apple.com/en-ie/guide/security/sec1a976c067/web), [capabilities por modalidade de conta](https://developer.apple.com/help/account/reference/supported-capabilities-ios), [configurar App Groups](https://help.apple.com/xcode/mac/current/en.lproj/dev8dd3880fe.html), [controles e OpenIntent](https://developer.apple.com/documentation/widgetkit/creating-controls-to-perform-actions-across-the-system), [OCR local com Vision](https://developer.apple.com/documentation/vision/recognizing-text-in-images).

## Agenda e redefinição

- Em uma conta a vencer/atrasada, abra a edição e toque em **Excluir agendamento**. O gesto lateral também continua disponível.
- Em **Pagos**, use o botão de reticências ou deslize a linha. Você pode excluir somente o agendamento (preservando a despesa e o saldo) ou excluir também a despesa vinculada. A confirmação explica a diferença.
- Em **Ajustes → Dados, backup e extratos → Apagar todos os dados e redefinir**, digite **APAGAR**. A operação remove os registros financeiros, restaura as nove categorias padrão, reseta aparência/orçamento/privacidade/lembretes e limpa o resumo dos widgets. Backups exportados no app Arquivos são preservados. A autorização de notificações concedida pelo iOS só pode ser alterada nos Ajustes do sistema.

## Build e organização

`project.yml` define o app, a extensão WidgetKit e os XCTest. `scripts/prepare_build.py` gera `project-ci.yml` com os mesmos caminhos. O workflow escolhe o Xcode mais novo já instalado na imagem macOS, executa os testes, arquiva sem assinatura e empacota `Payload/Trackr.app` em `Trackr.ipa`.

SDK 26+ usa o `.icon` nativo corrigido; SDK 27+ também habilita `TRACKR_SIRI_AI`. O deployment target continua iOS 17. O modo de linguagem é Swift 5 (`SWIFT_VERSION: '5.0'`), compilado pelo Swift moderno do Xcode. Não se usa `5.10` como build setting de versão de linguagem.

```bash
brew install xcodegen
python3 -m unittest discover -s scripts/tests -v
python3 scripts/prepare_build.py --sdk-version "$(xcrun --sdk iphoneos --show-sdk-version)"
xcodegen generate --spec project-ci.yml
xcodebuild test -project Trackr.xcodeproj -scheme Trackr \
  -destination 'platform=iOS Simulator,id=SEU_UUID' \
  CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="-"
xcodebuild archive -project Trackr.xcodeproj -scheme Trackr \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath "$PWD/build/Trackr.xcarchive" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""
```

Os arquivos novos de maior interesse são:

```text
Trackr/Services/BackupService.swift
Trackr/Services/StatementParser.swift
Trackr/Services/StatementImportService.swift
Trackr/Services/TrackrPreferences.swift
Trackr/Views/DataManagementView.swift
Trackr/Views/StatementImportView.swift
Trackr/Views/BudgetSettingsView.swift
Trackr/Views/ReportsView.swift
Trackr/Views/CategoryManagementView.swift
Trackr/Settings.bundle/Root.plist
TrackrWidgets/TrackrWidgets.swift
TrackrWidgets/Info.plist
Tests/BackupServiceTests.swift
Tests/StatementImportTests.swift
Trackr/Services/PDFStatementReader.swift
Trackr/Services/AppResetService.swift
Trackr/Services/WidgetSnapshotService.swift
Shared/TrackrWidgetStore.swift
Shared/TrackrControlIntent.swift
Shared/Trackr.entitlements
TrackrWidgets/TrackrControls.swift
Tests/PDFStatementTests.swift
Tests/ResetAndAgendaTests.swift
Trackr/Services/AppLockService.swift
Trackr/Services/FinancialReview.swift
Trackr/Views/TrackrSecurityHost.swift
Trackr/Views/CashFlowReviewView.swift
Trackr/Views/InvoiceForecastChart.swift
Trackr/pt-BR.lproj/InfoPlist.strings
Tests/AppLockTests.swift
Tests/FinancialReviewTests.swift
```

Há **88 testes XCTest**: regras financeiras originais, persistência, migração V1 → V2, lembretes, backup/restauração e importação bancária. Há também dezesseis testes Python para preparação do build, ícone e configuração compartilhada dos widgets/controles. As verificações nativas também cobrem PDF, exclusão de pagamentos, redefinição, categorias, sessão de bloqueio (com autenticador simulado), cálculos da evolução e cópias de lançamentos.

A autoria é feita no Windows: parser Swift, YAML, plists e testes Python ajudam a revisar a estrutura, mas não substituem compilação no SDK da Apple. Esta atualização precisa passar pelo workflow macOS e ser conferida no aparelho, especialmente ícone, widgets, fontes ampliadas, autorização de notificações e importação de um extrato real de cada layout utilizado. A versão anterior já foi compilada/instalada pelo usuário; isso não confirma a compilação desta versão.

Na validação em aparelho desta versão, confira Face ID/Touch ID, alternativa por código, cancelamento/repetição do prompt, bloqueio ao trocar de app com um formulário aberto, prévia do seletor de apps e abertura pelos widgets/controles. Os testes com autenticador simulado verificam a lógica da sessão, não o sensor físico nem o desenho das janelas pelo iOS. A correção do nome no Atalhos depende da instalação da nova versão e da atualização dos metadados pelo sistema.

Fechamentos e vencimentos de novas compras e previsões passam para a segunda-feira quando caem em sábado ou domingo. Feriados não são considerados. Datas de parcelas e pagamentos já gravados são preservadas.

Recorrências: a edição permite suspender apenas a próxima renovação ou pausar indefinidamente, com aplicação ao salvar. Dispensados saem da lista após 30 dias do vencimento; identificadores mínimos permanecem para impedir reaparecimento nos atrasados, sem remover compras ou alterar o saldo.

O envio do IPA usa `actions/upload-artifact@v7` com `archive: false`: baixe `Trackr.ipa` diretamente nos artefatos, sem ZIP externo. O IPA continua exigindo assinatura para instalação. Artefatos de builds anteriores mantêm o formato antigo.

O CI resolve pacotes antes de compilar e limita o build a dois jobs. Se o serviço de build do Xcode travar, os testes têm uma única nova tentativa com DerivedData separado. Erros de compilação e falhas de testes não são repetidos. Os logs e xcresult de ambas as tentativas ficam no artefato iOS-TestResults.
