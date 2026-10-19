#!/usr/bin/env bash

# ==============================================================================
# rsync4me - Sincronizador interactivo de carpetas por SSH
# ==============================================================================

set -eo pipefail
shopt -s inherit_errexit 2>/dev/null || true

# --- CONFIGURACIÓN DE COLORES ---
RESET='\e[0m'
NEGRITA='\e[1m'
VERDE_BRILLANTE='\e[92m'
VERDE='\e[32m'
AMARILLO='\e[33m'
AZUL='\e[34m'
AZUL_BRILLANTE='\e[94m'
CIAN='\e[36m'
MAGENTA='\e[35m'
ROJO='\e[31m'
ROJO_BRILLANTE='\e[91m'
BLANCO='\e[97m'
NC='\033[0m'
ver="v.1.0"

info()    { echo -e "${AZUL_BRILLANTE}[INFO]${RESET} $1"; }
success() { echo -e "${VERDE_BRILLANTE}[OK]${RESET} $1"; }
warn()    { echo -e "${AMARILLO}[WARN]${RESET} $1"; }
error()   { echo -e "${ROJO_BRILLANTE}[ERROR]${RESET} $1" >&2; exit 1; }

REAL_USER=${SUDO_USER:-$USER}
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)

# --- RUTAS DE CONFIGURACIÓN (sobreescribibles con RSYNC4ME_CONFIG_DIR) ---
CONFIG_DIR="${RSYNC4ME_CONFIG_DIR:-$REAL_HOME/.config/rsync4me}"
CONFIG_FILE="$CONFIG_DIR/config"
FAVS_FILE="$CONFIG_DIR/carpetas.txt"
EXCL_FILE="$CONFIG_DIR/exclude.txt"
LOG_FILE="$CONFIG_DIR/rsync4me.log"

# --- VALORES POR DEFECTO (los sobrescribe el archivo de configuración) ---
RSYNC4ME_HOST="${RSYNC4ME_HOST:-}"
RSYNC4ME_PORT="${RSYNC4ME_PORT:-22}"
RSYNC4ME_USER="${RSYNC4ME_USER:-}"
RSYNC4ME_BASE="${RSYNC4ME_BASE:-}"

MARCA_EXPLORAR="➕ Explorar el disco completo…"

# ==============================================================================
# CONFIGURACIÓN
# ==============================================================================

cargar_config() {
    if [ -f "$CONFIG_FILE" ]; then
        # shellcheck disable=SC1090
        source "$CONFIG_FILE"
    fi
}

guardar_config() {
    mkdir -p "$CONFIG_DIR"
    cat > "$CONFIG_FILE" <<EOF
# Configuración de rsync4me
RSYNC4ME_HOST="$RSYNC4ME_HOST"
RSYNC4ME_PORT="$RSYNC4ME_PORT"
RSYNC4ME_USER="$RSYNC4ME_USER"
RSYNC4ME_BASE="$RSYNC4ME_BASE"
EOF
    success "Configuración guardada en $CONFIG_FILE"
}

config_completa() {
    [ -n "$RSYNC4ME_HOST" ] && [ -n "$RSYNC4ME_USER" ] && [ -n "$RSYNC4ME_BASE" ]
}

destino_ssh() { echo "$RSYNC4ME_USER@$RSYNC4ME_HOST"; }

probar_conexion() {
    info "Probando conexión con $(destino_ssh):$RSYNC4ME_PORT ..."
    if ssh -p "$RSYNC4ME_PORT" -o BatchMode=yes -o ConnectTimeout=5 \
            "$(destino_ssh)" true 2>/dev/null; then
        success "Conexión correcta."
        return 0
    fi
    warn "No se pudo conectar (revisa el host, el puerto o la clave SSH)."
    return 1
}

