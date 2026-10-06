#!/usr/bin/env bash
# =============================================================================
#  install-glpi.sh - Instalação automatizada da última versão estável do GLPI
# -----------------------------------------------------------------------------
#  Sistemas suportados : Debian 11/12/13, Ubuntu 22.04/24.04 (e derivados)
#  Pilha instalada     : Apache 2 + PHP (mod_php) ou Nginx + PHP-FPM, e MariaDB (local ou remoto)
#  Uso                 : sudo bash install-glpi.sh
#
#  O script:
#    1. Verifica os pré-requisitos (root, SO, internet, disco, memória)
#    2. Descobre a última versão estável do GLPI no GitHub
#    3. Pergunta as configurações (banco, credenciais, URL, porta...)
#    4. Instala/ajusta Apache, PHP e extensões, MariaDB (opcional)
#    5. Cria banco e usuário, carrega timezones
#    6. Baixa e instala o GLPI em layout seguro (/etc/glpi, /var/lib/glpi,
#       /var/log/glpi) com DocumentRoot em /public
#    7. Executa a instalação do banco via console (sem assistente web)
#    8. Parametriza: idioma, URL, inventário nativo habilitado, cron em modo
#       CLI, senha do admin "glpi", desativa usuários padrão
#    9. Cria a estrutura da empresa (matriz + filiais como entidades)
#   10. Cria o catálogo padrão de categorias (TI, RH, Financeiro, Marketing, Facilities)
#   11. Cria grupos de atendimento por área, perfis de acesso e regras
#       (cada área vê só os seus chamados; só o Super-Admin vê todos)
#   12. Configura 4 prioridades (matriz ITIL), calendário, SLAs e OLAs
#   13. Instala e ativa os plugins Cascater, GLPI Inventory, Asset Terms e GLPI Chatbot
#   14. Cadastra modelos de atendimento, status de ciclo de vida, tipos de computador
#       e dicionários de inventário (ignora KBs do Windows)
#
#  Se encontrar um GLPI já instalado, oferece ATUALIZAR mantendo todos os dados
#  (backup completo, código novo, db:update e plugins compatíveis) ou reinstalar.
#
#  Modo não interativo: qualquer variável abaixo pode ser pré-definida em um
#  arquivo de configuração (veja glpi-install.conf.example) ou no ambiente;
#  a pergunta correspondente será pulada. Ex.:
#    sudo bash install-glpi.sh glpi-install.conf
#    sudo GLPI_PORT=8080 DB_NAME=glpi DB_PASS='xxx' bash install-glpi.sh
#  Variáveis: GLPI_VERSION WEB_SERVER GLPI_FQDN GLPI_PORT GLPI_LANG GLPI_TZ DB_LOCAL
#             DB_HOST DB_PORT DB_ADMIN_USER DB_ADMIN_PASS DB_NAME DB_USER
#             DB_USER_HOST DB_PASS GLPI_ADMIN_PASS DISABLE_DEFAULT_USERS
#             GLPI_ROOT_ENTITY GLPI_BRANCHES CREATE_CATEGORIES CATEGORY_AREAS
#             EXTRA_AREAS CREATE_ACCESS TEAM_GROUPS INSTALL_CASCATER CASCATER_REPO
#             INSTALL_GLPIINVENTORY INSTALL_MODE GLPI_EXISTING_DIR GLPI_BACKUP_DIR
#             SIMPLIFY_PRIORITIES LINK_URGENCY_IMPACT CREATE_SLA BUSINESS_HOURS
#             BUSINESS_SATURDAY SATURDAY_HOURS ADD_HOLIDAYS INSTALL_ASSETTERMS
#             ASSETTERMS_REPO INSTALL_CHATBOT CHATBOT_REPO
#             UPDATE_APPLY_TEMPLATES UPDATE_APPLY_INVENTORY UPDATE_APPLY_ITIL
#             OVERWRITE CONFIRM
# =============================================================================
set -Eeuo pipefail

readonly SCRIPT_VERSION="1.0.0"
readonly LOG_FILE="/var/log/glpi-install-$(date +%Y%m%d-%H%M%S).log"
readonly INFO_FILE="/root/glpi-install-info.txt"
GLPI_DIR="/var/www/glpi"          # não é readonly: no modo atualização aponta para o GLPI encontrado
readonly GLPI_CONFIG_DIR="/etc/glpi"
readonly GLPI_VAR_DIR="/var/lib/glpi"
readonly GLPI_LOG_DIR="/var/log/glpi"
readonly MIN_DISK_MB=2048
export DEBIAN_FRONTEND=noninteractive

if [[ -t 1 ]]; then
  C_R=$'\e[31m'; C_G=$'\e[32m'; C_Y=$'\e[33m'; C_B=$'\e[36m'; C_W=$'\e[1m'; C_N=$'\e[0m'
else
  C_R=""; C_G=""; C_Y=""; C_B=""; C_W=""; C_N=""
fi

# -----------------------------------------------------------------------------
# Funções utilitárias
# -----------------------------------------------------------------------------
log()   { echo "${C_G}[ OK ]${C_N} $*"; }
info()  { echo "${C_B}[ .. ]${C_N} $*"; }
warn()  { echo "${C_Y}[AVISO]${C_N} $*"; }
die()   { echo "${C_R}[ERRO]${C_N} $*" >&2; exit 1; }
title() { echo; echo "${C_W}==== $* ====${C_N}"; }

TMP_FILES=()
cleanup() { local f; for f in "${TMP_FILES[@]}"; do rm -rf -- "$f"; done; }
trap cleanup EXIT
trap 'die "Falha na linha $LINENO: $BASH_COMMAND (log: $LOG_FILE)"' ERR

# Regra para todas as perguntas: se a variável já estiver DEFINIDA (arquivo de
# configuração ou ambiente), a pergunta é pulada. Definida porém vazia = padrão.

# ask VAR "Pergunta" "padrão"
ask() {
  local __var=$1 __prompt=$2 __def=${3-} __ans
  if [[ -n ${!__var+x} ]]; then
    [[ -z ${!__var} ]] && printf -v "$__var" '%s' "$__def"
    return 0
  fi
  if [[ -n $__def ]]; then
    read -rp "  $__prompt [$__def]: " __ans </dev/tty
  else
    read -rp "  $__prompt: " __ans </dev/tty
  fi
  printf -v "$__var" '%s' "${__ans:-$__def}"
}

# ask_secret VAR "Pergunta" permitir_vazio(0/1) confirmar(0/1)
ask_secret() {
  local __var=$1 __prompt=$2 __empty=${3:-0} __confirm=${4:-0} __a __b
  if [[ -n ${!__var+x} ]]; then
    [[ -n ${!__var} || $__empty == 1 ]] || die "$__var não pode ser vazia."
    return 0
  fi
  while true; do
    read -rsp "  $__prompt: " __a </dev/tty; echo
    if [[ -z $__a && $__empty != 1 ]]; then warn "O valor não pode ser vazio."; continue; fi
    if [[ -n $__a && $__confirm == 1 ]]; then
      read -rsp "  Confirme: " __b </dev/tty; echo
      [[ $__a == "$__b" ]] || { warn "Os valores não conferem."; continue; }
    fi
    break
  done
  printf -v "$__var" '%s' "$__a"
}

# ask_yn VAR "Pergunta" S|N  -> VAR recebe S ou N
ask_yn() {
  local __var=$1 __prompt=$2 __def=${3:-S} __ans __hint="S/n"
  [[ $__def == N ]] && __hint="s/N"
  if [[ -n ${!__var+x} ]]; then
    __ans=${!__var:-$__def}
  else
    read -rp "  $__prompt [$__hint]: " __ans </dev/tty
    __ans=${__ans:-$__def}
  fi
  case ${__ans,,} in s|sim|y|yes|1) printf -v "$__var" S ;; *) printf -v "$__var" N ;; esac
}

# version_ge A B -> verdadeiro se A >= B
version_ge() { printf '%s\n%s\n' "$2" "$1" | sort -V -C; }

gen_pass() { head -c 96 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | cut -c1-24; }

