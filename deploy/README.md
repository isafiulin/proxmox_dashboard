# Deployment and operations

Production topology: один Linux-сервер с Docker Compose. Контейнер `frontend`
публикуется только на `127.0.0.1:8081` и проксирует `/api/` в `backend`;
инфраструктурный reverse proxy публикует HTTPS, а backend и PostgreSQL наружу
не публикуются.

## 1. Требования

- Docker Engine и `docker compose`;
- 2 CPU, 4 GB RAM и 20 GB свободного диска как разумный стартовый минимум;
- DNS/HTTPS reverse proxy для production;
- сетевой доступ к VE/PBS/BMC management endpoints;
- отдельные read-only credentials для мониторинга;
- регулярный backup PostgreSQL volume.

## 2. Environment

```bash
cp deploy/.env.example deploy/.env
chmod 600 deploy/.env
```

| Переменная | Назначение |
|---|---|
| `APP_PUBLIC_URL` | Информационный публичный URL |
| `BACKEND_VERSION` | Версия backend в `/api/health` |
| `FRONTEND_VERSION` | Версия UI и build arg Flutter |
| `GIT_COMMIT` | Commit текущего деплоя |
| `POSTGRES_*` | Создание PostgreSQL database/user |
| `DATABASE_URL` | Подключение backend к PostgreSQL |
| `STORE_DRIVER` | В production всегда `postgres` |
| `JWT_SECRET` | Зарезервировано; текущие сессии process-local |
| `CREDENTIALS_ENCRYPTION_KEY` | Шифрование source и Telegram credentials |
| `ALLOW_INSECURE_TLS` | Разрешить self-signed TLS у источников |
| `BOOTSTRAP_ADMIN_*` | Первый admin, создаётся только при пустой БД |
| `BACKEND_PORT` | Внутренний порт API, по умолчанию 8080 |

Сгенерировать секреты можно стандартным `openssl`:

```bash
openssl rand -hex 32
```

`POSTGRES_PASSWORD` должен совпадать в `POSTGRES_PASSWORD` и `DATABASE_URL`.
Символы со специальным значением в URL необходимо percent-encode.

## 3. Первый запуск

```bash
export GIT_COMMIT="$(git rev-parse --short HEAD)"
docker compose --env-file deploy/.env build
docker compose --env-file deploy/.env up -d
docker compose --env-file deploy/.env ps
curl -fsS http://127.0.0.1:8081/api/health
```

Посмотреть запуск и ошибки:

```bash
docker compose --env-file deploy/.env logs --tail=200 backend
docker compose --env-file deploy/.env logs --tail=100 frontend postgres
```

После первого входа смените bootstrap password. Переменные
`BOOTSTRAP_ADMIN_*` не перезаписывают уже созданного пользователя.

## 4. HTTPS

Встроенный Nginx слушает HTTP `:80` внутри контейнера и публикуется на host как
`127.0.0.1:8081`. В production завершайте TLS на внешнем reverse proxy или
load balancer и проксируйте весь origin в `127.0.0.1:8081`.
Важно передавать `Host`, `X-Forwarded-For` и `X-Forwarded-Proto`.

Если сервис доступен только через внутренний VPN/management LAN, всё равно
предпочтителен сертификат внутреннего CA. Не публикуйте backend `:8080` и
PostgreSQL `:5432`.

## 5. Обновление

Сначала сделайте backup БД, затем:

```bash
git pull --ff-only
export GIT_COMMIT="$(git rev-parse --short HEAD)"
docker compose --env-file deploy/.env build
docker compose --env-file deploy/.env up -d
docker compose --env-file deploy/.env ps
curl -fsS http://127.0.0.1:8081/api/health
```

`docker compose up -d` пересоздаёт только изменившиеся контейнеры. PostgreSQL
данные остаются в named volume `postgres_data`.

## 6. Backup и restore PostgreSQL

Создать каталог и дамп:

```bash
mkdir -p backups
chmod 700 backups
docker compose --env-file deploy/.env exec -T postgres \
  pg_dump -U neotelecom -d neotelecom -Fc > \
  "backups/neotelecom-$(date +%F-%H%M).dump"
```

Проверить, что файл непустой:

```bash
test -s "$(ls -t backups/*.dump | head -n 1)"
```

Restore перезаписывает данные, поэтому сначала остановите backend и сохраните
отдельный предаварийный дамп:

```bash
docker compose --env-file deploy/.env stop backend
docker compose --env-file deploy/.env exec -T postgres \
  dropdb -U neotelecom --if-exists neotelecom
docker compose --env-file deploy/.env exec -T postgres \
  createdb -U neotelecom neotelecom
docker compose --env-file deploy/.env exec -T postgres pg_restore \
  -U neotelecom -d neotelecom --clean --if-exists < backup.dump
docker compose --env-file deploy/.env start backend
```

Дампы необходимо копировать за пределы этого сервера и проверять тестовым
restore по расписанию.

## 7. Rollback приложения

Rollback кода не должен откатывать PostgreSQL вслепую:

```bash
git log --oneline -n 10
git switch --detach <known-good-commit>
export GIT_COMMIT="$(git rev-parse --short HEAD)"
docker compose --env-file deploy/.env build frontend backend
docker compose --env-file deploy/.env up -d frontend backend
```

Перед rollback проверьте совместимость схемы. Восстановление БД из дампа —
отдельная разрушительная операция и выполняется только при необходимости.

## 8. Диагностика

```bash
docker compose --env-file deploy/.env ps
docker compose --env-file deploy/.env logs --since=30m backend
docker compose --env-file deploy/.env exec postgres \
  pg_isready -U neotelecom -d neotelecom
curl -i http://127.0.0.1:8081/api/health
docker stats --no-stream
```

Типовые причины:

- `DATABASE_URL is required` — не подключён `deploy/.env`;
- ошибка decrypt после рестарта — изменён `CREDENTIALS_ENCRYPTION_KEY`;
- `502` от UI — backend не запущен или ещё стартует;
- source test падает по TLS — установить доверенный CA; временно и только во
  внутренней сети можно использовать `ALLOW_INSECURE_TLS=true`;
- пустой dashboard — проверить source credentials, сетевую доступность и экран
  **Метрики сбора**;
- Telegram не отправляет — проверить bot token, Chat ID, membership бота и
  нажать **Сохранить и проверить**.

## 9. Что сохраняется

- PostgreSQL volume: users, sources, encrypted credentials, settings, audit и
  snapshots;
- snapshots хранятся rolling window 7 дней;
- Docker images и контейнеры можно пересобрать без потери данных;
- секреты находятся в `deploy/.env`; этот файл тоже требует защищённой резервной
  копии.

Не используйте `docker compose down -v`: флаг `-v` удалит volume PostgreSQL.
