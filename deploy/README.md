# Deployment

Target: one server, two application containers plus database.

## Services

- `frontend`: Flutter Web static build served by Nginx/Caddy.
- `backend`: Dart API.
- `postgres`: database.
- `reverse-proxy`: public HTTPS entrypoint.

## Flow

```text
git pull
docker compose build
docker compose up -d
```

## Required server files

- `.env`, based on `.env.example`;
- TLS config or internal CA if not using public DNS;
- database volume backup policy.

## Backend storage

Production/Docker mode uses PostgreSQL:

```text
STORE_DRIVER=postgres
DATABASE_URL=postgres://neotelecom:change-me@postgres:5432/neotelecom?sslmode=disable
CREDENTIALS_ENCRYPTION_KEY=change-me-32-byte-key
ALLOW_INSECURE_TLS=true
```

Local development can still use JSON storage:

```text
STORE_DRIVER=json
STORE_PATH=data/store.json
```

## Deployment notes

- Do not commit real `.env`.
- Backend should not be exposed directly to the internet.
- Use read-only Proxmox API tokens for the MVP.
- Replace `CREDENTIALS_ENCRYPTION_KEY` before adding real sources.
- Set `ALLOW_INSECURE_TLS=false` if Proxmox/PBS uses trusted certificates.
- Back up PostgreSQL before migrations.