# Escapa texto para uso dentro de '...' no SQL
sql_escape() { local s=${1//\\/\\\\}; s=${s//\'/\'\'}; printf '%s' "$s"; }

# Escapa texto para uso dentro de "..." em arquivo de opções do MySQL
cnf_escape() { local s=${1//\\/\\\\}; s=${s//\"/\\\"}; printf '%s' "$s"; }

pkg_exists() { LC_ALL=C apt-cache policy "$1" 2>/dev/null | grep -E '^\s*Candidate:' | grep -qv '(none)'; }

valid_ident() { [[ $1 =~ ^[A-Za-z0-9_]{1,64}$ ]]; }

# Cria arquivo de credenciais temporário (evita senha na linha de comando)
make_mycnf() { # make_mycnf arquivo host porta usuario senha
  local f=$1
  : >"$f"; chmod 600 "$f"
  {
    echo "[client]"
    echo "host=$2"
    echo "port=$3"
    echo "user=$4"
    [[ -n $5 ]] && echo "password=\"$(cnf_escape "$5")\""
    echo "default-character-set=utf8mb4"
  } >>"$f"
}

trim() { local s=$1; s=${s#"${s%%[![:space:]]*}"}; s=${s%"${s##*[![:space:]]}"}; printf '%s' "$s"; }

# Catálogo padrão de categorias: "Área > Grupo > Categoria | Tipo"
# Tipo: I = incidente, R = requisição, A = ambos. Grupos herdam os tipos dos filhos.
category_catalog() {
  cat <<'CATALOG'
TI > Hardware > Computador ou notebook não liga | I
TI > Hardware > Lentidão no computador | I
TI > Hardware > Periféricos (mouse, teclado, monitor) | A
TI > Hardware > Manutenção de notebook ou desktop | I
TI > Hardware > Mudança de posto ou equipamento | R
TI > Hardware > Solicitação de equipamento | R
TI > Impressoras > Impressora não imprime | I
TI > Impressoras > Atolamento de papel | I
TI > Impressoras > Troca de toner ou cartucho | R
TI > Impressoras > Instalação de impressora | R
TI > Rede e Internet > Sem acesso à internet | I
TI > Rede e Internet > Wi-Fi | A
TI > Rede e Internet > VPN | A
TI > Rede e Internet > Novo ponto de rede | R
TI > Servidores e Nuvem > Falha em servidor ou VM | I
TI > Servidores e Nuvem > Backup e restauração | A
TI > Servidores e Nuvem > Armazenamento e disco | A
TI > Sistemas e Softwares > Erro em sistema | I
TI > Sistemas e Softwares > ERP e Gestão | A
TI > Sistemas e Softwares > Relatórios e BI | R
TI > Sistemas e Softwares > Instalação de software | R
TI > Sistemas e Softwares > Atualização de software | R
TI > Sistemas e Softwares > Licenças | R
TI > E-mail e Colaboração > Problema no e-mail | I
TI > E-mail e Colaboração > Nova caixa ou lista de e-mail | R
TI > E-mail e Colaboração > Teams e reuniões online | A
TI > Acessos e Contas > Criação de usuário | R
TI > Acessos e Contas > Redefinição de senha | R
TI > Acessos e Contas > Conta bloqueada | I
TI > Acessos e Contas > Permissão em pastas ou sistemas | R
TI > Acessos e Contas > Desativação de usuário (desligamento) | R
TI > Telefonia > Ramal ou telefone com defeito | I
TI > Telefonia > Linha ou celular corporativo | R
TI > Segurança da Informação > Suspeita de vírus ou phishing | I
TI > Segurança da Informação > Incidente de segurança | I
TI > Segurança da Informação > Liberação de site ou firewall | R
RH > Folha de Pagamento > Dúvida no holerite | R
RH > Folha de Pagamento > Divergência no pagamento | I
RH > Benefícios > Vale-transporte | R
RH > Benefícios > Vale-refeição ou alimentação | R
RH > Benefícios > Plano de saúde ou odontológico | R
RH > Ponto e Jornada > Ajuste de ponto | R
RH > Ponto e Jornada > Banco de horas | R
RH > Férias e Afastamentos > Solicitação de férias | R
RH > Férias e Afastamentos > Atestados e afastamentos | R
RH > Admissão e Desligamento > Admissão de colaborador | R
RH > Admissão e Desligamento > Desligamento de colaborador | R
RH > Documentos e Declarações | R
RH > Treinamento e Desenvolvimento | R
Financeiro > Contas a Pagar > Pagamento a fornecedor | R
Financeiro > Contas a Pagar > Pagamento em atraso | I
Financeiro > Contas a Receber > Emissão de boleto | R
Financeiro > Contas a Receber > Baixa de pagamento | R
Financeiro > Notas Fiscais > Emissão de nota fiscal | R
Financeiro > Notas Fiscais > Erro em nota fiscal | I
Financeiro > Reembolso de Despesas | R
Financeiro > Adiantamentos | R
Financeiro > Orçamento e Centro de Custo | R
Marketing > Criação de Peças > Arte para redes sociais | R
Marketing > Criação de Peças > Material impresso | R
Marketing > Criação de Peças > Apresentação institucional | R
Marketing > Site e Redes Sociais > Atualização do site | R
Marketing > Site e Redes Sociais > Problema no site | I
Marketing > Site e Redes Sociais > Publicação em redes sociais | R
Marketing > Eventos e Patrocínios | R
Marketing > Brindes e Materiais | R
Marketing > Comunicação Interna | R
Facilities > Manutenção Predial > Ar-condicionado | A
Facilities > Manutenção Predial > Elétrica e iluminação | A
Facilities > Manutenção Predial > Hidráulica | I
Facilities > Mobiliário e Espaço > Reparo em mobiliário | I
Facilities > Mobiliário e Espaço > Mudança de layout | R
Facilities > Acesso e Chaves > Cópia de chave ou crachá | R
CATALOG
}
readonly CATEGORY_AREAS_AVAILABLE="TI,RH,Financeiro,Marketing,Facilities"

# Cria as categorias das áreas informadas (lista separada por vírgula).
# Categorias ficam na entidade raiz e recursivas: valem para todas as filiais.
create_categories() {
  local areas=",$1," line path flag prefix parent id i inc req itil count=0
  local -A FLAGS=() IDS=()
  local -a lines=() parts=()

  while IFS= read -r line; do
    [[ -z $line ]] && continue
    path=$(trim "${line%|*}")
    local area; area=$(trim "${path%%>*}")
    [[ ${areas,,} == *",${area,,},"* ]] || continue
    lines+=("$line")
  done < <(category_catalog)

  # Departamentos extras (fora do catálogo padrão): 3 categorias básicas cada
  local known extra
  local -a selected=()
  known=",$(category_catalog | sed -E 's/ >.*//' | sort -u | tr '\n' ',')"
  IFS=',' read -ra selected <<<"$1"
  for extra in "${selected[@]}"; do
    [[ -z $extra || ${known,,} == *",${extra,,},"* ]] && continue
    lines+=("$extra > Dúvidas e orientações | R"
            "$extra > Solicitações | R"
            "$extra > Problemas e reclamações | I")
  done

  # 1ª passada: tipos (I/R) de cada grupo = união dos tipos dos filhos
  for line in "${lines[@]}"; do
    path=$(trim "${line%|*}"); flag=$(trim "${line##*|}")
    IFS='>' read -ra parts <<<"$path"
    prefix=""
    for i in "${!parts[@]}"; do
      prefix="${prefix:+$prefix > }$(trim "${parts[$i]}")"
      FLAGS[$prefix]+="$flag"
    done
  done

  # 2ª passada: cria na ordem do catálogo
  for line in "${lines[@]}"; do
    path=$(trim "${line%|*}")
    IFS='>' read -ra parts <<<"$path"
    prefix=""; parent=0
    for i in "${!parts[@]}"; do
      local name; name=$(trim "${parts[$i]}")
      prefix="${prefix:+$prefix > }$name"
      if [[ -z ${IDS[$prefix]+x} ]]; then
        inc=0; req=0
        [[ ${FLAGS[$prefix]} == *[IA]* ]] && inc=1
        [[ ${FLAGS[$prefix]} == *[RA]* ]] && req=1
        itil=0; [[ $prefix == TI || $prefix == "TI > "* ]] && itil=1
        id=$(db_glpi -N -e "INSERT INTO glpi_itilcategories
            (entities_id, is_recursive, itilcategories_id, name, completename, level,
             is_helpdeskvisible, is_incident, is_request, is_problem, is_change, date_creation, date_mod)
          VALUES (0, 1, $parent, '$(sql_escape "$name")', '$(sql_escape "$prefix")', $((i + 1)),
             1, $inc, $req, $itil, $itil, NOW(), NOW());
          SELECT LAST_INSERT_ID();")
        IDS[$prefix]=$id
        count=$((count + 1))
      fi
      parent=${IDS[$prefix]}
    done
  done
  echo "$count"
}

# Baixa (Release mais recente ou branch principal) e instala o plugin Cascater
WORK_TMP=""
work_tmp() { # diretório temporário removido no fim do script
  [[ -n $WORK_TMP ]] || { WORK_TMP=$(mktemp -d); TMP_FILES+=("$WORK_TMP"); }
  mktemp -d -p "$WORK_TMP"
}

copy_plugin() { # copy_plugin origem chave  -> plugins/<chave>, código pertencente ao root
  rm -rf "${GLPI_DIR:?}/plugins/$2"
  cp -r "$1" "$GLPI_DIR/plugins/$2"
  chown -R root:root "$GLPI_DIR/plugins/$2"
  chmod -R u=rwX,go=rX "$GLPI_DIR/plugins/$2"
}

readonly GH_UA="User-Agent: Install-GLPI/1.0"

# Baixa o Cascater (Release mais recente ou branch principal). Imprime a versão.
fetch_cascater() {
  local repo=${CASCATER_REPO:-GustavoMS0/Cascater} tmp url downloaded=0
  tmp=$(work_tmp)
  url=$(curl -fsSL -H "$GH_UA" "https://api.github.com/repos/$repo/releases/latest" 2>/dev/null \
        | jq -r '[.assets[]? | select(.name | test("^cascater-.*\\.zip$"))][0].browser_download_url // empty' 2>/dev/null || true)
  if [[ -n $url ]]; then
    if curl -fsSL -o "$tmp/cascater.zip" "$url" 2>/dev/null && unzip -q "$tmp/cascater.zip" -d "$tmp" 2>/dev/null; then
      downloaded=1
    fi
  fi
  if (( downloaded == 0 )); then
    curl -fsSL -H "$GH_UA" "https://codeload.github.com/$repo/tar.gz/refs/heads/main" | tar -xz -C "$tmp" --strip-components=1 || return 1
  fi
  [[ -f $tmp/Cascater/setup.php ]] || return 1
  copy_plugin "$tmp/Cascater" Cascater
  grep -oP "PLUGIN_CASCATER_VERSION', '\K[^']+" "$GLPI_DIR/plugins/Cascater/setup.php" 2>/dev/null || echo "?"
}

# Baixa o plugin oficial GLPI Inventory na linha compatível com o GLPI:
# 1.6.x -> GLPI 11 | 1.5.x -> GLPI 10. Imprime a versão.
fetch_glpiinventory() { # fetch_glpiinventory versão_maior_do_glpi
  local prefix tag tmp downloaded=0
  case $1 in
    11) prefix="1.6." ;;
    10) prefix="1.5." ;;
    *)  return 1 ;;
  esac
  tag=$(curl -fsSL -H "$GH_UA" "https://api.github.com/repos/glpi-project/glpi-inventory-plugin/releases?per_page=60" 2>/dev/null \
        | jq -r --arg p "$prefix" '[.[] | select((.draft | not) and (.prerelease | not) and (.tag_name | startswith($p)))][0].tag_name // empty' 2>/dev/null || true)
  [[ -n $tag ]] || return 1
  tmp=$(work_tmp)
  if curl -fsSL -o "$tmp/glpiinventory.tar.bz2" \
    "https://github.com/glpi-project/glpi-inventory-plugin/releases/download/$tag/glpi-glpiinventory-$tag.tar.bz2" 2>/dev/null \
    && tar -xjf "$tmp/glpiinventory.tar.bz2" -C "$tmp" 2>/dev/null; then
    downloaded=1
  fi
  if (( downloaded == 0 )); then
    mkdir -p "$tmp/glpiinventory"
    curl -fsSL -H "$GH_UA" "https://codeload.github.com/glpi-project/glpi-inventory-plugin/tar.gz/refs/tags/$tag" \
      | tar -xz -C "$tmp/glpiinventory" --strip-components=1 || return 1
  fi
  [[ -f $tmp/glpiinventory/setup.php ]] || return 1
  copy_plugin "$tmp/glpiinventory" glpiinventory
  echo "$tag"
}

# Baixa o Asset Terms (termos de responsabilidade; Release mais recente ou branch principal). Imprime a versão.
fetch_assetterms() {
  local repo=${ASSETTERMS_REPO:-GustavoMS0/GLPI-AssetTerms} tmp url downloaded=0
  tmp=$(work_tmp)
  url=$(curl -fsSL -H "$GH_UA" "https://api.github.com/repos/$repo/releases/latest" 2>/dev/null \
        | jq -r '[.assets[]? | select(.name | test("^assetterms-.*\\.zip$"))][0].browser_download_url // empty' 2>/dev/null || true)
  if [[ -n $url ]]; then
    if curl -fsSL -o "$tmp/assetterms.zip" "$url" 2>/dev/null && unzip -q "$tmp/assetterms.zip" -d "$tmp" 2>/dev/null; then
      downloaded=1
    fi
  fi
  if (( downloaded == 0 )); then
    curl -fsSL -H "$GH_UA" "https://codeload.github.com/$repo/tar.gz/refs/heads/main" | tar -xz -C "$tmp" --strip-components=1 || return 1
  fi
  [[ -f $tmp/assetterms/setup.php ]] || return 1
  copy_plugin "$tmp/assetterms" assetterms
  grep -oP "PLUGIN_ASSETTERMS_VERSION', '\K[^']+" "$GLPI_DIR/plugins/assetterms/setup.php" 2>/dev/null || echo "?"
}

# Baixa o GLPI Chatbot (assistente guiado de chamados; Release mais recente ou branch principal). Imprime a versão.
fetch_chatbot() {
  local repo=${CHATBOT_REPO:-GustavoMS0/GLPI-Chatbot} tmp url downloaded=0
  # Cópia local (ex.: versão em desenvolvimento): CHATBOT_SRC=/caminho/para/glpichatbot
  if [[ -n ${CHATBOT_SRC:-} && -f ${CHATBOT_SRC%/}/setup.php ]]; then
    copy_plugin "${CHATBOT_SRC%/}" glpichatbot
    grep -oP "PLUGIN_GLPICHATBOT_VERSION', '\K[^']+" "$GLPI_DIR/plugins/glpichatbot/setup.php" 2>/dev/null || echo "?"
    return 0
  fi
  tmp=$(work_tmp)
  url=$(curl -fsSL -H "$GH_UA" "https://api.github.com/repos/$repo/releases/latest" 2>/dev/null \
        | jq -r '[.assets[]? | select(.name | test("^glpichatbot-.*\\.zip$"))][0].browser_download_url // empty' 2>/dev/null || true)
  if [[ -n $url ]]; then
    if curl -fsSL -o "$tmp/glpichatbot.zip" "$url" 2>/dev/null && unzip -q "$tmp/glpichatbot.zip" -d "$tmp" 2>/dev/null; then
      downloaded=1
    fi
  fi
  if (( downloaded == 0 )); then
    curl -fsSL -H "$GH_UA" "https://codeload.github.com/$repo/tar.gz/refs/heads/main" | tar -xz -C "$tmp" --strip-components=1 || return 1
  fi
  [[ -f $tmp/glpichatbot/setup.php ]] || return 1
  copy_plugin "$tmp/glpichatbot" glpichatbot
  grep -oP "PLUGIN_GLPICHATBOT_VERSION', '\K[^']+" "$GLPI_DIR/plugins/glpichatbot/setup.php" 2>/dev/null || echo "?"
}

# Remove o plugin "termoresponsabilidade", nome antigo do Asset Terms. Os termos já
# gerados ficam na aba Documentos dos computadores e continuam aparecendo no Asset Terms.
remove_old_term_plugin() {
  [[ -d $GLPI_DIR/plugins/termoresponsabilidade ]] || return 0
  glpi_console plugin:deactivate --no-interaction termoresponsabilidade >/dev/null 2>&1 || true
  glpi_console plugin:uninstall --username="${PLUGIN_ADMIN:-glpi}" --no-interaction termoresponsabilidade >/dev/null 2>&1 || true
  rm -rf "${GLPI_DIR:?}/plugins/termoresponsabilidade"
  db_glpi -e "DELETE FROM glpi_plugins WHERE directory = 'termoresponsabilidade'" 2>/dev/null || true
  log "Plugin antigo termoresponsabilidade removido (substituído pelo Asset Terms)"
}

# Instala (ou atualiza) e ativa um plugin já copiado para plugins/<chave>.
# O GLPI retorna erro quando o plugin já está instalado/ativo, então o resultado
# é conferido pelo estado gravado no banco (1 = ativado).
plugin_enable() {
  local state
  glpi_console plugin:install --username="${PLUGIN_ADMIN:-glpi}" --no-interaction "$1" >/dev/null 2>&1 || true
  glpi_console plugin:activate --no-interaction "$1" >/dev/null 2>&1 || true
  state=$(db_glpi -N -e "SELECT state FROM glpi_plugins WHERE directory = '$(sql_escape "$1")'" 2>/dev/null || true)
  [[ $state == 1 ]]
}

# --- Prioridades, SLA e OLA (ITIL) --------------------------------------------
# Só 4 níveis: Baixa(2) Média(3) Alta(4) Muito alta(5). Máscara = soma de (1 << nível) = 60.
# Matriz ITIL priority_matrix[urgência][impacto]; os níveis 1 (desativados) contam como Baixa.
readonly PRIORITY_MASK=60
readonly PRIORITY_MATRIX='{"1":{"1":2,"2":2,"3":2,"4":3,"5":4},"2":{"1":2,"2":2,"3":2,"4":3,"5":4},"3":{"1":2,"2":2,"3":3,"4":4,"5":4},"4":{"1":3,"2":3,"3":4,"4":4,"5":5},"5":{"1":4,"2":4,"3":4,"4":5,"5":5}}'

configure_priorities() {
  db_glpi -e "INSERT INTO glpi_configs (context, name, value) VALUES
      ('core', 'urgency_mask', '$PRIORITY_MASK'),
      ('core', 'impact_mask', '$PRIORITY_MASK'),
      ('core', 'priority_matrix', '$PRIORITY_MATRIX')
    ON DUPLICATE KEY UPDATE value = VALUES(value);"
}

# Metas por prioridade. Tempo em horário de atendimento: Nm = minutos, Nh = horas, Nd = dias úteis.
# prioridade | nome | SLA 1º atendimento | SLA solução | OLA 1º atendimento | OLA solução
sla_catalog() {
  cat <<'SLAS'
5|Muito alta|15m|4h|10m|3h
4|Alta|30m|8h|20m|6h
3|Média|2h|2d|1h|1d
2|Baixa|4h|5d|3h|4d
SLAS
}

# Feriados nacionais de data fixa (perpétuos): DD-MM|nome
br_holidays() {
  cat <<'FERIADOS'
01-01|Confraternização Universal
21-04|Tiradentes
01-05|Dia do Trabalho
07-09|Independência do Brasil
12-10|Nossa Senhora Aparecida
02-11|Finados
15-11|Proclamação da República
20-11|Dia Nacional de Zumbi e da Consciência Negra
25-12|Natal
FERIADOS
}

hhmm_to_seconds() { local h=${1%%:*} m=${1##*:}; echo $(( 10#$h * 3600 + 10#$m * 60 )); }

# Cria o calendário de atendimento (seg-sex, sábado opcional, feriados) e devolve o id
create_business_calendar() {
  local wstart=${BUSINESS_HOURS%%-*} wend=${BUSINESS_HOURS##*-} sstart="" send="" cal day secs hid
  local -a cache=(0 0 0 0 0 0 0)
  cal=$(db_glpi -N -e "INSERT INTO glpi_calendars (name, entities_id, is_recursive, comment, cache_duration, date_creation, date_mod)
      VALUES ('Horário de atendimento', 0, 1, 'Criado pelo instalador: $BUSINESS_HOURS em dias úteis', '[]', NOW(), NOW());
    SELECT LAST_INSERT_ID();")
  secs=$(( $(hhmm_to_seconds "$wend") - $(hhmm_to_seconds "$wstart") ))
  for day in 1 2 3 4 5; do   # 0 = domingo ... 6 = sábado
    db_glpi -e "INSERT INTO glpi_calendarsegments (calendars_id, entities_id, is_recursive, day, begin, end)
                VALUES ($cal, 0, 1, $day, '$wstart:00', '$wend:00');"
    cache[$day]=$secs
  done
  if [[ $BUSINESS_SATURDAY == S ]]; then
    sstart=${SATURDAY_HOURS%%-*}; send=${SATURDAY_HOURS##*-}
    db_glpi -e "INSERT INTO glpi_calendarsegments (calendars_id, entities_id, is_recursive, day, begin, end)
                VALUES ($cal, 0, 1, 6, '$sstart:00', '$send:00');"
    cache[6]=$(( $(hhmm_to_seconds "$send") - $(hhmm_to_seconds "$sstart") ))
  fi
  # Cache que o GLPI usa para pular dias sem expediente (segundos por dia, domingo primeiro)
  db_glpi -e "UPDATE glpi_calendars SET cache_duration = '[$(IFS=,; echo "${cache[*]}")]' WHERE id = $cal;"

  if [[ $ADD_HOLIDAYS == S ]]; then
    local line date name year
    year=$(date +%Y)
    while IFS='|' read -r date name; do
      [[ -z $date ]] && continue
      hid=$(db_glpi -N -e "INSERT INTO glpi_holidays (name, entities_id, is_recursive, begin_date, end_date, is_perpetual, date_creation, date_mod)
          VALUES ('$(sql_escape "$name")', 0, 1, '$year-${date#*-}-${date%-*}', '$year-${date#*-}-${date%-*}', 1, NOW(), NOW());
        SELECT LAST_INSERT_ID();")
      db_glpi -e "INSERT INTO glpi_calendars_holidays (calendars_id, holidays_id) VALUES ($cal, $hid);"
    done < <(br_holidays)
  fi
  echo "$cal"
}

# Impacto atrelado à urgência: ao definir ou alterar a urgência, impacto e prioridade passam
# a ter o mesmo nível. Precisa rodar ANTES das regras de SLA (criar antes = ranking menor):
# nas regras de chamado do GLPI, cada regra recebe o resultado da anterior, então as regras
# de SLA/OLA enxergam a prioridade já ajustada. Se o técnico mudar só o impacto ou a
# prioridade, estas regras não rodam (a urgência não mudou) e o SLA segue a nova prioridade.
create_link_rules() {
  local prio name rid ranking count=0
  while IFS='|' read -r prio name _; do
    [[ -z $prio ]] && continue
    ranking=$(db_glpi -N -e "SELECT COALESCE(MAX(ranking), 0) + 1 FROM glpi_rules WHERE sub_type = 'RuleTicket'")
    rid=$(db_glpi -N -e "INSERT INTO glpi_rules
        (entities_id, sub_type, ranking, name, description, \`match\`, is_active, comment, is_recursive, uuid, \`condition\`, date_creation, date_mod)
      VALUES (0, 'RuleTicket', $ranking, '$(sql_escape "Prioridade pela urgência: $name")',
        'Criada pelo instalador: impacto e prioridade acompanham a urgência (abertura e alteração da urgência)',
        'AND', 1, '', 1, '$(cat /proc/sys/kernel/random/uuid 2>/dev/null || openssl rand -hex 16)', 3, NOW(), NOW());
      SELECT LAST_INSERT_ID();")
    db_glpi -e "INSERT INTO glpi_rulecriterias (rules_id, criteria, \`condition\`, pattern) VALUES ($rid, 'urgency', 0, '$prio');
                INSERT INTO glpi_ruleactions (rules_id, action_type, field, value) VALUES
                  ($rid, 'assign', 'impact', '$prio'), ($rid, 'assign', 'priority', '$prio');"
    count=$((count + 1))
  done < <(sla_catalog)
  echo "$count"
}

# "15m" -> "15 minute" | "4h" -> "4 hour" | "2d" -> "2 day"
sla_time() {
  local n=${1%[mhd]} u=${1: -1}
  case $u in m) echo "$n minute" ;; h) echo "$n hour" ;; d) echo "$n day" ;; esac
}

sla_label() { # texto amigável: "15 min", "4 h", "2 dias úteis"
  local n=${1%[mhd]} u=${1: -1}
  case $u in m) echo "$n min" ;; h) echo "$n h" ;; d) (( n == 1 )) && echo "1 dia útil" || echo "$n dias úteis" ;; esac
}

# Insere um SLA ou OLA e devolve o id. insert_level tabela slm calendário tipo(0=solução,1=atendimento) nome meta
insert_level() {
  local table=$1 slm=$2 cal=$3 type=$4 name=$5 n unit
  read -r n unit <<<"$(sla_time "$6")"
  db_glpi -N -e "INSERT INTO $table (name, entities_id, is_recursive, type, comment, number_time, use_ticket_calendar,
        calendars_id, definition_time, end_of_working_day, slms_id, date_creation, date_mod)
      VALUES ('$(sql_escape "$name")', 0, 1, $type, 'Criado pelo instalador (ITIL)', $n, 0, $cal, '$unit', 0, $slm, NOW(), NOW());
    SELECT LAST_INSERT_ID();"
}

# Calendário + SLM + 8 SLAs + 8 OLAs + 1 regra por prioridade (na abertura e na atualização)
create_sla_ola() {
  local cal slm prio name s_tto s_ttr o_tto o_ttr id_s_tto id_s_ttr id_o_tto id_o_ttr rid ranking count=0
  cal=$(create_business_calendar)
  slm=$(db_glpi -N -e "INSERT INTO glpi_slms (name, entities_id, is_recursive, comment, use_ticket_calendar, calendars_id, date_creation, date_mod)
      VALUES ('Níveis de serviço (ITIL)', 0, 1, 'SLA = prazo para o usuário; OLA = prazo interno da equipe', 0, $cal, NOW(), NOW());
    SELECT LAST_INSERT_ID();")

  while IFS='|' read -r prio name s_tto s_ttr o_tto o_ttr; do
    [[ -z $prio ]] && continue
    id_s_tto=$(insert_level glpi_slas "$slm" "$cal" 1 "SLA $name - 1º atendimento ($(sla_label "$s_tto"))" "$s_tto")
    id_s_ttr=$(insert_level glpi_slas "$slm" "$cal" 0 "SLA $name - solução ($(sla_label "$s_ttr"))" "$s_ttr")
    id_o_tto=$(insert_level glpi_olas "$slm" "$cal" 1 "OLA $name - 1º atendimento ($(sla_label "$o_tto"))" "$o_tto")
    id_o_ttr=$(insert_level glpi_olas "$slm" "$cal" 0 "OLA $name - solução ($(sla_label "$o_ttr"))" "$o_ttr")

    ranking=$(db_glpi -N -e "SELECT COALESCE(MAX(ranking), 0) + 1 FROM glpi_rules WHERE sub_type = 'RuleTicket'")
    rid=$(db_glpi -N -e "INSERT INTO glpi_rules
        (entities_id, sub_type, ranking, name, description, \`match\`, is_active, comment, is_recursive, uuid, \`condition\`, date_creation, date_mod)
      VALUES (0, 'RuleTicket', $ranking, '$(sql_escape "SLA/OLA: prioridade $name")',
        'Criada pelo instalador: aplica SLA e OLA conforme a prioridade (abertura e atualização)',
        'AND', 1, '', 1, '$(cat /proc/sys/kernel/random/uuid 2>/dev/null || openssl rand -hex 16)', 3, NOW(), NOW());
      SELECT LAST_INSERT_ID();")
    db_glpi -e "INSERT INTO glpi_rulecriterias (rules_id, criteria, \`condition\`, pattern) VALUES ($rid, 'priority', 0, '$prio');
                INSERT INTO glpi_ruleactions (rules_id, action_type, field, value) VALUES
                  ($rid, 'assign', 'slas_id_tto', '$id_s_tto'), ($rid, 'assign', 'slas_id_ttr', '$id_s_ttr'),
                  ($rid, 'assign', 'olas_id_tto', '$id_o_tto'), ($rid, 'assign', 'olas_id_ttr', '$id_o_ttr');"
    # O seletor manual do GLPI sempre mostra Crítica (6) e Muito baixa (1). Esses níveis entram
    # na regra de Muito alta / Baixa e, com 4 níveis, são corrigidos para 5 / 2.
    local extra=""
    [[ $prio == 5 ]] && extra=6
    [[ $prio == 2 ]] && extra=1
    if [[ -n $extra ]]; then
      db_glpi -e "UPDATE glpi_rules SET \`match\` = 'OR' WHERE id = $rid;
                  INSERT INTO glpi_rulecriterias (rules_id, criteria, \`condition\`, pattern) VALUES ($rid, 'priority', 0, '$extra');"
      [[ ${SIMPLIFY_PRIORITIES:-N} == S ]] && \
        db_glpi -e "INSERT INTO glpi_ruleactions (rules_id, action_type, field, value) VALUES ($rid, 'assign', 'priority', '$prio');"
    fi
    count=$((count + 1))
  done < <(sla_catalog)
  echo "$count"
}

# --- Modelos de Atendimento e Melhores Práticas de Inventário -----------------
create_followup_and_solution_templates() {
  local existing_sol
  existing_sol=$(db_glpi -N -e "SELECT COUNT(*) FROM glpi_solutiontemplates" 2>/dev/null || echo "0")
  if (( existing_sol > 0 )); then
    log "Modelos de solução já existem ($existing_sol encontrados); mantendo os atuais."
  else
    # 1. Tipos de solução
    local sol_def sol_work sol_canc sol_noans
    sol_def=$(db_glpi -N -e "INSERT INTO glpi_solutiontypes (name, comment, entities_id, is_recursive, date_creation, date_mod)
        VALUES ('Solução Definitiva', 'Incidente resolvido de forma permanente ou requisição atendida integralmente', 0, 1, NOW(), NOW());
      SELECT LAST_INSERT_ID();" 2>/dev/null || true)
    sol_work=$(db_glpi -N -e "INSERT INTO glpi_solutiontypes (name, comment, entities_id, is_recursive, date_creation, date_mod)
        VALUES ('Solução de Contorno (Workaround)', 'Operação restaurada com solução paliativa ou temporária', 0, 1, NOW(), NOW());
      SELECT LAST_INSERT_ID();" 2>/dev/null || true)
    sol_canc=$(db_glpi -N -e "INSERT INTO glpi_solutiontypes (name, comment, entities_id, is_recursive, date_creation, date_mod)
        VALUES ('Cancelado pelo Solicitante', 'Atendimento cancelado por desistência ou erro na abertura', 0, 1, NOW(), NOW());
      SELECT LAST_INSERT_ID();" 2>/dev/null || true)
    sol_noans=$(db_glpi -N -e "INSERT INTO glpi_solutiontypes (name, comment, entities_id, is_recursive, date_creation, date_mod)
        VALUES ('Sem Retorno do Usuário', 'Encerrado por expiração de prazo sem resposta às solicitações da equipe técnica', 0, 1, NOW(), NOW());
      SELECT LAST_INSERT_ID();" 2>/dev/null || true)

    # 2. Modelos de Encerramento (glpi_solutiontemplates)
    local tpl_inc tpl_req tpl_semretorno tpl_duplicado tpl_devolucao
    tpl_inc="<p>Prezado(a),</p><p>O incidente reportado foi analisado e solucionado pela equipe técnica. Realizamos os devidos testes e o funcionamento do serviço foi normalizado com sucesso.</p><p>Por gentileza, valide o funcionamento. Este chamado será homologado e encerrado automaticamente após o período de aprovação.</p><p>Agradecemos a colaboração!</p>"
    tpl_req="<p>Prezado(a),</p><p>Informamos que sua solicitação foi concluída e implementada com sucesso conforme requerido.</p><p>Permanecemos à disposição para quaisquer esclarecimentos adicionais.</p>"
    tpl_semretorno="<p>Prezado(a),</p><p>Como não obtivemos retorno aos nossos contatos e tentativas de esclarecimento dentro do prazo estipulado, estamos encerrando este atendimento.</p><p>Caso a necessidade ou o problema persista, você poderá reabrir este chamado ou registrar uma nova solicitação a qualquer momento.</p>"
    tpl_duplicado="<p>Prezado(a),</p><p>Este chamado foi unificado ou encerrado por constatar duplicidade de solicitação já em andamento.</p><p>O acompanhamento permanecerá centralizado no chamado principal de referência.</p>"
    tpl_devolucao="<h3>TERMO DE DEVOLUÇÃO E VISTORIA TÉCNICA</h3><p>Atestamos o recolhimento e devolução do equipamento corporativo:</p><ul><li><strong>Colaborador / Entregador:</strong> [Nome do Usuário]</li><li><strong>Patrimônio:</strong> [Nº do Patrimônio]</li><li><strong>Número de Série:</strong> [Serial Number]</li><li><strong>Equipamento / Modelo:</strong> [Modelo]</li><li><strong>Estado de Conservação:</strong> ( ) Perfeito  ( ) Avarias leves  ( ) Defeito funcional</li><li><strong>Acessórios Devolvidos:</strong> ( ) Fonte/Carregador  ( ) Cabos  ( ) Mochila  ( ) Mouse</li></ul><p>O equipamento foi inspecionado, testado e retornado ao estoque da TI para higienização e futura alocação.</p>"

    db_glpi -e "INSERT INTO glpi_solutiontemplates (name, content, solutiontypes_id, entities_id, is_recursive, date_creation, date_mod) VALUES
        ('Incidente Resolvido (Padrão)', '$(sql_escape "$tpl_inc")', ${sol_def:-0}, 0, 1, NOW(), NOW()),
        ('Requisição Atendida (Padrão)', '$(sql_escape "$tpl_req")', ${sol_def:-0}, 0, 1, NOW(), NOW()),
        ('Encerramento por Falta de Retorno', '$(sql_escape "$tpl_semretorno")', ${sol_noans:-0}, 0, 1, NOW(), NOW()),
        ('Chamado Duplicado / Unificado', '$(sql_escape "$tpl_duplicado")', ${sol_canc:-0}, 0, 1, NOW(), NOW()),
        ('Termo de Devolução de Equipamento', '$(sql_escape "$tpl_devolucao")', ${sol_def:-0}, 0, 1, NOW(), NOW());" 2>/dev/null || true
  fi

  local existing_fup
  existing_fup=$(db_glpi -N -e "SELECT COUNT(*) FROM glpi_itilfollowuptemplates" 2>/dev/null || echo "0")
  if (( existing_fup > 0 )); then
    log "Modelos de acompanhamento já existem ($existing_fup encontrados); mantendo os atuais."
  else
    # 3. Modelos de Acompanhamento (glpi_itilfollowuptemplates)
    local fup_aguardando fup_analise fup_terceiro fup_contato fup_entrega
    fup_aguardando="<p>Olá!</p><p>Para prosseguirmos com o seu atendimento, precisamos de algumas informações complementares:</p><ul><li>[Descreva aqui as informações ou evidências solicitadas]</li></ul><p>Por favor, responda diretamente a este chamado assim que possível para retomarmos a tratativa.</p>"
    fup_analise="<p>Olá!</p><p>Seu chamado foi atribuído aos especialistas da área técnica e encontra-se em análise.</p><p>Estamos executando os diagnósticos e testes necessários. Em breve traremos novas atualizações.</p>"
    fup_terceiro="<p>Olá!</p><p>Informamos que a tratativa deste atendimento depende de suporte externo/fornecedor/operadora. Já realizamos o acionamento e estamos acompanhando a evolução até a conclusão.</p>"
    fup_contato="<p>Olá!</p><p>Tentamos contato via telefone/ramal/chat para dar sequência ao atendimento, porém sem sucesso no momento.</p><p>Por gentileza, informe o melhor horário ou canal para entrarmos em contato.</p>"
    fup_entrega="<h3>TERMO DE RESPONSABILIDADE E ENTREGA DE EQUIPAMENTO</h3><p>Eu, <strong>[Nome do Colaborador]</strong>, declaro ter recebido da empresa o equipamento de TI abaixo discriminado em perfeitas condições de uso e funcionamento:</p><ul><li><strong>Patrimônio:</strong> [Nº do Patrimônio]</li><li><strong>Número de Série:</strong> [Serial Number]</li><li><strong>Modelo:</strong> [Modelo do Equipamento]</li><li><strong>Acessórios:</strong> ( ) Carregador/Fonte  ( ) Mouse  ( ) Mochila  ( ) Outros</li></ul><p>Comprometo-me a zelar pela guarda, integridade e conservação do equipamento, utilizando-o estritamente para finalidades profissionais de acordo com as normas da empresa.</p><p><em>Por gentileza, confirme o recebimento formal deste equipamento aprovando este chamado.</em></p>"

    db_glpi -e "INSERT INTO glpi_itilfollowuptemplates (name, content, requesttypes_id, entities_id, is_recursive, date_creation, date_mod) VALUES
        ('Aguardando Informações do Solicitante', '$(sql_escape "$fup_aguardando")', 0, 0, 1, NOW(), NOW()),
        ('Em Análise Técnica', '$(sql_escape "$fup_analise")', 0, 0, 1, NOW(), NOW()),
        ('Aguardando Fornecedor / Terceiro', '$(sql_escape "$fup_terceiro")', 0, 0, 1, NOW(), NOW()),
        ('Tentativa de Contato sem Sucesso', '$(sql_escape "$fup_contato")', 0, 0, 1, NOW(), NOW()),
        ('Termo de Entrega de Equipamento', '$(sql_escape "$fup_entrega")', 0, 0, 1, NOW(), NOW());" 2>/dev/null || true
  fi
}

configure_inventory_best_practices() {
  local uuid line st_name st_comment st_id t vis_table type_id rid ranking where p count
  uuid() { cat /proc/sys/kernel/random/uuid 2>/dev/null || openssl rand -hex 16; }

  # 1. Inventário nativo ligado, com frequência de 24 h (chaves de Glpi\Inventory\Conf)
  db_glpi <<'SQL'
INSERT INTO glpi_configs (context, name, value) VALUES
  ('inventory', 'enabled_inventory', '1'),
  ('inventory', 'inventory_frequency', '24')
ON DUPLICATE KEY UPDATE value = VALUES(value);
DELETE FROM glpi_configs WHERE context = 'inventory' AND name IN ('inventory_freq', 'clean_agent');
SQL

  # 2. Ciclo de vida dos ativos (Status). O GLPI 11 guarda em glpi_dropdownvisibilities
  #    para quais tipos de ativo cada status aparece; no GLPI 10 as colunas is_visible_* já nascem com 1.
  vis_table=$(db_glpi -N -e "SHOW TABLES LIKE 'glpi_dropdownvisibilities'")
  local -a states=(
    "Em uso|Em operação com um colaborador ou setor"
    "Em estoque|Disponível no estoque para entrega"
    "Em preparação|Em configuração, formatação ou instalação"
    "Em manutenção|Em reparo ou na garantia do fabricante"
    "Empréstimo|Equipamento temporário ou máquina reserva"
    "Desativado / Descarte|Fim de vida útil, sucata ou doação"
  )
  local -a state_types=(Computer Monitor NetworkEquipment Peripheral Phone Printer SoftwareLicense
    Certificate Enclosure PDU Line Rack SoftwareVersion Cluster Contract Appliance DatabaseInstance
    Cable Unmanaged PassiveDCEquipment)
  for line in "${states[@]}"; do
    IFS='|' read -r st_name st_comment <<<"$line"
    st_id=$(db_glpi -N -e "SELECT id FROM glpi_states WHERE name = '$(sql_escape "$st_name")' LIMIT 1")
    if [[ -z $st_id ]]; then
      st_id=$(db_glpi -N -e "INSERT INTO glpi_states (name, completename, comment, level, states_id, entities_id, is_recursive, date_creation, date_mod)
        VALUES ('$(sql_escape "$st_name")', '$(sql_escape "$st_name")', '$(sql_escape "$st_comment")', 1, 0, 0, 1, NOW(), NOW());
        SELECT LAST_INSERT_ID();")
    fi
    if [[ -n $vis_table ]]; then
      for t in "${state_types[@]}"; do
        db_glpi -e "INSERT INTO glpi_dropdownvisibilities (itemtype, items_id, visible_itemtype, is_visible)
          SELECT 'State', $st_id, '$t', 1 FROM DUAL WHERE NOT EXISTS (
            SELECT 1 FROM glpi_dropdownvisibilities WHERE itemtype = 'State' AND items_id = $st_id AND visible_itemtype = '$t')"
      done
    fi
  done

  # Equipamentos novos no inventário entram como "Em uso"
  st_id=$(db_glpi -N -e "SELECT id FROM glpi_states WHERE name = 'Em uso' LIMIT 1")
  [[ -n $st_id ]] && db_glpi -e "INSERT INTO glpi_configs (context, name, value) VALUES ('inventory', 'states_id_default', '$st_id')
    ON DUPLICATE KEY UPDATE value = VALUES(value)"

  # 3. Tipos de computador padronizados
  local -a types=(
    "Servidor|Servidores físicos (rack, torre ou blade)"
    "Notebook|Notebooks e portáteis"
    "Desktop|Estações de trabalho fixas"
    "Máquina Virtual|Máquinas virtuais (VMware, Hyper-V, Proxmox/KVM, VirtualBox)"
  )
  for line in "${types[@]}"; do
    IFS='|' read -r st_name st_comment <<<"$line"
    [[ -n $(db_glpi -N -e "SELECT id FROM glpi_computertypes WHERE name = '$(sql_escape "$st_name")' LIMIT 1") ]] && continue
    db_glpi -e "INSERT INTO glpi_computertypes (name, comment, date_creation, date_mod)
      VALUES ('$(sql_escape "$st_name")', '$(sql_escape "$st_comment")', NOW(), NOW())"
  done

  # 4. Dicionário de tipos de computador. O agente informa o chassi (ex.: "Rack Mount Chassis",
  #    "Notebook") ou, em VMs, o hipervisor (ex.: "VMware", "HyperV"); a regra troca pelo tipo padronizado.
  #    Remove as regras de versões anteriores do instalador, que não funcionavam (RuleAsset não altera o tipo).
  db_glpi -e "DELETE r, c, a FROM glpi_rules r
      LEFT JOIN glpi_rulecriterias c ON c.rules_id = r.id
      LEFT JOIN glpi_ruleactions a ON a.rules_id = r.id
    WHERE (r.sub_type = 'RuleDictionnaryComputerType' AND r.name = 'Classificar Servidores por Nome/Tipo')
       OR (r.sub_type = 'RuleAsset' AND r.name = 'Definir Tipo Servidor pelo SO')
       OR r.sub_type IN ('RuleDictionarySoftware', 'RuleDictionaryComputerType')"
  local -a type_rules=(
    "Máquina Virtual|/^(vmware|hyper-?v|kvm|qemu|virtualbox|virtual machine|xen|parallels|bhyve|lxc|docker)/i"
    "Servidor|/(server|rack|blade)/i"
    "Notebook|/(notebook|laptop|portable|convertible|detachable|tablet)/i"
    "Desktop|/(desktop|tower|all in one|mini pc|space-saving|lunch box|pizza box)/i"
  )
  for line in "${type_rules[@]}"; do
    IFS='|' read -r st_name p <<<"$line"
    [[ -n $(db_glpi -N -e "SELECT id FROM glpi_rules WHERE sub_type = 'RuleDictionnaryComputerType' AND name = 'Tipo: $(sql_escape "$st_name")' LIMIT 1") ]] && continue
    ranking=$(db_glpi -N -e "SELECT COALESCE(MAX(ranking), 0) + 1 FROM glpi_rules WHERE sub_type = 'RuleDictionnaryComputerType'")
    rid=$(db_glpi -N -e "INSERT INTO glpi_rules
        (entities_id, sub_type, ranking, name, description, \`match\`, is_active, comment, is_recursive, uuid, \`condition\`, date_creation, date_mod)
      VALUES (0, 'RuleDictionnaryComputerType', $ranking, 'Tipo: $(sql_escape "$st_name")',
        'Padroniza o tipo informado pelo inventário', 'AND', 1, 'Criado pelo instalador', 1, '$(uuid)', 0, NOW(), NOW());
      SELECT LAST_INSERT_ID();")
    db_glpi -e "INSERT INTO glpi_rulecriterias (rules_id, criteria, \`condition\`, pattern) VALUES ($rid, 'name', 6, '$(sql_escape "$p")');
                INSERT INTO glpi_ruleactions (rules_id, action_type, field, value) VALUES ($rid, 'assign', 'name', '$(sql_escape "$st_name")');"
  done

  # 5. Pesquisa salva pública "Servidores" (Ativos > Computadores > Pesquisas salvas)
  type_id=$(db_glpi -N -e "SELECT id FROM glpi_computertypes WHERE name = 'Servidor' LIMIT 1")
  if [[ -n $type_id && -z $(db_glpi -N -e "SELECT id FROM glpi_savedsearches WHERE itemtype = 'Computer' AND name = 'Servidores' LIMIT 1") ]]; then
    db_glpi -e "INSERT INTO glpi_savedsearches (name, type, itemtype, users_id, is_private, entities_id, is_recursive, query)
      VALUES ('Servidores', 1, 'Computer', 2, 0, 0, 1,
        'is_deleted=0&criteria%5B0%5D%5Blink%5D=AND&criteria%5B0%5D%5Bfield%5D=4&criteria%5B0%5D%5Bsearchtype%5D=equals&criteria%5B0%5D%5Bvalue%5D=$type_id&itemtype=Computer')"
  fi

  # 6. Dicionário de software: não importar atualizações do Windows, KBs e pacotes de idioma
  local -a noise=('Security Update' 'Update for Windows' 'Atualização para Windows' 'Atualização de Segurança'
    'Security Intelligence Update' 'Cumulative Update' 'Atualização Cumulativa' 'Hotfix' 'Package_for_'
    'Language Experience Pack' 'Pacote de Experiência Local' 'Windows Setup Remediations')
  if [[ -z $(db_glpi -N -e "SELECT id FROM glpi_rules WHERE sub_type = 'RuleDictionnarySoftware' AND name = 'Ignorar atualizações do Windows e KBs' LIMIT 1") ]]; then
    ranking=$(db_glpi -N -e "SELECT COALESCE(MAX(ranking), 0) + 1 FROM glpi_rules WHERE sub_type = 'RuleDictionnarySoftware'")
    rid=$(db_glpi -N -e "INSERT INTO glpi_rules
        (entities_id, sub_type, ranking, name, description, \`match\`, is_active, comment, is_recursive, uuid, \`condition\`, date_creation, date_mod)
      VALUES (0, 'RuleDictionnarySoftware', $ranking, 'Ignorar atualizações do Windows e KBs',
        'Não importa hotfixes e pacotes do Windows Update, para manter a lista de softwares limpa', 'OR', 1,
        'Criado pelo instalador', 1, '$(uuid)', 0, NOW(), NOW());
      SELECT LAST_INSERT_ID();")
    local values=""
    for p in "${noise[@]}"; do values+="${values:+,}($rid, 'name', 2, '$(sql_escape "$p")')"; done
    values+=",($rid, 'name', 6, '/^KB[0-9]+/i')"
    db_glpi -e "INSERT INTO glpi_rulecriterias (rules_id, criteria, \`condition\`, pattern) VALUES $values;
                INSERT INTO glpi_ruleactions (rules_id, action_type, field, value) VALUES ($rid, 'assign', '_ignore_import', '1');"
  fi

  # 7. Remove os mesmos itens já importados. Softwares com licença cadastrada são mantidos.
  where=""
  for p in "${noise[@]}"; do where+="${where:+ OR }s.name LIKE '%$(sql_escape "${p//_/\\_}")%'"; done
  where+=" OR s.name REGEXP '^KB[0-9]+'"
  count=$(db_glpi -N -e "
    CREATE TEMPORARY TABLE tmp_noise_soft AS
      SELECT s.id FROM glpi_softwares s
      WHERE ($where)
        AND NOT EXISTS (SELECT 1 FROM glpi_softwarelicenses l WHERE l.softwares_id = s.id);
    DELETE isv FROM glpi_items_softwareversions isv
      JOIN glpi_softwareversions sv ON sv.id = isv.softwareversions_id
      JOIN tmp_noise_soft t ON t.id = sv.softwares_id;
    DELETE sv FROM glpi_softwareversions sv JOIN tmp_noise_soft t ON t.id = sv.softwares_id;
    DELETE s FROM glpi_softwares s JOIN tmp_noise_soft t ON t.id = s.id;
    SELECT COUNT(*) FROM tmp_noise_soft;") || { warn "Não foi possível limpar os softwares já importados."; count=0; }
  log "Inventário: status, tipos de computador, dicionários e limpeza de $count softwares de atualização do Windows"
}


# --- Instalação existente (modo atualização) ---------------------------------
glpi_version_in() { # versão do GLPI instalado em um diretório
  # GLPI 11: src/autoload/constants.php | GLPI 10: inc/define.php (um dos dois não existe)
  local f
  for f in "$1/src/autoload/constants.php" "$1/inc/define.php"; do
    [[ -f $f ]] && grep -oP "define\('GLPI_VERSION', '\K[^']+" "$f" 2>/dev/null && return 0
  done
  return 0
}

glpi_config_dir_of() { # diretório de configuração (respeita inc/downstream.php)
  local cfg
  cfg=""
  [[ -f $1/inc/downstream.php ]] && cfg=$(grep -m1 -oP "define\('GLPI_CONFIG_DIR',\s*'\K[^']+" "$1/inc/downstream.php" || true)
  cfg=${cfg:-$1/config}
  echo "${cfg%/}"
}

glpi_var_dir_of() { # diretório de dados: GLPI_VAR_DIR do local_define.php, senão <glpi>/files
  local var
  var=""
  [[ -f $2/local_define.php ]] && var=$(grep -m1 -oP "define\('GLPI_VAR_DIR',\s*'\K[^']+" "$2/local_define.php" || true)
  var=${var:-$1/files}
  echo "${var%/}"
}

# Lê as credenciais do config_db.php sem carregar o GLPI.
# A senha é gravada com rawurlencode pelo GLPI. Define OLD_DB* (host, porta, usuário, senha, base).
read_glpi_db_config() {
  local json host
  json=$(php -r 'class DBmysql {} require $argv[1]; $d = new DB();
    echo json_encode([$d->dbhost, $d->dbuser, rawurldecode($d->dbpassword), $d->dbdefault]);' "$1" 2>/dev/null) || return 1
  host=$(jq -r '.[0]' <<<"$json")
  OLD_DBUSER=$(jq -r '.[1]' <<<"$json")
  OLD_DBPASS=$(jq -r '.[2]' <<<"$json")
  OLD_DBNAME=$(jq -r '.[3]' <<<"$json")
  OLD_DBHOST=$host; OLD_DBPORT=3306
  if [[ $host =~ ^(.+):([0-9]+)$ ]]; then OLD_DBHOST=${BASH_REMATCH[1]}; OLD_DBPORT=${BASH_REMATCH[2]}; fi
  [[ -n $OLD_DBNAME && -n $OLD_DBUSER ]]
}

# Ajusta o VirtualHost do Apache para o DocumentRoot em /public (exigência do GLPI 11)
fix_apache_docroot() { # fix_apache_docroot diretório_glpi carimbo
  local dir=$1 ts=$2 conf changed=0
  for conf in /etc/apache2/sites-enabled/*.conf; do
    [[ -f $conf ]] || continue
    grep -qE "^[[:space:]]*DocumentRoot[[:space:]]+\"?$dir/?\"?[[:space:]]*$" "$conf" || continue
    conf=$(readlink -f "$conf")
    cp -a "$conf" "$conf.bak-$ts"
    sed -i -E "s#^([[:space:]]*DocumentRoot[[:space:]]+)\"?$dir/?\"?[[:space:]]*\$#\1$dir/public#" "$conf"
    if ! grep -q 'RewriteRule \^(\.\*)\$ index\.php' "$conf"; then
      sed -i "0,/<\/VirtualHost>/s##    <Directory $dir/public>\n        Require all granted\n        RewriteEngine On\n        RewriteCond %{HTTP:Authorization} ^(.+)\$\n        RewriteRule .* - [E=HTTP_AUTHORIZATION:%{HTTP:Authorization}]\n        RewriteCond %{REQUEST_FILENAME} !-f\n        RewriteRule ^(.*)\$ index.php [QSA,L]\n    </Directory>\n</VirtualHost>#" "$conf"
    fi
    log "VirtualHost ajustado para $dir/public ($conf; backup em $conf.bak-$ts)"
    changed=1
  done
  a2enmod -q rewrite >/dev/null
  if ! apachectl configtest >/dev/null 2>&1; then
    for conf in /etc/apache2/sites-available/*.bak-"$ts"; do [[ -f $conf ]] && mv "$conf" "${conf%.bak-$ts}"; done
    die "A configuração do Apache ficou inválida e foi restaurada. Ajuste o DocumentRoot para $dir/public manualmente."
  fi
  (( changed )) || info "Nenhum VirtualHost com DocumentRoot em $dir encontrado (já usa /public ou outro caminho)."
}

# Atualiza a instalação existente mantendo todos os dados. Encerra o script ao terminar.
run_upgrade() {
  local old=$EXISTING_DIR prev ts backup cfg var tmp tgz free need p name status console_cmds
  ts=$(date +%Y%m%d-%H%M%S)
  backup="${GLPI_BACKUP_DIR:-/root}/glpi-backup-$ts"
  GLPI_DIR=$old
  cfg=$(glpi_config_dir_of "$old")
  var=$(glpi_var_dir_of "$old" "$cfg")

  read_glpi_db_config "$cfg/config_db.php" || die "Não foi possível ler $cfg/config_db.php."
  DB_HOST=$OLD_DBHOST; DB_PORT=$OLD_DBPORT; DB_USER=$OLD_DBUSER; DB_PASS=$OLD_DBPASS; DB_NAME=$OLD_DBNAME
  command -v mysql >/dev/null 2>&1 || apt-get install -y -qq mariadb-client >/dev/null
  GLPI_CNF=$(mktemp); TMP_FILES+=("$GLPI_CNF")
  make_mycnf "$GLPI_CNF" "$DB_HOST" "$DB_PORT" "$DB_USER" "$DB_PASS"
  db_glpi -e "SELECT 1" >/dev/null 2>&1 || die "Sem conexão com a base '$DB_NAME' em $DB_HOST:$DB_PORT (dados do config_db.php)."
  PLUGIN_ADMIN=$(db_glpi -N -e "SELECT u.name FROM glpi_users u
      JOIN glpi_profiles_users pu ON pu.users_id = u.id JOIN glpi_profiles p ON p.id = pu.profiles_id
      WHERE p.name = 'Super-Admin' AND u.is_active = 1 AND u.is_deleted = 0 ORDER BY u.id LIMIT 1" 2>/dev/null || true)
  PLUGIN_ADMIN=${PLUGIN_ADMIN:-glpi}

  echo
  echo "  ${C_W}Resumo da atualização:${C_N}"
  echo "    GLPI ............: $EXISTING_VERSION  ->  $GLPI_VERSION"
  echo "    Código ..........: $old"
  echo "    Configuração ....: $cfg"
  echo "    Dados (files) ...: $var"
  echo "    Banco ...........: $DB_NAME em $DB_HOST:$DB_PORT"
  echo "    Servidor web ....: $WEB_SERVER"
  echo "    Backup em .......: $backup"
  echo "    GLPI Inventory ..: $( [[ $INSTALL_GLPIINVENTORY == S ]] && echo "instalar/atualizar" || echo "não mexer")"
  echo "    Cascater ........: $( [[ $INSTALL_CASCATER == S ]] && echo "instalar/atualizar" || echo "não mexer")"
  echo "    Asset Terms .....: $( [[ $INSTALL_ASSETTERMS == S ]] && echo "instalar/atualizar" || echo "não mexer")"
  echo "    GLPI Chatbot ....: $( [[ $INSTALL_CHATBOT == S ]] && echo "instalar/atualizar" || echo "não mexer")"
  echo "  O GLPI fica em manutenção (fora do ar para os usuários) durante a atualização."
  echo
  ask_yn CONFIRM "Prosseguir com a atualização?" S
  [[ $CONFIRM == S ]] || die "Atualização cancelada pelo usuário."
  # Nginx: confere ANTES de alterar qualquer coisa se a configuração pode ser ajustada
  [[ $WEB_SERVER == nginx ]] && fix_nginx_conf check "$old" "$ts"

  title "5/9 Backup completo"
  need=$(du -sm "$old" "$cfg" "$var" 2>/dev/null | awk '{s+=$1} END {print int(s*1.5)+500}')
  mkdir -p "${GLPI_BACKUP_DIR:-/root}"
  free=$(df -Pm "${GLPI_BACKUP_DIR:-/root}" | awk 'NR==2 {print $4}')
  (( free > need )) || die "Espaço insuficiente em ${GLPI_BACKUP_DIR:-/root} para o backup: ${free}MB livres, ~${need}MB necessários."
  mkdir -p "$backup"; chmod 700 "$backup"
  glpi_console maintenance:enable --no-interaction >/dev/null 2>&1 || warn "Não foi possível ativar o modo de manutenção."
  mysqldump --defaults-extra-file="$GLPI_CNF" --single-transaction --routines --triggers --no-tablespaces "$DB_NAME" \
    | gzip >"$backup/banco-$DB_NAME.sql.gz" || die "Falha no backup do banco. Nada foi alterado."
  tar -czf "$backup/codigo.tar.gz" -C "$(dirname "$old")" "$(basename "$old")" || die "Falha no backup dos arquivos. Nada foi alterado."
  [[ $cfg == "$old"/* ]] || tar -czf "$backup/config.tar.gz" -C "$(dirname "$cfg")" "$(basename "$cfg")"
  [[ $var == "$old"/* ]] || tar -czf "$backup/dados.tar.gz" -C "$(dirname "$var")" "$(basename "$var")"
  log "Backup salvo em $backup ($(du -sh "$backup" | cut -f1))"

  cat >"$backup/COMO-VOLTAR.txt" <<EOF
Para desfazer a atualização e voltar ao GLPI $EXISTING_VERSION:
  systemctl stop $WEB_SVC
  rm -rf "$old" && tar -xzf "$backup/codigo.tar.gz" -C "$(dirname "$old")"
$( [[ $cfg == "$old"/* ]] || echo "  rm -rf \"$cfg\" && tar -xzf \"$backup/config.tar.gz\" -C \"$(dirname "$cfg")\"")
$( [[ $var == "$old"/* ]] || echo "  rm -rf \"$var\" && tar -xzf \"$backup/dados.tar.gz\" -C \"$(dirname "$var")\"")
  mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p -e 'DROP DATABASE \`$DB_NAME\`; CREATE DATABASE \`$DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;'
  gunzip -c "$backup/banco-$DB_NAME.sql.gz" | mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p "$DB_NAME"
  for f in /etc/apache2/sites-available/*.bak-$ts /etc/nginx/sites-available/*.bak-$ts /etc/nginx/conf.d/*.bak-$ts; do [ -f "\$f" ] && mv "\$f" "\${f%.bak-$ts}"; done
  systemctl start $WEB_SVC
EOF
  chmod 600 "$backup/COMO-VOLTAR.txt"

  if [[ $EXISTING_VERSION != "$GLPI_VERSION" ]]; then
    title "6/9 Ajustando servidor web ($WEB_SERVER) e PHP para o GLPI $GLPI_VERSION"
    setup_php_web

    title "7/9 Atualizando os arquivos do GLPI"
    tmp=$(work_tmp); tgz="$tmp/glpi.tgz"
    curl -fL --retry 3 --progress-bar -o "$tgz" "$GLPI_URL_TGZ" || die "Falha no download. Nada foi alterado; desative a manutenção com: php $old/bin/console maintenance:disable"
    tar -xzf "$tgz" -C "$tmp" && [[ -f $tmp/glpi/bin/console ]] || die "Pacote do GLPI inválido."
    prev="$old.old-$ts"
    mv "$old" "$prev"
    mv "$tmp/glpi" "$old"
    if [[ $cfg == "$old/config" ]]; then cp -a "$prev/config/." "$old/config/"; fi
    if [[ $var == "$old/files" ]]; then rm -rf "$old/files"; mv "$prev/files" "$old/files"; fi
    [[ -f $prev/inc/downstream.php ]] && cp -a "$prev/inc/downstream.php" "$old/inc/downstream.php"
    for p in "$prev"/plugins/*/; do
      [[ -d $p ]] || continue
      name=$(basename "$p")
      [[ -e $old/plugins/$name ]] || cp -a "$p" "$old/plugins/$name"
    done
    mkdir -p "$old/marketplace"
    [[ -d $prev/marketplace ]] && cp -a "$prev/marketplace/." "$old/marketplace/"
    chown -R root:root "$old"
    chown -R www-data:www-data "$old/marketplace"
    [[ $cfg == "$old/config" ]] && chown -R www-data:www-data "$old/config"
    [[ $var == "$old/files" ]] && chown -R www-data:www-data "$old/files"
    for p in "$prev"/plugins/*/; do [[ -d $p ]] && chown -R --reference="$p" "$old/plugins/$(basename "$p")"; done
    log "Arquivos do GLPI $GLPI_VERSION no lugar (versão anterior em $prev)"

    if [[ $WEB_SERVER == nginx ]]; then
      fix_nginx_conf apply "$old" "$ts"
      # Código novo no mesmo caminho: reinicia o PHP-FPM para o OPcache não servir arquivos antigos
      systemctl restart "php$PHP_VER-fpm"
    else
      (( GLPI_MAJOR >= 11 )) && fix_apache_docroot "$old" "$ts"
      systemctl restart apache2
    fi

    title "8/9 Atualizando o banco de dados"
    if ! glpi_console db:update --no-interaction; then
      warn "A atualização do banco falhou. Para voltar à versão anterior, siga $backup/COMO-VOLTAR.txt"
      die "db:update falhou."
    fi
    log "Banco atualizado para o GLPI $GLPI_VERSION"
  else
    log "O GLPI já está na versão mais recente ($GLPI_VERSION); só os plugins serão verificados."
  fi

  title "9/9 Plugins"
  # Com os arquivos novos no lugar, retoma os plugins (o GLPI 11 os suspende após atualizar)
  local inv_ver="" cas_ver="" termo_ver="" chat_ver=""
  if [[ $INSTALL_GLPIINVENTORY == S ]]; then
    inv_ver=$(fetch_glpiinventory "$GLPI_MAJOR") || { inv_ver=""; warn "Não foi possível baixar o GLPI Inventory compatível."; }
  fi
  if [[ $INSTALL_CASCATER == S ]]; then
    cas_ver=$(fetch_cascater) || { cas_ver=""; warn "Não foi possível baixar o Cascater."; }
  fi
  if [[ $INSTALL_ASSETTERMS == S ]]; then
    termo_ver=$(fetch_assetterms) || { termo_ver=""; warn "Não foi possível baixar o Asset Terms."; }
  fi
  if [[ $INSTALL_CHATBOT == S ]] && (( GLPI_MAJOR < 11 )); then
    warn "O GLPI Chatbot é só para o GLPI 11; não foi instalado no GLPI $GLPI_VERSION."
  elif [[ $INSTALL_CHATBOT == S ]]; then
    chat_ver=$(fetch_chatbot) || { chat_ver=""; warn "Não foi possível baixar o GLPI Chatbot."; }
  fi
  console_cmds=$(glpi_console list --raw 2>/dev/null || true)
  if grep -q '^plugin:resume_execution' <<<"$console_cmds"; then
    glpi_console plugin:resume_execution --no-interaction >/dev/null 2>&1 || true
  fi
  [[ -n $inv_ver ]] && { plugin_enable glpiinventory && log "GLPI Inventory $inv_ver instalado/atualizado e ativo" || warn "Falha ao ativar o GLPI Inventory."; }
  [[ -n $cas_ver ]] && { plugin_enable Cascater && log "Cascater $cas_ver instalado/atualizado e ativo" || warn "Falha ao ativar o Cascater."; }
  if [[ -n $termo_ver ]]; then
    if plugin_enable assetterms; then
      log "Asset Terms $termo_ver instalado/atualizado e ativo"
      remove_old_term_plugin
    else
      warn "Falha ao ativar o Asset Terms."
    fi
  fi
  [[ -n $chat_ver ]] && { plugin_enable glpichatbot && log "GLPI Chatbot $chat_ver instalado/atualizado e ativo" || warn "Falha ao ativar o GLPI Chatbot."; }

  glpi_console maintenance:disable --no-interaction >/dev/null 2>&1 || true
  glpi_console cache:clear --no-interaction >/dev/null 2>&1 || true

  echo
  ask_yn UPDATE_APPLY_TEMPLATES "Deseja cadastrar os modelos de atendimento (5 de acompanhamento e 5 de solução/encerramento)?" S
  if [[ $UPDATE_APPLY_TEMPLATES == S ]]; then
    create_followup_and_solution_templates
  fi

  ask_yn UPDATE_APPLY_INVENTORY "Deseja aplicar as melhores práticas de inventário (status padrão 'Em uso' e ignorar ruídos/KBs de software)?" S
  if [[ $UPDATE_APPLY_INVENTORY == S ]]; then
    configure_inventory_best_practices
  fi

  ask_yn UPDATE_APPLY_ITIL "Deseja aplicar a matriz ITIL (4 prioridades) e SLAs de atendimento nesta base?" N
  if [[ $UPDATE_APPLY_ITIL == S ]]; then
    if [[ -n $(db_glpi -N -e "SELECT id FROM glpi_slms WHERE name = 'Níveis de serviço (ITIL)' LIMIT 1") ]]; then
      log "Prioridades e SLAs do instalador já existem nesta base; nada foi alterado."
    else
      # Mesmos padrões da instalação nova; dá para mudar pelo arquivo de configuração
      SIMPLIFY_PRIORITIES=S
      BUSINESS_HOURS=${BUSINESS_HOURS:-08:00-18:00}
      BUSINESS_SATURDAY=${BUSINESS_SATURDAY:-N}
      SATURDAY_HOURS=${SATURDAY_HOURS:-08:00-12:00}
      ADD_HOLIDAYS=${ADD_HOLIDAYS:-S}
      configure_priorities
      [[ ${LINK_URGENCY_IMPACT:-S} == S ]] && create_link_rules >/dev/null
      create_sla_ola >/dev/null
      log "Prioridades ITIL, SLAs e OLAs configurados (atendimento seg-sex $BUSINESS_HOURS)"
    fi
  fi

  if [[ -d /etc/cron.d && ! -f /etc/cron.d/glpi ]]; then
    echo "* * * * * www-data /usr/bin/php $old/front/cron.php >/dev/null 2>&1" >/etc/cron.d/glpi
    chmod 644 /etc/cron.d/glpi
  fi

  echo
  info "Situação dos plugins:"
  glpi_console plugin:list 2>/dev/null | sed 's/^/    /' || true
  local port
  if [[ $WEB_SERVER == nginx ]]; then
    port=$(cat "${NGINX_CONF:-/dev/null}" 2>/dev/null | grep -m1 -oP '^\s*listen\s+(\S+:)?\K[0-9]+' || true)
  else
    port=$(cat /etc/apache2/sites-enabled/*.conf 2>/dev/null | grep -m1 -oP '<VirtualHost \*:\K[0-9]+' || true)
  fi
  status=$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 "http://127.0.0.1:${port:-80}/" || true)
  echo
  echo "${C_G}${C_W}  Atualização concluída: GLPI $EXISTING_VERSION -> $GLPI_VERSION${C_N}"
  echo "  Resposta HTTP local ..: $status"
  echo "  Backup ...............: $backup"
  echo "  Como voltar ..........: $backup/COMO-VOLTAR.txt"
  [[ -n ${prev:-} ]] && echo "  Versão anterior ......: $prev (apague depois de validar)"
  echo "  Plugins marcados como 'Para atualizar' ou 'Não instalado' acima precisam de uma versão"
  echo "  compatível com o GLPI $GLPI_VERSION (veja Configurar > Plugins > Marketplace)."
  echo "  Log completo: $LOG_FILE"
  exit 0
}

# --- Grupos, perfis e regras de acesso ---------------------------------------
# Direitos de chamado (bits do GLPI): READMY=1 UPDATE=2 CREATE=4 DELETE=8
# READGROUP=2048 READASSIGN=4096 ASSIGN=8192 STEAL=16384 OWN=32768
# CHANGEPRIORITY=65536 SURVEY=131072. Nenhum perfil novo recebe READALL (1024)
# nem READNEWTICKET (262144): só o Super-Admin vê todos os chamados.
readonly RIGHTS_TICKET_ATTENDANT=249863   # meus + atribuídos a mim/meu grupo, assumir, prioridade
readonly RIGHTS_TICKET_MANAGER=260111     # atendente + abertos pela equipe, atribuir, excluir
readonly RIGHTS_TICKET_TEAM_MANAGER=2053  # autoatendimento + abertos pela equipe
# Módulos mantidos nos perfis das áreas que não são TI (sem inventário)
readonly AREA_PROFILE_RIGHTS="'document','followup','group','knowbase','password_update','personalization','pendingreason','planning','reminder_public','rssfeed_public','task','ticket','ticketvalidation','user'"

# Cria um grupo na entidade raiz (recursivo) e devolve o id
create_group() { # create_group nome atende(0/1)
  local q; q=$(sql_escape "$1")
  db_glpi -N -e "INSERT INTO glpi_groups
      (entities_id, is_recursive, name, completename, level, groups_id,
       is_requester, is_watcher, is_assign, is_task, is_notify, is_itemgroup, is_usergroup, is_manager,
       date_creation, date_mod)
    VALUES (0, 1, '$q', '$q', 1, 0, 1, 1, $2, $2, 1, 0, 1, 1, NOW(), NOW());
    SELECT LAST_INSERT_ID();"
}

# Copia um perfil existente (todas as colunas e direitos) e devolve o id do novo
clone_profile() { # clone_profile perfil_origem nome comentario
  local cols src id
  src=$(db_glpi -N -e "SELECT id FROM glpi_profiles WHERE name = '$(sql_escape "$1")' LIMIT 1")
  [[ -n $src ]] || return 1
  cols=$(db_glpi -N -e "SELECT GROUP_CONCAT(CONCAT('\`', column_name, '\`'))
      FROM information_schema.columns WHERE table_schema = DATABASE() AND table_name = 'glpi_profiles'
      AND column_name NOT IN ('id', 'name', 'comment', 'is_default', 'date_mod', 'date_creation')")
  id=$(db_glpi -N -e "INSERT INTO glpi_profiles (name, comment, is_default, date_mod, date_creation, $cols)
      SELECT '$(sql_escape "$2")', '$(sql_escape "$3")', 0, NOW(), NOW(), $cols FROM glpi_profiles WHERE id = $src;
    SELECT LAST_INSERT_ID();")
  db_glpi -e "INSERT INTO glpi_profilerights (profiles_id, name, rights)
      SELECT $id, name, rights FROM glpi_profilerights WHERE profiles_id = $src;"
  echo "$id"
}

set_rights() { # set_rights perfil_id "nome=valor nome=valor ..."
  local pair
  for pair in $2; do
    db_glpi -e "UPDATE glpi_profilerights SET rights = ${pair#*=} WHERE profiles_id = $1 AND name = '${pair%%=*}';"
  done
}

# Regra de negócio: requerente que faz parte do grupo -> grupo entra como requerente
create_requester_group_rule() { # create_requester_group_rule grupo_id nome
  local rid ranking uuid
  ranking=$(db_glpi -N -e "SELECT COALESCE(MAX(ranking), 0) + 1 FROM glpi_rules WHERE sub_type = 'RuleTicket'")
  uuid=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || openssl rand -hex 16)
  rid=$(db_glpi -N -e "INSERT INTO glpi_rules
      (entities_id, sub_type, ranking, name, description, \`match\`, is_active, comment, is_recursive, uuid, \`condition\`, date_creation, date_mod)
    VALUES (0, 'RuleTicket', $ranking, '$(sql_escape "Grupo requerente: $2")',
      'Criada pelo instalador: chamados abertos por membros do grupo ficam visíveis para o gestor da equipe',
      'AND', 1, '', 1, '$uuid', 1, NOW(), NOW());
    SELECT LAST_INSERT_ID();")
  db_glpi -e "INSERT INTO glpi_rulecriterias (rules_id, criteria, \`condition\`, pattern) VALUES ($rid, '_groups_id_of_requester', 0, '$1');
              INSERT INTO glpi_ruleactions (rules_id, action_type, field, value) VALUES ($rid, 'append', '_groups_id_requester', '$1');"
}

# Monta grupos de atendimento, perfis e regras. Usa: SELECTED_AREAS, TEAMS (array)
create_access_structure() {
  local area team gid pid groups=0 profiles=0 qa
  local -A GROUP_IDS=()
  local -a areas=()
  IFS=',' read -ra areas <<<"$SELECTED_AREAS"

  for area in "${areas[@]}"; do
    GROUP_IDS[$area]=$(create_group "$area" 1); groups=$((groups + 1))
    # Categorias da área passam a ter o grupo como responsável (atribuição automática)
    qa=$(sql_escape "$area")
    db_glpi -e "UPDATE glpi_itilcategories SET groups_id = ${GROUP_IDS[$area]}
                WHERE completename = '$qa' OR LEFT(completename, CHAR_LENGTH('$qa > ')) = '$qa > ';"
  done
  for team in "${TEAMS[@]}"; do
    GROUP_IDS[$team]=$(create_group "$team" 0); groups=$((groups + 1))
  done
  for gid in "${!GROUP_IDS[@]}"; do
    create_requester_group_rule "${GROUP_IDS[$gid]}" "$gid"
  done

  # Atribuição automática: primeiro pela categoria, depois pelo item
  db_glpi -e "UPDATE glpi_entities SET auto_assign_mode = 2 WHERE id = 0;"

  if [[ ",$SELECTED_AREAS," == *",TI,"* ]]; then
    pid=$(clone_profile Technician "Técnico de TI" "Atende chamados atribuídos a ele ou ao grupo TI. Acesso ao inventário.")
    set_rights "$pid" "ticket=$RIGHTS_TICKET_ATTENDANT"; profiles=$((profiles + 1))
    pid=$(clone_profile Supervisor "Gestor de TI" "Técnico de TI + chamados abertos pela equipe, atribuição e estatísticas.")
    set_rights "$pid" "ticket=$RIGHTS_TICKET_MANAGER"; profiles=$((profiles + 1))
  fi

  pid=$(clone_profile Technician "Atendente de Área" "Atende chamados atribuídos a ele ou ao grupo da sua área (RH, Financeiro...). Sem inventário.")
  db_glpi -e "UPDATE glpi_profilerights SET rights = 0 WHERE profiles_id = $pid AND name NOT IN ($AREA_PROFILE_RIGHTS);"
  set_rights "$pid" "ticket=$RIGHTS_TICKET_ATTENDANT user=1 group=1"; profiles=$((profiles + 1))

  pid=$(clone_profile Technician "Gestor de Área" "Atendente de Área + chamados abertos pela equipe, atribuição e estatísticas.")
  db_glpi -e "UPDATE glpi_profilerights SET rights = 0 WHERE profiles_id = $pid AND name NOT IN ($AREA_PROFILE_RIGHTS, 'statistic', 'reports');"
  set_rights "$pid" "ticket=$RIGHTS_TICKET_MANAGER user=1 group=1 statistic=1 reports=1 ticketvalidation=15376"; profiles=$((profiles + 1))

  pid=$(clone_profile Self-Service "Gestor de Equipe" "Autoatendimento + chamados abertos pelos membros dos seus grupos.")
  set_rights "$pid" "ticket=$RIGHTS_TICKET_TEAM_MANAGER"; profiles=$((profiles + 1))

  echo "$groups $profiles"
}

db_admin() { mysql --defaults-extra-file="$ADMIN_CNF" "$@"; }
db_glpi()  { mysql --defaults-extra-file="$GLPI_CNF" "$DB_NAME" "$@"; }
glpi_console() { runuser -u www-data -- php "$GLPI_DIR/bin/console" "$@"; }

distro_php_version() {
  apt-cache depends php-cli 2>/dev/null | grep -oE 'php[0-9]+\.[0-9]+-cli' | head -n1 | grep -oE '[0-9]+\.[0-9]+' || true
}

add_php_repo() {
  info "Adicionando repositório PHP de terceiros (Ondřej Surý)..."
  if [[ $OS_ID == ubuntu ]]; then
    apt-get install -y -qq software-properties-common >/dev/null
    add-apt-repository -y ppa:ondrej/php >/dev/null
  else
    local deb=/tmp/debsuryorg-archive-keyring.deb
    TMP_FILES+=("$deb")
    curl -fsSLo "$deb" https://packages.sury.org/debsuryorg-archive-keyring.deb
    dpkg -i "$deb" >/dev/null
    echo "deb [signed-by=/usr/share/keyrings/debsuryorg-archive-keyring.gpg] https://packages.sury.org/php/ $OS_CODENAME main" \
      >/etc/apt/sources.list.d/php-sury.list
  fi
  apt-get update -qq
}

# Instala/ajusta Apache + PHP (versão exigida pelo GLPI alvo) e o php.ini recomendado
# WEB_SERVER=apache: Apache + mod_php | WEB_SERVER=nginx: Nginx + PHP-FPM (define PHP_FPM_SOCK)
setup_php_web() {
local m mod d sapi ext

PHP_VER=$(distro_php_version)
if [[ -z $PHP_VER ]] || ! version_ge "$PHP_VER" "$PHP_MIN"; then
  warn "PHP da distribuição (${PHP_VER:-nenhum}) é inferior ao exigido ($PHP_MIN)."
  add_php_repo
  PHP_VER="8.3"
fi
log "Versão do PHP escolhida: $PHP_VER"

PHP_EXTS=(cli common mysql curl gd intl mbstring xml zip bz2 ldap bcmath apcu opcache)
if [[ $WEB_SERVER == nginx ]]; then
  PKGS=(nginx "php$PHP_VER-fpm")
else
  PKGS=(apache2 "libapache2-mod-php$PHP_VER")
fi
for ext in "${PHP_EXTS[@]}"; do
  if pkg_exists "php$PHP_VER-$ext"; then PKGS+=("php$PHP_VER-$ext")
  elif pkg_exists "php-$ext"; then PKGS+=("php-$ext")
  else warn "Pacote da extensão PHP '$ext' não encontrado (ignorado)."
  fi
done
info "Instalando: ${PKGS[*]}"
apt-get install -y -qq "${PKGS[@]}" >/dev/null

if [[ -x /usr/bin/php$PHP_VER ]]; then update-alternatives --set php "/usr/bin/php$PHP_VER" >/dev/null 2>&1 || true; fi

if [[ $WEB_SERVER == nginx ]]; then
  PHP_FPM_SOCK="/run/php/php$PHP_VER-fpm.sock"
  systemctl enable --now "php$PHP_VER-fpm" >/dev/null 2>&1
  systemctl enable nginx >/dev/null 2>&1
else
  # Garante que somente o mod_php da versão escolhida está ativo
  for m in /etc/apache2/mods-enabled/php*.load; do
    [[ -e $m ]] || continue
    mod=$(basename "$m" .load)
    [[ $mod == "php$PHP_VER" ]] || a2dismod -q "$mod" >/dev/null
  done
  a2dismod -q mpm_event >/dev/null 2>&1 || true
  a2enmod -q mpm_prefork "php$PHP_VER" rewrite headers >/dev/null
fi

# Validação das extensões (lista do RequirementsManager do GLPI)
PHP_MODS=$(php -m)
REQUIRED_EXTS=(curl dom fileinfo filter gd intl libxml mbstring mysqli openssl session simplexml tokenizer xmlreader xmlwriter zlib)
(( GLPI_MAJOR >= 11 )) && REQUIRED_EXTS+=(bcmath sodium)
MISSING=()
for ext in "${REQUIRED_EXTS[@]}"; do
  grep -qix "$ext" <<<"$PHP_MODS" || MISSING+=("$ext")
done
(( ${#MISSING[@]} == 0 )) || die "Extensões PHP obrigatórias ausentes: ${MISSING[*]}"
for ext in bz2 exif ldap Phar zip ctype iconv apcu "Zend OPcache"; do
  grep -qix "$ext" <<<"$PHP_MODS" || warn "Extensão PHP opcional ausente: $ext"
done
log "PHP $(php -r 'echo PHP_VERSION;') com todas as extensões obrigatórias"

# php.ini recomendado para o GLPI
for sapi in apache2 fpm cli; do
  d="/etc/php/$PHP_VER/$sapi/conf.d"
  [[ -d $d ]] || continue
  cat >"$d/99-glpi.ini" <<EOF
; Gerado por install-glpi.sh
memory_limit = 512M
upload_max_filesize = 64M
post_max_size = 64M
max_execution_time = 600
max_input_vars = 5000
file_uploads = On
session.use_strict_mode = 1
session.cookie_httponly = On
session.cookie_samesite = Lax
date.timezone = $GLPI_TZ
opcache.enable = 1
opcache.enable_cli = 0
opcache.memory_consumption = 128
opcache.interned_strings_buffer = 16
opcache.max_accelerated_files = 20000
opcache.revalidate_freq = 60
EOF
done
log "php.ini ajustado (/etc/php/$PHP_VER/*/conf.d/99-glpi.ini)"
[[ $WEB_SERVER == nginx ]] && systemctl restart "php$PHP_VER-fpm"
return 0
}

# Configuração Nginx recomendada pela documentação do GLPI (root em /public,
# tudo roteado para index.php, só o index.php vai para o PHP-FPM).
# nginx_glpi_server <porta> <server_name> <diretório_glpi> [linhas extras: listen/ssl preservados]
nginx_glpi_server() {
  local port=$1 name=$2 dir=$3 extra=${4:-}
  cat <<EOF
# Gerado por install-glpi.sh em $(date '+%F %T')
server {
$(if [[ -n $extra ]]; then printf '%s\n' "$extra"; else printf '    listen %s;\n' "$port"; fi)
    server_name $name;

    root $dir/public;
    index index.php;

    client_max_body_size 64M;
    server_tokens off;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "SAMEORIGIN" always;

    location / {
        try_files \$uri /index.php\$is_args\$args;
    }

    location ~ ^/index\.php\$ {
        fastcgi_pass unix:$PHP_FPM_SOCK;
        fastcgi_split_path_info ^(.+\.php)(/.*)\$;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_read_timeout 600;
    }

    access_log /var/log/nginx/glpi_access.log;
    error_log  /var/log/nginx/glpi_error.log;
}
EOF
}

# Atualização com Nginx: garante a configuração do GLPI 11 (root em /public e roteamento
# pelo index.php) e aponta o fastcgi_pass para o PHP-FPM atual. Faz backup e valida com nginx -t.
# Chamado ANTES de qualquer alteração (modo "check") e depois da troca do código ("apply").
fix_nginx_conf() { # fix_nginx_conf check|apply diretório_glpi carimbo
  local mode=$1 dir=$2 ts=$3 conf real blocks name extra
  NGINX_CONF=""
  for conf in /etc/nginx/sites-enabled/* /etc/nginx/conf.d/*.conf; do
    [[ -f $conf ]] || continue
    grep -qE "^[[:space:]]*root[[:space:]]+\"?$dir(/public)?/?\"?[[:space:]]*;" "$conf" && { NGINX_CONF=$(readlink -f "$conf"); break; }
  done
  [[ -n $NGINX_CONF ]] || { [[ $mode == check ]] && die "Nenhuma configuração do Nginx com 'root $dir' foi encontrada em /etc/nginx/sites-enabled ou conf.d."; return 0; }
  NGINX_COMPATIBLE=0
  if grep -qE "^[[:space:]]*root[[:space:]]+\"?$dir/public/?\"?[[:space:]]*;" "$NGINX_CONF" \
     && grep -qE 'try_files[[:space:]]+\$uri[[:space:]]+/index\.php' "$NGINX_CONF"; then
    NGINX_COMPATIBLE=1
  fi
  blocks=$(grep -cE '^[[:space:]]*server[[:space:]]*\{' "$NGINX_CONF" || true)

  if [[ $mode == check ]]; then
    if (( GLPI_MAJOR >= 11 && ! NGINX_COMPATIBLE && blocks != 1 )); then
      warn "O arquivo $NGINX_CONF tem $blocks blocos 'server' e não pode ser ajustado automaticamente com segurança."
      echo "  Ajuste o bloco do GLPI para ficar assim e rode o script de novo:"
      nginx_glpi_server 80 "seu.servidor" "$dir" | sed 's/^/    /'
      die "Atualização cancelada antes de qualquer alteração."
    fi
    return 0
  fi

  cp -a "$NGINX_CONF" "$NGINX_CONF.bak-$ts"
  if (( GLPI_MAJOR >= 11 && ! NGINX_COMPATIBLE )); then
    # Regenera o bloco preservando portas (listen), server_name e certificados SSL
    name=$(grep -m1 -oP '^\s*server_name\s+\K[^;]+' "$NGINX_CONF" || echo "_")
    extra=$(grep -E '^[[:space:]]*(listen|ssl_[a-z_]+|http2)[[:space:]]' "$NGINX_CONF" | sed -E 's/^[[:space:]]*/    /' || true)
    nginx_glpi_server 80 "$name" "$dir" "$extra" >"$NGINX_CONF"
    log "Nginx: bloco do GLPI regenerado para o GLPI 11 ($NGINX_CONF; backup em $NGINX_CONF.bak-$ts)"
  else
    # Já compatível: só aponta o fastcgi_pass para o PHP-FPM atual
    sed -i -E "s#fastcgi_pass[[:space:]]+unix:[^;]*php[^;]*\.sock;#fastcgi_pass unix:$PHP_FPM_SOCK;#" "$NGINX_CONF"
    grep -qE 'fastcgi_pass[[:space:]]+(127\.0\.0\.1|localhost):' "$NGINX_CONF" \
      && warn "O fastcgi_pass usa TCP; confira se o PHP-FPM $PHP_VER escuta nesse endereço."
    log "Nginx: configuração já compatível; PHP-FPM apontado para $PHP_FPM_SOCK"
  fi
  if ! nginx -t >/dev/null 2>&1; then
    mv "$NGINX_CONF.bak-$ts" "$NGINX_CONF"
    nginx -t || true
    die "A configuração do Nginx ficou inválida e foi restaurada. Veja a mensagem acima."
  fi
  systemctl reload nginx
}

# Qual servidor web atende o GLPI instalado em <dir>: imprime apache, nginx ou nada
detect_web_server() {
  local dir=$1
  if command -v nginx >/dev/null 2>&1 \
     && grep -rqsE "^[[:space:]]*root[[:space:]]+\"?$dir(/public)?/?\"?[[:space:]]*;" /etc/nginx/sites-enabled /etc/nginx/conf.d; then
    echo nginx; return 0
  fi
  if command -v apache2ctl >/dev/null 2>&1 \
     && grep -rqsE "DocumentRoot[[:space:]]+\"?$dir(/public)?/?\"?[[:space:]]*$" /etc/apache2/sites-enabled; then
    echo apache; return 0
  fi
  if systemctl is-active --quiet nginx 2>/dev/null; then echo nginx
  elif systemctl is-active --quiet apache2 2>/dev/null; then echo apache
  fi
  return 0
}

# -----------------------------------------------------------------------------
# 0. Verificações iniciais
# -----------------------------------------------------------------------------
case "${1-}" in
  -h|--help)
    sed -n '3,46p' "$0" | sed 's/^# \{0,1\}//'
    exit 0 ;;
  "") ;;
  *)
    [[ -r $1 ]] || die "Arquivo de configuração '$1' não encontrado."
    # shellcheck disable=SC1090
    . "$1"
    echo "Configuração carregada de: $1" ;;
esac
# Nome antigo da opção do plugin de termos (antes do Asset Terms)
if [[ -n ${INSTALL_TERMORESPONSABILIDADE+x} && -z ${INSTALL_ASSETTERMS+x} ]]; then
  INSTALL_ASSETTERMS=$INSTALL_TERMORESPONSABILIDADE
fi

[[ $EUID -eq 0 ]] || die "Execute como root: sudo bash $0"
[[ -r /dev/tty || -n "${CONFIRM-}" ]] || die "Sem terminal interativo. Defina as variáveis de ambiente (veja o cabeçalho)."

mkdir -p "$(dirname "$LOG_FILE")"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "${C_W}"
echo "  ============================================================"
echo "     Instalador automatizado do GLPI  -  v$SCRIPT_VERSION"
echo "  ============================================================${C_N}"
echo "  Log: $LOG_FILE"

title "1/11 Verificando pré-requisitos do sistema"

[[ -r /etc/os-release ]] || die "Não foi possível identificar o sistema operacional."
# shellcheck disable=SC1091
. /etc/os-release
OS_ID=${ID,,}
OS_LIKE=${ID_LIKE:-}
OS_CODENAME=${VERSION_CODENAME:-}
OS_VER=${VERSION_ID:-0}

case "$OS_ID" in
  debian) version_ge "$OS_VER" 11 || die "Debian $OS_VER não suportado (mínimo 11)." ;;
  ubuntu) version_ge "$OS_VER" 22.04 || die "Ubuntu $OS_VER não suportado (mínimo 22.04)." ;;
  *)
    if [[ $OS_LIKE == *ubuntu* ]]; then OS_ID=ubuntu; OS_CODENAME=${UBUNTU_CODENAME:-$OS_CODENAME}
    elif [[ $OS_LIKE == *debian* ]]; then OS_ID=debian
    else die "Sistema '$PRETTY_NAME' não suportado. Use Debian 11+ ou Ubuntu 22.04+."
    fi ;;
esac
[[ -n $OS_CODENAME ]] || OS_CODENAME=$(lsb_release -sc 2>/dev/null || true)
log "Sistema: $PRETTY_NAME ($OS_CODENAME)"

ARCH=$(uname -m)
[[ $ARCH == x86_64 || $ARCH == aarch64 ]] || warn "Arquitetura $ARCH não testada."

DISK_FREE_MB=$(df -Pm /var | awk 'NR==2 {print $4}')
(( DISK_FREE_MB >= MIN_DISK_MB )) || die "Espaço livre em /var insuficiente: ${DISK_FREE_MB}MB (mínimo ${MIN_DISK_MB}MB)."
log "Espaço livre em /var: ${DISK_FREE_MB}MB"

MEM_MB=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)
(( MEM_MB >= 1024 )) || warn "Memória RAM baixa (${MEM_MB}MB). Recomendado: 2GB ou mais."
log "Memória RAM: ${MEM_MB}MB"

info "Testando acesso à internet..."
curl -fsS --max-time 15 -o /dev/null https://api.github.com 2>/dev/null \
  || wget -q --spider --timeout=15 https://api.github.com 2>/dev/null \
  || die "Sem acesso a https://api.github.com. Verifique internet/proxy/DNS."
log "Acesso à internet OK"

title "2/11 Instalando ferramentas básicas"
apt-get update -qq
apt-get install -y -qq curl wget ca-certificates gnupg lsb-release tar bzip2 \
  jq unzip cron openssl apt-transport-https >/dev/null
log "Ferramentas básicas instaladas"

# -----------------------------------------------------------------------------
# 1. Descobrindo a última versão estável
# -----------------------------------------------------------------------------
title "3/11 Consultando a última versão estável do GLPI"
if [[ -z "${GLPI_VERSION-}" ]]; then
  REL_JSON=$(curl -fsSL -H 'Accept: application/vnd.github+json' \
    https://api.github.com/repos/glpi-project/glpi/releases/latest) \
    || die "Falha ao consultar a API do GitHub."
  GLPI_VERSION=$(jq -r '.tag_name // empty' <<<"$REL_JSON")
  GLPI_URL_TGZ=$(jq -r '[.assets[] | select(.name | test("^glpi-.*\\.tgz$"))][0].browser_download_url // empty' <<<"$REL_JSON")
fi
[[ -n $GLPI_VERSION ]] || die "Não foi possível determinar a versão do GLPI."
GLPI_URL_TGZ=${GLPI_URL_TGZ:-https://github.com/glpi-project/glpi/releases/download/$GLPI_VERSION/glpi-$GLPI_VERSION.tgz}
GLPI_MAJOR=${GLPI_VERSION%%.*}

# Requisitos por versão (documentação oficial do GLPI)
if (( GLPI_MAJOR >= 11 )); then
  PHP_MIN="8.2"; MARIADB_MIN="10.6"; MYSQL_MIN="8.0"
else
  PHP_MIN="7.4"; MARIADB_MIN="10.2"; MYSQL_MIN="5.7"
fi
log "Versão estável mais recente: GLPI $GLPI_VERSION (PHP >= $PHP_MIN, MariaDB >= $MARIADB_MIN / MySQL >= $MYSQL_MIN)"

# -----------------------------------------------------------------------------
# GLPI já instalado? Oferece atualizar mantendo os dados
# -----------------------------------------------------------------------------
EXISTING_DIR=""
for d in "${GLPI_EXISTING_DIR:-}" /var/www/glpi /var/www/html/glpi /usr/share/glpi /var/www/html /srv/glpi; do
  [[ -n $d && -f $d/bin/console && -n $(glpi_version_in "$d") ]] && { EXISTING_DIR=${d%/}; break; }
done
if [[ -n $EXISTING_DIR ]]; then
  EXISTING_VERSION=$(glpi_version_in "$EXISTING_DIR")
  version_ge "$GLPI_VERSION" "$EXISTING_VERSION" || die "O GLPI instalado ($EXISTING_VERSION) é mais novo que o disponível ($GLPI_VERSION)."
  echo
  warn "Encontrado o GLPI $EXISTING_VERSION em $EXISTING_DIR"
  echo "    [A] Atualizar para o $GLPI_VERSION mantendo TODOS os dados (inventário, chamados, usuários) - recomendado"
  echo "    [R] Reinstalar do zero - APAGA todos os dados (as pastas antigas são movidas para .bak)"
  echo "    [C] Cancelar"
  while true; do
    ask INSTALL_MODE "Escolha A, R ou C" "A"
    case ${INSTALL_MODE^^} in A|R|C) INSTALL_MODE=${INSTALL_MODE^^}; break ;; esac
    unset INSTALL_MODE
  done
  [[ $INSTALL_MODE == C ]] && die "Cancelado pelo usuário."

  if [[ $INSTALL_MODE == A ]]; then
    WEB_SERVER=$(detect_web_server "$EXISTING_DIR")
    [[ -n $WEB_SERVER ]] || die "Não identifiquei se o GLPI é servido pelo Apache ou pelo Nginx. Atualize manualmente."
    WEB_SVC=$([[ $WEB_SERVER == nginx ]] && echo nginx || echo apache2)
    log "Servidor web em uso: $WEB_SERVER"
    title "4/9 Configuração da atualização"
    ask GLPI_TZ "Fuso horário (PHP/GLPI)" "America/Sao_Paulo"
    ask_yn INSTALL_GLPIINVENTORY "Instalar/atualizar o plugin GLPI Inventory (descoberta de rede, SNMP, implantação)?" S
    ask_yn INSTALL_CASCATER "Instalar/atualizar o plugin Cascater (seleção de categorias em cascata)?" S
    ask_yn INSTALL_ASSETTERMS "Instalar/atualizar o plugin Asset Terms (termos de entrega e devolução com assinatura na tela)?" S
    ask_yn INSTALL_CHATBOT "Instalar/atualizar o plugin GLPI Chatbot (assistente guiado de abertura de chamados)?" S
    run_upgrade
  fi

  warn "REINSTALAR apaga a base de dados do GLPI: inventário, chamados e usuários serão perdidos."
  ask REINSTALL_CONFIRM "Para confirmar, digite APAGAR" ""
  [[ $REINSTALL_CONFIRM == APAGAR ]] || die "Reinstalação não confirmada. Nada foi alterado."
  [[ $EXISTING_DIR == "$GLPI_DIR" ]] || warn "A nova instalação vai para $GLPI_DIR; a antiga em $EXISTING_DIR não será removida."
fi

# -----------------------------------------------------------------------------
# 2. Perguntas
# -----------------------------------------------------------------------------
title "4/11 Configuração da instalação"
DEFAULT_IP=$(hostname -I 2>/dev/null | awk '{print $1}')

echo "  -- Acesso web --"
while true; do
  ask WEB_SERVER "Servidor web: apache ou nginx" "apache"
  case ${WEB_SERVER,,} in
    a|apache|apache2) WEB_SERVER=apache; break ;;
    n|nginx)          WEB_SERVER=nginx; break ;;
  esac
  warn "Responda apache ou nginx."; unset WEB_SERVER
done
WEB_SVC=$([[ $WEB_SERVER == nginx ]] && echo nginx || echo apache2)
ask GLPI_FQDN "Nome DNS ou IP pelo qual o GLPI será acessado" "${DEFAULT_IP:-localhost}"
while true; do
  ask GLPI_PORT "Porta HTTP" "80"
  [[ $GLPI_PORT =~ ^[0-9]+$ ]] && (( GLPI_PORT >= 1 && GLPI_PORT <= 65535 )) && break
  warn "Porta inválida."; unset GLPI_PORT
done
ask GLPI_LANG "Idioma padrão do GLPI" "pt_BR"
ask GLPI_TZ   "Fuso horário (PHP/GLPI)" "America/Sao_Paulo"
[[ -e /usr/share/zoneinfo/$GLPI_TZ ]] || warn "Fuso '$GLPI_TZ' não encontrado em /usr/share/zoneinfo."

echo
echo "  -- Banco de dados --"
ask_yn DB_LOCAL "Instalar/usar MariaDB LOCAL neste servidor?" S
if [[ $DB_LOCAL == S ]]; then
  DB_HOST=${DB_HOST:-localhost}; DB_PORT=${DB_PORT:-3306}
else
  ask DB_HOST "Endereço do servidor de banco" ""
  [[ -n $DB_HOST ]] || die "Endereço do banco é obrigatório."
  ask DB_PORT "Porta do banco" "3306"
fi

ask DB_ADMIN_USER "Usuário ADMINISTRADOR do banco (para criar base/usuário)" "root"
if [[ $DB_LOCAL == S && $DB_ADMIN_USER == root ]]; then
  ask_secret DB_ADMIN_PASS "Senha do '$DB_ADMIN_USER' (Enter = autenticação unix_socket do root local)" 1 0
else
  ask_secret DB_ADMIN_PASS "Senha do '$DB_ADMIN_USER'" 0 0
fi

while true; do
  ask DB_NAME "Nome da base de dados do GLPI" "glpi"
  valid_ident "$DB_NAME" && break; warn "Use apenas letras, números e _"; unset DB_NAME
done
while true; do
  ask DB_USER "Usuário da aplicação no banco" "glpi"
  valid_ident "$DB_USER" && break; warn "Use apenas letras, números e _"; unset DB_USER
done
if [[ $DB_LOCAL == S ]]; then
  DB_USER_HOST=${DB_USER_HOST:-localhost}
else
  ask DB_USER_HOST "Host de origem permitido para '$DB_USER' (IP deste servidor ou %)" "${DEFAULT_IP:-%}"
fi
ask_secret DB_PASS "Senha do usuário '$DB_USER' (Enter = gerar automaticamente)" 1 1
DB_PASS_GENERATED=N
if [[ -z $DB_PASS ]]; then DB_PASS=$(gen_pass); DB_PASS_GENERATED=S; fi

echo
echo "  -- Primeiro acesso ao GLPI --"
ask_secret GLPI_ADMIN_PASS "Nova senha do super-admin 'glpi' (Enter = gerar automaticamente)" 1 1
GLPI_ADMIN_PASS_GENERATED=N
if [[ -z $GLPI_ADMIN_PASS ]]; then GLPI_ADMIN_PASS=$(gen_pass); GLPI_ADMIN_PASS_GENERATED=S; fi
ask_yn DISABLE_DEFAULT_USERS "Desativar os usuários padrão tech, normal e post-only?" S

echo
echo "  -- Estrutura da empresa (entidades) --"
ask GLPI_ROOT_ENTITY "Nome da matriz / empresa (entidade principal)" "Matriz"
GLPI_ROOT_ENTITY=$(trim "$GLPI_ROOT_ENTITY")
if [[ -z ${GLPI_BRANCHES+x} ]]; then
  while true; do
    ask BRANCH_COUNT "Quantas filiais a empresa possui? (0 = nenhuma)" "0"
    [[ $BRANCH_COUNT =~ ^[0-9]+$ ]] && (( BRANCH_COUNT <= 200 )) && break
    warn "Informe um número entre 0 e 200."; unset BRANCH_COUNT
  done
  GLPI_BRANCHES=""
  for (( n = 1; n <= BRANCH_COUNT; n++ )); do
    unset BRANCH_NAME
    ask BRANCH_NAME "Nome da filial $n" "Filial $n"
    GLPI_BRANCHES+="${GLPI_BRANCHES:+;}$BRANCH_NAME"
  done
fi
# Lista final de filiais (separadas por ";"), sem vazios nem repetidas
BRANCHES=()
IFS=';' read -ra __branches <<<"$GLPI_BRANCHES"
for b in "${__branches[@]}"; do
  b=$(trim "$b")
  [[ -z $b ]] && continue
  [[ ${#b} -le 100 ]] || die "Nome de filial muito longo: $b"
  for existing in "$GLPI_ROOT_ENTITY" "${BRANCHES[@]}"; do
    [[ ${existing,,} == "${b,,}" ]] && die "Nome de entidade repetido: $b"
  done
  BRANCHES+=("$b")
done

echo
echo "  -- Categorias, grupos de atendimento e permissões --"
ask_yn CREATE_CATEGORIES "Criar o catálogo padrão de categorias (TI, RH, Financeiro, Marketing)?" S
ask_yn CREATE_ACCESS "Criar grupos de atendimento por área e perfis de acesso (cada área vê só os seus chamados)?" S
SELECTED_AREAS=""
if [[ $CREATE_CATEGORIES == S || $CREATE_ACCESS == S ]]; then
  while true; do
    ask CATEGORY_AREAS "Áreas a criar, separadas por vírgula" "$CATEGORY_AREAS_AVAILABLE"
    SELECTED_AREAS=""; invalid=""
    IFS=',' read -ra __areas <<<"$CATEGORY_AREAS"
    for a in "${__areas[@]}"; do
      a=$(trim "$a"); [[ -z $a ]] && continue
      match=""
      IFS=',' read -ra __avail <<<"$CATEGORY_AREAS_AVAILABLE"
      for v in "${__avail[@]}"; do [[ ${v,,} == "${a,,}" ]] && match=$v; done
      if [[ -n $match ]]; then
        [[ ",$SELECTED_AREAS," == *",$match,"* ]] || SELECTED_AREAS+="${SELECTED_AREAS:+,}$match"
      else
        invalid+=" $a"
      fi
    done
    [[ -z $invalid && -n $SELECTED_AREAS ]] && break
    warn "Área(s) inválida(s):${invalid:- nenhuma informada}. Opções: $CATEGORY_AREAS_AVAILABLE"
    unset CATEGORY_AREAS
  done

  # Departamentos extras que também ATENDEM chamados (grupo + categorias básicas)
  while true; do
    ask EXTRA_AREAS "Outros departamentos que ATENDEM chamados, além dos padrão (ex.: Jurídico, Compras, Facilities). Enter = nenhum" ""
    EXTRA_OK=""; bad=""
    IFS=',' read -ra __extra <<<"$EXTRA_AREAS"
    for x in "${__extra[@]}"; do
      x=$(trim "$x"); [[ -z $x ]] && continue
      if [[ $x == *[\>\|\;]* || ${#x} -gt 60 ]]; then bad+=" '$x' (sem > | ; e até 60 caracteres)"; continue; fi
      IFS=',' read -ra __known <<<"$CATEGORY_AREAS_AVAILABLE,$SELECTED_AREAS,$EXTRA_OK"
      dup=""; for k in "${__known[@]}"; do [[ -n $k && ${k,,} == "${x,,}" ]] && dup=1; done
      if [[ -n $dup ]]; then bad+=" '$x' (repetido ou já é padrão)"; continue; fi
      EXTRA_OK+="${EXTRA_OK:+,}$x"
    done
    [[ -z $bad ]] && break
    warn "Departamento(s) inválido(s):$bad"
    unset EXTRA_AREAS
  done
  [[ -n $EXTRA_OK ]] && SELECTED_AREAS+="${SELECTED_AREAS:+,}$EXTRA_OK"
fi

# Equipes que só abrem chamados (ex.: Comercial). Seus gestores veem os chamados da equipe.
TEAMS=()
if [[ $CREATE_ACCESS == S ]]; then
  ask TEAM_GROUPS "Outras equipes/departamentos que abrem chamados, separados por vírgula (Enter = nenhum)" ""
  IFS=',' read -ra __teams <<<"$TEAM_GROUPS"
  for t in "${__teams[@]}"; do
    t=$(trim "$t"); [[ -z $t ]] && continue
    [[ ${#t} -le 100 ]] || die "Nome de equipe muito longo: $t"
    IFS=',' read -ra __sel <<<"$SELECTED_AREAS"
    for existing in "${__sel[@]}" "${TEAMS[@]}"; do
      [[ ${existing,,} == "${t,,}" ]] && die "Grupo repetido: $t (as áreas já viram grupos automaticamente)"
    done
    TEAMS+=("$t")
  done
fi

echo
echo "  -- Prioridades, SLA e OLA (ITIL) --"
ask_yn SIMPLIFY_PRIORITIES "Usar 4 níveis de prioridade (Baixa, Média, Alta, Muito alta) com a matriz ITIL?" S
ask_yn LINK_URGENCY_IMPACT "Atrelar impacto à urgência (o chamado nasce com a prioridade escolhida pelo usuário)?" S
ask_yn CREATE_SLA "Criar SLAs e OLAs por prioridade e vincular automaticamente aos chamados?" S
valid_hours() { # HH:MM-HH:MM com fim depois do início
  [[ $1 =~ ^([01][0-9]|2[0-3]):[0-5][0-9]-([01][0-9]|2[0-3]):[0-5][0-9]$ ]] || return 1
  (( $(hhmm_to_seconds "${1##*-}") > $(hhmm_to_seconds "${1%%-*}") ))
}
if [[ $CREATE_SLA == S ]]; then
  while true; do
    ask BUSINESS_HOURS "Horário de atendimento de segunda a sexta (HH:MM-HH:MM)" "08:00-18:00"
    valid_hours "$BUSINESS_HOURS" && break
    warn "Use o formato 08:00-18:00."; unset BUSINESS_HOURS
  done
  ask_yn BUSINESS_SATURDAY "A equipe atende aos sábados?" N
  if [[ $BUSINESS_SATURDAY == S ]]; then
    while true; do
      ask SATURDAY_HOURS "Horário de sábado (HH:MM-HH:MM)" "08:00-12:00"
      valid_hours "$SATURDAY_HOURS" && break
      warn "Use o formato 08:00-12:00."; unset SATURDAY_HOURS
    done
  fi
  ask_yn ADD_HOLIDAYS "Cadastrar os feriados nacionais de data fixa no calendário?" S
fi

echo
echo "  -- Plugins --"
ask_yn INSTALL_CASCATER "Instalar o plugin Cascater (seleção de categorias em cascata)?" S
ask_yn INSTALL_GLPIINVENTORY "Instalar o plugin GLPI Inventory (descoberta de rede, SNMP, implantação de software)?" S
ask_yn INSTALL_ASSETTERMS "Instalar o plugin Asset Terms (termos de entrega e devolução com assinatura na tela)?" S
ask_yn INSTALL_CHATBOT "Instalar o plugin GLPI Chatbot (assistente guiado de abertura de chamados)?" S

if [[ $GLPI_PORT == 80 ]]; then GLPI_URL="http://$GLPI_FQDN"; else GLPI_URL="http://$GLPI_FQDN:$GLPI_PORT"; fi

echo
echo "  ${C_W}Resumo:${C_N}"
echo "    GLPI ............: $GLPI_VERSION  ->  $GLPI_DIR"
echo "    URL .............: $GLPI_URL"
echo "    Servidor web ....: $WEB_SERVER"
echo "    Idioma / Fuso ...: $GLPI_LANG / $GLPI_TZ"
echo "    Banco ...........: $DB_HOST:$DB_PORT  (local: $DB_LOCAL)"
echo "    Base / Usuário ..: $DB_NAME / $DB_USER@$DB_USER_HOST"
echo "    Admin do banco ..: $DB_ADMIN_USER"
echo "    Matriz ..........: $GLPI_ROOT_ENTITY"
echo "    Filiais .........: ${#BRANCHES[@]}$( (( ${#BRANCHES[@]} )) && printf ' (%s)' "$(IFS=';'; echo "${BRANCHES[*]}" | sed 's/;/, /g')")"
echo "    Categorias ......: $( [[ $CREATE_CATEGORIES == S ]] && echo "${SELECTED_AREAS//,/, }" || echo "não criar")"
echo "    Grupos e perfis .: $( [[ $CREATE_ACCESS == S ]] && echo "${SELECTED_AREAS//,/, }$( (( ${#TEAMS[@]} )) && printf ' + equipes: %s' "$(IFS=','; echo "${TEAMS[*]}" | sed 's/,/, /g')")" || echo "não criar")"
echo "    Prioridades .....: $( [[ $SIMPLIFY_PRIORITIES == S ]] && echo "4 níveis + matriz ITIL" || echo "padrão do GLPI")"
echo "    Impacto=urgência : $( [[ $LINK_URGENCY_IMPACT == S ]] && echo "sim" || echo "não")"
echo "    SLA / OLA .......: $( [[ $CREATE_SLA == S ]] && echo "criar (seg-sex $BUSINESS_HOURS$( [[ $BUSINESS_SATURDAY == S ]] && echo ", sáb $SATURDAY_HOURS"))" || echo "não criar")"
echo "    Plugin Cascater .: $( [[ $INSTALL_CASCATER == S ]] && echo "instalar" || echo "não instalar")"
echo "    GLPI Inventory ..: $( [[ $INSTALL_GLPIINVENTORY == S ]] && echo "instalar" || echo "não instalar")"
echo "    Asset Terms .....: $( [[ $INSTALL_ASSETTERMS == S ]] && echo "instalar" || echo "não instalar")"
echo "    GLPI Chatbot ....: $( [[ $INSTALL_CHATBOT == S ]] && echo "instalar" || echo "não instalar")"
echo
ask_yn CONFIRM "Prosseguir com a instalação?" S
[[ $CONFIRM == S ]] || die "Instalação cancelada pelo usuário."

# -----------------------------------------------------------------------------
# 3. PHP + Apache
# -----------------------------------------------------------------------------
title "5/11 Instalando servidor web ($WEB_SERVER) e PHP"

setup_php_web

# -----------------------------------------------------------------------------
# 4. Banco de dados
# -----------------------------------------------------------------------------
title "6/11 Preparando o banco de dados"

if [[ $DB_LOCAL == S ]]; then
  if ! command -v mariadbd >/dev/null 2>&1 && ! command -v mysqld >/dev/null 2>&1; then
    info "Instalando MariaDB Server..."
    apt-get install -y -qq mariadb-server mariadb-client >/dev/null
  fi
  systemctl enable --now mariadb >/dev/null 2>&1 || systemctl enable --now mysql >/dev/null 2>&1
else
  command -v mysql >/dev/null 2>&1 || apt-get install -y -qq mariadb-client >/dev/null
fi

ADMIN_CNF=$(mktemp); TMP_FILES+=("$ADMIN_CNF")
make_mycnf "$ADMIN_CNF" "$DB_HOST" "$DB_PORT" "$DB_ADMIN_USER" "$DB_ADMIN_PASS"
db_admin -e "SELECT 1" >/dev/null 2>&1 || die "Não foi possível conectar em $DB_HOST:$DB_PORT com o usuário '$DB_ADMIN_USER'."
log "Conexão com o banco como '$DB_ADMIN_USER' OK"

DB_VERSION=$(db_admin -N -e "SELECT VERSION()")
DB_VNUM=$(grep -oE '^[0-9]+\.[0-9]+(\.[0-9]+)?' <<<"$DB_VERSION")
if [[ ${DB_VERSION,,} == *mariadb* ]]; then
  version_ge "$DB_VNUM" "$MARIADB_MIN" || die "MariaDB $DB_VNUM é inferior ao mínimo exigido ($MARIADB_MIN)."
else
  version_ge "$DB_VNUM" "$MYSQL_MIN" || die "MySQL $DB_VNUM é inferior ao mínimo exigido ($MYSQL_MIN)."
fi
log "Servidor de banco: $DB_VERSION"

if [[ $DB_LOCAL == S ]]; then
  # Equivalente ao mysql_secure_installation (sem alterar a autenticação do root)
  db_admin -e "DELETE FROM mysql.global_priv WHERE User='';" 2>/dev/null \
    || db_admin -e "DELETE FROM mysql.user WHERE User='';" 2>/dev/null || true
  db_admin -e "DROP DATABASE IF EXISTS test; FLUSH PRIVILEGES;" 2>/dev/null || true
fi

# Base existente?
DB_TABLES=$(db_admin -N -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='$DB_NAME'")
FORCE_DB=N
if (( DB_TABLES > 0 )); then
  warn "A base '$DB_NAME' já existe e possui $DB_TABLES tabelas."
  ask_yn OVERWRITE "APAGAR o conteúdo da base '$DB_NAME' e reinstalar?" N
  [[ $OVERWRITE == S ]] || die "Instalação cancelada para preservar a base existente."
  FORCE_DB=S
fi

Q_USER="'$(sql_escape "$DB_USER")'@'$(sql_escape "$DB_USER_HOST")'"
Q_PASS="'$(sql_escape "$DB_PASS")'"
db_admin <<SQL
CREATE DATABASE IF NOT EXISTS \`$DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS $Q_USER IDENTIFIED BY $Q_PASS;
ALTER USER $Q_USER IDENTIFIED BY $Q_PASS;
GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO $Q_USER;
GRANT SELECT ON \`mysql\`.\`time_zone_name\` TO $Q_USER;
FLUSH PRIVILEGES;
SQL
log "Base '$DB_NAME' e usuário '$DB_USER@$DB_USER_HOST' prontos"

TZ_COUNT=$(db_admin -N -e "SELECT COUNT(*) FROM mysql.time_zone_name" 2>/dev/null || echo 0)
if (( TZ_COUNT == 0 )); then
  info "Carregando tabelas de fuso horário no banco..."
  TZ_TOOL=$(command -v mariadb-tzinfo-to-sql || command -v mysql_tzinfo_to_sql || true)
  if [[ -n $TZ_TOOL ]] \
     && "$TZ_TOOL" /usr/share/zoneinfo 2>/dev/null | db_admin mysql 2>/dev/null; then
    log "Timezones carregados"
  else
    warn "Não foi possível carregar os timezones (faça manualmente no servidor de banco)."
  fi
fi

GLPI_CNF=$(mktemp); TMP_FILES+=("$GLPI_CNF")
make_mycnf "$GLPI_CNF" "$DB_HOST" "$DB_PORT" "$DB_USER" "$DB_PASS"
db_glpi -e "SELECT 1" >/dev/null 2>&1 || die "O usuário '$DB_USER' não conseguiu conectar na base '$DB_NAME'."

# -----------------------------------------------------------------------------
# 5. Download e arquivos do GLPI
# -----------------------------------------------------------------------------
title "7/11 Baixando e instalando o GLPI $GLPI_VERSION"

TS=$(date +%Y%m%d-%H%M%S)
for d in "$GLPI_DIR" "$GLPI_CONFIG_DIR" "$GLPI_VAR_DIR" "$GLPI_LOG_DIR"; do
  if [[ -e $d ]]; then
    warn "$d já existe -> movido para $d.bak-$TS"
    mv "$d" "$d.bak-$TS"
  fi
done

TGZ=$(mktemp --suffix=.tgz); TMP_FILES+=("$TGZ")
info "Baixando $GLPI_URL_TGZ"
curl -fL --retry 3 --progress-bar -o "$TGZ" "$GLPI_URL_TGZ" || die "Falha no download do GLPI."
tar -tzf "$TGZ" >/dev/null || die "Arquivo baixado está corrompido."
mkdir -p /var/www
tar -xzf "$TGZ" -C /var/www/
[[ -f $GLPI_DIR/bin/console ]] || die "Estrutura inesperada no pacote do GLPI."
log "Arquivos extraídos em $GLPI_DIR"

# Layout seguro (FHS) recomendado pela documentação do GLPI
mkdir -p "$GLPI_CONFIG_DIR" "$GLPI_VAR_DIR" "$GLPI_LOG_DIR"
if [[ -d $GLPI_DIR/files ]];  then cp -a "$GLPI_DIR/files/."  "$GLPI_VAR_DIR/";    rm -rf "$GLPI_DIR/files"; fi
if [[ -d $GLPI_DIR/config ]]; then cp -a "$GLPI_DIR/config/." "$GLPI_CONFIG_DIR/"; rm -rf "$GLPI_DIR/config"; fi
mkdir -p "$GLPI_DIR/marketplace"

cat >"$GLPI_DIR/inc/downstream.php" <<EOF
<?php
define('GLPI_CONFIG_DIR', '$GLPI_CONFIG_DIR/');
if (file_exists(GLPI_CONFIG_DIR . '/local_define.php')) {
    require_once GLPI_CONFIG_DIR . '/local_define.php';
}
EOF

cat >"$GLPI_CONFIG_DIR/local_define.php" <<EOF
<?php
define('GLPI_VAR_DIR', '$GLPI_VAR_DIR');
define('GLPI_LOG_DIR', '$GLPI_LOG_DIR');
EOF

chown -R root:root "$GLPI_DIR"
chown -R www-data:www-data "$GLPI_CONFIG_DIR" "$GLPI_VAR_DIR" "$GLPI_LOG_DIR" "$GLPI_DIR/marketplace"
chmod -R u=rwX,g=rX,o= "$GLPI_CONFIG_DIR" "$GLPI_VAR_DIR" "$GLPI_LOG_DIR"
log "Diretórios: config=$GLPI_CONFIG_DIR  dados=$GLPI_VAR_DIR  logs=$GLPI_LOG_DIR"

# -----------------------------------------------------------------------------
# 6. Apache
# -----------------------------------------------------------------------------
title "8/11 Configurando o servidor web ($WEB_SERVER)"

LISTENERS=$(ss -ltnpH "sport = :$GLPI_PORT" 2>/dev/null || true)
if [[ -n $LISTENERS && $LISTENERS != *"\"$WEB_SVC\""* ]]; then
  die "A porta $GLPI_PORT já está em uso por outro serviço: $LISTENERS"
fi

if [[ $WEB_SERVER == nginx ]]; then
  nginx_glpi_server "$GLPI_PORT" "$GLPI_FQDN" "$GLPI_DIR" >/etc/nginx/sites-available/glpi.conf
  ln -sf /etc/nginx/sites-available/glpi.conf /etc/nginx/sites-enabled/glpi.conf
  [[ $GLPI_PORT == 80 ]] && rm -f /etc/nginx/sites-enabled/default
  nginx -t >/dev/null 2>&1 || { nginx -t; die "Configuração do Nginx inválida."; }
  systemctl enable nginx >/dev/null 2>&1
  systemctl restart nginx
  log "Nginx: site glpi ativo na porta $GLPI_PORT (root $GLPI_DIR/public, PHP-FPM $PHP_FPM_SOCK)"
else

if ! grep -qE "^[[:space:]]*Listen[[:space:]]+([^[:space:]]*:)?$GLPI_PORT([[:space:]]|$)" /etc/apache2/ports.conf; then
  echo "Listen $GLPI_PORT" >>/etc/apache2/ports.conf
fi

if [[ -f $GLPI_DIR/public/index.php ]]; then
  DOCROOT="$GLPI_DIR/public"
  DIR_BLOCK="    <Directory $DOCROOT>
        Require all granted
        RewriteEngine On
        # Repassa o cabeçalho Authorization (API / OAuth)
        RewriteCond %{HTTP:Authorization} ^(.+)\$
        RewriteRule .* - [E=HTTP_AUTHORIZATION:%{HTTP:Authorization}]
        # Todas as requisições passam pelo roteador do GLPI
        RewriteCond %{REQUEST_FILENAME} !-f
        RewriteRule ^(.*)\$ index.php [QSA,L]
    </Directory>"
else
  DOCROOT="$GLPI_DIR"
  DIR_BLOCK="    <Directory $DOCROOT>
        Require all granted
        AllowOverride All
    </Directory>"
fi

cat >/etc/apache2/sites-available/glpi.conf <<EOF
# Gerado por install-glpi.sh em $(date '+%F %T')
<VirtualHost *:$GLPI_PORT>
    ServerName $GLPI_FQDN
    DocumentRoot $DOCROOT

$DIR_BLOCK

    Header always set X-Content-Type-Options "nosniff"
    Header always set X-Frame-Options "SAMEORIGIN"

    ErrorLog \${APACHE_LOG_DIR}/glpi_error.log
    CustomLog \${APACHE_LOG_DIR}/glpi_access.log combined
</VirtualHost>
EOF

[[ $GLPI_PORT == 80 ]] && a2dissite -q 000-default >/dev/null 2>&1 || true
a2ensite -q glpi >/dev/null
grep -q '^ServerTokens' /etc/apache2/conf-available/security.conf 2>/dev/null \
  && sed -i 's/^ServerTokens .*/ServerTokens Prod/; s/^ServerSignature .*/ServerSignature Off/' /etc/apache2/conf-available/security.conf
apachectl configtest >/dev/null 2>&1 || { apachectl configtest; die "Configuração do Apache inválida."; }
systemctl enable apache2 >/dev/null 2>&1
systemctl restart apache2
log "VirtualHost glpi ativo na porta $GLPI_PORT (DocumentRoot $DOCROOT)"
fi

# -----------------------------------------------------------------------------
# 7. Instalação do banco do GLPI
# -----------------------------------------------------------------------------
title "9/11 Instalando o banco do GLPI (pode levar alguns minutos)"

INSTALL_ARGS=(
  db:install
  --db-host="$DB_HOST"
  --db-port="$DB_PORT"
  --db-name="$DB_NAME"
  --db-user="$DB_USER"
  --db-password="$DB_PASS"
  --default-language="$GLPI_LANG"
  --no-interaction
)
[[ $FORCE_DB == S ]] && INSTALL_ARGS+=(--force)
glpi_console "${INSTALL_ARGS[@]}"
log "Banco do GLPI instalado"

glpi_console db:enable_timezones --no-interaction >/dev/null 2>&1 \
  && log "Suporte a timezones habilitado" \
  || warn "Não foi possível habilitar timezones (verifique mysql.time_zone_name)."

# Parametrização inicial
ADMIN_HASH=$(P="$GLPI_ADMIN_PASS" php -r 'echo password_hash(getenv("P"), PASSWORD_DEFAULT);')
db_glpi <<SQL
INSERT INTO glpi_configs (context, name, value) VALUES ('core', 'url_base', '$(sql_escape "$GLPI_URL")')
  ON DUPLICATE KEY UPDATE value = VALUES(value);
INSERT INTO glpi_configs (context, name, value) VALUES ('inventory', 'enabled_inventory', '1')
  ON DUPLICATE KEY UPDATE value = VALUES(value);
UPDATE glpi_crontasks SET mode = 2;
UPDATE glpi_users SET password = '$(sql_escape "$ADMIN_HASH")', password_last_update = NOW() WHERE name = 'glpi';
SQL
log "URL base: $GLPI_URL | Inventário nativo: habilitado | Ações automáticas: modo CLI"
log "Senha do usuário 'glpi' alterada"

if [[ $DISABLE_DEFAULT_USERS == S ]]; then
  db_glpi -e "UPDATE glpi_users SET is_active = 0 WHERE name IN ('tech','normal','post-only');"
  log "Usuários padrão tech, normal e post-only desativados"
fi

# -----------------------------------------------------------------------------
# 8. Estrutura da empresa, categorias e plugins
# -----------------------------------------------------------------------------
title "10/11 Estrutura da empresa, categorias e plugins"

# Entidades: a matriz é a entidade raiz; as filiais são subentidades dela
Q_ROOT=$(sql_escape "$GLPI_ROOT_ENTITY")
db_glpi -e "UPDATE glpi_entities SET name = '$Q_ROOT', completename = '$Q_ROOT' WHERE id = 0;"
for b in "${BRANCHES[@]}"; do
  db_glpi -e "INSERT INTO glpi_entities (name, entities_id, completename, level, date_creation, date_mod)
              VALUES ('$(sql_escape "$b")', 0, '$(sql_escape "$GLPI_ROOT_ENTITY > $b")', 2, NOW(), NOW());"
done
db_glpi -e "UPDATE glpi_entities SET sons_cache = NULL, ancestors_cache = NULL;"
log "Entidades: $GLPI_ROOT_ENTITY + ${#BRANCHES[@]} filial(is)"

CATEGORIES_CREATED=0
if [[ $CREATE_CATEGORIES == S ]]; then
  EXISTING_CATEGORIES=$(db_glpi -N -e "SELECT COUNT(*) FROM glpi_itilcategories")
  if (( EXISTING_CATEGORIES > 0 )); then
    warn "Já existem $EXISTING_CATEGORIES categorias; o catálogo padrão não foi criado."
  else
    CATEGORIES_CREATED=$(create_categories "$SELECTED_AREAS")
    log "$CATEGORIES_CREATED categorias criadas (${SELECTED_AREAS//,/, }), válidas para todas as entidades"
  fi
fi

ACCESS_SUMMARY="não criados"
if [[ $CREATE_ACCESS == S ]]; then
  ACCESS_RESULT=$(create_access_structure)
  ACCESS_SUMMARY="${ACCESS_RESULT% *} grupos, ${ACCESS_RESULT#* } perfis"
  log "Grupos de atendimento: ${SELECTED_AREAS//,/, }$( (( ${#TEAMS[@]} )) && printf ' | equipes: %s' "$(IFS=','; echo "${TEAMS[*]}" | sed 's/,/, /g')")"
  log "Perfis criados: $( [[ ",$SELECTED_AREAS," == *",TI,"* ]] && echo 'Técnico de TI, Gestor de TI, ')Atendente de Área, Gestor de Área, Gestor de Equipe"
  log "Chamados atribuídos automaticamente ao grupo da área pela categoria"
fi

PLUGIN_ADMIN=glpi
PRIORITY_SUMMARY="padrão do GLPI (5 níveis)"
if [[ $SIMPLIFY_PRIORITIES == S ]]; then
  configure_priorities
  PRIORITY_SUMMARY="4 níveis (Baixa, Média, Alta, Muito alta) com matriz ITIL"
  log "Prioridades: $PRIORITY_SUMMARY"
fi

LINK_SUMMARY="não"
if [[ $LINK_URGENCY_IMPACT == S ]]; then
  create_link_rules >/dev/null
  LINK_SUMMARY="sim (impacto e prioridade acompanham a urgência)"
  log "Impacto atrelado à urgência: o chamado nasce com a prioridade escolhida pelo usuário"
fi

SLA_SUMMARY="não criados"
if [[ $CREATE_SLA == S ]]; then
  SLA_RULES=$(create_sla_ola)
  SLA_SUMMARY="8 SLAs + 8 OLAs ($SLA_RULES prioridades), atendimento seg-sex $BUSINESS_HOURS$( [[ $BUSINESS_SATURDAY == S ]] && echo ", sáb $SATURDAY_HOURS")$( [[ $ADD_HOLIDAYS == S ]] && echo ", com feriados nacionais")"
  log "SLA/OLA: $SLA_SUMMARY"
  log "Regras de negócio aplicam SLA e OLA pela prioridade na abertura e em cada mudança"
fi

CASCATER_STATUS="não instalado"
if [[ $INSTALL_CASCATER == S ]]; then
  if CASCATER_VERSION=$(fetch_cascater) && plugin_enable Cascater; then
    CASCATER_STATUS="instalado e ativo (v$CASCATER_VERSION)"
    log "Plugin Cascater $CASCATER_VERSION instalado e ativado"
  else
    CASCATER_STATUS="FALHOU (instale manualmente)"
    warn "Não foi possível instalar o Cascater. Instale depois: https://github.com/${CASCATER_REPO:-GustavoMS0/Cascater}"
  fi
fi

GLPIINVENTORY_STATUS="não instalado"
if [[ $INSTALL_GLPIINVENTORY == S ]]; then
  if GLPIINVENTORY_VERSION=$(fetch_glpiinventory "$GLPI_MAJOR") && plugin_enable glpiinventory; then
    GLPIINVENTORY_STATUS="instalado e ativo (v$GLPIINVENTORY_VERSION)"
    log "Plugin GLPI Inventory $GLPIINVENTORY_VERSION instalado e ativado"
  else
    GLPIINVENTORY_STATUS="FALHOU (instale manualmente)"
    warn "Não foi possível instalar o GLPI Inventory. Instale depois: https://github.com/glpi-project/glpi-inventory-plugin"
  fi
fi

ASSETTERMS_STATUS="não instalado"
if [[ $INSTALL_ASSETTERMS == S ]]; then
  if ASSETTERMS_VERSION=$(fetch_assetterms) && plugin_enable assetterms; then
    ASSETTERMS_STATUS="instalado e ativo (v$ASSETTERMS_VERSION)"
    log "Plugin Asset Terms $ASSETTERMS_VERSION instalado e ativado"
  else
    ASSETTERMS_STATUS="FALHOU (instale manualmente: github.com/GustavoMS0/GLPI-AssetTerms)"
    warn "Não foi possível instalar o Asset Terms."
  fi
fi

CHATBOT_STATUS="não instalado"
if [[ $INSTALL_CHATBOT == S ]] && (( GLPI_MAJOR < 11 )); then
  CHATBOT_STATUS="não instalado (o GLPI Chatbot é só para o GLPI 11)"
  warn "O GLPI Chatbot é só para o GLPI 11; não foi instalado no GLPI $GLPI_VERSION."
elif [[ $INSTALL_CHATBOT == S ]]; then
  if CHATBOT_VERSION=$(fetch_chatbot) && plugin_enable glpichatbot; then
    CHATBOT_STATUS="instalado e ativo (v$CHATBOT_VERSION)"
    log "Plugin GLPI Chatbot $CHATBOT_VERSION instalado e ativado"
  else
    CHATBOT_STATUS="FALHOU (instale manualmente: github.com/${CHATBOT_REPO:-GustavoMS0/GLPI-Chatbot})"
    warn "Não foi possível instalar o GLPI Chatbot."
  fi
fi

# Modelos de atendimento (acompanhamento e solução)
create_followup_and_solution_templates
log "Modelos de atendimento: 5 modelos de acompanhamento e 5 de solução/encerramento cadastrados"

# Melhores práticas de inventário & dicionário de softwares
configure_inventory_best_practices

rm -f "$GLPI_DIR/install/install.php"
glpi_console cache:clear --no-interaction >/dev/null 2>&1 || true

# -----------------------------------------------------------------------------
# 9. Cron, firewall e validação
# -----------------------------------------------------------------------------
title "11/11 Cron, firewall e validação"

CONSOLE_CMDS=$(glpi_console list --raw 2>/dev/null | awk '{print $1}' || true)
if [[ -f $GLPI_DIR/front/cron.php ]]; then
  CRON_CMD="/usr/bin/php $GLPI_DIR/front/cron.php"
elif CRON_NAME=$(grep -m1 -E '^(glpi:)?cron(:run)?$' <<<"$CONSOLE_CMDS"); then
  CRON_CMD="/usr/bin/php $GLPI_DIR/bin/console $CRON_NAME"
else
  CRON_CMD="/usr/bin/php $GLPI_DIR/front/cron.php"
  warn "Comando de cron do GLPI não identificado; revise /etc/cron.d/glpi."
fi
cat >/etc/cron.d/glpi <<EOF
# Ações automáticas do GLPI - gerado por install-glpi.sh
* * * * * www-data $CRON_CMD >/dev/null 2>&1
EOF
chmod 644 /etc/cron.d/glpi
systemctl enable --now cron >/dev/null 2>&1 || true
log "Cron configurado: $CRON_CMD (a cada minuto)"

if command -v ufw >/dev/null 2>&1; then
  UFW_STATUS=$(ufw status 2>/dev/null || true)
  if [[ $UFW_STATUS == *"Status: active"* ]]; then ufw allow "$GLPI_PORT/tcp" >/dev/null; log "UFW: porta $GLPI_PORT liberada"; fi
fi
if command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
  firewall-cmd --permanent --add-port="$GLPI_PORT/tcp" >/dev/null && firewall-cmd --reload >/dev/null
  log "firewalld: porta $GLPI_PORT liberada"
fi

HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 "http://127.0.0.1:$GLPI_PORT/" || echo 000)
if [[ $HTTP_CODE =~ ^(200|302)$ ]]; then
  log "GLPI respondendo em http://127.0.0.1:$GLPI_PORT/ (HTTP $HTTP_CODE)"
else
  warn "GLPI respondeu HTTP $HTTP_CODE. Verifique /var/log/apache2/glpi_error.log e $GLPI_LOG_DIR"
fi

AGENT_URL="$GLPI_URL/front/inventory.php"
SERVER_IP=${DEFAULT_IP:-$GLPI_FQDN}

umask 077
cat >"$INFO_FILE" <<EOF
===================== INSTALAÇÃO DO GLPI =====================
Data ..................: $(date '+%F %T')
Versão ................: GLPI $GLPI_VERSION (PHP $(php -r 'echo PHP_VERSION;'))
URL de acesso .........: $GLPI_URL
Servidor web ..........: $WEB_SERVER
Usuário super-admin ...: glpi
Senha super-admin .....: $GLPI_ADMIN_PASS
Usuários padrão .......: $( [[ $DISABLE_DEFAULT_USERS == S ]] && echo "tech/normal/post-only DESATIVADOS" || echo "tech/normal/post-only ativos (senhas padrão!)")

Banco de dados ........: $DB_HOST:$DB_PORT
Base ..................: $DB_NAME
Usuário do banco ......: $DB_USER@$DB_USER_HOST
Senha do banco ........: $DB_PASS

Diretórios ............: código=$GLPI_DIR  config=$GLPI_CONFIG_DIR
                         dados=$GLPI_VAR_DIR  logs=$GLPI_LOG_DIR
Chave de criptografia .: $GLPI_CONFIG_DIR/glpicrypt.key  (FAÇA BACKUP!)

Matriz (entidade raiz) : $GLPI_ROOT_ENTITY
Filiais ...............: $( (( ${#BRANCHES[@]} )) && (IFS=';'; echo "${BRANCHES[*]}" | sed 's/;/, /g') || echo "nenhuma")
Categorias criadas ....: $CATEGORIES_CREATED$( [[ $CREATE_CATEGORIES == S ]] && echo " (${SELECTED_AREAS//,/, })")
Grupos e perfis .......: $ACCESS_SUMMARY
Prioridades ...........: $PRIORITY_SUMMARY
Impacto x urgência ....: $LINK_SUMMARY
SLA / OLA .............: $SLA_SUMMARY
Modelos de atendimento : 5 de acompanhamento + 5 de solução (com Termos de Entrega e Devolução)
Inventário assertivo ..: status 'Em uso' + filtro de KBs + classificação de Servidores/VMs
Ciclo de vida .........: 6 estados (Em estoque, Em preparação, Em uso, Manutenção, Empréstimo, Descarte)
Plugin Cascater .......: $CASCATER_STATUS
Plugin GLPI Inventory .: $GLPIINVENTORY_STATUS
Plugin Asset Terms ....: $ASSETTERMS_STATUS
Plugin GLPI Chatbot ...: $CHATBOT_STATUS

Como liberar o acesso de cada pessoa (Administração > Usuários):
  - Atendente de RH ....: perfil "Atendente de Área" + grupo "RH"
  - Gestor do RH .......: perfil "Gestor de Área"    + grupo "RH"
  - Técnico / Gestor TI : perfil "Técnico de TI" / "Gestor de TI" + grupo "TI"
  - Gestor de equipe ...: perfil "Gestor de Equipe"  + grupo da equipe
  - Colaboradores ......: perfil "Self-Service" (padrão) + grupo da sua equipe
  Somente o perfil Super-Admin vê todos os chamados.

---------------------- GLPI AGENT / INTUNE -------------------
ServerUrl .............: $AGENT_URL
HttpdTrust ............: $SERVER_IP
===============================================================
EOF
chmod 600 "$INFO_FILE"

echo
echo "${C_G}${C_W}  Instalação concluída com sucesso!${C_N}"
echo
echo "  Acesse ..............: ${C_W}$GLPI_URL${C_N}"
echo "  Usuário .............: glpi"
if [[ $GLPI_ADMIN_PASS_GENERATED == S ]]; then
  echo "  Senha (gerada) ......: ${C_W}$GLPI_ADMIN_PASS${C_N}"
else
  echo "  Senha ...............: (a que você informou)"
fi
[[ $DB_PASS_GENERATED == S ]] && echo "  Senha do banco ......: gerada automaticamente (ver $INFO_FILE)"
echo "  URL p/ o GLPI Agent .: ${C_W}$AGENT_URL${C_N}"
echo "  Entidades ...........: $GLPI_ROOT_ENTITY + ${#BRANCHES[@]} filial(is)"
echo "  Categorias ..........: $CATEGORIES_CREATED criadas"
echo "  Grupos e perfis .....: $ACCESS_SUMMARY"
echo "  Prioridades .........: $PRIORITY_SUMMARY"
echo "  Impacto x urgência ..: $LINK_SUMMARY"
echo "  SLA / OLA ...........: $SLA_SUMMARY"
echo "  Modelos ..............: 5 de acompanhamento + 5 de solução (inclui Termos de Entrega/Devolução)"
echo "  Gestão de Ativos .....: 6 estados de ciclo de vida + classificação automática de Servidores"
echo "  Plugin Cascater .....: $CASCATER_STATUS"
echo "  GLPI Inventory ......: $GLPIINVENTORY_STATUS"
echo "  Asset Terms .........: $ASSETTERMS_STATUS"
echo "  GLPI Chatbot ........: $CHATBOT_STATUS"
echo
echo "  Todas as credenciais foram salvas em $INFO_FILE (somente root)."
echo "  Faça backup de $GLPI_CONFIG_DIR/glpicrypt.key e $GLPI_CONFIG_DIR/config_db.php."
echo "  Recomendado: configurar HTTPS (ex.: certbot --apache) antes de uso em produção."
echo "  Log completo: $LOG_FILE"
