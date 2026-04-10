#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SERVER_NAME="EMBY ISLA"
EMBY_SERVICE="emby_isla"

CACHE_ROOT="/var/cache/rclone"
MOUNT_LIST="/root/emby_isla_mounts.tsv"
WATCHDOG_SCRIPT="/root/watchdog_emby_isla.sh"
SYSTEMD_SERVICE="/etc/systemd/system/emby-isla-mounts.service"
WATCHDOG_LOG="/var/log/watchdog_emby_isla.log"
STATUS_FILE="/root/.emby_isla_status"

DEPENDENCIAS=0
RCLONE=0
CONFIG=0
ESTRUCTURA=0
MOUNTS=0
EMBY_OK=0
SYSTEMD_OK=0
CRON_OK=0

pause() {
  read -r -p "Pulsa ENTER para continuar..."
}

load_status() {
  [ -f "$STATUS_FILE" ] && source "$STATUS_FILE"
}

save_status() {
  cat > "$STATUS_FILE" << EOF
DEPENDENCIAS=${DEPENDENCIAS:-0}
RCLONE=${RCLONE:-0}
CONFIG=${CONFIG:-0}
ESTRUCTURA=${ESTRUCTURA:-0}
MOUNTS=${MOUNTS:-0}
EMBY_OK=${EMBY_OK:-0}
SYSTEMD_OK=${SYSTEMD_OK:-0}
CRON_OK=${CRON_OK:-0}
EOF
}

checkmark() {
  [ "${1:-0}" = "1" ] && echo -e "${GREEN}[✔]${NC}" || echo -e "${RED}[✘]${NC}"
}

refresh_status_from_system() {
  command -v rclone >/dev/null 2>&1 && RCLONE=1
  [ -f /root/.config/rclone/rclone.conf ] && [ -s /root/.config/rclone/rclone.conf ] && CONFIG=1
  [ -f "$MOUNT_LIST" ] && ESTRUCTURA=1

  if findmnt -t fuse.rclone >/dev/null 2>&1; then
    MOUNTS=1
  fi

  if systemctl is-active --quiet "$EMBY_SERVICE"; then
    EMBY_OK=1
  fi

  if systemctl is-enabled emby-isla-mounts.service >/dev/null 2>&1; then
    SYSTEMD_OK=1
  fi

  CURRENT_CRON="$(crontab -l 2>/dev/null)"
  if echo "$CURRENT_CRON" | grep -Fq "$WATCHDOG_SCRIPT" && \
     echo "$CURRENT_CRON" | grep -Fq "0 4 */2 * * /usr/sbin/reboot"; then
    CRON_OK=1
  fi

  save_status
}

get_ip() {
  hostname -I 2>/dev/null | awk '{print $1}'
}

show_emby_link() {
  IP=$(get_ip)
  if [ -n "$IP" ]; then
    echo ""
    echo -e "${GREEN}Enlace Emby:${NC} http://$IP:8096"
  else
    echo ""
    echo -e "${YELLOW}No pude detectar la IP automáticamente.${NC}"
    echo "Entra manualmente con: http://IP_DEL_SERVER:8096"
  fi
}

show_emby_state() {
  echo ""
  if systemctl is-active --quiet "$EMBY_SERVICE"; then
    echo -e "${GREEN}${EMBY_SERVICE} está ACTIVO${NC}"
  else
    echo -e "${RED}${EMBY_SERVICE} está PARADO${NC}"
  fi
}

