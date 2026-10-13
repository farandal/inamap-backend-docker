#!/usr/bin/env bash
# ----------------------------------------------------------------------------
# INAMAP — utilitario del runtime local.
#
#   ./inamap.sh init              crea .env y .env.app.local con secretos nuevos
#   ./inamap.sh up [--core-dev] [--tunnel]
#                                 levanta el stack, migra y siembra la 1.ª vez;
#                                 --tunnel además publica api-dev/ws-dev.inamap.space
#   ./inamap.sh tunnel:init       crea .env.app.tunnel y .env.tunnel (una vez)
#   ./inamap.sh tunnel            abre el Cloudflare Tunnel (en primer plano)
#   ./inamap.sh down              detiene el stack (conserva la base de datos)
#   ./inamap.sh restart           reinicia el contenedor app
#   ./inamap.sh status            estado de los contenedores y procesos
#   ./inamap.sh logs [laravel|horizon|reverb|nginx]
#   ./inamap.sh migrate           php artisan migrate (nunca migrate:fresh)
#   ./inamap.sh seed              php artisan db:seed (base nueva)
#   ./inamap.sh seed:base         monedas, idiomas y plan de prueba (idempotente)
#   ./inamap.sh test [args]       suite Domain contra la base de pruebas
#   ./inamap.sh artisan <cmd>     cualquier comando artisan
#   ./inamap.sh shell | tinker
#
# --core-dev monta el código del core (../dash-backend) — solo para el equipo del core.
# --tunnel usa .env.app.tunnel (APP_URL/REVERB públicos) y queda recordado hasta `down`.
# ----------------------------------------------------------------------------
set -euo pipefail

cd "$(dirname "$0")"

COMPOSE_FILES=(-f docker-compose.yml)
if [[ " $* " == *" --core-dev "* ]] || [[ -f storage/.core-dev ]]; then
  COMPOSE_FILES+=(-f docker-compose.core-dev.yml)
fi

# Modo túnel: monta .env.app.tunnel en lugar de .env.app.local. Una variable de
# entorno real gana sobre APP_ENV_FILE de .env, y el marcador lo recuerda entre
# comandos (igual que --core-dev).
TUNNEL_APP_ENV="./.env.app.tunnel"
TUNNEL_ENV=".env.tunnel"
TUNNEL_SCRIPT="../dash-backend-docker/scripts/cloudflare-tunnel.js"
if [[ " $* " == *" --tunnel "* ]] || [[ -f storage/.tunnel ]] || [[ "${1:-}" == "tunnel" ]]; then
  TUNNEL_MODE=1
  export APP_ENV_FILE="$TUNNEL_APP_ENV"
else
  TUNNEL_MODE=0
fi

compose() { docker compose "${COMPOSE_FILES[@]}" "$@"; }
artisan() { compose exec app php artisan "$@"; }

info() { printf '\033[1;34m›\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31m✗\033[0m %s\n' "$*" >&2; exit 1; }

rand_hex() { openssl rand -hex "${1:-16}"; }

# Reemplaza KEY=... en un archivo env (portable macOS/Linux, sin sed -i).
set_env() {
  local file="$1" key="$2" value="$3" tmp
  tmp="$(mktemp)"
  awk -v k="$key" -v v="$value" 'BEGIN{done=0} $0 ~ "^"k"=" {print k"="v; done=1; next} {print} END{if(!done) print k"="v}' "$file" > "$tmp"
  mv "$tmp" "$file"
}

get_env() { grep -E "^$2=" "$1" 2>/dev/null | tail -1 | cut -d= -f2-; }

require_env() {
  [[ -f .env ]] || fail "Falta .env — ejecute ./inamap.sh init"
  local app_env
  app_env="${APP_ENV_FILE:-$(get_env .env APP_ENV_FILE)}"; app_env="${app_env:-./.env.app.local}"
  [[ -f "$app_env" ]] || fail "Falta $app_env — ejecute ./inamap.sh $([[ "$app_env" == "$TUNNEL_APP_ENV" ]] && echo tunnel:init || echo init)"
  [[ -d "$(get_env .env DOMAIN_PATH || echo ../inamap-backend-domain)" ]] || fail "No se encuentra el dominio (DOMAIN_PATH en .env)"
  [[ -n "$(get_env .env DASH_IMAGE)" && "$(get_env .env DASH_IMAGE)" != *"<tag>"* ]] || fail "Defina DASH_IMAGE en .env (imagen del core entregada por el equipo del core)"
}

prepare_dirs() {
  mkdir -p storage/app-storage/{app/public,framework/{cache,sessions,views},logs} storage/bootstrap-cache storage/pgsql-data reports
}