configurar_servidor() {
    echo -e "${CIAN}══ CONFIGURACIÓN DEL SERVIDOR SSH ══${RESET}"
    info "Archivo: $CONFIG_FILE"
    echo
    local resp

    read -rp "➤ Servidor (host o IP)        [${RSYNC4ME_HOST}]: " resp
    if [ -n "$resp" ]; then RSYNC4ME_HOST="$resp"; fi

    read -rp "➤ Puerto SSH                  [${RSYNC4ME_PORT}]: " resp
    if [ -n "$resp" ]; then RSYNC4ME_PORT="$resp"; fi

    read -rp "➤ Usuario remoto              [${RSYNC4ME_USER}]: " resp
    if [ -n "$resp" ]; then RSYNC4ME_USER="$resp"; fi

    local base_sug="${RSYNC4ME_BASE:-$REAL_HOME}"
    read -rp "➤ Carpeta base remota         [$base_sug]: " resp
    RSYNC4ME_BASE="${resp:-$base_sug}"

    echo
    if config_completa; then
        guardar_config
        probar_conexion || warn "Configuración guardada, pero la conexión falló."
    else
        error "Faltan datos obligatorios; no se guardó nada."
    fi
}

asistente_config() {
    echo
    echo -e "${CIAN}╔══════════════════════════════════════════════════════╗${RESET}"
    echo -e "${CIAN}║${RESET}  ${NEGRITA}Primera ejecución: configuremos tu servidor SSH${RESET}      ${CIAN}║${RESET}"
    echo -e "${CIAN}╚══════════════════════════════════════════════════════╝${RESET}"
    echo
    info "Estos datos se guardarán en $CONFIG_FILE"
    echo
    configurar_servidor
    echo
    read -rp "Presione Enter para continuar..."
}

# ==============================================================================
# DEPENDENCIAS
# ==============================================================================

PKG_MANAGER=""
DISTRO_NAME=""

detectar_distro() {
    if [ -f /etc/os-release ]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        DISTRO_NAME=${NAME:-Linux}
        case "${ID:-}" in
            arch|manjaro|endeavouros|garuda) PKG_MANAGER="pacman" ;;
            ubuntu|debian|pop|mint|elementary) PKG_MANAGER="apt" ;;
            fedora|rhel|nobara|centos) PKG_MANAGER="dnf" ;;
            *)
                if [[ "${ID_LIKE:-}" == *"arch"* ]]; then PKG_MANAGER="pacman"
                elif [[ "${ID_LIKE:-}" == *"debian"* || "${ID_LIKE:-}" == *"ubuntu"* ]]; then PKG_MANAGER="apt"
                elif [[ "${ID_LIKE:-}" == *"fedora"* || "${ID_LIKE:-}" == *"rhel"* ]]; then PKG_MANAGER="dnf"
                else PKG_MANAGER=""
                fi
                ;;
        esac
    fi
}

# Traduce el nombre del comando a su paquete según la distro
paquete_de() {
    case "$1" in
        ssh) [ "$PKG_MANAGER" = "pacman" ] && echo "openssh" || echo "openssh-client" ;;
        *)   echo "$1" ;;
    esac
}

asegurar_dependencias() {
    local faltan=() c
    for c in rsync ssh fzf; do
        command -v "$c" >/dev/null 2>&1 || faltan+=("$c")
    done
    if [ ${#faltan[@]} -eq 0 ]; then return 0; fi

    warn "Faltan dependencias: ${faltan[*]}"
    if [ -z "$PKG_MANAGER" ]; then
        error "Instálalas manualmente y vuelve a ejecutar."
    fi

    local pkgs=()
    for c in "${faltan[@]}"; do pkgs+=("$(paquete_de "$c")"); done

    read -rp "¿Instalarlas ahora con $PKG_MANAGER? [s/N]: " resp
    [[ "$resp" =~ ^[sSyY]$ ]] || error "No se puede continuar sin: ${faltan[*]}"

    case "$PKG_MANAGER" in
        pacman) sudo pacman -S --needed "${pkgs[@]}" ;;
        apt)    sudo apt update && sudo apt install -y "${pkgs[@]}" ;;
        dnf)    sudo dnf install -y "${pkgs[@]}" ;;
    esac
}

# ==============================================================================
# INTERFAZ
# ==============================================================================