ensure_mount_list() {
  if [ -f "$MOUNT_LIST" ]; then
    return 0
  fi

  mkdir -p "$CACHE_ROOT"

  cat > "$MOUNT_LIST" << EOF
DROPBOX||/mnt/DROPBOX|$CACHE_ROOT/rclone_DROPBOX|/var/log/rclone-DROPBOX.log|100G
00.PEL4K|@3 ! CONTENIDO/00 PEL 4K|/mnt/00.PEL4K|$CACHE_ROOT/rclone_00.PEL4K|/var/log/rclone-00.PEL4K.log|50G
00.SER4K|@3 ! CONTENIDO/00 SER 4K|/mnt/00.SER4K|$CACHE_ROOT/rclone_00.SER4K|/var/log/rclone-00.SER4K.log|50G
01.PEL|@3 ! CONTENIDO/01 PEL|/mnt/01.PEL|$CACHE_ROOT/rclone_01.PEL|/var/log/rclone-01.PEL.log|50G
02.SER|@3 ! CONTENIDO/02 SER|/mnt/02.SER|$CACHE_ROOT/rclone_02.SER|/var/log/rclone-02.SER.log|50G
03.DIB|@3 ! CONTENIDO/03 DIB|/mnt/03.DIB|$CACHE_ROOT/rclone_03.DIB|/var/log/rclone-03.DIB.log|50G
04.DIBSER|@3 ! CONTENIDO/04 DIB SER|/mnt/04.DIBSER|$CACHE_ROOT/rclone_04.DIBSER|/var/log/rclone-04.DIBSER.log|50G
05.ANI|@3 ! CONTENIDO/05 ANI|/mnt/05.ANI|$CACHE_ROOT/rclone_05.ANI|/var/log/rclone-05.ANI.log|50G
06.ANISER|@3 ! CONTENIDO/06 ANI SER|/mnt/06.ANISER|$CACHE_ROOT/rclone_06.ANISER|/var/log/rclone-06.ANISER.log|50G
07.DOC|@3 ! CONTENIDO/07 DOC|/mnt/07.DOC|$CACHE_ROOT/rclone_07.DOC|/var/log/rclone-07.DOC.log|50G
08.DOCSER|@3 ! CONTENIDO/08 DOC SER|/mnt/08.DOCSER|$CACHE_ROOT/rclone_08.DOCSER|/var/log/rclone-08.DOCSER.log|50G
09.PTV|@3 ! CONTENIDO/09 PTV|/mnt/09.PTV|$CACHE_ROOT/rclone_09.PTV|/var/log/rclone-09.PTV.log|50G
10.CON|@3 ! CONTENIDO/10 CON|/mnt/10.CON|$CACHE_ROOT/rclone_10.CON|/var/log/rclone-10.CON.log|50G
11.DEP|@3 ! CONTENIDO/11 DEP|/mnt/11.DEP|$CACHE_ROOT/rclone_11.DEP|/var/log/rclone-11.DEP.log|50G
12.AUDLIB|@3 ! CONTENIDO/12 AUD-LIB|/mnt/12.AUDLIB|$CACHE_ROOT/rclone_12.AUDLIB|/var/log/rclone-12.AUDLIB.log|50G
EOF
}

create_structure() {
  ensure_mount_list
  mkdir -p "$CACHE_ROOT"

  while IFS='|' read -r remote subpath mountpoint cache_dir log_file cache_size; do
    mkdir -p "$mountpoint" "$cache_dir"
  done < "$MOUNT_LIST"

  ESTRUCTURA=1
  save_status
  echo "Estructura creada"
}

generate_mount_script() {
  ensure_mount_list

  cat > /root/montar_emby_isla.sh << EOF
#!/bin/bash

EMBY_SERVICE="$EMBY_SERVICE"
MOUNT_LIST="$MOUNT_LIST"
CACHE_ROOT="$CACHE_ROOT"

echo "=== INICIO MONTAJE \$(date) ==="

mkdir -p "\$CACHE_ROOT"

sleep 5
systemctl stop "\$EMBY_SERVICE" 2>/dev/null

pkill -f "rclone mount" 2>/dev/null
sleep 3

while IFS='|' read -r remote subpath mountpoint cache_dir log_file cache_size; do
  umount -l "\$mountpoint" 2>/dev/null
  mkdir -p "\$mountpoint" "\$cache_dir"

  nohup rclone mount "\${remote}:\${subpath}" "\$mountpoint" \\
    --allow-other \\
    --allow-non-empty \\
    --umask 002 \\
    --dir-cache-time 1000h \\
    --poll-interval 30s \\
    --buffer-size 256M \\
    --vfs-cache-mode full \\
    --vfs-cache-max-size "\$cache_size" \\
    --vfs-cache-max-age 6h \\
    --vfs-read-chunk-size 512M \\
    --vfs-read-chunk-size-limit 0 \\
    --cache-dir "\$cache_dir" \\
    --log-file "\$log_file" \\
    --log-level INFO \\
    > /dev/null 2>&1 &

  sleep 2
done < "\$MOUNT_LIST"

sleep 15
systemctl start "\$EMBY_SERVICE"

echo "=== FIN MONTAJE \$(date) ==="
EOF

  chmod +x /root/montar_emby_isla.sh
}

