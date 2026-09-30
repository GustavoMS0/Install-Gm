# Instalar direto do GitHub

Este guia mostra como **baixar e executar os scripts direto deste repositório**, sem copiar arquivos manualmente. Há um modo com perguntas e um modo 100% automático.

> **Repositório privado:** o GitHub só entrega os arquivos com autenticação. Sem ela, o download retorna **404 (não encontrado)**. Por isso todos os comandos abaixo usam um **token de acesso**, criado uma única vez no passo 0.

## Sumário
- [Passo 0: criar um token de acesso (uma vez)](#passo-0-criar-um-token-de-acesso-uma-vez)
- [Servidor Linux](#servidor-linux)
  - [Modo A: interativo](#modo-a-interativo-o-script-pergunta-tudo)
  - [Modo B: 100% automático com arquivo de configuração](#modo-b-100-automático-com-arquivo-de-configuração)
  - [Modo C: 100% automático em uma linha](#modo-c-100-automático-em-uma-linha)
  - [Modo D: clonar o repositório inteiro](#modo-d-clonar-o-repositório-inteiro)
- [Windows: gerar o pacote do Intune](#windows-gerar-o-pacote-do-intune)
- [Boas práticas com o token](#boas-práticas-com-o-token)

---

## Passo 0: criar um token de acesso (uma vez)

Use um token **fine-grained**, que só consegue **ler** este repositório. Mesmo que vaze, não dá acesso a mais nada.

1. Acesse **https://github.com/settings/personal-access-tokens/new**
2. Preencha:

   | Campo | Valor |
   |---|---|
   | **Token name** | `instalador-glpi` |
   | **Expiration** | 30 ou 90 dias |
   | **Repository access** | **Only select repositories** → `Instalador-automatico` |
   | **Permissions › Repository permissions › Contents** | **Read-only** |

3. Clique em **Generate token** e **copie o token** (começa com `github_pat_`). Ele só aparece uma vez. Guarde-o no seu cofre de senhas.

> Já usa o GitHub CLI no computador? O comando `gh auth token` mostra um token que também funciona. Ele tem mais permissões, então prefira o fine-grained nos servidores.

---

## Servidor Linux

Em todos os modos, o primeiro passo é **informar o token sem que ele fique no histórico do terminal**:

```bash
read -rsp "Token do GitHub: " GH_TOKEN; echo
```

> Cole o token e aperte Enter. Nada aparece na tela; isso é normal.

### Modo A: interativo (o script pergunta tudo)

```bash
curl -fsSL -H "Authorization: Bearer $GH_TOKEN" -H "Accept: application/vnd.github.raw" \
  -o install-glpi.sh \
  https://api.github.com/repos/GustavoMS0/Instalador-automatico/contents/servidor/install-glpi.sh

sudo bash install-glpi.sh
```

Responda às perguntas (Enter aceita o padrão) e confirme. Veja o que cada pergunta significa no [README](README.md#passo-2-executar).

### Modo B: 100% automático com arquivo de configuração

Ideal para quando você já sabe todos os valores e quer que a instalação rode do início ao fim sem parar.

**1. Baixe o script e o modelo de configuração:**

```bash
REPO_API=https://api.github.com/repos/GustavoMS0/Instalador-automatico/contents
for f in install-glpi.sh glpi-install.conf.example; do
  curl -fsSL -H "Authorization: Bearer $GH_TOKEN" -H "Accept: application/vnd.github.raw" \
    -o "$f" "$REPO_API/servidor/$f"
done
cp glpi-install.conf.example glpi-install.conf
chmod 600 glpi-install.conf
```

**2. Edite a configuração** (`nano glpi-install.conf`), tirando o `#` das linhas que quiser preencher. Um exemplo completo para **banco local**, que não faz nenhuma pergunta:

```bash
GLPI_FQDN="glpi.suaempresa.local"   # ou o IP do servidor
GLPI_PORT="80"
GLPI_LANG="pt_BR"
GLPI_TZ="America/Sao_Paulo"

DB_LOCAL="S"
DB_ADMIN_USER="root"
DB_ADMIN_PASS=""                     # vazio = root local via unix_socket
DB_NAME="glpi"
DB_USER="glpi"
DB_PASS=""                           # vazio = gera senha forte

GLPI_ADMIN_PASS=""                   # vazio = gera senha forte
DISABLE_DEFAULT_USERS="S"
CONFIRM="S"                          # não pede confirmação final
```

<details>
<summary>Exemplo para <b>banco em outro servidor</b></summary>

```bash
GLPI_FQDN="glpi.suaempresa.local"
GLPI_PORT="80"

DB_LOCAL="N"
DB_HOST="10.0.0.20"
DB_PORT="3306"
DB_USER_HOST="10.0.0.10"             # IP deste servidor GLPI (ou %)
DB_ADMIN_USER="admin"
DB_ADMIN_PASS="SenhaDoAdminDoBanco"
DB_NAME="glpi"
DB_USER="glpi"
DB_PASS=""

GLPI_ADMIN_PASS=""
DISABLE_DEFAULT_USERS="S"
CONFIRM="S"
```
</details>

**Como o script lê o arquivo:**

| No arquivo | Comportamento |
|---|---|
| `VARIAVEL="valor"` | Usa o valor e **não pergunta** |
| `VARIAVEL=""` | **Não pergunta** e usa o padrão (nas senhas, gera uma automaticamente) |
| `#VARIAVEL="..."` (comentada) | **Pergunta** normalmente durante a instalação |

**3. Execute e apague o arquivo de configuração:**

```bash
sudo bash install-glpi.sh glpi-install.conf
rm -f glpi-install.conf
sudo cat /root/glpi-install-info.txt      # senhas geradas e URL do agente
```

### Modo C: 100% automático em uma linha

Os mesmos valores do modo B podem ser passados direto no comando, sem arquivo:

```bash
curl -fsSL -H "Authorization: Bearer $GH_TOKEN" -H "Accept: application/vnd.github.raw" \
  -o install-glpi.sh \
  https://api.github.com/repos/GustavoMS0/Instalador-automatico/contents/servidor/install-glpi.sh \
&& sudo GLPI_FQDN="glpi.suaempresa.local" GLPI_PORT="80" \
        DB_LOCAL="S" DB_ADMIN_USER="root" DB_ADMIN_PASS="" \
        DB_NAME="glpi" DB_USER="glpi" DB_PASS="" \
        GLPI_ADMIN_PASS="" DISABLE_DEFAULT_USERS="S" CONFIRM="S" \
        bash install-glpi.sh
```

> Não escreva senhas reais nesta linha: elas ficariam no histórico do terminal (`~/.bash_history`). Deixe as senhas vazias (o script gera senhas fortes) ou use o modo B.

### Modo D: clonar o repositório inteiro

Útil se você vai usar o servidor para ajustar os scripts.

**Com git** (quando pedir senha, cole o **token**):
```bash
sudo apt install -y git
git clone https://github.com/GustavoMS0/Instalador-automatico.git
cd Instalador-automatico/servidor
sudo bash install-glpi.sh
```

**Com GitHub CLI** (login pelo navegador, sem token manual):
```bash
sudo apt install -y gh
gh auth login
gh repo clone GustavoMS0/Instalador-automatico
cd Instalador-automatico/servidor
sudo bash install-glpi.sh
```

> Ao terminar qualquer modo, limpe o token da sessão: `unset GH_TOKEN`

---

## Windows: gerar o pacote do Intune

### Opção 1: com GitHub CLI (se você já fez `gh auth login`)

```powershell
cd $env:USERPROFILE
gh repo clone GustavoMS0/Instalador-automatico
cd .\Instalador-automatico\intune
powershell -ExecutionPolicy Bypass -File .\Build-IntunePackage.ps1 -ServerUrl 'http://glpi.suaempresa.local/front/inventory.php'
```

Para atualizar depois: `cd $env:USERPROFILE\Instalador-automatico; git pull`

### Opção 2: só com PowerShell (sem git)

Cole no PowerShell, trocando a URL do servidor na última linha:

```powershell
$sec = Read-Host "Token do GitHub" -AsSecureString
$tok = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$dest = "$env:USERPROFILE\Instalador-automatico"
$zip  = "$env:TEMP\instalador.zip"; $tmp = "$env:TEMP\instalador"
Remove-Item $dest, $tmp -Recurse -Force -ErrorAction SilentlyContinue
Invoke-WebRequest -UseBasicParsing -Headers @{ Authorization = "Bearer $tok" } `
  -Uri 'https://api.github.com/repos/GustavoMS0/Instalador-automatico/zipball/main' -OutFile $zip
Expand-Archive $zip $tmp -Force
Get-ChildItem $tmp -Directory | Select-Object -First 1 | Move-Item -Destination $dest
Remove-Item $zip, $tmp -Recurse -Force; Remove-Variable tok, sec

cd "$dest\intune"
powershell -ExecutionPolicy Bypass -File .\Build-IntunePackage.ps1 -ServerUrl 'http://glpi.suaempresa.local/front/inventory.php'
```

O pacote fica em `intune\output\`. Siga para [Criar o app no Intune](README.md#passo-2-criar-o-app-no-intune).

---

## Boas práticas com o token

- **Nunca** coloque o token dentro dos scripts, no arquivo de configuração ou em um commit.
- Use `read -rsp` (Linux) ou `Read-Host -AsSecureString` (Windows) para ele não ficar no histórico.
- Prefira o token **fine-grained, somente leitura e com validade curta**.
- Se o token vazar, revogue-o em **https://github.com/settings/personal-access-tokens** e crie outro.

### Se um dia o repositório ficar público

O token deixa de ser necessário e tudo vira um único comando:

```bash
curl -fsSL -o install-glpi.sh https://raw.githubusercontent.com/GustavoMS0/Instalador-automatico/main/servidor/install-glpi.sh && sudo bash install-glpi.sh
```

---

## Problemas comuns

| Erro | Causa / solução |
|---|---|
| `curl: (22) ... 404` | Token ausente, errado, expirado ou sem acesso ao repositório `Instalador-automatico`. Confira o passo 0. |
| `curl: (22) ... 401` | Token inválido ou revogado. Gere um novo. |
| `curl: (22) ... 403` | Limite de requisições da API atingido, ou o token não tem a permissão **Contents: Read-only**. |
| `Arquivo de configuração '...' não encontrado` | Rode o comando na mesma pasta do `glpi-install.conf`, ou informe o caminho completo. |
| `/bin/bash^M: bad interpreter` | O arquivo foi editado no Windows. Rode `sed -i 's/\r$//' install-glpi.sh glpi-install.conf` |
| `DB_ADMIN_PASS não pode ser vazia.` | Com banco **remoto**, a senha do admin é obrigatória no arquivo de configuração. |
