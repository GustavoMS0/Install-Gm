# GLPI: instalação automatizada do servidor + GLPI Agent via Intune

Scripts para colocar um **servidor GLPI** no ar em poucos minutos e fazer o **inventário automático de todos os computadores Windows** pelo Microsoft Intune.

| Parte | O que faz | Onde roda |
|---|---|---|
| **1. Servidor** | Instala a última versão estável do GLPI com todos os pré-requisitos, já configurado para o primeiro acesso | Servidor Linux (Debian/Ubuntu) |
| **2. Agente** | Instala o GLPI Agent e agenda um inventário a cada 30 minutos em cada computador | Estações Windows, distribuído pelo Intune |

```
 ┌──────────────────────┐        a cada 30 min         ┌──────────────────────────┐
 │  Computadores        │  ─── testa conexão e envia ─▶ │  Servidor GLPI (Linux)   │
 │  Windows (Intune)    │       o inventário            │  Apache + PHP + MariaDB  │
 │  GLPI Agent          │                               │                          │
 └──────────────────────┘                               └──────────────────────────┘
```

> Você pode usar só a parte 1 (o servidor), ou só a parte 2 se já tiver um GLPI funcionando.

> **Início rápido:** no servidor Linux, um único comando instala tudo (o script faz as perguntas):
> ```bash
> curl -fsSLO https://raw.githubusercontent.com/GustavoMS0/Install-Gm/main/servidor/install-glpi.sh && sudo bash install-glpi.sh
> ```
> Para o modo 100% automático, sem perguntas, veja o **[guia de instalação direto do GitHub](INSTALAR-DO-GITHUB.md)**.

---

