# Ledger

App nativo de finanças pessoais para iPhone e iPad, com SwiftUI, SwiftData, Charts, App Intents e notificações locais. Deployment target iOS 17. O projeto é gerado pelo XcodeGen e compilado no GitHub Actions, sem depender de um Mac local.

## Atualização 1.1

- Nova identidade Ledger, paleta verde-petróleo e logo original em `FinancialApp/Ledger.icon`.
- Início com saldo, projeção do mês, ações rápidas, próximos pagamentos e gráficos.
- Extrato com categorias visuais; cartões com destaque de limite; recorrências com busca e filtros de situação.
- Agenda com faturas, assinaturas, contas recorrentes e contas avulsas agendadas.
- Lembretes locais com antecedência, horário, opção de mostrar valores e abertura da área relevante ao tocar no alerta.
- App Shortcuts para consultar saldo, registrar receitas/despesas, agendar contas, abrir a Agenda e buscar no extrato.
- Busca da Siri AI usando o schema oficial `system.searchInApp` quando compilado com SDK iOS 27.
- Migração SwiftData V1 → V2 para adicionar contas agendadas, sem alterar os modelos existentes.

O bundle identifier permanece **`com.mikhael.FinancialApp`** para atualizar a instalação existente. O nome técnico do target/projeto continua `FinancialApp`; o nome exibido no iPhone é **Ledger**. Para preservar os dados ao atualizar, mantenha a mesma identidade de assinatura e não desinstale o app antes de instalar a atualização.

## Enviar os próximos commits

Na pasta do projeto, confira as alterações e envie ao seu repositório:

```powershell
git status
git add .
git commit -m "Evolui app para Ledger com Agenda, alertas e Atalhos"
git push
```

Push em `main` ou `master` inicia **Actions → Build Ledger IPA**. Também é possível iniciar manualmente em **Run workflow**. Ao concluir, baixe **Artifacts → Ledger-unsigned** e extraia `Ledger.ipa`. O workflow também publica `iOS-TestResults`.

