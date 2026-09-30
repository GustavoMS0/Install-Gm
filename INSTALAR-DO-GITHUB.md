# Instalar direto do GitHub

Este guia mostra como **baixar e executar os scripts direto deste repositório**, sem copiar arquivos manualmente. Há um modo com perguntas e um modo 100% automático.

## Sumário
- [Servidor Linux](#servidor-linux)
  - [Modo A: interativo](#modo-a-interativo-o-script-pergunta-tudo)
  - [Modo B: 100% automático com arquivo de configuração](#modo-b-100-automático-com-arquivo-de-configuração)
  - [Modo C: 100% automático em uma linha](#modo-c-100-automático-em-uma-linha)
  - [Modo D: clonar o repositório inteiro](#modo-d-clonar-o-repositório-inteiro)
- [Windows: gerar o pacote do Intune](#windows-gerar-o-pacote-do-intune)
- [Usar uma versão fixa do instalador](#usar-uma-versão-fixa-do-instalador)
- [Problemas comuns](#problemas-comuns)

---

## Servidor Linux

> **Pré-requisito:** o `curl` precisa estar instalado. Se não estiver: `sudo apt update && sudo apt install -y curl`

### Modo A: interativo (o script pergunta tudo)

```bash
curl -fsSLO https://raw.githubusercontent.com/GustavoMS0/Install-Gm/main/servidor/install-glpi.sh
sudo bash install-glpi.sh
```

Responda às perguntas (Enter aceita o padrão) e confirme. Veja o que cada pergunta significa no [README](README.md#passo-2-executar).

<details>
<summary>Prefere executar sem salvar o arquivo?</summary>

```bash
curl -fsSL https://raw.githubusercontent.com/GustavoMS0/Install-Gm/main/servidor/install-glpi.sh | sudo bash
```

As perguntas continuam funcionando normalmente. Ainda assim, **baixar primeiro é mais seguro**: você pode ler o script antes de rodar como root (`less install-glpi.sh`).
</details>

### Modo B: 100% automático com arquivo de configuração

Ideal para quando você já sabe todos os valores e quer que a instalação rode do início ao fim sem parar.

**1. Baixe o script e o modelo de configuração:**

```bash
BASE=https://raw.githubusercontent.com/GustavoMS0/Install-Gm/main/servidor
curl -fsSLO "$BASE/install-glpi.sh"
curl -fsSL  "$BASE/glpi-install.conf.example" -o glpi-install.conf
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
curl -fsSLO https://raw.githubusercontent.com/GustavoMS0/Install-Gm/main/servidor/install-glpi.sh \
&& sudo GLPI_FQDN="glpi.suaempresa.local" GLPI_PORT="80" \
        DB_LOCAL="S" DB_ADMIN_USER="root" DB_ADMIN_PASS="" \
        DB_NAME="glpi" DB_USER="glpi" DB_PASS="" \
        GLPI_ADMIN_PASS="" DISABLE_DEFAULT_USERS="S" CONFIRM="S" \
        bash install-glpi.sh
```

> Não escreva senhas reais nesta linha: elas ficariam no histórico do terminal (`~/.bash_history`). Deixe as senhas vazias (o script gera senhas fortes e salva em `/root/glpi-install-info.txt`) ou use o modo B.

### Modo D: clonar o repositório inteiro

Útil se você quer adaptar os scripts ou manter uma cópia atualizada com `git pull`.

```bash
sudo apt install -y git
git clone https://github.com/GustavoMS0/Install-Gm.git
cd Install-Gm/servidor
sudo bash install-glpi.sh                       # interativo
# ou: sudo bash install-glpi.sh glpi-install.conf   (automático)
```

---

## Windows: gerar o pacote do Intune

### Opção 1: só com PowerShell (sem instalar nada)

Cole no PowerShell, trocando a URL do servidor na última linha:

```powershell
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$dest = "$env:USERPROFILE\Install-Gm"
$zip  = "$env:TEMP\instalador.zip"; $tmp = "$env:TEMP\instalador"
Remove-Item $dest, $tmp -Recurse -Force -ErrorAction SilentlyContinue
Invoke-WebRequest -UseBasicParsing -OutFile $zip `
  -Uri 'https://github.com/GustavoMS0/Install-Gm/archive/refs/heads/main.zip'
Expand-Archive $zip $tmp -Force
Get-ChildItem $tmp -Directory | Select-Object -First 1 | Move-Item -Destination $dest
Remove-Item $zip, $tmp -Recurse -Force

cd "$dest\intune"
powershell -ExecutionPolicy Bypass -File .\Build-IntunePackage.ps1 -ServerUrl 'http://glpi.suaempresa.local/front/inventory.php'
```

> Também dá para baixar pelo navegador: botão verde **Code › Download ZIP** na página do repositório. Depois é só extrair e rodar a última linha acima dentro da pasta `intune`.

### Opção 2: com git

```powershell
cd $env:USERPROFILE
git clone https://github.com/GustavoMS0/Install-Gm.git
cd .\Install-Gm\intune
powershell -ExecutionPolicy Bypass -File .\Build-IntunePackage.ps1 -ServerUrl 'http://glpi.suaempresa.local/front/inventory.php'
```

Para atualizar depois: `cd $env:USERPROFILE\Install-Gm; git pull`

O pacote fica em `intune\output\`. Siga para [Criar o app no Intune](README.md#passo-2-criar-o-app-no-intune).

---

## Usar uma versão fixa do instalador

Os comandos acima baixam a versão mais recente do instalador, na branch `main`. Para instalar sempre com uma versão testada, troque `main` pela **tag** ou pelo **hash do commit**:

```bash
# Exemplo com uma tag de release (ex.: v1.0.0)
curl -fsSLO https://raw.githubusercontent.com/GustavoMS0/Install-Gm/v1.0.0/servidor/install-glpi.sh
```

> Isso fixa a versão **do instalador**. A versão **do GLPI** é escolhida à parte, com `GLPI_VERSION="11.0.10"` no arquivo de configuração. Sem essa variável, o instalador usa a última versão estável do GLPI.

---

## Problemas comuns

| Erro | Causa / solução |
|---|---|
| `curl: command not found` | Instale com `sudo apt update && sudo apt install -y curl` |
| `curl: (22) ... 404` | Endereço digitado errado (confira maiúsculas: `GustavoMS0/Install-Gm`) ou arquivo renomeado |
| `curl: (6) Could not resolve host` | Servidor sem DNS ou internet. Teste com `ping -c2 github.com` |
| `Arquivo de configuração '...' não encontrado` | Rode o comando na mesma pasta do `glpi-install.conf`, ou informe o caminho completo |
| `/bin/bash^M: bad interpreter` | O arquivo foi editado no Windows. Rode `sed -i 's/\r$//' install-glpi.sh glpi-install.conf` |
| `DB_ADMIN_PASS não pode ser vazia.` | Com banco **remoto**, a senha do admin é obrigatória no arquivo de configuração |
