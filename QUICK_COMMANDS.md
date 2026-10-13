# inamap-backend-docker — Quick Commands

Todo se ejecuta desde `inamap-backend-docker/` con `./inamap.sh`. Guía completa: [README.md](./README.md).

## Arranque

```bash
./inamap.sh init                # una vez: .env + .env.app.local con secretos nuevos
./inamap.sh up                  # local: http://localhost:25200
./inamap.sh up --tunnel         # público: api-dev / ws-dev .inamap.space (túnel en primer plano)
./inamap.sh tunnel              # solo el túnel (el stack ya corre)
./inamap.sh down                # detiene todo (conserva la base) y olvida --tunnel / --core-dev
./inamap.sh restart             # reinicia app (tras cambiar rutas/config del dominio)
./inamap.sh status              # contenedores + Horizon / Reverb / scheduler
```

`up --tunnel` queda recordado hasta `down`: `restart`, `migrate`, etc. siguen usando la env pública.

## URLs

| Servicio | Local | Túnel (`--tunnel`) |
|---|---|---|
| API | http://localhost:25200/api | https://api-dev.inamap.space/api |
| Reverb (WS) | ws://localhost:27001 | wss://ws-dev.inamap.space (443) |
| Mailhog | http://localhost:25030 | — |
| PostgreSQL | `localhost:25434` · `im_dev_db` · usuario `im` | — |
| Redis | `localhost:25389` | — |

## Túnel de Cloudflare

```bash
./inamap.sh tunnel:init         # una vez: crea .env.app.tunnel y .env.tunnel
./inamap.sh up --tunnel         # stack + túnel
```

- Config del túnel: `.env.tunnel` (`CF_*`; zona `inamap.space`, túnel `inamap-dev`). Fuera de git.
- Env de Laravel pública: `.env.app.tunnel` (copia de `.env.app.local` con `APP_URL` y `REVERB_*` públicos).
- Un túnel recién creado puede tardar hasta ~10 min en aceptar conexiones (`Unauthorized: Tunnel not found`
  en el log de cloudflared): es retraso de Cloudflare, no de la config; cloudflared reintenta solo.
  No borre y recree el túnel: reinicia ese retraso.
- Comprobar: `curl -i https://api-dev.inamap.space/api/health` (530 = el túnel aún no conectó).
- Frontends públicos (`app-dev` / `web-dev` / `system-dev` `.inamap.space`) sobre este mismo túnel:
  `cd ../inamap-frontend-domain && pnpm tunnel:init && pnpm dev:tunnel:all` (ver su `TUNNELS.md`).
- CORS: capas `domain-config-layers/10-inamap-local` (localhost) y `20-inamap-tunnel` (hostnames públicos).

## Base de datos

```bash
./inamap.sh migrate             # migraciones nuevas (core + dominio). NUNCA migrate:fresh / db:wipe
./inamap.sh seed                # sembrar base nueva (roles, permisos, usuarios)
./inamap.sh seed:base           # monedas, idiomas y plan de prueba (idempotente)
docker compose exec -T pgsql psql -U im -d im_dev_db
```

## Logs

```bash
./inamap.sh logs                # Laravel
./inamap.sh logs horizon        # colas
./inamap.sh logs reverb         # websockets
./inamap.sh logs nginx
```

## Artisan / tests

```bash
./inamap.sh artisan route:list --path=inamap
./inamap.sh artisan optimize:clear
./inamap.sh artisan tinker      # o: ./inamap.sh tinker
./inamap.sh shell               # bash dentro del contenedor
./inamap.sh test                # suite Domain (base im_dev_db_test)
./inamap.sh test --filter=RouteSessionTest
```

## Procesos internos (supervisord)

```bash
docker compose exec app supervisorctl -c /etc/supervisor/supervisord.conf status
docker compose exec app supervisorctl -c /etc/supervisor/supervisord.conf restart reverb horizon
```

## Imagen del core (solo si cambia el core)

```bash
cd ../dash-backend
docker build -f docker/php8.3/Dockerfile.core -t local/dash-backend-core:latest --build-arg OBFUSCATE_APP=false .
cd ../inamap-backend-docker && ./inamap.sh up
```

Con `../dash-backend` en disco: `./inamap.sh up --core-dev` monta el código del core.

## Problemas frecuentes

| Síntoma | Solución |
|---|---|
| Rutas del dominio dan 404 | `./inamap.sh restart` |
| `https://api-dev.inamap.space` responde 530 | El túnel no está corriendo o aún no conectó: `./inamap.sh tunnel` |
| Cambió `.env.app.tunnel` y no se nota | `./inamap.sh down && ./inamap.sh up --tunnel` |
| Puerto ocupado | Cambiar el puerto en `.env` y `APP_URL` / `REVERB_PORT` en la env de Laravel |
