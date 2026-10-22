# Meu Fluxo — FinancialApp

Aplicação nativa para iPhone e iPad com iOS 17+, Swift 5.10, SwiftUI, SwiftData e Swift Charts. O projeto é gerado pelo XcodeGen e compilado no macOS do GitHub Actions. Não exige Xcode instalado no Windows, dependências Swift externas ou credenciais Apple para gerar o **IPA unsigned**.

## Começar pelo Windows

1. Crie um repositório no GitHub e envie **todo o conteúdo desta pasta**, incluindo `.github/workflows/build-ipa.yml`. A pasta `.git` local não deve ser enviada por upload.
2. Se usar Git, execute na pasta do projeto, substituindo a URL pelo seu repositório:

   ```powershell
   git add .
   git commit -m "Adiciona app financeiro nativo e pipeline iOS"
   git branch -M main
   git remote add origin https://github.com/SEU_USUARIO/FinancialApp.git
   git push -u origin main
   ```

   Se já existir um remoto `origin`, use-o ou altere-o com `git remote set-url origin URL`. Se ainda não houver repositório Git local, execute `git init` antes desses comandos.

3. Abra **Actions → Build unsigned iOS IPA → Run workflow**. Push em `main`/`master` e pull requests também executam o pipeline. Caso Actions esteja desabilitado no repositório, habilite-o primeiro.
4. Após uma execução bem-sucedida, abra **Artifacts → FinancialApp-unsigned**. Extraia o ZIP baixado para obter `FinancialApp.ipa`.
5. O artefato `iOS-TestResults` contém o resultado dos testes do Xcode.

