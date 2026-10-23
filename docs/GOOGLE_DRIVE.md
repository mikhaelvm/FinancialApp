# Sincronização e backup do Trackr no Google Drive

O código está preparado para Google Drive, mas o login só funciona depois de configurar um cliente OAuth seu. Sem Client ID, o app compila normalmente e mostra “Configuração do Google pendente”. O backup manual pelo app Arquivos continua disponível.

## 1. Criar o projeto e ativar a API

1. Abra o [Google Cloud Console](https://console.cloud.google.com/) com sua conta Google.
2. No seletor de projetos, crie um projeto chamado **Trackr** e selecione-o.
3. Acesse **APIs e serviços → Biblioteca**.
4. Procure **Google Drive API** e clique em **Ativar**.

Não é necessário Firebase, servidor próprio ou uma conta Apple Developer para este OAuth básico.

## 2. Configurar o consentimento

1. Abra **Google Auth Platform**. Se aparecer o fluxo inicial, clique em começar.
2. Em **Branding**, use **Trackr** como nome e preencha os e-mails de suporte/contato.
3. Em **Público-alvo / Audience**, escolha **Externo** se estiver usando uma conta Gmail pessoal.
4. Enquanto estiver em **Testing / Em teste**, adicione seu próprio e-mail em **Test users / Usuários de teste**.
5. Em **Data Access / Acesso a dados**, adicione somente o escopo:

   ```text
   https://www.googleapis.com/auth/drive.appdata
   ```

O login também utiliza perfil/e-mail para identificar a conta conectada. Não selecione acesso completo ao Drive. `drive.appdata` é um escopo não sensível, limitado à área privada do aplicativo.

Em modo de teste, o Google limita as autorizações deste fluxo a **7 dias**; depois pode ser necessário conectar novamente. Para uso contínuo, revise o status de publicação em Audience e as exigências que o Console apresentar. Publicar o consentimento OAuth é diferente de publicar na App Store. Não prometa sessão permanente: o usuário ou o Google podem revogar a autorização.

## 3. Criar o Client ID de iOS

1. Em **Clients / Clientes**, escolha **Criar cliente**.
2. Tipo de aplicativo: **iOS**.
3. Nome: **Trackr iOS**.
4. Bundle ID: **`com.mikhael.trackr`**.
5. App Store ID e Team ID são opcionais para este login básico. Não ative App Check/App Attest neste fluxo sem configurar os requisitos próprios desses recursos.
6. Crie e copie o **Client ID**, que termina em `.apps.googleusercontent.com`.
7. Copie também o **iOS URL scheme** exibido pelo Google.

Exemplo fictício:

```text
Client ID:      1234567890-abcdef.apps.googleusercontent.com
iOS URL scheme: com.googleusercontent.apps.1234567890-abcdef
```

Envie apenas o Client ID se quiser que eu configure o projeto. Ele é um identificador público do app. Não envie senha, certificado, token, client secret ou conta de serviço.

## 4. Configurar o projeto sem Xcode

Edite estas duas configurações em `project.yml`:

```yaml
TRACKR_GOOGLE_CLIENT_ID: '1234567890-abcdef.apps.googleusercontent.com'
TRACKR_GOOGLE_REVERSED_CLIENT_ID: 'com.googleusercontent.apps.1234567890-abcdef'
```

Use seus valores reais, sem os exemplos. Faça commit/push, aguarde o workflow, baixe `Trackr.ipa` e assine como de costume. O bundle precisa continuar sendo `com.mikhael.trackr`; o assinador precisa preservar os URL schemes e o acesso normal ao Keychain. Tokens são gerenciados pelo SDK do Google no Keychain, não pelo JSON do backup.

## 5. Sincronizar iPhone e iPad

1. Atualize **os dois aparelhos** para Trackr 2.2 ou superior.
2. Primeiro, no iPhone que contém seus dados, abra **Ajustes → Dados e backup → Google Drive** e toque em **Sincronizar agora**. Uma sessão já conectada é reutilizada.
3. No iPad, conecte a **mesma conta Google**, mantenha **Sincronizar entre aparelhos** ativado e aguarde a confirmação.
4. Os registros são buscados automaticamente. O botão **Sincronizar agora** permite repetir a operação.

A sincronização é ativada por padrão ao conectar. Combina registros financeiros, categorias, cartões, recorrências, contas agendadas e dispensas. A primeira conexão preserva registros locais exclusivos e busca o estado remoto; registros com a mesma identidade seguem a versão remota. Na migração do backup antigo, o aparelho com dados locais financeiros tem prioridade sobre a cópia antiga. Por isso, sincronize primeiro o iPhone principal. Um aparelho ainda usando a versão antiga só envia backups e não participa da sincronização.

As mudanças são enviadas cerca de cinco segundos após salvar. Com o app aberto, também busca novidades aproximadamente a cada minuto e ao voltar à tela/desbloquear. Offline, continua funcionando localmente e combina alterações na próxima conexão. Isso não é sincronização instantânea em tempo real nem execução contínua com o app fechado. O iOS decide quando permite atualizações em segundo plano. Com bloqueio de acesso ativo, só sincroniza em uma sessão aberta e desbloqueada.

Cada instalação mantém um documento próprio na área privada do Drive. Revisões por registro combinam alterações independentes; marcadores persistentes impedem que exclusões reapareçam ao reconectar um aparelho antigo. Edições simultâneas no mesmo registro usam revisão lógica e desempate por identificador do aparelho. Uma exclusão recebida vence uma edição offline daquele registro. Cobranças automáticas, recibos de contas agendadas e categorias equivalentes recebem identidades estáveis. Não registre o mesmo pagamento manual nos dois aparelhos enquanto estiverem offline: ações manuais distintas podem gerar registros distintos.

Aparência, ocultação de valores, biometria, orçamento, metas e preferências de notificações continuam próprias de cada aparelho. Use o mesmo projeto OAuth e bundle nas duas instalações.

## 6. Backups independentes da sincronização

**Fazer backup agora** cria uma cópia datada; **Backup automático** é opcional e cria versões somente quando os dados mudam. Mantém as cinco versões mais recentes após confirmar o novo envio. Os documentos de sincronização não entram nessa limpeza. Em **Buscar backups**, há duas opções:

- **Adicionar registros:** inclui os ausentes e preserva os atuais.
- **Substituir todos os dados por esta versão:** restaura o conjunto completo de registros financeiros, inclusive versões anteriores de registros editados, e remove os que não existiam no backup. Antes de alterar o aparelho, envia uma cópia do estado atual ao Drive. O rollback é enviado à mesma conta e os demais aparelhos o aplicam na próxima sincronização. Alterações offline anteriores ao rollback são descartadas. Preferências locais de aparência, orçamento, metas e proteção continuam mantidas. Recorrências automáticas podem gerar novamente cobranças devidas após a data do backup.

Use Trackr **2.3 ou superior em todos os aparelhos** antes do rollback. O documento de sincronização passa ao formato V2 após a primeira substituição; versões anteriores do app precisam atualizar para continuar sincronizando. Backups JSON de versões anteriores continuam sendo aceitos. Se o envio falhar após a substituição local, o app informa que falta sincronizar e conserva a operação para nova tentativa. Uma falha ao criar a cópia de segurança anterior à substituição interrompe o rollback, mantendo os dados locais.

Também é possível sincronizar puxando uma lista para baixo, inclusive as colunas e os cartões do iPad. Sem conexão configurada ou com a sincronização desativada, o gesto orienta a ativação nos ajustes.

A área privada não aparece como pasta navegável no Drive. Desconectar interrompe a sincronização e os backups automáticos, mas mantém dados locais e arquivos remotos. **Apagar todos os dados** redefine somente o aparelho e esquece seu histórico local de sincronização, sem enviar uma exclusão em massa para os outros aparelhos. Reconectar pode trazer os dados da conta novamente. Os arquivos remotos podem ser removidos nas opções de aplicativos conectados do Google.

Os registros viajam em JSON por HTTPS. O Trackr não adiciona criptografia com senha ao arquivo. Continue exportando uma cópia local quando precisar de um backup independente.

## Conferência da versão no iPhone e iPad

- Primeira conexão importa automaticamente e não duplica categorias padrão.
- Criar, editar e excluir lançamentos, cartões e recorrências em cada aparelho; verificar no outro.
- Alterar registros diferentes offline nos dois aparelhos e reconectar; conferir a combinação.
- Dispensar e reativar pagamentos; conferir a Agenda e o Resumo nos dois aparelhos.
- Cobranças automáticas geradas nos dois aparelhos não duplicam os valores.
- Backup manual, listagem das cinco versões e restauração aditiva.
- Rollback: editar e criar registros após um backup, substituí-los pela versão antiga e verificar os dois aparelhos; um aparelho offline deve aceitar a substituição sem reenviar seus registros antigos.
- Confirmar a cópia de segurança anterior ao rollback e o aviso de sincronização pendente se o envio for interrompido.
- Conta desconectada, sessão expirada, sem rede e espaço insuficiente: dados locais permanecem utilizáveis.
- Bloqueio de acesso e redefinição respeitam as regras descritas acima.
- iPad horizontal, vertical e Split View: colunas e grade somente em janela horizontal com pelo menos 950 pontos; Dynamic Type de acessibilidade mantém uma coluna.

## Fontes oficiais

- [Criar credenciais OAuth de iOS](https://developers.google.com/workspace/guides/create-credentials)
- [Google Sign-In para iOS](https://developers.google.com/identity/sign-in/ios/start-integrating)
- [Área privada de dados no Drive](https://developers.google.com/workspace/drive/api/guides/appdata)
- [Expiração de tokens OAuth](https://developers.google.com/identity/protocols/oauth2/)
- [Execução em segundo plano no iOS](https://developer.apple.com/documentation/backgroundtasks/choosing-background-strategies-for-your-app)
