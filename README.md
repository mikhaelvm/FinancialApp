# Ledger — iOS

Finanças pessoais com SwiftUI, SwiftData, Charts, App Intents, notificações locais e WidgetKit. O armazenamento é **local**, sem CloudKit, servidor ou assinatura de sincronização. O projeto usa XcodeGen e compila no GitHub Actions, sem depender de um Mac local.

## Versão 1.2

- Ícone nativo do Icon Composer em **todos os builds SDK 26+**, com fundo contínuo, escala original e sem refratividade, sombra ou reflexos extras. Os PNGs com acabamento pré-renderizado não são mais usados como ícone.
- Interface baseada em listas agrupadas, cores semânticas, fontes do sistema e superfícies discretas. Resumo, cartões, recorrências e Agenda seguem Light/Dark Mode e Dynamic Type.
- Novo lançamento começa com um seletor **Despesa / Receita**, valor em destaque e ações coerentes com a modalidade.
- Orçamento mensal, meta de reserva, relatórios por mês e categorias com símbolos/cores personalizáveis.
- Aparência automática/clara/escura, seis cores de destaque e opção para ocultar valores no resumo e listas. Essas preferências também aparecem nos Ajustes do iOS.
- Backup completo em JSON pelo app Arquivos, restauração aditiva e exportação de transações em CSV.
- Importação assistida de extratos bancários OFX/CSV, com prévia, seleção de lançamentos, categorias, revisão da natureza e detecção de duplicados.
- Widgets de acesso rápido para despesas, receitas e Agenda, na Tela de Início e Tela Bloqueada, sem App Groups nem compartilhamento do banco.
- Atalhos/Siri e lembretes de faturas, recorrências e contas agendadas continuam disponíveis.

O bundle identifier permanece `com.mikhael.FinancialApp`. O nome exibido é Ledger; projeto e target continuam `FinancialApp` para preservar a identidade da instalação. Os seis modelos persistidos e o schema V2 não foram alterados nesta atualização.

## Enviar e instalar

```powershell
git status
git add .
git commit -m "Refina Ledger e adiciona widgets, backup e importacao bancaria"
git push
```

Push em `main`/`master` inicia **Actions → Build Ledger IPA**. Também há **Run workflow**. Ao concluir, baixe **Artifacts → Ledger-unsigned**, extraia `Ledger.ipa` e assine/instale pelo seu fluxo habitual.