## Sumário
- [Instalar direto do GitHub (guia separado)](INSTALAR-DO-GITHUB.md)
- [O que você vai precisar](#o-que-você-vai-precisar)
- [Parte 1: instalar o servidor GLPI](#parte-1-instalar-o-servidor-glpi)
- [Atualizar um GLPI que já existe](#atualizar-um-glpi-que-já-existe)
- [Parte 2: distribuir o agente pelo Intune](#parte-2-distribuir-o-agente-pelo-intune)
- [O que preciso alterar para o meu ambiente?](#o-que-preciso-alterar-para-o-meu-ambiente)
- [Solução de problemas](#solução-de-problemas)
- [Perguntas frequentes](#perguntas-frequentes)

---

## O que você vai precisar

**Para o servidor**
- Uma VM ou servidor com **Debian 11, 12 ou 13** ou **Ubuntu 22.04 ou 24.04**, de preferência recém-instalado
- 2 GB de RAM e 2 GB livres em `/var`, no mínimo
- Acesso de **root** (ou `sudo`)
- Acesso à internet (para baixar pacotes e o GLPI)
- Um IP fixo ou um nome DNS para o servidor

**Para o agente**
- Um computador Windows com PowerShell 5.1 ou superior, para gerar o pacote
- Permissão para criar apps no **Microsoft Intune**
- Computadores **Windows 10/11 de 64 bits** registrados no Intune
- Os computadores precisam alcançar o servidor GLPI pela rede, na porta escolhida

---

## Parte 1: instalar o servidor GLPI

### Passo 1: baixar o script no servidor

```bash
curl -fsSLO https://raw.githubusercontent.com/GustavoMS0/Install-Gm/main/servidor/install-glpi.sh
```

**Outras formas:** clonar o repositório inteiro (`git clone https://github.com/GustavoMS0/Install-Gm.git`) ou rodar tudo em uma linha. Todas as opções, inclusive a instalação 100% automática, estão em **[INSTALAR-DO-GITHUB.md](INSTALAR-DO-GITHUB.md)**.

### Passo 2: executar

```bash
sudo bash install-glpi.sh
```

O script faz algumas perguntas. **Na maioria delas basta apertar Enter para aceitar o padrão** (o valor entre colchetes):

```
  Nome DNS ou IP pelo qual o GLPI será acessado [192.168.1.50]:
  Porta HTTP do Apache [80]:
  Idioma padrão do GLPI [pt_BR]:
  Fuso horário (PHP/GLPI) [America/Sao_Paulo]:
  Instalar/usar MariaDB LOCAL neste servidor? [S/n]:
  Usuário ADMINISTRADOR do banco (para criar base/usuário) [root]:
  Senha do 'root' (Enter = autenticação unix_socket do root local):
  Nome da base de dados do GLPI [glpi]:
  Usuário da aplicação no banco [glpi]:
  Senha do usuário 'glpi' (Enter = gerar automaticamente):
  Nova senha do super-admin 'glpi' (Enter = gerar automaticamente):
  Desativar os usuários padrão tech, normal e post-only? [S/n]:
  Nome da matriz / empresa (entidade principal) [Matriz]:
  Quantas filiais a empresa possui? (0 = nenhuma) [0]: 2
  Nome da filial 1 [Filial 1]: Filial São Paulo
  Nome da filial 2 [Filial 2]: Filial Rio de Janeiro
  Criar o catálogo padrão de categorias (TI, RH, Financeiro, Marketing)? [S/n]:
  Criar grupos de atendimento por área e perfis de acesso (cada área vê só os seus chamados)? [S/n]:
  Áreas a criar, separadas por vírgula [TI,RH,Financeiro,Marketing]:
  Outros departamentos que ATENDEM chamados, além dos padrão (ex.: Jurídico, Compras, Facilities). Enter = nenhum: Jurídico,Compras
  Outras equipes/departamentos que abrem chamados, separados por vírgula (Enter = nenhum): Comercial,Produção
  Instalar o plugin Cascater (seleção de categorias em cascata)? [S/n]:
  Instalar o plugin GLPI Inventory (descoberta de rede, SNMP, implantação de software)? [S/n]:
```

> 📄 Antes de responder, veja o que será criado:
> - **[CATEGORIAS-PADRAO.md](CATEGORIAS-PADRAO.md)**: as 81 categorias de atendimento
> - **[PERFIS-E-PERMISSOES.md](PERFIS-E-PERMISSOES.md)**: grupos, perfis e quem vê quais chamados

| Pergunta | O que responder |
|---|---|
| **Nome DNS ou IP** | O endereço que as pessoas e os agentes usarão para acessar o GLPI |
| **Porta HTTP** | `80`, a não ser que outra aplicação já use essa porta |
| **MariaDB local?** | `S` instala o banco no próprio servidor (recomendado). `N` usa um banco que já existe em outro servidor |
| **Usuário/senha admin do banco** | No banco local recém-instalado, use `root` e **deixe a senha em branco**. Em banco remoto, informe um usuário com permissão para criar bases e usuários |
| **Nome da base / usuário / senha** | Os dados que o GLPI usará para se conectar. Deixe a senha em branco para gerar uma senha forte |
| **Senha do super-admin `glpi`** | A senha do seu primeiro login na interface web |
| **Matriz / filiais** | O nome da empresa ou da matriz vira a entidade principal do GLPI, e cada filial vira uma subentidade dela. Com `0` filiais, tudo fica na matriz |
| **Catálogo de categorias** | Cria uma árvore pronta com 81 categorias de atendimento para as áreas escolhidas. Dá para criar só algumas áreas, por exemplo `TI,RH`. 📄 **[Veja todas as categorias que serão criadas](CATEGORIAS-PADRAO.md)** |
| **Grupos e perfis de acesso** | Cria um grupo de atendimento por área e perfis em que **cada área vê só os seus chamados**, os gestores acompanham a equipe e **só o Super-Admin vê tudo**. Os chamados caem sozinhos no grupo da área pela categoria. 📄 **[Veja os perfis e quem vê o quê](PERFIS-E-PERMISSOES.md)** |
| **Outros departamentos que atendem** | Departamentos além dos 4 padrão que também **recebem** chamados (ex.: `Jurídico,Compras,Facilities`). Cada um ganha um grupo de atendimento e 3 categorias básicas ([veja quais](CATEGORIAS-PADRAO.md#outros-departamentos)) e funciona igual ao RH: atendentes e gestores veem só os chamados dele |
| **Outras equipes** | Setores que só **abrem** chamados (ex.: `Comercial,Produção`), para que o gestor de cada um acompanhe os chamados da equipe. Deixe em branco se não houver |
| **Plugin Cascater** | Troca a lista enorme de categorias por menus por nível (área › grupo › categoria). [Saiba mais](https://github.com/GustavoMS0/Cascater) |
| **Plugin GLPI Inventory** | Plugin oficial que complementa o inventário nativo com **descoberta de rede**, **inventário SNMP** (switches, impressoras), **implantação de software** e coleta de informações pelos agentes. O script baixa a versão compatível com o GLPI instalado (1.6.x para GLPI 11, 1.5.x para GLPI 10). [Saiba mais](https://github.com/glpi-project/glpi-inventory-plugin) |

No fim ele mostra um resumo e pede confirmação. A instalação leva de 3 a 10 minutos.

### Passo 3: primeiro acesso

Ao terminar, o script mostra algo assim:

```
  Instalação concluída com sucesso!

  Acesse ..............: http://192.168.1.50
  Usuário .............: glpi
  Senha (gerada) ......: Xk82hQp...
  URL p/ o GLPI Agent .: http://192.168.1.50/front/inventory.php
```

Abra a URL no navegador e entre com o usuário `glpi`. **Todas as senhas ficam salvas em `/root/glpi-install-info.txt`**, que só o root consegue ler:

```bash
sudo cat /root/glpi-install-info.txt
```

> Guarde a **URL p/ o GLPI Agent**. Ela será usada na Parte 2.

### Instalação sem perguntas (opcional)

Para automatizar ou repetir a instalação, preencha um arquivo de configuração:

```bash
cp glpi-install.conf.example glpi-install.conf
nano glpi-install.conf              # descomente e preencha o que quiser
sudo bash install-glpi.sh glpi-install.conf
rm glpi-install.conf                # o arquivo contém senhas
```

Cada variável definida no arquivo deixa de ser perguntada. Se ela estiver vazia (`""`), o script usa o valor padrão ou gera uma senha. As que ficarem comentadas continuam sendo perguntadas normalmente. Veja todas as opções em [`servidor/glpi-install.conf.example`](servidor/glpi-install.conf.example) e exemplos completos em [INSTALAR-DO-GITHUB.md](INSTALAR-DO-GITHUB.md#modo-b-100-automático-com-arquivo-de-configuração).

### O que o script faz, em detalhe

1. **Verifica os pré-requisitos**: sistema operacional, espaço em disco, memória RAM e acesso à internet.
2. **Descobre a última versão estável** do GLPI no GitHub oficial e ajusta os requisitos para ela (GLPI 11: PHP 8.2 ou superior, MariaDB 10.6 ou superior).
3. **Instala o Apache, o PHP e todas as extensões**. Se o PHP da distribuição for antigo demais, adiciona o repositório de PHP do Ondřej Surý.
4. **Prepara o banco**: instala o MariaDB (se for local), cria a base em `utf8mb4`, cria o usuário e carrega os fusos horários.
5. **Instala o GLPI** no layout seguro recomendado pela documentação oficial:

   | Diretório | Conteúdo |
   |---|---|
   | `/var/www/glpi` | Código da aplicação (a web só acessa `/public`) |
   | `/etc/glpi` | Configuração e chave de criptografia |
   | `/var/lib/glpi` | Documentos, anexos, cache e sessões |
   | `/var/log/glpi` | Logs do GLPI |

6. **Instala o banco do GLPI** pela linha de comando, sem precisar do assistente web.
7. **Deixa pronto para uso**:
   - URL base definida
   - Inventário nativo **habilitado**
   - Ações automáticas rodando pelo cron do Linux
   - Senha do `glpi` trocada
   - Usuários padrão desativados
   - `install.php` removido
8. **Monta a estrutura da empresa**: matriz como entidade principal e filiais como subentidades.
9. **Cria o catálogo de categorias** das áreas escolhidas, válido para a matriz e todas as filiais.
10. **Cria os grupos de atendimento e os perfis de acesso**: um grupo por área, perfis de atendente e gestor sem "ver todos", atribuição automática pela categoria e regras que marcam o grupo de quem abriu o chamado ([detalhes](PERFIS-E-PERMISSOES.md)).
11. **Instala e ativa o plugin Cascater** (versão mais recente publicada).
12. **Libera a porta** no firewall (ufw ou firewalld) e testa se o GLPI está respondendo.

### Depois de instalar: liberar o acesso das pessoas

Cada pessoa precisa de um **perfil** (o que pode fazer) e de um **grupo** (quais chamados vê), em **Administração › Usuários**:

| Quem | Perfil | Grupo |
|---|---|---|
| Atendente do RH, Financeiro ou Marketing | Atendente de Área | RH / Financeiro / Marketing |
| Gestor(a) dessas áreas | Gestor de Área | a área |
| Técnico(a) / coordenador(a) de TI | Técnico de TI / Gestor de TI | TI |
| Gestor(a) de uma equipe que só abre chamados | Gestor de Equipe | a equipe (ex.: Comercial) |
| Colaboradores em geral | Self-Service (padrão) | a sua equipe |

Só o perfil **Super-Admin** vê todos os chamados. O passo a passo e os cuidados estão em **[PERFIS-E-PERMISSOES.md](PERFIS-E-PERMISSOES.md)**.

> 🔐 **Usa Active Directory, LDAP ou SSO?** Dá para o GLPI colocar cada pessoa no grupo e no perfil certos sozinho, a partir dos grupos do AD. Veja **[INTEGRACAO-LDAP-SSO.md](INTEGRACAO-LDAP-SSO.md)**.

### Catálogo padrão de categorias

Cada categoria já vem marcada como **incidente** (algo parou de funcionar) ou **requisição** (um pedido). No chamado, o GLPI só mostra as categorias que combinam com o tipo escolhido. Com o Cascater, o usuário navega por **Área › Grupo › Categoria**.

| Área | Grupos |
|---|---|
| **TI** | Hardware · Impressoras · Rede e Internet · Sistemas e Softwares · E-mail e Colaboração · Acessos e Contas · Telefonia · Segurança da Informação |
| **RH** | Folha de Pagamento · Benefícios · Ponto e Jornada · Férias e Afastamentos · Admissão e Desligamento · Documentos e Declarações · Treinamento e Desenvolvimento |
| **Financeiro** | Contas a Pagar · Contas a Receber · Notas Fiscais · Reembolso de Despesas · Adiantamentos · Orçamento e Centro de Custo |
| **Marketing** | Criação de Peças · Site e Redes Sociais · Eventos e Patrocínios · Brindes e Materiais · Comunicação Interna |

📄 **[Ver o catálogo completo, com o tipo de cada categoria](CATEGORIAS-PADRAO.md)**

> As categorias ficam na matriz e valem para todas as filiais. Depois da instalação, é só ajustar em **Configurar › Listas suspensas › Categorias ITIL**: renomear, criar novas, desativar as que não usar ou definir um grupo técnico responsável por área.

### Depois da instalação (recomendado)

- **Faça backup** de `/etc/glpi/glpicrypt.key`. Sem esse arquivo, as senhas guardadas no GLPI (e-mail, LDAP etc.) não podem ser recuperadas.
- **Configure HTTPS** se o GLPI ficar acessível fora da rede interna:
  ```bash
  sudo apt install -y certbot python3-certbot-apache
  sudo certbot --apache -d glpi.suaempresa.com.br
  ```
- Configure backups regulares do banco (`mysqldump`) e de `/var/lib/glpi`.

---

## Atualizar um GLPI que já existe

Rode o mesmo comando da instalação no servidor onde o GLPI já está:

```bash
sudo bash install-glpi.sh
```

Se ele encontrar um GLPI instalado (em `/var/www/glpi`, `/var/www/html/glpi`, `/usr/share/glpi` ou no caminho informado em `GLPI_EXISTING_DIR`), pergunta o que fazer:

```
[AVISO] Encontrado o GLPI 10.0.28 em /var/www/glpi
    [A] Atualizar para o 11.0.10 mantendo TODOS os dados (inventário, chamados, usuários) - recomendado
    [R] Reinstalar do zero - APAGA todos os dados (as pastas antigas são movidas para .bak)
    [C] Cancelar
  Escolha A, R ou C [A]:
```

### O que a opção [A] Atualizar faz

1. **Lê a instalação atual**: versão, pastas de configuração e de dados (inclusive o layout `/etc/glpi` + `/var/lib/glpi`) e o acesso ao banco, direto do `config_db.php`. Não pergunta senha do banco.
2. **Coloca o GLPI em manutenção**: os usuários veem um aviso em vez de usar o sistema pela metade.
3. **Faz backup completo** em `/root/glpi-backup-<data>/`: banco (`.sql.gz`), código, configuração e anexos, além de um `COMO-VOLTAR.txt` com os comandos para desfazer tudo. Se o backup falhar, **nada é alterado**.
4. **Ajusta PHP e Apache** para a versão exigida (GLPI 11: PHP 8.2 ou superior; o DocumentRoot passa para `/public`).
5. **Troca o código** pela versão nova, mantendo configuração, anexos, plugins e marketplace. A versão anterior fica em `<pasta>.old-<data>`.
6. **Atualiza o banco** (`db:update`), passando por todas as versões intermediárias.
7. **Atualiza os plugins**: baixa a versão do **GLPI Inventory** e do **Cascater** compatível com o GLPI novo, retoma a execução dos plugins (o GLPI 11 os suspende depois de atualizar) e reativa.
8. **Tira da manutenção** e mostra a situação de cada plugin.

> **Antes de atualizar a produção:** tire um **snapshot da VM**, se possível, e faça a atualização num horário sem uso. Plugins de terceiros sem versão para o GLPI novo ficam desativados até você instalar uma versão compatível. O resumo final lista esses plugins.

### Inventário e agentes

O inventário (computadores, softwares, componentes) **é mantido**, e a URL do agente continua a mesma (`http://servidor:porta/front/inventory.php`). Os agentes já instalados, inclusive os distribuídos pelo Intune, continuam enviando normalmente.

---

## Parte 2: distribuir o agente pelo Intune

### Passo 1: gerar o pacote (em um computador Windows)

1. Baixe o repositório (**Code › Download ZIP**, ou `git clone`).
2. Abra o **PowerShell** na pasta `intune` e rode o comando abaixo, **trocando a URL pela URL do seu servidor** (a "URL p/ o GLPI Agent" que o instalador mostrou):

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\Build-IntunePackage.ps1 -ServerUrl 'http://glpi.suaempresa.local/front/inventory.php'
```

Parâmetros opcionais:

| Parâmetro | Padrão | Para que serve |
|---|---|---|
| `-ServerUrl` | *(obrigatório)* | Endereço do seu GLPI + `/front/inventory.php` |
| `-IntervalMinutes` | `30` | De quantos em quantos minutos cada computador envia o inventário |
| `-AgentVersion` | última versão | Fixa uma versão do GLPI Agent, ex.: `1.20` |
| `-Tag` | vazio | Etiqueta enviada no inventário (ex.: `Matriz`, `Filial-SP`), útil para regras no GLPI |

O script baixa sozinho o GLPI Agent e a ferramenta da Microsoft que gera o pacote. Ele cria dois arquivos em `intune\output\`:

- `GLPI-Agent-<versão>-Intune.intunewin`: o pacote que vai para o Intune
- `Detect-GLPIAgent.ps1`: o script de detecção, já configurado com a sua URL

### Passo 2: criar o app no Intune

No [Intune](https://intune.microsoft.com): **Aplicativos › Windows › Adicionar › Aplicativo do Windows (Win32)**

**Informações do aplicativo**
- Arquivo do pacote: `GLPI-Agent-<versão>-Intune.intunewin`
- Nome: `GLPI Agent`; Editor: `GLPI Project`

**Programa**

| Campo | Valor |
|---|---|
| Comando de instalação | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-GLPIAgent.ps1` |
| Comando de desinstalação | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Uninstall-GLPIAgent.ps1` |
| Comportamento de instalação | **Sistema** |
| Comportamento de reinicialização | Determinar comportamento com base nos códigos de retorno |

**Requisitos**: arquitetura **64 bits**, sistema mínimo **Windows 10 1809**.

**Regras de detecção**
- Formato: **Usar um script de detecção personalizado**
- Arquivo: `intune\output\Detect-GLPIAgent.ps1`
- Executar script como processo de 64 bits: **Sim**
- Impor verificação de assinatura: **Não**

**Atribuições**: **Obrigatório** para o grupo de dispositivos desejado. Comece por um grupo de teste.

### O que acontece em cada computador

1. O GLPI Agent é instalado (ou atualizado, se a versão for antiga) e já apontado para o seu servidor.
2. É criada a tarefa agendada **`GLPI_Inventario_Forcado`**, que roda como SYSTEM:
   - a cada 30 minutos (ou o intervalo que você escolheu)
   - 5 minutos depois de o computador ligar
   - com um pequeno atraso aleatório, para os computadores não chegarem ao servidor todos ao mesmo tempo
3. A cada execução, a tarefa **testa se o servidor GLPI responde** e só então envia o inventário.
4. O computador aparece no GLPI em **Ativos › Computadores**.

Logs em cada computador: `C:\ProgramData\GLPI-Agent-Intune\`

| Arquivo | Conteúdo |
|---|---|
| `install.log` | Instalação feita pelo Intune |
| `msiexec.log` | Log detalhado do instalador MSI |
| `inventory.log` | Cada execução da tarefa (conexão OK/falha, resultado) |

### Mudou o servidor ou quer atualizar o agente?

Rode o `Build-IntunePackage.ps1` de novo com a nova URL ou versão. Depois, no app do Intune, **substitua o arquivo `.intunewin` e o script de detecção**. A detecção passa a falhar nos computadores antigos e o Intune reaplica o pacote sozinho.

### Testar em um computador antes de publicar

Depois de rodar o `Build-IntunePackage.ps1`, abra o PowerShell **como administrador**:

```powershell
cd .\intune\source
.\Install-GLPIAgent.ps1
& ..\output\Detect-GLPIAgent.ps1; "Código: $LASTEXITCODE"     # esperado: 0
Get-Content C:\ProgramData\GLPI-Agent-Intune\inventory.log -Tail 20
```

### Sem Intune? (GPO, SCCM, manual)

O `Install-GLPIAgent.ps1` funciona em qualquer ferramenta que execute scripts como SYSTEM. Coloque o MSI na mesma pasta e informe a URL:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\Install-GLPIAgent.ps1 -ServerUrl "http://glpi.suaempresa.local/front/inventory.php"
```

---

## O que preciso alterar para o meu ambiente?

**Nenhum arquivo precisa ser editado à mão.** Os valores do seu ambiente entram assim:

| Valor | Onde é informado |
|---|---|
| IP/nome, porta, idioma e fuso do servidor | Perguntas do `install-glpi.sh` (ou `glpi-install.conf`) |
| Credenciais de admin do banco | Perguntas do `install-glpi.sh` (ou `glpi-install.conf`) |
| Nome da base, usuário e senha do GLPI | Perguntas do `install-glpi.sh` (ou `glpi-install.conf`) |
| Senha do super-admin `glpi` | Perguntas do `install-glpi.sh` (ou `glpi-install.conf`) |
| URL do servidor para os agentes | Parâmetro `-ServerUrl` do `Build-IntunePackage.ps1` |
| Intervalo do inventário / TAG | Parâmetros `-IntervalMinutes` / `-Tag` do `Build-IntunePackage.ps1` |

> Os scripts do Intune vêm com a URL de exemplo `http://SEU-SERVIDOR-GLPI/...`. Se o pacote for publicado sem configurar a URL, a instalação para com uma mensagem de erro clara, em vez de instalar um agente apontando para lugar nenhum.

---

## Solução de problemas

<details>
<summary><b><code>/bin/bash^M: bad interpreter</code> ou <code>$'\r': command not found</code></b></summary>

O arquivo foi salvo com quebras de linha do Windows. Corrija no servidor:
```bash
sed -i 's/\r$//' install-glpi.sh
```
</details>

<details>
<summary><b>"Não foi possível conectar ... com o usuário 'root'"</b></summary>

- **Banco local**: rode o script com `sudo` e deixe a senha do root **em branco**.
- **Banco remoto**: confirme que o usuário admin pode se conectar a partir do IP do servidor GLPI e que a porta 3306 está liberada no firewall do banco.
</details>

<details>
<summary><b>"A porta 80 já está em uso por outro serviço"</b></summary>

Outra aplicação (nginx, outro Apache) já usa a porta. Escolha outra, por exemplo `8080`, e use-a também na URL do agente: `http://servidor:8080/front/inventory.php`.
</details>

<details>
<summary><b>O GLPI abre, mas mostra erro ou tela em branco</b></summary>

Veja os logs:
```bash
sudo tail -50 /var/log/apache2/glpi_error.log
sudo ls -la /var/log/glpi/ && sudo tail -50 /var/log/glpi/php-errors.log
```
O log completo da instalação fica em `/var/log/glpi-install-<data>.log`.
</details>

<details>
<summary><b>O computador não aparece no GLPI</b></summary>

1. Veja `C:\ProgramData\GLPI-Agent-Intune\inventory.log` no computador.
   - `servidor ... inacessivel`: é problema de rede ou firewall entre o computador e o servidor.
2. No navegador do computador, abra a URL do agente. Ela deve responder, mesmo que com uma mensagem de erro do GLPI.
3. No GLPI, confira se o inventário está ativo em **Administração › Inventário › Habilitar inventário**.
4. Force manualmente e veja a saída:
   ```powershell
   & "C:\Program Files\GLPI-Agent\glpi-agent.bat" --force
   ```
</details>

<details>
<summary><b>O Intune mostra "Falha" na instalação</b></summary>

No computador, veja `C:\ProgramData\GLPI-Agent-Intune\install.log`. O erro mais comum é `ServerUrl nao configurada`: o pacote foi gerado sem `-ServerUrl`. Gere de novo seguindo o [Passo 1](#passo-1-gerar-o-pacote-em-um-computador-windows).
</details>

---

## Perguntas frequentes

**Qual versão do GLPI é instalada?**
A última versão **estável** publicada em [github.com/glpi-project/glpi/releases](https://github.com/glpi-project/glpi/releases). Versões beta e RC são ignoradas. Para fixar uma versão, use `GLPI_VERSION="11.0.10"` no arquivo de configuração.

**Posso rodar o script num servidor que já tem GLPI?**
Pode. Ele detecta a instalação e oferece **atualizar mantendo todos os dados**. Veja [Atualizar um GLPI que já existe](#atualizar-um-glpi-que-já-existe).

**Funciona com CentOS, Rocky ou RHEL?**
Ainda não. Por enquanto só Debian e Ubuntu (e derivados).

**Os scripts enviam dados para algum lugar?**
Não. O script do servidor só acessa os repositórios de pacotes e o GitHub, para baixar o GLPI. Os agentes só se comunicam com o **seu** servidor GLPI.

**Por que 30 minutos?**
O agente já envia inventário por conta própria, mas a tarefa agendada garante que os dados fiquem atualizados e que computadores recém-ligados apareçam logo. Para ambientes grandes (milhares de máquinas), considere `-IntervalMinutes 120` ou mais.

---

## Estrutura do repositório

```
├── README.md                        Este guia
├── INSTALAR-DO-GITHUB.md            Baixar e rodar direto do GitHub / modo automático
├── CATEGORIAS-PADRAO.md             Catálogo de categorias criado pelo instalador
├── PERFIS-E-PERMISSOES.md           Grupos, perfis e quem vê quais chamados
├── INTEGRACAO-LDAP-SSO.md           Grupos e perfis automáticos via AD/LDAP e SSO
├── LICENSE                          Licença MIT
├── servidor/
│   ├── install-glpi.sh              Instalador do servidor GLPI
│   └── glpi-install.conf.example    Modelo de configuração (instalação sem perguntas)
└── intune/
    ├── Build-IntunePackage.ps1      Gera o pacote .intunewin (rode este)
    ├── Install-GLPIAgent.ps1        Instala o agente e cria a tarefa agendada
    ├── Detect-GLPIAgent.ps1         Regra de detecção do Intune
    └── Uninstall-GLPIAgent.ps1      Remove o agente e a tarefa
```

## Contribuindo

Sugestões e correções são bem-vindas. Abra uma *issue* ou envie um *pull request*.

## Créditos

- [GLPI Project](https://glpi-project.org/) e [GLPI Agent](https://github.com/glpi-project/glpi-agent), da Teclib'
- [Microsoft Win32 Content Prep Tool](https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool)

Este projeto não é oficial nem tem ligação com a Teclib' ou com a Microsoft.

## Licença

Distribuído sob a licença **MIT**. Veja o arquivo [LICENSE](LICENSE).

Você pode usar, modificar e redistribuir livremente, inclusive em ambientes comerciais, desde que mantenha o aviso de copyright. Os scripts são fornecidos **"como estão", sem garantia**: teste em um ambiente de homologação antes de usar em produção.

> O GLPI e o GLPI Agent, que estes scripts baixam e instalam, são softwares separados, distribuídos sob a licença GPL pelos seus autores.
