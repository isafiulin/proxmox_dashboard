# NeoTelecom Infrastructure Dashboard

Единое окно для анализа состояния Proxmox VE, Proxmox Backup Server и, позже, физических серверов через iLO/Redfish.

## Цель первого этапа

Собрать нормальный внутренний дашборд, который показывает текущую жизнь инфраструктуры:

- Proxmox VE кластеры и отдельные ноды;
- виртуальные машины и LXC;
- состояние CPU, RAM, дисков, storage и сети;
- последние бэкапы VM/LXC из Proxmox Backup Server;
- ошибки, предупреждения и события аудита;
- первый admin-пользователь и добавление других пользователей из веб-интерфейса;
- базовую историю для анализа деградаций и проблем.

## Базовая архитектура

```text
Flutter Web UI
      |
      v
Dart Backend API
      |
      +--> Proxmox VE API
      +--> Proxmox Backup Server API
      +--> PostgreSQL
      +--> Redis / queue later
      +--> iLO / Redfish later
```

Frontend и backend на первом этапе деплоятся на один сервер, но как разные контейнеры.

## Структура репозитория

```text
backend/   Dart API, интеграции, сбор данных, хранение секретов
frontend/  Flutter Web dashboard
deploy/    Docker, reverse proxy, env templates, server deployment notes
docs/      Архитектура, roadmap, доменная модель
tbot/      Существующий код, пока не связан с новым продуктом
```

## Рекомендуемый стек

- Frontend: Flutter Web
- Backend: Dart, `shelf` или `dart_frog`
- Database: PostgreSQL
- Cache/queue later: Redis
- Deployment: Docker Compose на одном сервере
- Reverse proxy: Caddy или Nginx

Текущий backend уже имеет production storage driver для PostgreSQL и dev/test storage driver на JSON.

Подробности:

- [docs/architecture.md](docs/architecture.md) - архитектура и доменная модель;
- [docs/ui-guidelines.md](docs/ui-guidelines.md) - frontend дизайн-система, навигация, skeleton/loading, таблицы и UI definition of done.
