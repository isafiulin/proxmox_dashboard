# Архитектура первого этапа

## Принцип

Flutter отвечает только за интерфейс. Все обращения к Proxmox VE, Proxmox Backup Server и будущим iLO/Redfish-интеграциям идут через backend.

Причины:

- токены Proxmox нельзя хранить в браузере;
- нужен единый RBAC и audit log;
- нужны фоновые сборщики данных;
- нужен кэш, чтобы UI не долбил API гипервизоров;
- будущая оркестрация должна исполняться серверной частью.

## Сервисы

### `frontend`

Flutter Web SPA.

Основные экраны первого этапа:

- логин;
- пользователи: список, создание, блокировка/разблокировка, смена пароля;
- список подключенных источников;
- добавление и редактирование источника: `Proxmox VE`, `Proxmox Backup Server`, позже `iLO/Redfish`;
- общий dashboard;
- страница Proxmox VE источника;
- страница Proxmox Backup Server источника;
- карточка VM/LXC с текущими ресурсами и найденными PBS snapshots;
- backup timeline по VM/LXC;
- audit/events;
- settings.

### `backend`

Dart API.

Зоны ответственности:

- авторизация пользователей;
- bootstrap первого администратора;
- управление пользователями из веб-интерфейса;
- хранение подключений к инфраструктуре;
- шифрование и хранение API-токенов;
- адаптеры к Proxmox VE API;
- адаптеры к Proxmox Backup Server API;
- нормализация данных;
- фоновый polling;
- audit log;
- REST API для Flutter;
- исторические data snapshots по polling interval;
- позже: очереди задач и orchestrator.

### `postgres`

Хранит:

- пользователей;
- источники инфраструктуры;
- зашифрованные credentials;
- последние snapshots состояния;
- события аудита;
- историю health/status;
- связи VM/LXC с backup snapshots.
- системные настройки, включая interval фонового сбора.

В текущей реализации backend поддерживает два storage driver:

- `json` - локальный dev/test режим, хранение в `data/store.json`;
- `postgres` - production/Docker режим через `DATABASE_URL`.

Docker Compose использует `STORE_DRIVER=postgres`.

### `redis` later

Нужен не в самом первом MVP, но пригодится для:

- очередей задач;
- distributed locks;
- rate limiting;
- short-lived cache;
- orchestration jobs.

## Доменная модель

### User

В первом этапе система работает с одной ролью: `admin`.

Первый пользователь создается при первом запуске backend из переменных окружения. После входа этот admin может создавать других пользователей через веб-интерфейс.

Поля:

- `id`;
- `email`;
- `password_hash`;
- `display_name`;
- `role`: пока только `admin`;
- `is_active`;
- `last_login_at`;
- `created_at`;
- `updated_at`.

Минимальные правила:

- если пользователей в БД нет, backend создает bootstrap admin;
- bootstrap credentials берутся из `.env`;
- после первого входа admin должен иметь возможность сменить пароль;
- все созданные пользователи пока получают роль `admin`;
- удаление пользователя лучше заменить на `is_active = false`;
- нельзя деактивировать последнего активного admin;
- все действия с пользователями пишутся в audit log.

### Infrastructure source

Источник данных:

- `id`;
- `type`: `proxmox_ve`, `proxmox_backup`, `redfish`;
- `name`;
- `base_url`;
- `status`;
- `last_seen_at`;
- `created_at`;
- `updated_at`.

### System settings

Текущие настройки:

- `collectionIntervalMinutes`: как часто backend собирает snapshots с источников.

По умолчанию используется 30 минут. Допустимый диапазон MVP: 5-1440 минут.

### Data snapshot

Backend сохраняет исторические снимки, потому что Proxmox VE/PBS не решают все задачи исторической аналитики dashboard.

Поля:

- `id`;
- `source_id`;
- `source_type`;
- `status`;
- `payload`: JSON с собранными данными;
- `collected_at`.

В MVP хранится rolling window за последние 7 дней. При новом сборе и при старте backend snapshots старше 7 дней удаляются. Позже нужно добавить агрегации по часу/дню для долгосрочных трендов.

### Proxmox VE

Собираемые сущности:

- cluster;
- node;
- VM/QEMU;
- LXC;
- storage;
- task;
- event/log entry.

Минимальные метрики:

- node online/offline;
- CPU usage;
- memory usage;
- disk usage;
- storage usage;
- VM/LXC status;
- VM/LXC allocated CPU/RAM/disk;
- VM/LXC uptime;
- migration/backup/task failures.

Frontend показывает Proxmox VE как cluster endpoint:

- обзор нод;
- список VM/LXC по нодам;
- переход в карточку конкретной VM/LXC;
- текущий status/current через Proxmox API;
- базовое сопоставление PBS backup snapshots по `backup-id == vmid`.

### Proxmox Backup Server

Собираемые сущности:

- datastore;
- namespace;
- backup group;
- backup snapshot;
- verify job result;
- prune job result;
- sync job result;
- garbage collection status.

Минимальная аналитика:

- когда VM/LXC бэкапилась последний раз;
- есть ли свежий backup в пределах policy;
- есть ли failed jobs;
- сколько занимает datastore;
- retention/verify состояние;
- backup age по каждой VM/LXC.

В MVP backup age считается во frontend:

- `ok`: backup не старше 24 часов;
- `warning`: backup 24-48 часов;
- `critical`: backup старше 48 часов;
- `missing`: matching snapshot не найден.

### iLO / Redfish later

Собираемые данные:

- power state;
- temperatures;
- fans;
- PSU;
- disk/controller health;
- RAM health;
- NIC health;
- firmware versions;
- hardware alerts.

## API backend -> frontend

Начать лучше с REST, без усложнения GraphQL.

Базовые endpoints:

```text
POST   /api/auth/login
POST   /api/auth/logout
GET    /api/me
PATCH  /api/me

GET    /api/users
POST   /api/users
GET    /api/users/:id
PATCH  /api/users/:id
POST   /api/users/:id/change-password
POST   /api/users/:id/deactivate
POST   /api/users/:id/activate

GET    /api/sources
POST   /api/sources
GET    /api/sources/:id
PATCH  /api/sources/:id
DELETE /api/sources/:id
POST   /api/sources/:id/test

GET    /api/dashboard/summary
GET    /api/settings
PATCH  /api/settings
GET    /api/data-snapshots
POST   /api/data-snapshots/collect
GET    /api/proxmox-ve/:sourceId/nodes
GET    /api/proxmox-ve/:sourceId/resources
GET    /api/proxmox-ve/:sourceId/tasks
GET    /api/proxmox-ve/:sourceId/nodes/:node/qemu/:vmid/status/current
GET    /api/proxmox-ve/:sourceId/nodes/:node/lxc/:vmid/status/current

GET    /api/proxmox-backup/:sourceId/datastores
GET    /api/proxmox-backup/:sourceId/tasks
GET    /api/proxmox-backup/:sourceId/datastores/:datastore/snapshots

GET    /api/guests/:guestId/backups
GET    /api/audit-events
```

## Security baseline

Обязательно с первого этапа:

- backend-only Proxmox credentials;
- bootstrap первого admin из `.env`;
- password hashing на backend;
- session/JWT secret только в `.env`;
- API tokens вместо root/password где возможно;
- reversible шифрование credentials в БД через `CREDENTIALS_ENCRYPTION_KEY`;
- `.env` только на сервере, не в git;
- audit log на login, user add/update/deactivate, source add/update/delete, test connection;
- read-only Proxmox tokens для MVP;
- отдельный system user в Proxmox под этот dashboard.

Для Proxmox VE token вводится в формате:

```text
user@realm!tokenid=secret
```

Для Proxmox Backup Server token вводится в формате:

```text
user@realm!tokenid:secret
```

`ALLOW_INSECURE_TLS=true` разрешает подключение к Proxmox/PBS с self-signed сертификатами. Для production с нормальными сертификатами лучше переключить на `false`.

Для будущего управления:

- RBAC;
- approval flow для опасных операций;
- dry-run;
- task queue;
- idempotency keys;
- distributed locks;
- immutable audit log.

## Deployment

Первый сервер:

```text
docker compose
  frontend container
  backend container
  postgres container
  reverse proxy container
```

Внешне:

```text
https://dashboard.example.local      -> frontend
https://dashboard.example.local/api  -> backend
```

Backend должен быть доступен только через reverse proxy или private network.

## Что не делать в MVP

- не делать управление VM/HA сразу;
- не хранить Proxmox токены во Flutter;
- не делать прямой Flutter -> Proxmox API;
- не собирать долгую time-series историю без понимания объема;
- не писать orchestrator до появления хорошего audit/task слоя.