O IPA continua unsigned, conforme o fluxo original. Para instalar, assine-o com identidade e perfil compatíveis; gerar o IPA não exige certificados no GitHub. [Execução em dispositivo — Apple](https://help.apple.com/xcode/mac/current/en.lproj/dev5a825a1ca.html).

## Compatibilidade dos recursos novos

| Compilador/SDK | Ícone | Atalhos e Siri | Dispositivos |
| --- | --- | --- | --- |
| Xcode/SDK 26 | Exportações padrão e escura fornecidas pelo usuário | App Shortcuts com frases e parâmetros | iOS 17+ |
| Xcode/SDK 27+ | Arquivo `.icon` original, incluindo as aparências geradas pelo sistema | App Shortcuts + busca `system.searchInApp` da Siri AI no iOS 27 | iOS 17+, com APIs novas protegidas por disponibilidade |

O workflow seleciona o Xcode de maior versão **já instalado** no runner `macos-latest`. Ele não baixa um Xcode que não esteja na imagem. O passo de geração informa claramente qual modo foi escolhido. Se a imagem ainda só tiver SDK 26, o app compila com os recursos compatíveis; a integração específica da Siri AI fica para um build com SDK 27.

`scripts/prepare_build.py` cria `project-ci.yml` a partir do `project.yml`, sem alterar o arquivo principal. No modo 27, habilita a condição `LEDGER_SIRI_AI`. No modo 26, exclui o `.icon` que usa recursos novos de refratividade e adiciona o catálogo `Resources/LegacyIcon.xcassets`. Esse arquivo temporário é ignorado pelo Git.

O pacote `.icon` original foi preservado sem editar `icon.json` ou a imagem da camada. XcodeGen 2.45.1+ reconhece `.icon` como pacote. [XcodeGen](https://github.com/yonaskolb/XcodeGen/releases), [Icon Composer — Apple](https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer).

## Como usar

### Início e extrato

O Ledger começa com saldo zero. Para registrar seu saldo inicial, adicione uma receita. A tela inicial oferece **Registrar gasto**, **Receber dinheiro**, **Agendar conta** e **Nova recorrência**.

No Extrato, toque em um lançamento manual para editar; deslize para excluir. Cobranças automáticas e comprovantes de contas pagas são apresentados como histórico. Os detalhes dos cartões ficam em suas faturas.

### Cartões e faturas

Cadastre nome, limite, fechamento e vencimento. Compras avulsas podem ir para a conta ou para o cartão. Para parcelar, informe o valor total e de 2 a 120 parcelas.

Compras **antes** do dia de fechamento entram na fatura que fecha naquele mês. Compras **no dia ou depois** entram no ciclo seguinte. Se o dia de vencimento for anterior ou igual ao fechamento, o vencimento é no mês seguinte. Dias inexistentes são ajustados ao último dia do mês.

Exemplo: fechamento 25, vencimento 5. Compra em 24/01/2026 vence em 05/02/2026. Compra em 25/01/2026 vence em 05/03/2026. R$ 1.200,00 em 10x gera dez parcelas de R$ 120,00. R$ 100,00 em 3x gera 33,34 + 33,33 + 33,33, preservando todos os centavos.

O valor total compromete o limite imediatamente. O pagamento registrado de uma fatura fechada libera o limite e reduz o saldo da conta. Alterações de dias no cartão não deslocam parcelas já lançadas. O serviço relê os pagamentos atuais antes de pagar para impedir duplicidade por uma tela desatualizada.

### Recorrentes

Assinaturas e contas recorrentes usam ciclos semanal, mensal ou anual, com cobrança em conta ou cartão. O painel mostra a média mensal: mensal = valor; anual ÷ 12; semanal × 52 ÷ 12.

A agenda mantém o dia original: 31/01 → 28/02 → 31/03; assinaturas de 29/02 recuperam esse dia no próximo ano bissexto. Cada ocorrência tem uma chave estável para não duplicar cobranças ao reabrir o app.

Cobranças vencidas são materializadas quando o app abre, volta ao primeiro plano ou permanece ativo. Não dependemos de execução em segundo plano para os alertas: as notificações futuras são agendadas separadamente no sistema.

Pausar interrompe lançamentos e alertas futuros no Ledger; não cancela sua contratação externa. Retomar inicia uma nova agenda hoje, sem cobrar o período pausado. Editar valor, título, cartão ou categoria preserva o histórico. Alterar ciclo ou data reinicia a agenda futura. Excluir preserva cobranças já lançadas.

### Agenda e contas avulsas

Na aba **Agenda**, use **A vencer**, **Atrasados** e **Pagos**. A previsão cobre os próximos 60 dias e também apresenta compromissos atrasados.

Uma conta agendada é somente um compromisso. Ela entra no saldo projetado, mas só vira despesa no saldo efetivo ao tocar em **Já paguei esta conta** ou deslizar e escolher **Pago**. A confirmação registra o pagamento no extrato de hoje, uma única vez. Recorrências já usam seu próprio mecanismo automático; não devem ser cadastradas de novo como conta avulsa.

Renovação no cartão e pagamento da fatura são eventos diferentes, mas a soma de saídas na conta não conta o mesmo valor duas vezes. A aba Pagos lista contas avulsas concluídas; pagamentos de faturas continuam no Extrato.

## Ativar notificações

1. Abra **Início → sino → Preferências**, ou **Agenda → Configurar notificações e Siri**.
2. Ative **Lembretes de pagamento** e aceite a permissão do iOS.
3. Escolha somente no dia, ou também 1, 3 ou 7 dias antes; ajuste o horário.
4. Opcionalmente, permita mostrar valores nos alertas.

Os lembretes incluem faturas pendentes, renovações de assinaturas/recorrências e contas agendadas. Funcionam com o app fechado depois de serem agendados. Ao pagar uma conta ou fatura, excluir, editar ou pausar uma recorrência, o Ledger reconcilia os alertas e remove os obsoletos.

A fila mantém os **60 alertas mais próximos dentro de 60 dias**, em ordem cronológica, com IDs estáveis. Como não há servidor nem execução garantida em segundo plano, abra o Ledger periodicamente para renovar a fila. Horários já passados não geram alertas retroativos; atrasos ficam destacados na Agenda. Foco, permissões e ajustes do sistema podem silenciar notificações.

As preferências mostram a quantidade de alertas pendentes e a data do último alerta da fila, não uma promessa de cobertura de todos os compromissos até essa data. Notificações negadas podem ser reativadas nos Ajustes do Ledger, acessíveis pelo botão na tela de preferências.

## Atalhos e Siri

Abra o app Atalhos e procure **Ledger**, ou use o link em Preferências. As ações disponíveis são:

| Ação | Parâmetros/resultado |
| --- | --- |
| Consultar resumo financeiro | Retorna saldo efetivo e projeção do mês em texto e diálogo |
| Registrar gasto | Descrição, valor em reais, categoria e data opcionais |
| Registrar receita | Descrição, valor em reais, categoria e data opcionais |
| Agendar conta a pagar | Conta, valor em reais, vencimento, categoria opcional |
| Ver pagamentos | Abre a Agenda |
| Buscar no extrato | Busca um texto no Extrato |
| Abrir lançamento | Resolve um lançamento por entidade e abre seus detalhes |

Frases sugeridas: **“Qual é meu saldo no Ledger?”**, **“Registrar gasto no Ledger”**, **“Registrar receita no Ledger”**, **“Agendar conta no Ledger”**, **“Ver pagamentos no Ledger”** e **“Buscar no Ledger”**. Siri solicita os parâmetros que faltarem. Consultas financeiras e gravações exigem autenticação; registrar um gasto não faz pagamento bancário.

No build com SDK 27, `SearchLedgerWithSiriAI` adota `@AppIntent(schema: .system.searchInApp)` e encaminha o termo para a busca do Extrato. Essa é a integração específica da nova Siri AI. Ações financeiras continuam usando App Shortcuts: a Apple ainda não publica um domínio financeiro que permita prometer execução livre de toda operação em linguagem natural. Não usamos schemas de outros domínios para simular uma ação financeira. A disponibilidade da Siri AI também depende do dispositivo, idioma/região e configuração do sistema.

Referências: [App Shortcuts](https://developer.apple.com/documentation/appintents/app-shortcuts), [schema searchInApp](https://developer.apple.com/documentation/appintents/appschema/systemintent/searchinapp), [Apple Intelligence Group Lab](https://developer.apple.com/videos/play/wwdc2026/8011/).

## Fluxo de caixa e persistência

Todos os valores persistidos usam `Int64` em centavos. Nos formulários, digite valores em notação brasileira: `1.234,56`, `1200` ou `0,01`. Nos Atalhos, use o parâmetro numérico em reais.

`Saldo efetivo = receitas acumuladas − despesas na conta acumuladas − pagamentos de faturas acumulados`.

`Saldo projetado = saldo efetivo − faturas pendentes até o fim do mês (inclusive atrasadas) − recorrências futuras na conta no mês − contas agendadas pendentes até o fim do mês`.

O gráfico de categorias soma despesas na conta por data e despesas de cartão por mês de vencimento, incluindo assinaturas previstas. Pagamentos de faturas não entram como uma segunda despesa por categoria. O app não presume receitas futuras, juros, estornos ou movimentações ainda não registradas.

A persistência é local, sem CloudKit. O schema V1 original contém os cinco modelos originais. V2 adiciona somente `ScheduledPayment`, com migração leve. O nome do armazenamento e a identidade do app foram mantidos. O teste de migração cria um armazenamento V1 em disco, abre com V2 e confere os registros preservados. Não há exclusão de banco nem fallback silencioso para memória em caso de falha.

## Organização

```text
project.yml
.github/workflows/build-ipa.yml
FinancialApp/
  App/FinancialApp.swift
  Info.plist
  Ledger.icon/                         # pacote original do Icon Composer
  Assets.xcassets/                     # marca interna e cor de destaque
  Models/
    Category.swift
    CreditCard.swift
    InvoicePayment.swift
    Subscription.swift
    Transaction.swift
    ScheduledPayment.swift
  Services/
    FinanceSupport.swift
    InvoiceEngine.swift
    RecurrenceEngine.swift
    Persistence.swift
    FinanceEvents.swift
    LedgerRouter.swift
    PaymentPlanner.swift
    ReminderPlanner.swift
    NotificationService.swift
  ViewModels/
    CreditCardViewModel.swift
    DashboardViewModel.swift
    SubscriptionViewModel.swift
    TransactionViewModel.swift
    ScheduledPaymentViewModel.swift
  Intents/
    LedgerEntities.swift
    LedgerIntents.swift
    LedgerSiriAI.swift
  Views/
    RootView.swift
    LedgerTheme.swift
    Components.swift
    DashboardView.swift
    TransactionsView.swift
    CreditCardsView.swift
    CreditCardDetailView.swift
    SubscriptionsView.swift
    AddTransactionView.swift
    PaymentAgendaView.swift
    LedgerSettingsView.swift
Resources/LegacyIcon.xcassets/          # fallback dos PNGs fornecidos
scripts/
  prepare_build.py
  tests/test_prepare_build.py
Tests/
  InvoiceEngineTests.swift
  PersistenceAndCashFlowTests.swift
  LedgerPlanningTests.swift
  LedgerMigrationTests.swift
```

## Compilação e testes

No macOS com Xcode 26+ e XcodeGen 2.45.1+:

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

O workflow seleciona um simulador instalado, executa os testes, faz archive unsigned, copia `FinancialApp.app` para `Payload/` e gera `Ledger.ipa`. `SWIFT_VERSION: '5.0'` seleciona o modo de linguagem Swift 5, compilado pelo Swift moderno do Xcode; `5.10` não é um valor válido desse build setting.

Os testes incluem cálculos de faturas e arredondamento, recorrências, limite, pagamento sem duplicação, CRUD, projeção de caixa, migração V1 → V2, fila e antecedência de lembretes, exclusão de alertas de compromissos inativos e validação de valores dos Atalhos. Os testes Python cobrem a seleção dos recursos nos SDKs 26 e 27.

A versão original já foi compilada e instalada pelo usuário. Esta atualização foi desenvolvida no Windows: validação de sintaxe/estrutura e testes Python não substituem uma nova compilação iOS, execução dos XCTest e teste no aparelho. O primeiro workflow deste commit deve confirmar essa validação nativa.

No aparelho, confira ícone em aparências clara/escura, atualização sem perda dos dados antigos, texto ampliado, permissão de notificações, horário de um lembrete próximo com app fechado e frases Siri/Atalhos. Para o schema da Siri AI e o ícone nativo 27, confirme no log que o modo SDK 27 foi selecionado.
