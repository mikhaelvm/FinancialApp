# Trackr

App de finanças pessoais para iPhone e iPad, com armazenamento local e sincronização opcional pelo Google Drive.

## Recursos

- Resumo de saldo, receitas, despesas, orçamento e relatórios mensais.
- Extrato por mês, com busca e categorias personalizáveis.
- Cartões com limites, compras parceladas, faturas e registro de pagamentos.
- Agenda de pagamentos e contas recorrentes, com lembretes e opção de dispensar cobranças.
- Importação de extratos OFX, CSV e PDF, além de exportação CSV.
- Backup e restauração em JSON ou Google Drive, com histórico de versões e sincronização entre aparelhos.
- Widgets, Atalhos da Siri e proteção opcional por Face ID ou Touch ID.

## Requisitos

iOS/iPadOS 17 ou posterior. Desenvolvido com SwiftUI e SwiftData.

## Compilação e instalação

1. No GitHub Actions, execute o workflow **Build Trackr IPA**.
2. Ao concluir, baixe o arquivo **Trackr.ipa** nos artefatos da execução.
3. Assine o IPA com seu certificado e instale no dispositivo.

Para compilar no Mac, use Xcode 26 ou posterior e XcodeGen para gerar o projeto a partir de `project.yml`.

## Google Drive

A conexão é opcional e fica nas configurações do app. Use a mesma conta nos aparelhos para sincronizar os dados; também é possível sincronizar puxando as listas para baixo.

Consulte as [instruções de configuração do Google Drive](docs/GOOGLE_DRIVE.md) para configurar o OAuth de uma compilação própria.