cmd_init() {
  if [[ ! -f .env ]]; then
    cp .env.example .env
    set_env .env DB_PASSWORD "$(rand_hex 16)"
    info "Creado .env — revise DASH_IMAGE antes de continuar."
  else
    info ".env ya existe; no se modifica."
  fi

  if [[ ! -f .env.app.local ]]; then
    cp .env.app.example .env.app.local
    local reverb_key reverb_secret
    reverb_key="$(rand_hex 10)"; reverb_secret="$(rand_hex 16)"
    set_env .env.app.local APP_KEY "base64:$(openssl rand -base64 32)"
    set_env .env.app.local DB_PASSWORD "$(get_env .env DB_PASSWORD)"
    set_env .env.app.local DB_DATABASE "$(get_env .env DB_DATABASE)"
    set_env .env.app.local DB_DATABASE_TEST "$(get_env .env DB_DATABASE_TEST)"
    set_env .env.app.local DB_USERNAME "$(get_env .env DB_USERNAME)"
    set_env .env.app.local APP_PORT "$(get_env .env APP_PORT)"
    set_env .env.app.local APP_URL "http://localhost:$(get_env .env APP_PORT)"
    set_env .env.app.local REVERB_PORT "$(get_env .env REVERB_PUBLIC_PORT)"
    set_env .env.app.local PUSHER_APP_PORT "$(get_env .env REVERB_PUBLIC_PORT)"
    set_env .env.app.local REVERB_APP_ID "$((RANDOM * 10 + 100000))"
    set_env .env.app.local REVERB_APP_KEY "$reverb_key"
    set_env .env.app.local REVERB_APP_SECRET "$reverb_secret"
    set_env .env.app.local PUSHER_APP_ID "$(get_env .env.app.local REVERB_APP_ID)"
    set_env .env.app.local PUSHER_APP_KEY "$reverb_key"
    set_env .env.app.local PUSHER_APP_SECRET "$reverb_secret"
    for user in SYSTEM_ADMIN TENANT_ADMIN NORMAL_USER; do
      set_env .env.app.local "${user}_PASSWORD" "$(rand_hex 8)"
    done
    chmod 640 .env .env.app.local
    info "Creado .env.app.local con APP_KEY, contraseñas y claves de Reverb nuevas."
  else
    info ".env.app.local ya existe; no se modifica."
  fi

  prepare_dirs
}

cmd_tunnel_init() {
  [[ -f .env.app.local ]] || fail "Falta .env.app.local — ejecute ./inamap.sh init primero"
  if [[ ! -f .env.app.tunnel ]]; then
    cp .env.app.local .env.app.tunnel
    set_env .env.app.tunnel APP_URL "https://api-dev.inamap.space"
    set_env .env.app.tunnel REVERB_HOST "ws-dev.inamap.space"
    set_env .env.app.tunnel REVERB_PORT "443"
    set_env .env.app.tunnel REVERB_SCHEME "https"
    set_env .env.app.tunnel FRONTEND_URL "https://web-dev.inamap.space"
    set_env .env.app.tunnel INAMAP_APP_URL "https://app-dev.inamap.space"
    chmod 640 .env.app.tunnel
    info "Creado .env.app.tunnel (copia de .env.app.local con APP_URL y Reverb públicos)."
    info "FRONTEND_URL / INAMAP_APP_URL apuntan a web-dev / app-dev .inamap.space (frontends: ../inamap-frontend-domain, pnpm dev:tunnel:all)."
  else
    info ".env.app.tunnel ya existe; no se modifica."
  fi
  if [[ ! -f "$TUNNEL_ENV" ]]; then
    cp .env.tunnel.example "$TUNNEL_ENV"
    set_env "$TUNNEL_ENV" CF_TUNNEL_LOCAL_API "http://localhost:$(get_env .env APP_PORT)"
    set_env "$TUNNEL_ENV" CF_TUNNEL_LOCAL_WS "http://localhost:$(get_env .env REVERB_PUBLIC_PORT)"
    chmod 600 "$TUNNEL_ENV"
    info "Creado $TUNNEL_ENV — complete CF_API_TOKEN y CF_ACCOUNT_ID (y CF_ZONE_ID si lo tiene)."
  else
    info "$TUNNEL_ENV ya existe; no se modifica."
  fi
}

cmd_tunnel() {
  [[ -f "$TUNNEL_ENV" ]] || fail "Falta $TUNNEL_ENV — ejecute ./inamap.sh tunnel:init"
  [[ -f "$TUNNEL_SCRIPT" ]] || fail "No se encuentra $TUNNEL_SCRIPT (se necesita el repo dash-backend-docker como carpeta hermana)"
  command -v node >/dev/null || fail "Falta node"
  [[ -n "$(get_env "$TUNNEL_ENV" CF_API_TOKEN)" && -n "$(get_env "$TUNNEL_ENV" CF_ACCOUNT_ID)" ]] \
    || fail "Complete CF_API_TOKEN y CF_ACCOUNT_ID en $TUNNEL_ENV"
  info "Túnel: api-dev.inamap.space → :$(get_env .env APP_PORT) · ws-dev.inamap.space → :$(get_env .env REVERB_PUBLIC_PORT)"
  exec node "$TUNNEL_SCRIPT" --env-file "$TUNNEL_ENV"
}