generate_watchdog_script() {
  ensure_mount_list

  cat > "$WATCHDOG_SCRIPT" << EOF
#!/bin/bash

MOUNT_LIST="$MOUNT_LIST"
LOG="$WATCHDOG_LOG"
EMBY_SERVICE="$EMBY_SERVICE"

failed=0

while IFS='|' read -r remote subpath mountpoint cache_dir log_file cache_size; do
  if ! findmnt "\$mountpoint" >/dev/null 2>&1; then
    echo "\$(date) - ERROR mount caído: \$mountpoint" >> "\$LOG"
    failed=1
  fi
done < "\$MOUNT_LIST"

if ! systemctl is-active --quiet "\$EMBY_SERVICE"; then
  echo "\$(date) - ERROR \$EMBY_SERVICE parado, arrancando" >> "\$LOG"
  systemctl start "\$EMBY_SERVICE" >> "\$LOG" 2>&1
fi

if [ "\$failed" -eq 1 ]; then
  echo "\$(date) - Relanzando montaje completo" >> "\$LOG"
  /root/montar_emby_isla.sh >> "\$LOG" 2>&1
fi
EOF

  chmod +x "$WATCHDOG_SCRIPT"
}

install_systemd_service() {
  generate_mount_script

  cat > "$SYSTEMD_SERVICE" << EOF
[Unit]
Description=Montaje rclone $SERVER_NAME
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/root/montar_emby_isla.sh
RemainAfterExit=yes
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable emby-isla-mounts.service
  SYSTEMD_OK=1
  save_status
  echo -e "${GREEN}Servicio systemd instalado y habilitado.${NC}"
}

install_cron_and_watchdog() {
  generate_watchdog_script

  TMP_CRON="$(mktemp)"
  crontab -l 2>/dev/null | \
    grep -v "$WATCHDOG_SCRIPT" | \
    grep -v "0 4 */2 \* \* /usr/sbin/reboot" > "$TMP_CRON" || true

  {
    cat "$TMP_CRON"
    echo "*/5 * * * * $WATCHDOG_SCRIPT"
    echo "0 4 */2 * * /usr/sbin/reboot"
  } | crontab -

  rm -f "$TMP_CRON"

  CRON_OK=1
  save_status

  echo -e "${GREEN}Cron instalado:${NC}"
  echo " - Watchdog cada 5 minutos"
  echo " - Reinicio cada 2 días a las 04:00"
}

check_all_mounts() {
  ensure_mount_list

  echo -e "${BLUE}Comprobando montajes...${NC}"
  echo ""

  local ok=0
  local fail=0

  while IFS='|' read -r remote subpath mountpoint cache_dir log_file cache_size; do
    printf "%-30s" "$mountpoint"

    if findmnt "$mountpoint" > /dev/null 2>&1; then
      first_item=$(timeout 10 ls -A "$mountpoint" 2>/dev/null | head -n 1)
      if [ -n "$first_item" ]; then
        echo -e " ${GREEN}MONTADO Y CON CONTENIDO${NC}"
        ok=$((ok + 1))
      else
        if timeout 15 rclone lsd "${remote}:${subpath}" >/tmp/rclone_check.$$ 2>/dev/null && [ -s /tmp/rclone_check.$$ ]; then
          echo -e " ${YELLOW}MONTADO; REMOTE CON SUBCARPETAS${NC}"
        elif timeout 15 rclone lsd "${remote}:${subpath}" >/tmp/rclone_check.$$ 2>/dev/null; then
          echo -e " ${YELLOW}MONTADO PERO REMOTE VACÍO${NC}"
        else
          echo -e " ${RED}MONTADO PERO RUTA REMOTA NO RESPONDE${NC}"
        fi
        rm -f /tmp/rclone_check.$$
        fail=$((fail + 1))
      fi
    else
      echo -e " ${RED}SIN MONTAR${NC}"
      fail=$((fail + 1))
    fi
  done < "$MOUNT_LIST"

  echo ""
  echo -e "${GREEN}Correctos:${NC} $ok"
  echo -e "${RED}Con problema:${NC} $fail"
}