**Instalação no iPhone:** o IPA é deliberadamente gerado sem assinatura, conforme solicitado. Ele não abre diretamente no aparelho. Para instalar, é necessário assinar o app com identidade e perfil de provisionamento compatíveis. O pipeline não publica na App Store nem inclui certificados. [Documentação Apple sobre execução em dispositivo](https://help.apple.com/xcode/mac/current/en.lproj/dev5a825a1ca.html).

## Estrutura e código-fonte

Todo o código-fonte está nos arquivos abaixo, sem trechos omitidos ou pseudocódigo:

```text
.
├── .github/
│   └── workflows/
│       └── build-ipa.yml
├── .gitignore
├── project.yml
├── README.md
├── FinancialApp/
│   ├── Info.plist
│   ├── App/
│   │   └── FinancialApp.swift
│   ├── Models/
│   │   ├── Category.swift
│   │   ├── CreditCard.swift
│   │   ├── InvoicePayment.swift
│   │   ├── Subscription.swift
│   │   └── Transaction.swift
│   ├── Services/
│   │   ├── FinanceSupport.swift
│   │   ├── InvoiceEngine.swift
│   │   ├── Persistence.swift
│   │   └── RecurrenceEngine.swift
│   ├── ViewModels/
│   │   ├── CreditCardViewModel.swift
│   │   ├── DashboardViewModel.swift
│   │   ├── SubscriptionViewModel.swift
│   │   └── TransactionViewModel.swift
│   └── Views/
│       ├── AddTransactionView.swift
│       ├── Components.swift
│       ├── CreditCardDetailView.swift
│       ├── CreditCardsView.swift
│       ├── DashboardView.swift
│       ├── RootView.swift
│       ├── SubscriptionsView.swift
│       └── TransactionsView.swift
└── Tests/
    ├── InvoiceEngineTests.swift
    └── PersistenceAndCashFlowTests.swift
```

## Fluxo de uso

- **Cartões:** cadastre nome, limite, fechamento e vencimento. Abra o cartão para consultar todas as faturas, parcelas, previsão de assinaturas e compromissos dos próximos 12 meses.
- **Adicionar:** escolha À vista / avulsa, Parcelado ou Recorrente / assinatura. Compras avulsas podem ser pagas por conta ou cartão. Receitas são registradas na conta. No modo Parcelado, informe o valor **total**, o cartão e de 2 a 120 parcelas.
- **Transações:** consulte, busque, edite e exclua receitas e despesas manuais na conta. Lançamentos automáticos e pagamentos de faturas têm histórico preservado.
- **Assinaturas:** cadastre categoria, valor, ciclo e forma de cobrança; edite, pause, retome ou exclua. O painel destaca renovações até os próximos sete dias.
- **Resumo:** acompanhe saldo acumulado, receitas, saídas, pagamentos de faturas, compromissos restantes, categorias e evolução das faturas.
- **Pagar fatura:** quando a fatura estiver fechada, registre o pagamento integral do saldo lançado. Isso diminui o saldo da conta e libera o limite. A confirmação representa um pagamento já realizado; o app não se conecta ao banco.
- **Saldo inicial:** registre uma receita com o valor inicial da conta. O app começa sem transações fictícias.

## Regras financeiras implementadas

### Dinheiro e arredondamento

Os modelos usam `Int64` em centavos. Digite valores em notação brasileira, como `1.234,56`, `1200` ou `0,01`. O ponto é separador de milhar e a vírgula separa os centavos. O limite por lançamento é R$ 10 bilhões.

Divisão de parcelas não perde centavos: R$ 100,00 em 3x produz R$ 33,34 + R$ 33,33 + R$ 33,33. R$ 1.200,00 em 10x produz exatamente dez parcelas de R$ 120,00. As parcelas devem ter ao menos R$ 0,01.

### Fechamento e vencimento

O cálculo usa calendário gregoriano e datas civis no fuso do aparelho:

1. Compra **antes** do fechamento entra no ciclo que fecha naquele mês.
2. Compra **no dia ou depois** do fechamento entra no ciclo seguinte.
3. Se o dia de vencimento for maior que o de fechamento, o vencimento é no mesmo mês do fechamento; caso contrário, no mês seguinte.
4. Dias inexistentes usam o último dia do mês. Em meses seguintes, o dia original é restaurado.
5. Cada parcela mantém fechamento e vencimento próprios. Alterar o cartão não recalcula lançamentos existentes.

Exemplo: fechamento dia 25 e vencimento dia 5. Compra em 24/01/2026 vence em 05/02/2026; compra em 25/01/2026 vence em 05/03/2026. No primeiro caso, uma compra de R$ 1.200,00 em 10x distribui R$ 120,00 de fevereiro a novembro de 2026.

O status é `Paga` quando não há saldo restante, `Vencida` após o vencimento e `Fechada` a partir do fechamento. Faturas posteriores aparecem como `Aberta / futura`.

### Limite e pagamentos

O valor total de uma compra, incluindo todas as parcelas futuras, compromete o limite imediatamente. Compras manuais que excedem o limite disponível são rejeitadas. O limite é liberado quando o pagamento é registrado, não simplesmente quando o mês muda.

Assinaturas efetivamente renovadas são registradas mesmo se ultrapassarem o limite, para não esconder obrigações financeiras. Nesse caso, há um alerta no cartão. Renovações apenas previstas ainda não consomem limite.

O pagamento integral da fatura é salvo como `InvoicePayment`. Ele não gera uma segunda despesa por categoria. Cartões com histórico ou assinaturas vinculadas não podem ser excluídos. Esta versão não inclui pagamentos parciais, estornos, juros, rotativo ou reconciliação bancária.

### Recorrências

`RecurrenceEngine` gera cobranças vencidas quando o app é aberto, volta ao primeiro plano ou permanece ativo. O app confere atualizações a cada minuto enquanto estiver em primeiro plano. Não há processamento garantido em segundo plano: iOS não garante execução em cada data de renovação sem abrir o app.

Cada ocorrência tem uma chave estável de agenda e índice. A gravação da transação e o avanço da próxima renovação são salvos juntos, evitando duplicação ao reabrir o app. Se ele ficar fechado durante meses, as cobranças de assinaturas ativas são recuperadas ao reabrir.

A recorrência mensal se ancora no dia original: 31/01 → 28/02 → 31/03. Uma assinatura anual iniciada em 29/02 volta a esse dia no próximo ano bissexto. A semanal avança sete dias civis.

Ao editar valor, título, cartão ou categoria, cobranças existentes permanecem com os dados originais. Alterar ciclo ou próxima data cria uma nova agenda para ocorrências futuras. Pausar interrompe cobranças; **retomar inicia uma nova agenda hoje**, sem cobrar o período pausado. Excluir a assinatura preserva transações já lançadas.

Faturas futuras exibem cobranças virtuais das assinaturas ativas. Elas não criam transações nem afetam o saldo atual. A média mensal usa mensal = valor, anual = valor ÷ 12 e semanal = valor × 52 ÷ 12; o desembolso real varia conforme o calendário.

O alerta de sete dias é visual no painel. Não são solicitadas permissões de notificação nem programadas notificações locais.

### Dashboard

`Saldo consolidado = receitas acumuladas − despesas na conta acumuladas − pagamentos de faturas acumulados`.

O cartão não diminui o saldo da conta no momento da compra; ele cria uma obrigação. `Saldo após compromissos` subtrai do saldo atual as faturas pendentes até o fim do mês, inclusive atrasadas, e as recorrências futuras na conta até o fim do mês. Receitas futuras não são presumidas.

O gráfico de categorias soma despesas na conta pela data da transação e despesas no cartão pelo mês de vencimento da parcela, incluindo assinaturas projetadas. O gráfico de faturas apresenta o valor ainda pendente por mês. O detalhe do cartão mostra também as compras já lançadas ainda comprometidas a partir de cada mês.

## Arquitetura e persistência

- Models: entidades `@Model`, relações inversas explícitas, cascata e nullify conforme o histórico.
- Views: `NavigationStack`, `TabView`, formulários, sheets, listas `insetGrouped`, SF Symbols, tamanhos de fonte semânticos e cores de sistema para Light/Dark Mode.
- ViewModels: `@Observable` e `@MainActor` para validação, comandos e composição do dashboard.
- Services: cálculo de faturas, recorrências, formatação, schema versionado e criação do container.
- SwiftData local, sem CloudKit ou dependência de conta. Seed idempotente de nove categorias e consulta de assinaturas ativas com `#Predicate`.
- Falha de persistência apresenta erro; não há troca silenciosa para banco temporário nem exclusão do armazenamento.

O banco inicial usa `FinanceSchemaV1` e `FinanceMigrationPlan`. Antes de alterar modelos em uma versão distribuída, preserve a definição antiga no schema V1, crie o próximo schema e implemente a migração necessária. Dados permanecem no sandbox local; esta versão não possui exportação ou sincronização entre aparelhos.

## Compilação no macOS / GitHub Actions

O Bundle Identifier é `com.mikhael.FinancialApp`. Para personalizá-lo, edite `PRODUCT_BUNDLE_IDENTIFIER` em `project.yml`. O deployment target é iOS 17.0. O código requer compilador Swift 5.10 ou superior, fornecido pelo Xcode disponível no runner `macos-latest`. `SWIFT_VERSION: '5.0'` seleciona o modo de linguagem Swift 5; esse build setting não aceita `5.10` como versão de linguagem.

```bash
brew install xcodegen
xcodegen generate --spec project.yml

xcodebuild archive \
  -project FinancialApp.xcodeproj \
  -scheme FinancialApp \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$PWD/build/FinancialApp.xcarchive" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""

mkdir -p build/package/Payload
ditto build/FinancialApp.xcarchive/Products/Applications/FinancialApp.app \
      build/package/Payload/FinancialApp.app
cd build/package
zip -qry ../FinancialApp.ipa Payload
```

O workflow executa os testes antes do archive, escolhe dinamicamente um simulador iPhone instalado e usa `actions/upload-artifact@v4` para publicar os artefatos. Somente o build de simulador usa assinatura ad hoc (`-`), sem certificados ou conta Apple, para permitir execução em runners Apple Silicon. O archive para dispositivo permanece unsigned. Não usa `xcodebuild -exportArchive`, que envolveria um fluxo de distribuição assinado. O ZIP do IPA contém `Payload/FinancialApp.app` com o executável real do archive.

Não há ícone personalizado nesta entrega; o app usa a apresentação padrão de desenvolvimento. Para uma distribuição assinada pela App Store, adicione AppIcon, configure assinatura e os requisitos de distribuição do seu produto.

## Testes e validação

Os XCTest em `Tests/` verificam regras de fechamento, virada de ano, fevereiro e anos bissextos, soma exata das parcelas, parsing de reais, relações SwiftData, seed idempotente, limite, pagamento, fluxo de caixa, recorrências, projeções sem gravação, preservação de histórico e CRUD de transações.

Para executar no macOS, use um identificador de simulador obtido com `xcrun simctl list devices available`:

```bash
xcodebuild test -project FinancialApp.xcodeproj -scheme FinancialApp \
  -destination 'platform=iOS Simulator,id=SEU_UUID' \
  CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="-"
```

O ambiente Windows de autoria não possui o SDK iOS/Xcode. A compilação nativa, execução dos XCTest e geração do IPA precisam ser confirmadas pela primeira execução do workflow macOS. Nenhum IPA pré-compilado está incluído no código-fonte.

A revisão local verificou os 24 arquivos Swift com um parser de sintaxe, os dois YAML, o XML do `Info.plist`, as flags de archive e o Python embutido de seleção de simulador. Essas verificações não substituem a compilação, a resolução dos tipos Swift nem os testes no SDK da Apple.

Referências: [XcodeGen Project Spec](https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md), [SwiftData ModelContainer](https://developer.apple.com/documentation/swiftdata/modelcontainer), [GitHub workflow artifacts](https://docs.github.com/en/actions/concepts/workflows-and-actions/workflow-artifacts).
