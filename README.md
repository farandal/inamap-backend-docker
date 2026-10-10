# INAMAP — entorno local (Docker)

Runtime local del backend de INAMAP. Levanta el **core DASHADMIN** desde una imagen
Docker publicada y monta el **dominio INAMAP** (`inamap-backend-domain`) encima. No se
necesita el código fuente del core.

```text
carpeta-de-trabajo/
├── inamap-backend-docker/    ← este repositorio (runtime)
└── inamap-backend-domain/    ← código del dominio (se edita en vivo)
```

## Requisitos

- Docker Desktop (o Docker Engine + Compose v2) — en Windows, usar WSL2.
- `bash` y `openssl` (incluidos en macOS, Linux y WSL).
- Acceso a la imagen del core (`DASH_IMAGE`), entregada por el equipo del core.

## Primer arranque

```bash
git clone <url>/inamap-backend-docker.git
git clone <url>/inamap-backend-domain.git
cd inamap-backend-docker

./inamap.sh init        # crea .env y .env.app.local con secretos nuevos
# editar .env → DASH_IMAGE=<imagen y tag entregados>
./inamap.sh up          # levanta, migra y siembra roles/permisos la primera vez
```

Al terminar muestra las URLs. Los usuarios de prueba (administrador de sistema, de tenant
y usuario normal) y sus contraseñas están en `.env.app.local`.

| Servicio | URL local |
|---|---|
| API | http://localhost:25200/api |
| Websockets (Reverb) | ws://localhost:27001 |
| Mailhog (correos) | http://localhost:25030 |
| PostgreSQL | `localhost:25434` · base `im_dev_db` · usuario `im` |
| Redis | `localhost:25389` |

## Uso diario

```bash
./inamap.sh up                 # levantar (idempotente)
./inamap.sh down               # detener (los datos se conservan)
./inamap.sh status             # contenedores + Horizon / Reverb / scheduler
./inamap.sh logs               # log de Laravel   (también: horizon | reverb | nginx)
./inamap.sh migrate            # aplicar migraciones nuevas del dominio
./inamap.sh seed:base          # monedas, idiomas y plan de prueba (idempotente)
./inamap.sh test               # suite Domain (base de pruebas aparte)
./inamap.sh test --filter=RouteSessionTest
./inamap.sh artisan route:list --path=inamap
./inamap.sh shell              # bash dentro del contenedor
./inamap.sh tinker
```

Los cambios en `../inamap-backend-domain` se ven al instante: está montado en el
contenedor. Tras cambiar **rutas o config** del dominio: `./inamap.sh restart`
(la caché de rutas/config se regenera al iniciar).

## Archivos

| Archivo | Qué es | ¿Va a git? |
|---|---|---|
| `docker-compose.yml` | Stack: app (core + dominio), PostgreSQL, Redis, Mailhog | Sí |
| `docker-compose.core-dev.yml` | Opcional: monta el código del core para editarlo (solo equipo del core) | Sí |
| `inamap.sh` | Utilitario de comandos | Sí |
| `.env.example` / `.env` | Variables de Compose: imagen, puertos, credenciales de BD | Solo el ejemplo |
| `.env.app.example` / `.env.app.local` | Env de Laravel montado en el contenedor | Solo el ejemplo |
| `docker/pgsql/create-testing-db.sh` | Crea la base principal y la de pruebas | Sí |
| `domain-config-layers/` | Capas de config opcionales (vacío por defecto) | Sí |
| `storage/` | Datos de ejecución: archivos subidos, logs, caché, datos de PostgreSQL | No |

## Reglas importantes

- **Nunca** ejecutar `migrate:fresh`, `migrate:refresh` ni `db:wipe` sobre la base de
  desarrollo: usar `./inamap.sh migrate`. La suite de pruebas usa su propia base
  (`im_dev_db_test`).
- `.env` y `.env.app.local` contienen secretos: no se comparten por chat ni se suben a git.
  Cada desarrollador genera los suyos con `./inamap.sh init`.
- Para empezar de cero **a propósito**: `./inamap.sh down`, borrar `storage/pgsql-data` y
  `storage/.seeded`, y `./inamap.sh up`.

## Problemas frecuentes

| Síntoma | Causa / solución |
|---|---|
| `Defina DASH_IMAGE en .env` | Falta la imagen del core en `.env`. |
| `app` no arranca, `pgsql_setup` no queda *healthy* | `DB_PASSWORD` de `.env` y `.env.app.local` no coinciden, o se cambió la contraseña con la base ya creada (borrar `storage/pgsql-data` solo si no hay datos que conservar). |
| Error 500 "No application encryption key" | `.env.app.local` sin `APP_KEY`, o sin permiso de lectura (usar `chmod 640`). |
| Puerto ocupado | Cambiar el puerto en `.env` (y `APP_URL` / `REVERB_PORT` en `.env.app.local`). |
| `POST /api/trial/register` responde 422 `primary_currency: Invalid currency selected.` | Faltan los datos de referencia (monedas, idiomas, plan de prueba): `./inamap.sh seed:base`. |
| Rutas nuevas del dominio dan 404 | `./inamap.sh restart` (regenera la caché de rutas). |

## Para el equipo del core

Con `../dash-backend` en disco, `./inamap.sh up --core-dev` monta el código del core sobre
la imagen (queda recordado hasta `./inamap.sh down`). Imagen local:

```bash
cd ../dash-backend
docker build -f docker/php8.3/Dockerfile.core -t local/dash-backend-core:latest --build-arg OBFUSCATE_APP=false .
```

Guías completas de desarrollo (Docker, backend, frontend, comandos rápidos) en
[`inamap-documentation/desarrollo`](../inamap-documentation/README.md).

La especificación funcional y técnica del dominio está en
[`inamap-backend-domain/README.md`](../inamap-backend-domain/README.md).