fzf_menu_principal() {
    local preview_cmd='
        line="{}"
        if [[ "$line" =~ "SINCRONIZAR" ]]; then
            echo -e "\033[1;36m=== 📂 SINCRONIZAR CARPETA ===\033[0m\n\nElige una carpeta local y un destino remoto:\n ➔ Selección desde tus carpetas favoritas o explorando el disco\n ➔ Dirección: ambos sentidos, solo envío o solo traída\n ➔ Simulación previa (dry-run) antes de copiar\n ➔ Solo AÑADE: nunca borra ni sobrescribe"
        elif [[ "$line" =~ "MIS CARPETAS" ]]; then
            echo -e "\033[1;36m=== 📋 MIS CARPETAS ===\033[0m\n\nGestiona tus carpetas favoritas:\n ➔ Registra rutas locales frecuentes\n ➔ Lístalas y elimínalas cuando quieras\n ➔ Se guardan en ~/.config/rsync4me/carpetas.txt"
        elif [[ "$line" =~ "SERVIDOR" ]]; then
            echo -e "\033[1;36m=== ⚙️ SERVIDOR SSH ===\033[0m\n\nAjusta los datos de conexión:\n ➔ Host o IP, puerto y usuario\n ➔ Carpeta base remota (raíz de los destinos)\n ➔ Prueba automática de la conexión\n ➔ Se guarda en el archivo de configuración"
        elif [[ "$line" =~ "EXCLUSIONES" ]]; then
            echo -e "\033[1;36m=== 📦 EXCLUSIONES ===\033[0m\n\nEdita los patrones que rsync ignorará:\n ➔ Uno por línea (ej: .git/, node_modules/, *.tmp)\n ➔ Se aplican con --exclude-from"
        elif [[ "$line" =~ "REGISTRO" ]]; then
            echo -e "\033[1;36m=== 🧾 REGISTRO ===\033[0m\n\nConsulta el historial de sincronizaciones:\n ➔ Última ejecución y transferencias realizadas\n ➔ Se guarda en ~/.config/rsync4me/rsync4me.log"
        elif [[ "$line" =~ "AYUDA" ]]; then
            echo -e "\033[1;36m=== 💡 AYUDA Y ATAJOS ===\033[0m\n\nMuestra patrones útiles del panel:\n ➔ Atajos de fzf dentro de los menús\n ➔ Ejemplos de uso por línea de comandos"
        elif [[ "$line" =~ "SALIR" ]]; then
            echo -e "\033[1;31m=== ❌ SALIR ===\033[0m\n\nCierra el panel de administración rsync4me de forma segura."
        else
            echo -e "Selecciona una opción del menú para ver su descripción."
        fi
    '

    fzf --ansi \
        --height=60% \
        --layout=reverse \
        --border=rounded \
        --prompt=" Seleccione Opción ❯ " \
        --header="--- R S Y N C 4 M E  P A N E L ---" \
        --header-lines=1 \
        --color="border:#5fafd7,header:#af87ff,prompt:#5fb2ff,pointer:#afff00" \
        --preview-window="right:50%:border-rounded:wrap" \
        --preview="$preview_cmd"
}

fzf_generico() {
    local titulo="$1" prompt="$2"
    fzf --ansi \
        --height=60% \
        --layout=reverse \
        --border=rounded \
        --prompt=" $prompt ❯ " \
        --header="--- $titulo ---" \
        --header-lines=1 \
        --color="border:#5fafd7,header:#af87ff,prompt:#5fb2ff,pointer:#afff00"
}

