#!/usr/bin/env bash
# =============================================================================
#  install-glpi.sh - Instalação automatizada da última versão estável do GLPI
# -----------------------------------------------------------------------------
#  Sistemas suportados : Debian 11/12/13, Ubuntu 22.04/24.04 (e derivados)
#  Pilha instalada     : Apache 2 + PHP (mod_php) + MariaDB (local ou remoto)
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
#
#  Modo não interativo: qualquer variável abaixo pode ser pré-definida em um
#  arquivo de configuração (veja glpi-install.conf.example) ou no ambiente;
#  a pergunta correspondente será pulada. Ex.:
#    sudo bash install-glpi.sh glpi-install.conf
#    sudo GLPI_PORT=8080 DB_NAME=glpi DB_PASS='xxx' bash install-glpi.sh
#  Variáveis: GLPI_VERSION GLPI_FQDN GLPI_PORT GLPI_LANG GLPI_TZ DB_LOCAL
#             DB_HOST DB_PORT DB_ADMIN_USER DB_ADMIN_PASS DB_NAME DB_USER
#             DB_USER_HOST DB_PASS GLPI_ADMIN_PASS DISABLE_DEFAULT_USERS
#             OVERWRITE CONFIRM
# =============================================================================
set -Eeuo pipefail

readonly SCRIPT_VERSION="1.0.0"
readonly LOG_FILE="/var/log/glpi-install-$(date +%Y%m%d-%H%M%S).log"
readonly INFO_FILE="/root/glpi-install-info.txt"
readonly GLPI_DIR="/var/www/glpi"
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

pkg_exists() { apt-cache show "$1" >/dev/null 2>&1; }

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

db_admin() { mysql --defaults-extra-file="$ADMIN_CNF" "$@"; }
db_glpi()  { mysql --defaults-extra-file="$GLPI_CNF" "$DB_NAME" "$@"; }
glpi_console() { runuser -u www-data -- php "$GLPI_DIR/bin/console" "$@"; }

# -----------------------------------------------------------------------------
# 0. Verificações iniciais
# -----------------------------------------------------------------------------
case "${1-}" in
  -h|--help)
    sed -n '3,30p' "$0" | sed 's/^# \{0,1\}//'
    exit 0 ;;
  "") ;;
  *)
    [[ -r $1 ]] || die "Arquivo de configuração '$1' não encontrado."
    # shellcheck disable=SC1090
    . "$1"
    echo "Configuração carregada de: $1" ;;
esac

[[ $EUID -eq 0 ]] || die "Execute como root: sudo bash $0"
[[ -r /dev/tty || -n "${CONFIRM-}" ]] || die "Sem terminal interativo. Defina as variáveis de ambiente (veja o cabeçalho)."

mkdir -p "$(dirname "$LOG_FILE")"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "${C_W}"
echo "  ============================================================"
echo "     Instalador automatizado do GLPI  -  v$SCRIPT_VERSION"
echo "  ============================================================${C_N}"
echo "  Log: $LOG_FILE"

title "1/10 Verificando pré-requisitos do sistema"

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

title "2/10 Instalando ferramentas básicas"
apt-get update -qq
apt-get install -y -qq curl wget ca-certificates gnupg lsb-release tar bzip2 \
  jq unzip cron openssl apt-transport-https >/dev/null
log "Ferramentas básicas instaladas"

# -----------------------------------------------------------------------------
# 1. Descobrindo a última versão estável
# -----------------------------------------------------------------------------
title "3/10 Consultando a última versão estável do GLPI"
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
# 2. Perguntas
# -----------------------------------------------------------------------------
title "4/10 Configuração da instalação"
DEFAULT_IP=$(hostname -I 2>/dev/null | awk '{print $1}')

echo "  -- Acesso web --"
ask GLPI_FQDN "Nome DNS ou IP pelo qual o GLPI será acessado" "${DEFAULT_IP:-localhost}"
while true; do
  ask GLPI_PORT "Porta HTTP do Apache" "80"
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

if [[ $GLPI_PORT == 80 ]]; then GLPI_URL="http://$GLPI_FQDN"; else GLPI_URL="http://$GLPI_FQDN:$GLPI_PORT"; fi

echo
echo "  ${C_W}Resumo:${C_N}"
echo "    GLPI ............: $GLPI_VERSION  ->  $GLPI_DIR"
echo "    URL .............: $GLPI_URL"
echo "    Idioma / Fuso ...: $GLPI_LANG / $GLPI_TZ"
echo "    Banco ...........: $DB_HOST:$DB_PORT  (local: $DB_LOCAL)"
echo "    Base / Usuário ..: $DB_NAME / $DB_USER@$DB_USER_HOST"
echo "    Admin do banco ..: $DB_ADMIN_USER"
echo
ask_yn CONFIRM "Prosseguir com a instalação?" S
[[ $CONFIRM == S ]] || die "Instalação cancelada pelo usuário."

