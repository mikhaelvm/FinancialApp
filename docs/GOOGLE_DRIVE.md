# Configurar backup do Trackr no Google Drive

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

## 5. Usar no iPhone

1. Abra **Ajustes do Trackr → Dados e backup → Google Drive**.
2. Toque em **Conectar Google Drive**, escolha sua conta e autorize a área privada.
3. Faça um primeiro backup com **Fazer backup agora**.
4. Ative **Backup automático** se desejar.
5. Para recuperar dados, toque em **Buscar backups**, selecione uma versão e confirme.

O backup automático agrupa alterações por 30 segundos e só envia quando o conteúdo mudou. Também verifica alterações ao abrir o app. O iOS pode conceder execuções adicionais em segundo plano, mas não garante frequência nem horário. Com o bloqueio de acesso do Trackr ativo, o envio ocorre somente com uma sessão aberta e desbloqueada.

São mantidas as cinco versões mais recentes na área privada, **após** o novo envio ser confirmado. Essa área não aparece como pasta navegável no Drive. A restauração adiciona registros ausentes e preserva os existentes; não substitui valores já cadastrados. Preferências do aparelho não são restauradas.

Desconectar ou redefinir o Trackr interrompe o automático e remove a sessão local. Isso não apaga os backups do Drive. Ao reinstalar, conecte a mesma conta usando o mesmo projeto OAuth para encontrá-los. Backups podem ser removidos pelas opções de aplicativos conectados do Google; não os trate como única cópia.

O conteúdo financeiro é enviado em JSON pela conexão HTTPS. O Trackr não adiciona criptografia com senha ao arquivo. Continue usando a exportação local quando quiser uma cópia independente.

## Conferência após a configuração

- Login, cancelamento e retorno ao Trackr.
- Backup manual e listagem das versões.
- Nenhum envio automático antes de ativar a opção.
- Alterações agrupadas; sem nova versão quando nada mudou.
- Restauração em instalação de teste, sem apagar os dados da instalação principal.
- Conta desconectada, sem internet, sessão expirada e armazenamento insuficiente.
- Bloqueio de acesso e redefinição interrompem novos envios conforme descrito acima.

## Fontes oficiais

- [Criar credenciais OAuth de iOS](https://developers.google.com/workspace/guides/create-credentials)
- [Google Sign-In para iOS](https://developers.google.com/identity/sign-in/ios/start-integrating)
- [Área privada de dados no Drive](https://developers.google.com/workspace/drive/api/guides/appdata)
- [Expiração de tokens OAuth](https://developers.google.com/identity/protocols/oauth2/)
- [Execução em segundo plano no iOS](https://developer.apple.com/documentation/backgroundtasks/choosing-background-strategies-for-your-app)