mostrar_logo() {
    echo -e "${CIAN}██████╗ ███████╗██╗   ██╗███╗   ██╗ ██████╗ ██╗  ██╗███╗   ███╗███████╗${RESET}"
    echo -e "${AZUL_BRILLANTE}██╔══██╗██╔════╝╚██╗ ██╔╝████╗  ██║██╔════╝ ██║  ██║████╗ ████║██╔════╝${RESET}"
    echo -e "${AZUL}██████╔╝███████╗ ╚████╔╝ ██╔██╗ ██║██║      ███████║██╔████╔██║█████╗  ${RESET}"
    echo -e "${AZUL}██╔══██╗╚════██║  ╚██╔╝  ██║╚██╗██║██║      ╚════██║██║╚██╔╝██║██╔══╝  ${RESET}"
    echo -e "${AZUL_BRILLANTE}██║  ██║███████║   ██║   ██║ ╚████║╚██████╗      ██║██║ ╚═╝ ██║███████╗${RESET}"
    echo -e "${VERDE_BRILLANTE}╚═╝  ╚═╝╚══════╝   ╚═╝   ╚═╝  ╚═══╝ ╚═════╝      ╚═╝╚═╝     ╚═╝╚══════╝${RESET}"
    echo -e "${VERDE_BRILLANTE}  RSYNC4ME - SINCRONIZADOR DE CARPETAS POR SSH $ver${RESET}"
    echo -e "${CIAN}  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo -e "${AMARILLO}➤ Sistema:${RESET}  ${BLANCO}${DISTRO_NAME}${PKG_MANAGER:+ (${PKG_MANAGER})}${RESET}"
    echo -e "${AMARILLO}➤ Usuario:${RESET}  ${BLANCO}${REAL_USER}${RESET}"
    echo -e "${AMARILLO}➤ Home:${RESET}     ${BLANCO}${REAL_HOME}${RESET}"
    if config_completa; then
        echo -e "${AMARILLO}➤ Servidor:${RESET} ${BLANCO}${RSYNC4ME_USER}@${RSYNC4ME_HOST}:${RSYNC4ME_PORT}${RESET} ${CIAN}(${RSYNC4ME_BASE})${RESET}"
    else
        echo -e "${AMARILLO}➤ Servidor:${RESET} ${ROJO}sin configurar${RESET}"
    fi
    echo -e "${CIAN}  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n"
}

salir() {
    echo -e "\e[?25h"
    echo ""
    echo -e "${VERDE}  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo -e "${AZUL}  Saliendo de rsync4me...${RESET}"
    echo -e "${VERDE_BRILLANTE}  ¡Hasta pronto!${RESET}"
    echo -e "${VERDE}  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    exit 0
}

# ==============================================================================
# SELECCIÓN DE CARPETAS
# ==============================================================================