O IPA contém `FinancialApp.app` e `PlugIns/LedgerWidgets.appex`. O instalador precisa preservar e assinar também a extensão para que os widgets apareçam. Não é necessário App Group ou iCloud para esses widgets. A assinatura de dispositivo continua sendo uma etapa externa ao pipeline unsigned. [Execução em dispositivo — Apple](https://help.apple.com/xcode/mac/current/en.lproj/dev5a825a1ca.html).

Para manter os registros, atualize a instalação existente com a mesma identidade e não desinstale antes. Faça um backup pelo Ledger antes de trocar de instalação ou aparelho.

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

O seletor inclui **Itaú, Caixa, Bradesco, Banco do Brasil, Mercado Pago, Inter** e Outro banco. São aceitos:

- **OFX de conta** no padrão SGML ou XML: data, valor assinado, descrição e FITID. O identificador de conta do arquivo participa da detecção de duplicados. O saldo inicial/final não vira receita.
- **CSV** separado por ponto e vírgula, vírgula ou tabulação, com campos entre aspas, quebras de linha e codificações UTF-8, UTF-16 e Windows-1252.
- Colunas usuais de Data/Histórico/Lançamento/Descrição, Valor com sinal, D/C, Débito/Crédito separados e identificadores de transação.
- No Mercado Pago, o mapeamento prefere impacto líquido em conta (`SETTLEMENT_NET_AMOUNT`, `TRANSACTION_NET_AMOUNT` ou colunas líquidas de débito/crédito), em vez do valor bruto.

Os bancos podem mudar cabeçalhos e formatos conforme conta, canal e tipo de relatório. Por isso, o CSV tem um **mapeamento de colunas visível e ajustável**; os testes incluem exemplos representativos dos seis bancos, sem prometer reconhecimento de todo layout proprietário. Para a exportação, procure OFX ou CSV no app/site do banco; a disponibilidade pode variar por canal.

### Revisão antes de salvar

1. Selecione banco e uma identificação da conta, útil para distinguir CSVs de contas diferentes.
2. Escolha o arquivo. O processamento acontece em segundo plano, **no aparelho**, sem enviar dados a serviços externos.
3. No CSV, confira as colunas e use **Analisar colunas selecionadas** depois de qualquer ajuste. Não selecione a coluna Saldo como valor.
4. Confira os totais de receitas/despesas e os lançamentos individuais. Você pode mudar natureza e categoria e desmarcar itens.
5. Possíveis duplicados começam desmarcados. Se forem movimentos realmente distintos, use **É outro movimento: importar como novo** explicitamente.
6. Somente **Confirmar importação** altera o banco e o saldo.

O app sugere categorias por palavras-chave, sempre editáveis na revisão. Importações anteriores são reconhecidas por FITID/identificadores e impressões digitais estáveis. Movimentos manuais semelhantes e pagamentos de faturas já registrados podem ser apontados como possíveis duplicados. CSV sem identificador é inerentemente menos preciso; a prévia e a opção de inclusão explícita permitem resolver casos ambíguos.

Linhas inválidas são apresentadas separadamente e não viram movimentos. Lançamentos futuros não entram como realizados. Após importar, os movimentos ficam no Extrato com o selo **Extrato bancário** e podem ser editados ou excluídos.

O importador trabalha em BRL e com extratos de **conta**. PDF, XLS/XLSX e faturas de cartão não são analisados nesta versão; exporte OFX/CSV da conta. O app não busca saldos online nem acessa senhas bancárias. Para evitar duplicar pagamentos já registrados, confira os itens sinalizados antes de confirmar.

Referências dos formatos: [relatórios Mercado Pago](https://www.mercadopago.com.br/developers/pt/docs/qr-code/additional-content/reports/account-money/how-to-use), [exportação Bradesco](https://www.institucional.bradesco.com.br/simulador_bradesco_net_empresa/conteudo/perfil_corporate/extrato/pagfor_autorizacao.asp), [extratos Caixa](https://govconta.caixa.gov.br/sigovstatic/tour/servicos/serv_extrato02.htm).

## Fluxo financeiro

- **Saldo efetivo:** receitas na conta − despesas na conta − pagamentos de faturas.
- **Saldo projetado:** saldo efetivo − faturas pendentes até o fim do mês (inclusive atrasadas) − recorrências futuras na conta − contas agendadas pendentes.
- O app começa com zero. Registre uma receita para informar o saldo inicial, se necessário; o importador não presume esse saldo.
- O orçamento usa despesas na conta e parcelas por vencimento, incluindo previsões de assinaturas, sem contar o pagamento da fatura como uma segunda despesa por categoria.
- A meta de reserva acompanha o saldo em relação ao valor escolhido e não movimenta dinheiro.

Compras antes do fechamento entram no ciclo daquele mês; compras no dia ou após o fechamento vão ao seguinte. Se o vencimento for anterior ou igual ao dia de fechamento, ele fica no mês seguinte. Dias inexistentes usam o último dia do mês. Alterar o cartão preserva datas de parcelas já lançadas.

R$ 1.200,00 em 10x gera dez parcelas de R$ 120,00. R$ 100,00 em 3x gera 33,34 + 33,33 + 33,33. Todos os valores persistidos usam centavos inteiros. O valor total compromete o limite; o pagamento registrado libera o limite e diminui o saldo da conta.

Assinaturas e contas recorrentes têm ciclos semanal/mensal/anual. O dia original é preservado através de meses curtos. Pausar interrompe lançamentos/alertas futuros no Ledger, sem cancelar o serviço externo; retomar inicia nova agenda hoje. O app atualiza cobranças vencidas ao abrir/voltar ao primeiro plano. Contas avulsas só viram despesa ao marcar como pagas na Agenda.

## Sistema e personalização

- **Widgets:** adicione Ledger pela galeria de widgets. Pequeno/circular abre nova despesa; médio oferece despesa, receita e Agenda; retangular abre pagamentos. Não exibem saldos nem exigem acesso compartilhado ao banco.
- **Ajustes do iOS:** em Apps → Ledger estão aparência, cor e ocultação de valores. Orçamentos, categorias e arquivos ficam nos Ajustes dentro do app.
- **Atalhos/Siri:** consultar resumo, registrar despesa/receita, agendar conta, abrir Agenda, buscar e abrir lançamentos. Consultas financeiras e gravações exigem autenticação. Frases: “Qual é meu saldo no Ledger?”, “Registrar gasto no Ledger” e “Agendar conta no Ledger”.
- **Siri AI:** builds com SDK 27 habilitam o schema oficial `system.searchInApp`, que pesquisa o Extrato. Ações financeiras seguem via App Shortcuts, pois a Apple não oferece um domínio financeiro equivalente.
- **Alertas:** configure horário e antecedência nos Ajustes do Ledger. Depois de agendados, funcionam com o app fechado. Mantemos os 60 alertas mais próximos dentro de 60 dias; abra o app periodicamente para renovar a fila. Pagamentos/edições/pausas removem ou atualizam alertas obsoletos. Foco e permissões do iOS influenciam a apresentação.

Referências: [WidgetKit](https://developer.apple.com/documentation/widgetkit), [Settings bundle](https://developer.apple.com/documentation/foundation/building-a-settings-bundle-for-your-app), [Siri searchInApp](https://developer.apple.com/documentation/appintents/appschema/systemintent/searchinapp).

## Build e organização

`project.yml` define o app, a extensão WidgetKit e os XCTest. `scripts/prepare_build.py` gera `project-ci.yml` com os mesmos caminhos. O workflow escolhe o Xcode mais novo já instalado na imagem macOS, executa os testes, arquiva sem assinatura e empacota `Payload/FinancialApp.app` em `Ledger.ipa`.

SDK 26+ usa o `.icon` nativo corrigido; SDK 27+ também habilita `LEDGER_SIRI_AI`. O deployment target continua iOS 17. O modo de linguagem é Swift 5 (`SWIFT_VERSION: '5.0'`), compilado pelo Swift moderno do Xcode. Não se usa `5.10` como build setting de versão de linguagem.

```bash
brew install xcodegen
python3 -m unittest discover -s scripts/tests -v
python3 scripts/prepare_build.py --sdk-version "$(xcrun --sdk iphoneos --show-sdk-version)"
xcodegen generate --spec project-ci.yml
xcodebuild test -project FinancialApp.xcodeproj -scheme FinancialApp \
  -destination 'platform=iOS Simulator,id=SEU_UUID' \
  CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="-"
xcodebuild archive -project FinancialApp.xcodeproj -scheme FinancialApp \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath "$PWD/build/FinancialApp.xcarchive" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""
```

Os arquivos novos de maior interesse são:

```text
FinancialApp/Services/BackupService.swift
FinancialApp/Services/StatementParser.swift
FinancialApp/Services/StatementImportService.swift
FinancialApp/Services/LedgerPreferences.swift
FinancialApp/Views/DataManagementView.swift
FinancialApp/Views/StatementImportView.swift
FinancialApp/Views/BudgetSettingsView.swift
FinancialApp/Views/ReportsView.swift
FinancialApp/Views/CategoryManagementView.swift
FinancialApp/Settings.bundle/Root.plist
LedgerWidgets/LedgerWidgets.swift
LedgerWidgets/Info.plist
Tests/BackupServiceTests.swift
Tests/StatementImportTests.swift
```

Há **40 testes XCTest**: regras financeiras originais, persistência, migração V1 → V2, lembretes, backup/restauração e importação bancária. Há também quatro testes Python para preparação do build e configuração do ícone.

A autoria é feita no Windows: parser Swift, YAML, plists e testes Python ajudam a revisar a estrutura, mas não substituem compilação no SDK da Apple. Esta atualização precisa passar pelo workflow macOS e ser conferida no aparelho, especialmente ícone, widgets, fontes ampliadas, autorização de notificações e importação de um extrato real de cada layout utilizado. A versão anterior já foi compilada/instalada pelo usuário; isso não confirma a compilação desta versão.
