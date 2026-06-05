# MVP Roadmap

## Этап 0: каркас

- Создать backend приложение на Dart.
- Создать frontend приложение на Flutter Web.
- Поднять `docker-compose.yml`.
- Настроить `.env.example`.
- Подготовить PostgreSQL схему миграциями.

## Этап 1: источники

- Login в dashboard.
- Bootstrap первого пользователя из `.env`.
- Одна роль: `admin`.
- Страница пользователей.
- Создание новых пользователей из веб-интерфейса.
- Блокировка/разблокировка пользователей.
- Смена пароля.
- CRUD источников. `done: create/edit/delete/test`
- Типы источников:
  - Proxmox VE;
  - Proxmox Backup Server.
- Проверка подключения.
- Безопасное хранение токенов.
- Сохранение токена авторизации во frontend и восстановление через `/api/me`. `done`
- Редактирование текущего профиля. `done: display name`
- Дизайн-токены frontend. `done: colors/spacing/radii/theme`
- Адаптивное левое меню. `done`

## Этап 2: Proxmox VE read-only

- Список нод. `done: live API`
- Список VM/LXC через cluster resources. `done: live API`
- Статусы VM/LXC через cluster resources. `done: live API`
- Storage usage.
- Последние tasks. `done: live API`
- Текущий статус конкретной VM/LXC. `done: backend API + frontend detail page`
- Ошибки и warnings.
- Общий health score.

## Этап 3: Proxmox Backup Server read-only

- Список datastores. `done: live API`
- Список snapshots. `done: live API`
- Список jobs/tasks. `done: live API`
- Последний успешный backup по VM/LXC.
- Backup age status:
  - ok; `done: frontend MVP`
  - warning; `done: frontend MVP`
  - critical; `done: frontend MVP`
  - missing. `done: frontend MVP`

## Этап 4: связка VE + PBS

- Связать VM/LXC из Proxmox VE с backup snapshots из PBS. `done: MVP matching by backup-id/vmid`
- Показать на карточке VM:
  - текущий статус;
  - где запущена;
  - ресурсы;
  - последний backup;
  - возраст backup;
  - последние ошибки.

## Этап 5: аудит и эксплуатация

- Audit log действий пользователей.
- Локальное отображение времени аудита по timezone устройства. `done`
- Backend polling с настройкой interval. `done`
- Исторические data snapshots. `done: raw snapshots MVP, retention 7 days`
- Events/tasks из Proxmox.
- Фильтры по source/node/VM/severity.
- Экспорт basic report later.

## Этап 6: iLO/Redfish

- Добавление physical server источника.
- Health по железу.
- Связь physical server -> Proxmox node.

## Позже: orchestrator

Только после стабильного read-only dashboard:

- операции с VM;
- maintenance mode;
- controlled migration;
- backup before action;
- HA policy;
- task queue;
- locks;
- dry-run;
- rollback/compensation;
- approvals.