ruta_relativa() {
    local p="$1"
    if [ "$p" = "$REAL_HOME" ]; then
        echo "."
    elif [[ "$p" == "$REAL_HOME"/* ]]; then
        echo "${p#"$REAL_HOME"/}"
    else
        basename "$p"
    fi
}

explorar_local() {
    local elegida
    elegida=$(fzf --ansi \
        --height=70% \
        --layout=reverse \
        --border=rounded \
        --prompt=" Explorar carpeta local ❯ " \
        --header="--- ELIGE LA CARPETA DE ORIGEN (raíz: $REAL_HOME) ---" \
        --walker=dir \
        --walker-root="$REAL_HOME" \
        --preview='p={}; echo "$p"; echo; du -sh "$p" 2>/dev/null; echo; ls -lah "$p" 2>/dev/null | head -25' \
        --preview-window="right:55%:border-rounded:wrap" \
        --color="border:#5fafd7,header:#af87ff,prompt:#5fb2ff,pointer:#afff00") || return 1
    [ -n "$elegida" ] || return 1
    printf '%s\n' "$elegida"
}

seleccionar_carpeta_local() {
    local elegida

    if [ -s "$FAVS_FILE" ]; then
        local lista
        lista=$(cat "$FAVS_FILE")
        elegida=$(printf '%s\n%s\n' "$lista" "$MARCA_EXPLORAR" | fzf --ansi \
            --height=70% \
            --layout=reverse \
            --border=rounded \
            --prompt=" Carpeta local ❯ " \
            --header="--- FAVORITAS (elige o explora) ---" \
            --preview='p={}; [ "$p" = "'"$MARCA_EXPLORAR"'" ] && { echo "Abre el explorador del disco"; exit 0; }; echo "$p"; echo; du -sh "$p" 2>/dev/null; echo; ls -lah "$p" 2>/dev/null | head -25' \
            --preview-window="right:55%:border-rounded:wrap" \
            --color="border:#5fafd7,header:#af87ff,prompt:#5fb2ff,pointer:#afff00") || return 1

        if [ "$elegida" = "$MARCA_EXPLORAR" ]; then
            explorar_local
            return $?
        fi
        [ -n "$elegida" ] || return 1
        printf '%s\n' "$elegida"
        return 0
    fi

    explorar_local
}

seleccionar_direccion() {
    local opciones="ICONO | DIRECCIÓN   | DESCRIPCIÓN
0. 🔁 | AMBOS       | Fusionar en los dos sentidos (solo añade).
1. 📤 | SOLO ENVÍO  | De esta máquina al servidor.
2. 📥 | SOLO TRAER  | Del servidor a esta máquina."
    local sel
    sel=$(printf '%s\n' "$opciones" | fzf_generico "DIRECCIÓN DE LA SINCRONIZACIÓN" "Dirección") || return 1
    case "${sel%%.*}" in
        0) echo "both" ;;
        1) echo "push" ;;
        2) echo "pull" ;;
        *) return 1 ;;
    esac
}

seleccionar_carpeta_remota() {
    local sugerida="$1" lista out query sel

    lista=$(ssh -p "$RSYNC4ME_PORT" -o ConnectTimeout=5 "$(destino_ssh)" \
        "find '$RSYNC4ME_BASE' -maxdepth 3 -type d 2>/dev/null" 2>/dev/null || true)

    if [ -z "$lista" ]; then
        lista="$sugerida"
    elif ! printf '%s\n' "$lista" | grep -qxF "$sugerida"; then
        lista="$sugerida"$'\n'"$lista"
    fi

    out=$(printf '%s\n' "$lista" | fzf \
        --print-query \
        --query="$sugerida" \
        --height=70% \
        --layout=reverse \
        --border=rounded \
        --prompt=" Carpeta remota ❯ " \
        --header="--- DESTINO EN $(destino_ssh) (edita la ruta si quieres) ---" \
        --color="border:#5fafd7,header:#af87ff,prompt:#5fb2ff,pointer:#afff00") || return 1

    query=$(sed -n '1p' <<<"$out")
    sel=$(sed -n '2p' <<<"$out")
    printf '%s\n' "${sel:-${query:-$sugerida}}"
}

# ==============================================================================
# SINCRONIZACIÓN
# ==============================================================================

ejecutar_sync() {
    local local_dir="$1" remoto="$2" direccion="$3" dry="$4"
    local destino="$(destino_ssh):$remoto"
    local -a opts=(-av --ignore-existing -e "ssh -p $RSYNC4ME_PORT -o ConnectTimeout=8")
    if [ -s "$EXCL_FILE" ]; then opts+=(--exclude-from="$EXCL_FILE"); fi
    if [ "$dry" = "1" ]; then opts+=(-n); fi

    mkdir -p "$local_dir"
    if [ "$dry" != "1" ]; then
        ssh -p "$RSYNC4ME_PORT" -o ConnectTimeout=8 "$(destino_ssh)" "mkdir -p '$remoto'" 2>/dev/null || true
    fi

    local rc=0
    if [ "$direccion" = "push" ] || [ "$direccion" = "both" ]; then
        info "Enviando:  $local_dir  ->  $destino"
        rsync "${opts[@]}" "$local_dir/" "$destino/" 2>&1 | tee -a "$LOG_FILE" || rc=1
    fi
    if [ "$direccion" = "pull" ] || [ "$direccion" = "both" ]; then
        info "Trayendo:  $destino  ->  $local_dir"
        rsync "${opts[@]}" "$destino/" "$local_dir/" 2>&1 | tee -a "$LOG_FILE" || rc=1
    fi
    return $rc
}

sincronizar_interactivo() {
    local local_dir remoto direccion sugerida

    local_dir=$(seleccionar_carpeta_local) || { warn "Cancelado."; return 0; }
    [ -d "$local_dir" ] || { warn "No es una carpeta válida: $local_dir"; return 0; }

    direccion=$(seleccionar_direccion) || { warn "Cancelado."; return 0; }

    sugerida="$RSYNC4ME_BASE/$(ruta_relativa "$local_dir")"
    remoto=$(seleccionar_carpeta_remota "$sugerida") || { warn "Cancelado."; return 0; }
    remoto="${remoto:-$sugerida}"

    clear; mostrar_logo
    echo -e " ${AMARILLO}Origen local:${RESET}  ${BLANCO}$local_dir${RESET}"
    echo -e " ${AMARILLO}Destino SSH:${RESET}   ${BLANCO}$(destino_ssh):$remoto${RESET}"
    echo -e " ${AMARILLO}Dirección:${RESET}     ${BLANCO}$direccion${RESET}"
    echo -e " ${AMARILLO}Modo:${RESET}          ${BLANCO}solo añadir (--ignore-existing)${RESET}"
    echo
    echo -e "${CIAN}──────── SIMULACIÓN (dry-run) ────────${RESET}"
    ejecutar_sync "$local_dir" "$remoto" "$direccion" 1 || true
    echo -e "${CIAN}──────────────────────────────────────${RESET}"
    echo
    read -rp "¿Ejecutar la sincronización real? [s/N]: " resp
    [[ "$resp" =~ ^[sSyY]$ ]] || { warn "Cancelado."; return 0; }

    echo
    echo "$(date -Is) SYNC $direccion $local_dir <-> $remoto" >> "$LOG_FILE"
    if ejecutar_sync "$local_dir" "$remoto" "$direccion" 0; then
        success "Sincronización completada."
    else
        warn "Falló algún paso. Revisa el registro."
    fi
}

# ==============================================================================
# SUBMÓDULOS
# ==============================================================================

gestionar_carpetas() {
    while true; do
        clear; mostrar_logo
        local opciones="ICONO | ACCIÓN   | DESCRIPCIÓN
0. ➕ | AÑADIR   | Registrar una carpeta local en favoritos.
1. 📃 | LISTAR   | Ver las carpetas registradas.
2. 🗑️ | QUITAR   | Eliminar una carpeta de favoritos.
3. ↩️ | VOLVER   | Volver al menú principal."
        local sel
        sel=$(printf '%s\n' "$opciones" | fzf_generico "MIS CARPETAS" "Acción") || return 0
        case "${sel%%.*}" in
            0) clear; mostrar_logo; anadir_favorita ;;
            1) clear; mostrar_logo; listar_favoritas ;;
            2) clear; mostrar_logo; quitar_favorita ;;
            3) return 0 ;;
        esac
        echo; read -rp "Presione Enter..."
    done
}

anadir_favorita() {
    local sel
    sel=$(explorar_local) || { warn "Cancelado."; return 0; }
    mkdir -p "$CONFIG_DIR"; touch "$FAVS_FILE"
    if grep -qxF "$sel" "$FAVS_FILE"; then
        warn "Ya estaba registrada: $sel"
    else
        printf '%s\n' "$sel" >> "$FAVS_FILE"
        success "Registrada: $sel"
    fi
}

listar_favoritas() {
    if [ ! -s "$FAVS_FILE" ]; then
        warn "No hay carpetas favoritas registradas."
        return 0
    fi
    echo -e "${CIAN}Carpetas favoritas:$RESET"
    echo
    nl -ba "$FAVS_FILE"
}

quitar_favorita() {
    if [ ! -s "$FAVS_FILE" ]; then
        warn "No hay carpetas favoritas registradas."
        return 0
    fi
    local sel
    sel=$(cat "$FAVS_FILE" | fzf --ansi --height=60% --layout=reverse \
        --border=rounded --prompt=" Quitar ❯ " \
        --header="--- QUITAR CARPETA FAVORITA ---" \
        --color="border:#5fafd7,header:#af87ff,prompt:#5fb2ff,pointer:#afff00") || return 0
    [ -n "$sel" ] || return 0
    grep -vxF "$sel" "$FAVS_FILE" > "$FAVS_FILE.tmp" || true
    mv "$FAVS_FILE.tmp" "$FAVS_FILE"
    success "Eliminada: $sel"
}

gestionar_exclusiones() {
    echo -e "${CIAN}Patrones de exclusión:${RESET} $EXCL_FILE"
    if [ ! -f "$EXCL_FILE" ]; then
        cat > "$EXCL_FILE" <<'EOF'
# Patrones que rsync ignorará (uno por línea)
.git/
node_modules/
.cache/
*.tmp
*.log
EOF
        info "Creado con patrones por defecto."
    fi
    echo
    read -rp "¿Abrir con micro para editar? [s/N]: " resp
    if [[ "$resp" =~ ^[sSyY]$ ]]; then
        micro "$EXCL_FILE"
        success "Exclusiones actualizadas."
    fi
}

mostrar_log() {
    if [ ! -s "$LOG_FILE" ]; then
        warn "Todavía no hay registro de sincronizaciones."
        return 0
    fi
    less -R "$LOG_FILE"
}

mostrar_ayuda() {
    local ayuda="CATEGORÍA   | ATAJO / COMANDO            | DESCRIPCIÓN
fzf         | Flechas / Ctrl+J, Ctrl+K   | Moverse por las opciones
fzf         | Escribir                   | Filtrar la lista
fzf         | Enter                      | Seleccionar
fzf         | Esc / Ctrl+C               | Cancelar
fzf         | Ctrl+/                     | Alternar la vista previa
rsync4me    | rsync4me                   | Abrir el panel interactivo
rsync4me    | rsync4me --setup           | Forzar el asistente de configuración
rsync4me    | rsync4me --config FICHERO  | Usar otro archivo de configuración
rsync4me    | rsync4me -d ORIGEN [DEST]  | Sincronizar sin menú
rsync4me    | rsync4me -d A B --push     | Solo enviar
rsync4me    | rsync4me -d A B --pull     | Solo traer
rsync4me    | rsync4me -d A B --dry-run  | Simular sin copiar
rsync4me    | rsync4me -h                | Ver la ayuda
rsync       | --ignore-existing          | Nunca sobrescribe lo existente
rsync       | (sin --delete)             | Nunca borra en el destino"

    printf '%s\n' "$ayuda" | fzf --ansi \
        --height=70% \
        --layout=reverse \
        --border=rounded \
        --prompt=" 🔍 Buscar > " \
        --header="--- ATAJOS Y COMANDOS DE RSYNC4ME ---" \
        --header-lines=1 \
        --color="border:#5fafd7,header:#af87ff,prompt:#5fb2ff,pointer:#afff00"
}

# ==============================================================================
# LÍNEA DE COMANDOS
# ==============================================================================

uso() {
    cat <<EOF
rsync4me $ver - sincronizador interactivo de carpetas por SSH

Uso:
  rsync4me                          Abre el panel interactivo
  rsync4me --setup                  Fuerza el asistente de configuración
  rsync4me --config FICHERO         Usa otro archivo de configuración
  rsync4me -d ORIGEN [DESTINO] [opciones]

Opciones:
  -d, --dirs ORIGEN [DESTINO]   Sincroniza sin menú. Si DESTINO se omite,
                                se calcula a partir de la carpeta base remota.
      --push                    Solo esta máquina -> servidor
      --pull                    Solo servidor -> esta máquina
      --both                    Ambos sentidos (por defecto)
      --dry-run                 Simula sin copiar nada
  -h, --help                    Muestra esta ayuda
EOF
}

# ==============================================================================
# MENÚ PRINCIPAL
# ==============================================================================

menu() {
    asegurar_dependencias

    if ! config_completa; then
        asistente_config
    fi

    while true; do
        clear
        mostrar_logo

        opciones="ICONO | OPCIÓN        | DESCRIPCIÓN
0. 📂 | SINCRONIZAR   | Elegir carpeta y sincronizarla con el servidor.
1. 📋 | MIS CARPETAS  | Registrar, listar y quitar carpetas favoritas.
2. ⚙️ | SERVIDOR      | Ajustar usuario, host, puerto y base remota.
3. 📦 | EXCLUSIONES   | Gestionar patrones --exclude del rsync.
4. 🧾 | REGISTRO      | Ver el historial de sincronizaciones.
5. 💡 | AYUDA         | Ver atajos y comandos disponibles.
6. ❌ | SALIR         | Salir del administrador rsync4me."

        local seleccion
        seleccion=$(printf '%s\n' "$opciones" | fzf_menu_principal) || salir
        [ -n "$seleccion" ] || salir

        case "${seleccion%%.*}" in
            0) clear; mostrar_logo; sincronizar_interactivo; read -rp "Presione Enter...";;
            1) gestionar_carpetas ;;
            2) clear; mostrar_logo; configurar_servidor; read -rp "Presione Enter...";;
            3) clear; mostrar_logo; gestionar_exclusiones; read -rp "Presione Enter...";;
            4) clear; mostrar_logo; mostrar_log;;
            5) clear; mostrar_logo; mostrar_ayuda;;
            6) salir ;;
        esac
    done
}

# ==============================================================================
# ARRANQUE
# ==============================================================================

detectar_distro
cargar_config
trap salir SIGINT SIGTERM

SETUP_FORZADO=0
CLI_DIRS=0
CLI_LOCAL=""
CLI_REMOTO=""
CLI_DIRECCION="both"
CLI_DRY=0

while [ $# -gt 0 ]; do
    case "$1" in
        --setup) SETUP_FORZADO=1 ;;
        --config) shift; [ -n "${1:-}" ] || error "--config requiere un fichero"
                  CONFIG_FILE="$1"; CONFIG_DIR=$(dirname "$CONFIG_FILE")
                  FAVS_FILE="$CONFIG_DIR/carpetas.txt"; EXCL_FILE="$CONFIG_DIR/exclude.txt"; LOG_FILE="$CONFIG_DIR/rsync4me.log" ;;
        -d|--dirs) CLI_DIRS=1; shift; CLI_LOCAL="${1:-}"
                  if [ -n "${2:-}" ] && [[ "${2:-}" != -* ]]; then shift; CLI_REMOTO="$1"; fi ;;
        --push) CLI_DIRECCION="push" ;;
        --pull) CLI_DIRECCION="pull" ;;
        --both) CLI_DIRECCION="both" ;;
        --dry-run) CLI_DRY=1 ;;
        -h|--help) uso; exit 0 ;;
        *) error "Opción desconocida: $1 (usa -h para ver la ayuda)" ;;
    esac
    shift
done

cargar_config   # recargar con el posible --config

if [ "$SETUP_FORZADO" = "1" ]; then
    asistente_config
    exit 0
fi

if [ "$CLI_DIRS" = "1" ]; then
    asegurar_dependencias
    if ! config_completa; then
        asistente_config
    fi
    [ -n "$CLI_LOCAL" ] || error "Falta el origen (usa -h para ver la ayuda)"
    [ -d "$CLI_LOCAL" ] || error "El origen no existe: $CLI_LOCAL"
    CLI_LOCAL=$(cd "$CLI_LOCAL" && pwd)
    [ -n "$CLI_REMOTO" ] || CLI_REMOTO="$RSYNC4ME_BASE/$(ruta_relativa "$CLI_LOCAL")"

    echo "$(date -Is) SYNC $CLI_DIRECCION $CLI_LOCAL <-> $CLI_REMOTO" >> "$LOG_FILE"
    if ejecutar_sync "$CLI_LOCAL" "$CLI_REMOTO" "$CLI_DIRECCION" "$CLI_DRY"; then
        success "Hecho: $CLI_LOCAL <-> $(destino_ssh):$CLI_REMOTO"
    else
        error "Falló la sincronización."
    fi
    exit 0
fi

menu