full_diagnostic() {
  ensure_mount_list

  echo -e "${BLUE}==============================================${NC}"
  echo -e "${BLUE}        DIAGNÓSTICO INTEGRAL $SERVER_NAME${NC}"
  echo -e "${BLUE}==============================================${NC}"
  echo ""

  local total_ok=0
  local total_warn=0
  local total_fail=0

  echo -e "${YELLOW}1) Estado de Emby${NC}"
  if systemctl is-active --quiet "$EMBY_SERVICE"; then
    echo -e "   ${GREEN}OK${NC} $EMBY_SERVICE está ACTIVO"
    total_ok=$((total_ok + 1))
  else
    echo -e "   ${RED}ERROR${NC} $EMBY_SERVICE está PARADO"
    total_fail=$((total_fail + 1))
  fi
  echo ""

  echo -e "${YELLOW}2) Script de montaje${NC}"
  if [ -x /root/montar_emby_isla.sh ]; then
    echo -e "   ${GREEN}OK${NC} /root/montar_emby_isla.sh existe y es ejecutable"
    total_ok=$((total_ok + 1))
  else
    echo -e "   ${RED}ERROR${NC} falta /root/montar_emby_isla.sh"
    total_fail=$((total_fail + 1))
  fi
  echo ""

  echo -e "${YELLOW}3) Configuración FUSE${NC}"
  if grep -q '^user_allow_other' /etc/fuse.conf 2>/dev/null; then
    echo -e "   ${GREEN}OK${NC} user_allow_other presente"
    total_ok=$((total_ok + 1))
  else
    echo -e "   ${RED}ERROR${NC} falta user_allow_other en /etc/fuse.conf"
    total_fail=$((total_fail + 1))
  fi
  echo ""

  echo -e "${YELLOW}4) Caché principal${NC}"
  if [ -d "$CACHE_ROOT" ]; then
    echo -e "   ${GREEN}OK${NC} cache root existe: $CACHE_ROOT"
    total_ok=$((total_ok + 1))
  else
    echo -e "   ${YELLOW}AVISO${NC} cache root no existe aún: $CACHE_ROOT"
    total_warn=$((total_warn + 1))
  fi
  echo ""

  echo -e "${YELLOW}5) Remotos y montajes${NC}"
  while IFS='|' read -r remote subpath mountpoint cache_dir log_file cache_size; do
    printf "   %-24s" "${remote}:"
    if rclone listremotes 2>/dev/null | grep -Fxq "${remote}:"; then
      echo -e "${GREEN}REMOTE OK${NC}"
      total_ok=$((total_ok + 1))
    else
      echo -e "${RED}REMOTE FALTA${NC}"
      total_fail=$((total_fail + 1))
      continue
    fi

    printf "   %-24s" "$mountpoint"
    if findmnt "$mountpoint" > /dev/null 2>&1; then
      echo -e "${GREEN}MOUNT OK${NC}"
      total_ok=$((total_ok + 1))
    else
      echo -e "${RED}SIN MONTAR${NC}"
      total_fail=$((total_fail + 1))
    fi

    printf "   %-24s" "$(basename "$log_file")"
    if [ -f "$log_file" ]; then
      echo -e "${GREEN}LOG OK${NC}"
      total_ok=$((total_ok + 1))
    else
      echo -e "${YELLOW}SIN LOG${NC}"
      total_warn=$((total_warn + 1))
    fi

    echo ""
  done < "$MOUNT_LIST"

  echo -e "${YELLOW}6) Systemd${NC}"
  if systemctl is-enabled emby-isla-mounts.service >/dev/null 2>&1; then
    echo -e "   ${GREEN}OK${NC} emby-isla-mounts.service habilitado"
    total_ok=$((total_ok + 1))
  else
    echo -e "   ${YELLOW}AVISO${NC} emby-isla-mounts.service no habilitado"
    total_warn=$((total_warn + 1))
  fi
  echo ""

  echo -e "${YELLOW}7) Cron watchdog + reinicio${NC}"
  CURRENT_CRON="$(crontab -l 2>/dev/null)"
  if echo "$CURRENT_CRON" | grep -Fq "$WATCHDOG_SCRIPT"; then
    echo -e "   ${GREEN}OK${NC} watchdog en cron"
    total_ok=$((total_ok + 1))
  else
    echo -e "   ${YELLOW}AVISO${NC} watchdog no encontrado en cron"
    total_warn=$((total_warn + 1))
  fi

  if echo "$CURRENT_CRON" | grep -Fq "0 4 */2 * * /usr/sbin/reboot"; then
    echo -e "   ${GREEN}OK${NC} reinicio cada 2 días a las 04:00"
    total_ok=$((total_ok + 1))
  else
    echo -e "   ${YELLOW}AVISO${NC} reinicio programado no encontrado"
    total_warn=$((total_warn + 1))
  fi
  echo ""

  echo -e "${BLUE}==============================================${NC}"
  echo -e "${GREEN}OK:${NC} $total_ok   ${YELLOW}Avisos:${NC} $total_warn   ${RED}Errores:${NC} $total_fail"
  echo -e "${BLUE}==============================================${NC}"
}