wait_for_app() {
  info "Esperando al contenedor app…"
  for _ in $(seq 1 60); do
    if compose exec -T app php artisan --version >/dev/null 2>&1; then
      return 0
    fi
    sleep 3
  done
  fail "El contenedor app no respondió. Revise: ./inamap.sh logs"
}

cmd_up() {
  require_env
  prepare_dirs
  if [[ " $* " == *" --core-dev "* ]]; then touch storage/.core-dev; fi
  if [[ "$TUNNEL_MODE" == 1 ]]; then
    [[ -f .env.app.tunnel && -f "$TUNNEL_ENV" ]] || fail "Falta la config del túnel — ejecute ./inamap.sh tunnel:init"
    touch storage/.tunnel
  fi

  compose up -d
  wait_for_app

  info "Migraciones (core + dominio)…"
  artisan migrate --force

  if [[ ! -f storage/.seeded ]]; then
    info "Primera ejecución: sembrando datos base, roles y permisos…"
    artisan db:seed --force && touch storage/.seeded
  fi

  info "Listo:"
  echo "  API       http://localhost:$(get_env .env APP_PORT)/api"
  echo "  Reverb    ws://localhost:$(get_env .env REVERB_PUBLIC_PORT)"
  echo "  Mailhog   http://localhost:$(get_env .env MAILHOG_UI_PORT)"
  echo "  Postgres  localhost:$(get_env .env DB_FORWARD_PORT) (usuario $(get_env .env DB_USERNAME))"
  echo "  Usuarios de prueba: ver SYSTEM_ADMIN_* / TENANT_ADMIN_* / NORMAL_USER_* en .env.app.local"

  if [[ "$TUNNEL_MODE" == 1 ]]; then
    echo "  Público   https://api-dev.inamap.space/api · wss://ws-dev.inamap.space"
    cmd_tunnel
  fi
}

cmd_logs() {
  local target="${1:-laravel}"
  case "$target" in
    laravel) compose exec app tail -f /var/www/dash/storage/logs/laravel.log ;;
    horizon) compose exec app tail -f /var/www/dash/storage/logs/supervisor-horizon.log /var/www/dash/storage/logs/supervisor-horizon-error.log ;;
    reverb)  compose exec app tail -f /var/www/dash/storage/logs/supervisor-reverb.log /var/www/dash/storage/logs/supervisor-reverb-error.log ;;
    nginx)   compose exec app tail -f /var/log/nginx/dash.access.log /var/log/nginx/dash.nginx.error.log ;;
    *)       compose logs -f "$target" ;;
  esac
}

# Datos de referencia que el registro de prueba necesita (monedas, idiomas, plan
# por defecto). Idempotente: sirve para bases sembradas antes de que existieran.
BASE_SEEDERS=(Common\\CurrencySeeder Common\\LanguageSeeder Subscription\\TrialSubscriptionPlanSeeder)
cmd_seed_base() {
  for seeder in "${BASE_SEEDERS[@]}"; do
    compose exec -T app php artisan db:seed --force --class="Domain\\Database\\Seeders\\${seeder}"
  done
}

cmd_test() {
  local test_db
  test_db="$(get_env .env DB_DATABASE_TEST)"
  # El TestCase del core migra y siembra la base de pruebas (RefreshDatabase).
  compose exec -e DB_DATABASE="${test_db:-im_dev_db_test}" app php artisan test --testsuite=Domain "$@"
}

command="${1:-help}"
shift || true
args=()
for a in "$@"; do [[ "$a" == "--core-dev" || "$a" == "--tunnel" ]] || args+=("$a"); done

case "$command" in
  init)     cmd_init ;;
  up)       cmd_up "$@" ;;
  tunnel:init) cmd_tunnel_init ;;
  tunnel)   cmd_tunnel ;;
  down)     compose down; rm -f storage/.core-dev storage/.tunnel ;;
  restart)  compose restart app ;;
  status)   compose ps; compose exec app supervisorctl -c /etc/supervisor/supervisord.conf status || true ;;
  logs)     cmd_logs "${args[@]+"${args[@]}"}" ;;
  migrate)  artisan migrate --force ;;
  seed)     artisan db:seed --force && touch storage/.seeded ;;
  seed:base) cmd_seed_base ;;
  test)     cmd_test "${args[@]+"${args[@]}"}" ;;
  artisan)  artisan "${args[@]+"${args[@]}"}" ;;
  shell)    compose exec app bash ;;
  tinker)   artisan tinker ;;
  *)        sed -n '3,26p' "$0" ;;
esac