# -----------------------------------------------------------------------------
# 3. PHP + Apache
# -----------------------------------------------------------------------------
title "5/10 Instalando Apache e PHP"

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

PHP_VER=$(distro_php_version)
if [[ -z $PHP_VER ]] || ! version_ge "$PHP_VER" "$PHP_MIN"; then
  warn "PHP da distribuição (${PHP_VER:-nenhum}) é inferior ao exigido ($PHP_MIN)."
  add_php_repo
  PHP_VER="8.3"
fi
log "Versão do PHP escolhida: $PHP_VER"

PHP_EXTS=(cli common mysql curl gd intl mbstring xml zip bz2 ldap bcmath apcu opcache)
PKGS=(apache2 "libapache2-mod-php$PHP_VER")
for ext in "${PHP_EXTS[@]}"; do
  if pkg_exists "php$PHP_VER-$ext"; then PKGS+=("php$PHP_VER-$ext")
  elif pkg_exists "php-$ext"; then PKGS+=("php-$ext")
  else warn "Pacote da extensão PHP '$ext' não encontrado (ignorado)."
  fi
done
info "Instalando: ${PKGS[*]}"
apt-get install -y -qq "${PKGS[@]}" >/dev/null

if [[ -x /usr/bin/php$PHP_VER ]]; then update-alternatives --set php "/usr/bin/php$PHP_VER" >/dev/null 2>&1 || true; fi

# Garante que somente o mod_php da versão escolhida está ativo
for m in /etc/apache2/mods-enabled/php*.load; do
  [[ -e $m ]] || continue
  mod=$(basename "$m" .load)
  [[ $mod == "php$PHP_VER" ]] || a2dismod -q "$mod" >/dev/null
done
a2dismod -q mpm_event >/dev/null 2>&1 || true
a2enmod -q mpm_prefork "php$PHP_VER" rewrite headers >/dev/null

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
for sapi in apache2 cli; do
  d="/etc/php/$PHP_VER/$sapi/conf.d"
  [[ -d $d ]] || continue
  cat >"$d/99-glpi.ini" <<EOF
; Gerado por install-glpi.sh
memory_limit = 256M
upload_max_filesize = 64M
post_max_size = 64M
max_execution_time = 600
max_input_vars = 5000
file_uploads = On
session.use_strict_mode = 1
session.cookie_httponly = On
session.cookie_samesite = Lax
date.timezone = $GLPI_TZ
EOF
done
log "php.ini ajustado (/etc/php/$PHP_VER/*/conf.d/99-glpi.ini)"

# -----------------------------------------------------------------------------
# 4. Banco de dados
# -----------------------------------------------------------------------------
title "6/10 Preparando o banco de dados"

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
  if command -v mysql_tzinfo_to_sql >/dev/null 2>&1 \
     && mysql_tzinfo_to_sql /usr/share/zoneinfo 2>/dev/null | db_admin mysql 2>/dev/null; then
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
title "7/10 Baixando e instalando o GLPI $GLPI_VERSION"

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
title "8/10 Configurando o Apache"

LISTENERS=$(ss -ltnpH "sport = :$GLPI_PORT" 2>/dev/null || true)
if [[ -n $LISTENERS && $LISTENERS != *apache2* ]]; then
  die "A porta $GLPI_PORT já está em uso por outro serviço: $LISTENERS"
fi

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

# -----------------------------------------------------------------------------
# 7. Instalação do banco do GLPI
# -----------------------------------------------------------------------------
title "9/10 Instalando o banco do GLPI (pode levar alguns minutos)"

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

rm -f "$GLPI_DIR/install/install.php"
glpi_console cache:clear --no-interaction >/dev/null 2>&1 || true

# -----------------------------------------------------------------------------
# 8. Cron, firewall e validação
# -----------------------------------------------------------------------------
title "10/10 Cron, firewall e validação"

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
echo
echo "  Todas as credenciais foram salvas em $INFO_FILE (somente root)."
echo "  Faça backup de $GLPI_CONFIG_DIR/glpicrypt.key e $GLPI_CONFIG_DIR/config_db.php."
echo "  Recomendado: configurar HTTPS (ex.: certbot --apache) antes de uso em produção."
echo "  Log completo: $LOG_FILE"