edit_mount_list() {
  ensure_mount_list
  nano "$MOUNT_LIST"
}

show_logs() {
  echo -e "${BLUE}====== LOGS SYSTEMD ======${NC}"
  systemctl status emby-isla-mounts.service --no-pager -l 2>/dev/null || true
  echo ""
  echo -e "${BLUE}====== WATCHDOG ======${NC}"
  tail -50 "$WATCHDOG_LOG" 2>/dev/null || echo "No existe aún $WATCHDOG_LOG"
  echo ""
  echo -e "${BLUE}====== CRONTAB ======${NC}"
  crontab -l 2>/dev/null || echo "No hay crontab"
}

backup_config() {
  DEST="/root/backup_emby_isla_config_$(date +%F_%H-%M-%S)"
  mkdir -p "$DEST"

  [ -f /root/emby_isla.sh ] && cp -a /root/emby_isla.sh "$DEST/"
  [ -f "$MOUNT_LIST" ] && cp -a "$MOUNT_LIST" "$DEST/"
  [ -f /root/.config/rclone/rclone.conf ] && cp -a /root/.config/rclone/rclone.conf "$DEST/"
  [ -f /root/montar_emby_isla.sh ] && cp -a /root/montar_emby_isla.sh "$DEST/"
  [ -f "$WATCHDOG_SCRIPT" ] && cp -a "$WATCHDOG_SCRIPT" "$DEST/"

  crontab -l 2>/dev/null > "$DEST/crontab.txt" || true
  systemctl cat emby-isla-mounts.service > "$DEST/emby-isla-mounts.service.txt" 2>/dev/null || true

  echo -e "${GREEN}Backup guardado en:${NC} $DEST"
}

load_status
refresh_status_from_system

