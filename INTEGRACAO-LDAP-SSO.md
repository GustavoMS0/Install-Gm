# Grupos e perfis automáticos com LDAP / Active Directory e SSO

Este guia mostra como fazer o GLPI colocar cada pessoa **no grupo certo e com o perfil certo, sozinho**, a partir do Active Directory (ou outro LDAP) e do login único (SSO).

Ele complementa o [PERFIS-E-PERMISSOES.md](PERFIS-E-PERMISSOES.md): lá está **o que** cada perfil e grupo enxerga; aqui está **como** preencher isso automaticamente.

> Os nomes de menu seguem o GLPI 11 em português. No GLPI 10 o caminho é o mesmo. Entre parênteses está o nome em inglês, para quem usa o GLPI nesse idioma.

## Sumário
- [O que precisa ser automatizado](#o-que-precisa-ser-automatizado)
- [Qual cenário é o seu?](#qual-cenário-é-o-seu)
- [Passo 1: organizar os grupos no AD](#passo-1-organizar-os-grupos-no-ad)
- [Passo 2: conectar o GLPI ao AD](#passo-2-conectar-o-glpi-ao-ad)
- [Passo 3: ligar cada grupo do GLPI a um grupo do AD](#passo-3-ligar-cada-grupo-do-glpi-a-um-grupo-do-ad)
- [Passo 4: regras de autorização (perfil e entidade)](#passo-4-regras-de-autorização-perfil-e-entidade)
- [Passo 5: testar e sincronizar](#passo-5-testar-e-sincronizar)
- [SSO: login único](#sso-login-único)
- [Problemas comuns](#problemas-comuns)

---

## O que precisa ser automatizado

Cada pessoa precisa de duas coisas no GLPI:

| | Define | Exemplo | Como automatizar |
|---|---|---|---|
| **Grupo** | quais chamados vê e de qual equipe faz parte | RH, Comercial | ligar o grupo do GLPI a um grupo do AD ([Passo 3](#passo-3-ligar-cada-grupo-do-glpi-a-um-grupo-do-ad)) |
| **Perfil + entidade** | o que pode fazer e em qual empresa ou filial | Atendente de Área, na matriz | regras de autorização ([Passo 4](#passo-4-regras-de-autorização-perfil-e-entidade)) |

Depois disso, **é só gerenciar os grupos no AD**. Quem entra no grupo `GLPI-RH-Atendentes` passa a atender os chamados do RH no próximo login. Quem sai do grupo perde o acesso.

As regras de **grupo requerente** criadas pelo instalador funcionam sem ajuste: elas olham os grupos de que a pessoa faz parte, venham eles do AD ou do cadastro manual.

---

## Qual cenário é o seu?

| Cenário | Como o usuário entra | Grupos vêm do AD? | Siga |
|---|---|---|---|
| **A. Login com usuário e senha do AD** | digita o usuário e a senha da rede na tela do GLPI | ✅ | Passos 1 a 5 |
| **B. SSO + AD** (Kerberos no domínio, ou SAML/OpenID pelo Apache) | entra direto, sem digitar senha | ✅, o GLPI busca o usuário no AD | Passos 1 a 5 + [SSO](#sso-login-único) |
| **C. SSO sem AD** (só Entra ID / Google, sem LDAP) | entra com a conta Microsoft ou Google | ❌ não no GLPI padrão | [SSO sem LDAP](#cenário-c-sso-sem-ldap) |

---

## Passo 1: organizar os grupos no AD

Use um grupo de segurança por **papel**, com um prefixo fácil de filtrar. Exemplo para os grupos e perfis criados pelo instalador:

| Grupo no AD | Grupo no GLPI | Perfil no GLPI |
|---|---|---|
| `GLPI-TI-Tecnicos` | TI | Técnico de TI |
| `GLPI-TI-Gestores` | TI | Gestor de TI |
| `GLPI-RH-Atendentes` | RH | Atendente de Área |
| `GLPI-RH-Gestores` | RH | Gestor de Área |
| `GLPI-Financeiro-Atendentes` | Financeiro | Atendente de Área |
| `GLPI-Financeiro-Gestores` | Financeiro | Gestor de Área |
| `GLPI-Marketing-Atendentes` | Marketing | Atendente de Área |
| `GLPI-Marketing-Gestores` | Marketing | Gestor de Área |
| `GLPI-Comercial` | Comercial | (Self-Service, pela regra geral) |
| `GLPI-Comercial-Gestores` | Comercial | Gestor de Equipe |

> **Alternativa sem criar grupos no AD:** se o campo **Departamento** (`department`) do AD estiver bem preenchido, ele pode definir o grupo da equipe (veja a [opção B do Passo 3](#opção-b-pelo-departamento-do-usuário)). Os grupos `...-Atendentes` e `...-Gestores` continuam úteis para os perfis.

---

## Passo 2: conectar o GLPI ao AD

**Configurar › Autenticação › Diretórios LDAP** *(Setup › Authentication › LDAP directories)* › **Adicionar**

| Campo | Valor (exemplo para AD) |
|---|---|
| Nome | `Active Directory` |
| Servidor padrão | Sim |
| Ativo | Sim |
| Servidor | `ldap://dc01.empresa.local` (ou `ldaps://` na porta 636) |
| Porta | `389` (ou `636` com LDAPS) |
| Filtro de conexão | `(&(objectClass=user)(objectCategory=person)(!(userAccountControl:1.2.840.113556.1.4.803:=2)))` (só usuários ativos) |
| BaseDN | `DC=empresa,DC=local` |
| RootDN (usuário para conexões) | `CN=svc-glpi,OU=Servicos,DC=empresa,DC=local` (conta de serviço, só leitura) |
| Senha | senha da conta de serviço |
| Campo de login | `samaccountname` (ou `userprincipalname` para logins `nome@empresa.com`) |
| Campo de sincronização | `objectguid` |

Na aba **Grupos** *(Groups)* do mesmo diretório:

| Campo | Valor |
|---|---|
| Tipo de pesquisa | **Nos usuários** *(In users)* |
| Atributo do usuário que contém os grupos | `memberof` |
| Usar DN na pesquisa | Sim |

Clique em **Testar** na aba **Testar** para conferir a conexão.

> Grupos dentro de grupos (aninhados) não são seguidos pelo `memberof`. Coloque as pessoas **diretamente** nos grupos `GLPI-*`.

---

## Passo 3: ligar cada grupo do GLPI a um grupo do AD

**Administração › Grupos** *(Administration › Groups)* › abra o grupo, por exemplo **RH**, › aba **Diretório LDAP** *(LDAP directory link)*. Escolha **uma** das opções:

### Opção A: pelo grupo do AD (recomendada)

| Campo | Valor |
|---|---|
| DN do grupo *(Group DN)* | `CN=GLPI-RH-Atendentes,OU=Grupos,DC=empresa,DC=local` |

Quem está no grupo `GLPI-RH-Atendentes` do AD passa a fazer parte do grupo **RH** do GLPI.

Um grupo do GLPI aceita **um** DN. Como atendentes e gestores do RH estão em grupos diferentes do AD, ligue o grupo RH a `GLPI-RH-Atendentes` e inclua os gestores no grupo RH pela regra do [Passo 4](#passo-4-regras-de-autorização-perfil-e-entidade) (ação **Grupos**). Isso já está previsto nos exemplos de lá.

### Opção B: pelo departamento do usuário

| Campo | Valor |
|---|---|
| Atributo do usuário que contém os grupos | `department` |
| Valor do atributo | `RH` |

Quem tem **Departamento = RH** no AD entra no grupo RH. É ideal para os grupos de **equipe** (Comercial, Produção...), porque usa um campo que o RH ou a TI já mantêm atualizado.

> O valor precisa ser **idêntico** ao do AD, inclusive acentos e maiúsculas (`Produção` ≠ `Producao`).

Faça isso para cada grupo criado pelo instalador (TI, RH, Financeiro, Marketing e as equipes extras).

---

## Passo 4: regras de autorização (perfil e entidade)

As regras definem o **perfil** e a **entidade** de cada pessoa no login. O GLPI executa **todas** as regras que combinarem, então uma pessoa pode receber o Self-Service pela regra geral e o Atendente de Área por outra.

### 4.1 Cadastrar o critério `memberof`

O GLPI só usa nas regras os atributos LDAP cadastrados como critério. O `memberof` não vem cadastrado.

**Administração › Regras › Critérios LDAP** *(Administration › Rules › LDAP criteria)* › **Adicionar**:

| Nome | Critério |
|---|---|
| `Grupos do AD` | `memberof` |
| `Departamento` | `department` (se for usar) |

### 4.2 Criar as regras

**Administração › Regras › Regras de autorização** *(Authorizations assignment rules)* › **Adicionar**.

**Regra 1, para todo mundo** (colaboradores):

| | |
|---|---|
| Nome | `AD - todos: Self-Service` |
| Critério | **Servidor LDAP** *é* `Active Directory` |
| Ações | **Entidade** = *a matriz* · **Recursivo** = Sim · **Perfis** = Self-Service |

**Uma regra por papel**, por exemplo para os atendentes do RH:

| | |
|---|---|
| Nome | `AD - RH atendentes` |
| Critérios (todos) | **Servidor LDAP** *é* `Active Directory` **E** **Grupos do AD** *contém* `CN=GLPI-RH-Atendentes` |
| Ações | **Entidade** = *a matriz* · **Recursivo** = Sim · **Perfis** = Atendente de Área · **Grupos** = RH |

Repita trocando o grupo do AD, o perfil e o grupo:

| Regra | Grupos do AD contém | Perfis | Grupos |
|---|---|---|---|
| AD - TI técnicos | `CN=GLPI-TI-Tecnicos` | Técnico de TI | TI |
| AD - TI gestores | `CN=GLPI-TI-Gestores` | Gestor de TI | TI |
| AD - RH atendentes | `CN=GLPI-RH-Atendentes` | Atendente de Área | RH |
| AD - RH gestores | `CN=GLPI-RH-Gestores` | Gestor de Área | RH |
| AD - Comercial gestores | `CN=GLPI-Comercial-Gestores` | Gestor de Equipe | Comercial |
| *...uma linha por área ou equipe* | | | |

> **A ação "Grupos" também resolve o grupo da pessoa**, então para os perfis o [Passo 3](#passo-3-ligar-cada-grupo-do-glpi-a-um-grupo-do-ad) vira opcional. Use o Passo 3 para as equipes (todo colaborador do Comercial no grupo Comercial) e a regra para os papéis (atendentes e gestores).

### 4.3 Filiais

Para que o pessoal de uma filial fique **só** na filial, troque a ação **Entidade** pela filial e use **Recursivo = Não**. Exemplo: `AD - Filial SP: Self-Service`, com o critério **Grupos do AD** *contém* `CN=GLPI-Filial-SP` e a ação **Entidade** = `Matriz > Filial São Paulo`.

Também dá para usar a ação **Entidade baseada nas informações LDAP** *(Entity based on LDAP information)* com a OU do usuário, quando o AD já é organizado por filial.

---

## Passo 5: testar e sincronizar

1. **Testar as regras sem fazer login:** em **Regras de autorização**, clique em **Testar o motor de regras** *(Test rules engine)*, informe um login e veja quais perfis e grupos ele receberia.
2. **Primeiro login:** entre com um usuário de teste do AD. Em **Administração › Usuários**, confira as abas **Habilitações** (perfis) e **Grupos**. Os grupos que vieram do AD aparecem como **Dinâmico = Sim**.
3. **Sincronizar todos de uma vez** (sem esperar cada pessoa entrar), no servidor:
   ```bash
   cd /var/www/glpi
   sudo -u www-data php bin/console ldap:synchronize_users --only-update-existing   # atualiza quem já entrou
   sudo -u www-data php bin/console ldap:synchronize_users --only-create-new        # importa quem nunca entrou
   ```
   Para manter tudo em dia, agende no cron, por exemplo todos os dias às 6h:
   ```bash
   echo '0 6 * * * www-data /usr/bin/php /var/www/glpi/bin/console ldap:synchronize_users --no-interaction >/dev/null 2>&1' \
     | sudo tee /etc/cron.d/glpi-ldap-sync
   ```

> Os grupos e perfis **dinâmicos** (vindos do AD) são recalculados a cada login e a cada sincronização. Os **manuais**, adicionados à mão no GLPI, não são mexidos.

---

## SSO: login único

### Cenário B: SSO + AD

O GLPI **não faz o SSO sozinho**: quem autentica é o **servidor web** (Apache). Depois, o Apache entrega o usuário ao GLPI pela variável `REMOTE_USER`, e o GLPI **procura esse usuário no AD configurado no Passo 2**. Por isso os grupos e as regras dos Passos 3 e 4 continuam valendo.

| Origem do login | Módulo do Apache | O que chega em `REMOTE_USER` |
|---|---|---|
| Windows no domínio (Kerberos) | `mod_auth_gssapi` | `usuario@EMPRESA.LOCAL` |
| Entra ID / Azure AD, Google, Keycloak (OpenID Connect) | `mod_auth_openidc` | `usuario@empresa.com` (UPN ou e-mail) |
| ADFS, Entra ID e outros (SAML) | `mod_auth_mellon` | `usuario@empresa.com` |

**No GLPI:** **Configurar › Autenticação › Outros métodos de autenticação** *(Other authentication methods)* › **Outra autenticação enviada na requisição HTTP**:

| Campo | Valor |
|---|---|
| Campo de armazenamento do login na requisição HTTP | `REMOTE_USER` |
| Remover o domínio de logins como login@domínio | **Sim**, se o Campo de login do LDAP for `samaccountname`. **Não**, se for `userprincipalname` |
| URL de logout do SSO | a URL de logout do provedor (opcional) |

O login que chega do SSO precisa ser **o mesmo valor** do campo de login do LDAP. Por exemplo, `joao.silva` (com o domínio removido) e `samaccountname = joao.silva`. Se não for igual, o GLPI não encontra o usuário no AD e ele fica sem grupos.

> A configuração do módulo do Apache (certificados, client ID do Entra ID, keytab do Kerberos) depende do seu provedor e fica fora deste guia. Teste primeiro com uma página simples protegida pelo módulo e confira que `REMOTE_USER` chega como esperado. Só depois aponte para o GLPI.

### Cenário C: SSO sem LDAP

Quando **não existe LDAP** (por exemplo, empresa 100% Microsoft 365 com Entra ID, sem AD local), o login pelo `REMOTE_USER` funciona, mas o GLPI padrão **só recebe dados básicos** do SSO (nome, e-mail, telefone, cargo). Ele **não recebe os grupos**. Opções:

1. **Plugin de SSO (SAML ou OAuth/OpenID).** O GLPI Marketplace e a comunidade têm plugins que fazem o login com Entra ID e Google direto pelo GLPI. Antes de escolher, **confira se o plugin mapeia grupos ou claims do provedor para grupos e perfis do GLPI** e se é compatível com a sua versão do GLPI.
2. **Expor o diretório via LDAP:** o **Microsoft Entra Domain Services** oferece LDAP sobre os usuários do Entra ID. Assim você volta ao cenário B e usa os Passos 1 a 5.
3. **Regras de autorização sem grupos:** sem LDAP, as regras ainda podem usar o **login** e o **e-mail**. Por exemplo, todo `@empresa.com` vira Self-Service na matriz, e os atendentes e gestores são ajustados à mão em **Administração › Usuários**. Funciona bem para equipes pequenas.

---

## Problemas comuns

| Sintoma | Causa provável | Solução |
|---|---|---|
| O usuário entra, mas fica **sem nenhum perfil** ("Você não tem acesso") | nenhuma regra de autorização combinou | Crie a regra geral `AD - todos: Self-Service` e use **Testar o motor de regras** |
| O usuário não entra no grupo do GLPI | DN errado, grupo aninhado ou `memberof` não configurado | Confira o DN exato (no AD: *Propriedades › Editor de Atributos › distinguishedName*), coloque a pessoa direto no grupo e revise a aba **Grupos** do diretório |
| A regra com **Grupos do AD** nunca combina | critério `memberof` não cadastrado em **Critérios LDAP** | Cadastre-o ([4.1](#41-cadastrar-o-critério-memberof)) |
| Mudei a pessoa de grupo no AD e nada aconteceu | os dados só são atualizados no login ou na sincronização | Peça um novo login ou rode o `ldap:synchronize_users` |
| No SSO aparece "usuário não encontrado" ou ele vem sem grupos | o login do SSO é diferente do campo de login do LDAP | Ajuste "Remover o domínio" ou troque o campo de login para `userprincipalname` |
| O gestor da equipe não vê os chamados da equipe | o colaborador não está no grupo da equipe | Ligue o grupo da equipe ao AD (Passo 3, opção B, com `department`) ou inclua a ação **Grupos** na regra |
