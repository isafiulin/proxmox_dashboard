# Backend

Dart API service for the infrastructure dashboard.

## Responsibilities

- user authentication;
- bootstrap first admin user;
- admin-only user management;
- source registry;
- encrypted credentials;
- Proxmox VE API adapter;
- Proxmox Backup Server API adapter;
- Redfish and legacy HP iLO 2 hardware adapters;
- normalized read models for the frontend;
- polling workers;
- audit log;
- later orchestration task queue.

## Storage

The backend supports two storage drivers:

- `json` for local development and fast tests;
- `postgres` for Docker/production deployments.

Use PostgreSQL in deployment:

```text
STORE_DRIVER=postgres
DATABASE_URL=postgres://neotelecom:change-me@postgres:5432/neotelecom?sslmode=disable
```

The current PostgreSQL schema is mirrored in `db/schema.sql`.

## Source credentials

Source API tokens are stored encrypted, not hashed, because the backend must use them to query Proxmox APIs.

Required env:

```text
CREDENTIALS_ENCRYPTION_KEY=change-me-32-byte-key
```

Supported token formats:

```text
Proxmox VE: user@realm!tokenid=secret
PBS:        user@realm!tokenid:secret
Redfish:    username:password
Old iLO 2:  username:password (source URL: ssh://host)
```

## Suggested package layout

```text
lib/
  main.dart
  config/
  db/
  http/
  auth/
  users/
  audit/
  sources/
  integrations/
    proxmox_ve/
    proxmox_backup/
    redfish/
  collectors/
  dashboard/
  guests/
  backups/
  common/
test/
```

## Runtime env

See `../deploy/.env.example`.