while true; do
  echo ""
  echo -e "${BLUE}==============================================${NC}"
  echo -e "${BLUE}      🚀 $SERVER_NAME MANAGER - ESTABLE${NC}"
  echo -e "${BLUE}==============================================${NC}"
  echo "1)  $(checkmark $DEPENDENCIAS) 📦 Instalar dependencias"
  echo "2)  $(checkmark $RCLONE) ☁️ Instalar rclone"
  echo "3)  $(checkmark $CONFIG) 🔑 Editar rclone.conf"
  echo "4)  $(checkmark $ESTRUCTURA) 📁 Crear estructura"
  echo "5)  📝 Editar lista de montajes"
  echo "6)  $(checkmark $MOUNTS) ▶️ Montar TODO"
  echo "7)  $(checkmark $SYSTEMD_OK) ⚙️ Instalar systemd arranque automático"
  echo "8)  $(checkmark $CRON_OK) 🛡️ Instalar watchdog + cron + reboot cada 2 días"
  echo "9)  ▶️ Iniciar Emby + mostrar enlace"
  echo "10) ♻️ Reiniciar Emby"
  echo "11) 📊 Estado rápido"
  echo "12) 🔍 Comprobar montajes"
  echo "13) 🩺 Diagnóstico integral"
  echo "14) 📜 Ver logs systemd/watchdog/cron"
  echo "15) 💽 Backup de configuración"
  echo "0)  ❌ Salir"
  echo -e "${BLUE}==============================================${NC}"

  read -r -p "👉 Selecciona opción: " opcion

  case "$opcion" in
    1)
      echo -e "${GREEN}Instalando dependencias...${NC}"
      apt update && apt install -y \
        fuse3 curl wget unzip htop nano git ca-certificates \
        lsb-release apt-transport-https gnupg python3 tar
      DEPENDENCIAS=1
      save_status
      pause
      ;;

    2)
      echo -e "${GREEN}Instalando rclone...${NC}"
      curl https://rclone.org/install.sh | bash
      echo ""
      rclone version
      RCLONE=1
      save_status
      pause
      ;;

    3)
      echo -e "${YELLOW}Editando rclone.conf...${NC}"
      mkdir -p /root/.config/rclone
      touch /root/.config/rclone/rclone.conf
      nano /root/.config/rclone/rclone.conf
      chmod 600 /root/.config/rclone/rclone.conf
      grep -q '^user_allow_other' /etc/fuse.conf || echo 'user_allow_other' >> /etc/fuse.conf
      CONFIG=1
      save_status
      pause
      ;;

    4)
      echo -e "${GREEN}Creando estructura...${NC}"
      create_structure
      echo ""
      echo "Lista de montajes: $MOUNT_LIST"
      pause
      ;;

    5)
      edit_mount_list
      pause
      ;;

    6)
      echo -e "${GREEN}Montando todo...${NC}"
      ensure_mount_list
      generate_mount_script

      if ! bash -n /root/montar_emby_isla.sh; then
        echo -e "${RED}El script de montaje tiene errores.${NC}"
        pause
        continue
      fi

      /root/montar_emby_isla.sh
      MOUNTS=1
      save_status
      show_emby_state
      show_emby_link
      echo ""
      check_all_mounts
      pause
      ;;

    7)
      echo -e "${GREEN}Instalando systemd de arranque automático...${NC}"
      install_systemd_service
      pause
      ;;

    8)
      echo -e "${GREEN}Instalando watchdog + cron + reboot cada 2 días a las 04:00...${NC}"
      install_cron_and_watchdog
      pause
      ;;

    9)
      echo -e "${GREEN}Iniciando Emby...${NC}"
      systemctl start "$EMBY_SERVICE"
      sleep 2
      if systemctl is-active --quiet "$EMBY_SERVICE"; then
        EMBY_OK=1
        save_status
      fi
      show_emby_state
      show_emby_link
      pause
      ;;

    10)
      echo -e "${YELLOW}Reiniciando Emby...${NC}"
      systemctl restart "$EMBY_SERVICE"
      sleep 2
      if systemctl is-active --quiet "$EMBY_SERVICE"; then
        EMBY_OK=1
        save_status
      fi
      show_emby_state
      show_emby_link
      pause
      ;;

    11)
      echo -e "${BLUE}Estado rápido${NC}"
      echo ""
      echo "Mounts rclone:"
      findmnt -t fuse.rclone
      echo ""
      echo "Emby:"
      show_emby_state
      show_emby_link
      echo ""
      echo "Disco raíz:"
      df -h /
      echo ""
      echo "Cache root:"
      df -h "$CACHE_ROOT" 2>/dev/null || true
      echo ""
      echo "RAM:"
      free -h
      pause
      ;;

    12)
      check_all_mounts
      pause
      ;;

    13)
      full_diagnostic
      pause
      ;;

    14)
      show_logs
      pause
      ;;

    15)
      backup_config
      pause
      ;;

    0)
      exit
      ;;

    *)
      echo "Opción no válida"
      pause
      ;;
  esac

  refresh_status_from_system
done
