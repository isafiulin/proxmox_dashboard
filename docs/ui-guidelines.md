# UI Guidelines

Этот документ фиксирует правила frontend UI для NeoTelecom Infrastructure Dashboard. Новые экраны и доработки должны следовать этим требованиям, чтобы интерфейс оставался единым и предсказуемым.

## Цель интерфейса

Продукт является внутренним инфраструктурным dashboard, а не landing page. Интерфейс должен быть плотным, спокойным и удобным для ежедневного анализа состояния Proxmox VE, Proxmox Backup Server и будущих iLO/Redfish источников.

Приоритеты:

- быстро увидеть проблему;
- быстро перейти от summary к source, node, VM/LXC или backup detail;
- не прятать важные статусы за декоративной версткой;
- не ломать layout на широких и узких экранах;
- сохранять одинаковую семантику цветов, статусов и таблиц во всех разделах.

## Design system

Все базовые визуальные значения должны жить в одном месте:

- цвета: `frontend/lib/core/design/app_colors.dart`;
- spacing: `frontend/lib/core/design/app_spacing.dart`;
- radii: `frontend/lib/core/design/app_radii.dart`;
- тема Flutter: `frontend/lib/core/theme/app_theme.dart`.

Нельзя добавлять локальные палитры в страницах без причины. Если нужен новый цвет или размер, сначала добавить token в `core/design`, потом использовать его в компонентах.

Основная палитра:

- white/surface для карточек и таблиц;
- light blue scaffold/surfaceAlt для фона;
- black/ink для основного текста;
- blue/primary для навигации, focus и primary actions;
- green/success для healthy/online/running/available/ok;
- yellow/warning только для промежуточного риска;
- red/danger для failed/offline/stopped/critical;
- muted grey для unknown/missing/new/disabled.

## Shared widgets

Новые экраны должны сначала использовать существующие shared-компоненты:

- `AppCard` для отдельных карточек, таблиц, framed tools и info blocks;
- `MetricCard` для верхних KPI;
- `PageHeader` для заголовка страницы;
- `AppButton` для action buttons;
- `AppTextField` для форм;
- `StatusChip` для статусов;
- `UsageBar` для процентов CPU/RAM/Disk/Storage;
- `ResourceLineChart` для исторических графиков;
- `EmptyState`, `EmptyCardState`, `ErrorStateView`, `LoadingStateView` для состояний;
- `SortableDataTable` для typed таблиц;
- `GenericDataSection` для raw/dynamic API таблиц.

Не дублировать локально стили кнопок, карточек, полей и chips. Если компонент почти подходит, расширить shared-компонент параметром.

## Navigation

Навигация строится только через `go_router`.

Правила:

- маршруты объявляются в `frontend/lib/core/routing/app_router.dart`;
- основной layout идет через `ShellRoute` и `DashboardShell`;
- для dashboard-экранов используются `NoTransitionPage`, чтобы не было визуального наложения старого и нового экрана;
- переходы между сущностями делать через `context.go(...)`;
- не использовать локальные index-based page switching для основных экранов;
- не использовать `Navigator.of(context).pop(true)` для обычных переходов внутри dashboard;
- детали должны иметь явную кнопку назад, если пользователь проваливается в source/node/VM/LXC detail;
- URL должен отражать текущий экран, чтобы refresh оставлял пользователя на нужном route.

Текущая web strategy включается в `frontend/lib/main.dart`:

- `usePathUrlStrategy()`;
- `GoRouter.optionURLReflectsImperativeAPIs = true`.

## Responsive layout

Dashboard должен работать минимум в двух режимах:

- desktop/wide: левое меню раскрыто, данные показываются плотными grid/table секциями;
- narrow/mobile: меню сжимается/скрывается, контент не перекрывается и не уходит за экран без горизонтального scroll там, где он ожидаем.

Правила:

- таблицы с большим количеством колонок заворачивать в `SingleChildScrollView(scrollDirection: Axis.horizontal)`;
- карточки KPI раскладывать через `Wrap`, а не жесткую строку;
- фиксированные элементы вроде календаря, toolbar, grid и status chips должны иметь стабильные размеры;
- текст в кнопках/chips не должен обрезаться так, чтобы смысл терялся;
- календарные сетки не должны растягивать день до огромных плиток на wide screen.

## Loading, empty, error states

Каждая async-страница должна иметь три состояния:

- loading: `LoadingStateView`;
- empty: `EmptyState` или `EmptyCardState`;
- error: `ErrorStateView`.

Loading не должен показывать старый экран или мигать login page при проверке auth. Для auth restore используется отдельный `SplashPage`.

Для новых сложных страниц предпочтителен skeleton-подход: пользователь должен видеть структуру будущей страницы, а не один маленький spinner на пустом экране.

## Tables

Все таблицы должны быть сортируемыми по колонкам.

Правила:

- typed таблицы использовать через `SortableDataTable<T>`;
- raw/dynamic таблицы использовать через `GenericDataSection`;
- если остается прямой `DataTable`, у него обязательно должны быть `sortColumnIndex`, `sortAscending` и `onSort` на колонках;
- numeric/date columns должны сортироваться по исходным значениям, а не по отформатированной строке;
- byte values отображать через shared formatter, без scientific notation;
- timestamps отображать в timezone устройства;
- для кликабельных строк использовать `DataRow.onSelectChanged`;
- строки, ведущие в detail page, должны переходить через GoRouter.

## Status semantics

`StatusChip` является единой точкой отображения статусов.

Семантика:

- `ok`, `online`, `running`, `available`, `success`, `enabled` -> green;
- `warning` -> yellow;
- `critical`, `failed`, `error`, `offline`, `stopped`, `disabled` -> red;
- `missing`, `unknown`, `new` -> muted grey.

Не использовать orange/yellow для `running` или `online`. Эти статусы должны быть green.

## Forms

Формы должны использовать `AppTextField`.

Правила:

- login/email fields должны иметь корректный `TextInputType.emailAddress`;
- password fields должны иметь password semantics и eye toggle для ручного просмотра;
- source token/password fields не должны случайно провоцировать browser autofill чужими credentials;
- primary action располагается внизу формы и использует `AppButton`;
- ошибки формы показываются рядом с действием или конкретным полем.

## Dashboards

Каждый dashboard должен иметь одинаковую структуру:

1. `PageHeader`;
2. KPI через `MetricCard`;
3. info/rule card, если нужно объяснить health policy;
4. основная аналитическая секция;
5. sortable tables с drill-down в details.

Для health dashboard обязательно показывать:

- current status;
- source/node/VM context;
- backup freshness или risk;
- последнюю дату события, если она есть;
- путь к detail page.

## Backup calendar

Backup schedule calendar строится по фактическим PBS snapshots.

Правила:

- месяц листается через `PageView`;
- день показывает количество snapshots;
- клик по дню открывает список VM/LXC, которые бэкапились в этот день;
- в списке показывать время, PBS source и datastore;
- если VM/LXC сопоставлена с Proxmox VE guest, строка должна вести в detail page;
- календарная сетка должна быть компактной и не растягиваться в огромные плитки на wide screen.

## Accessibility and polish

Минимальные требования:

- icon-only actions должны иметь tooltip;
- важные действия должны быть доступны с клавиатуры через стандартные Flutter controls;
- contrast текста должен оставаться читаемым на status/background colors;
- страницы не должны иметь incoherent overlap;
- не использовать декоративные gradient/orb/background элементы;
- не добавлять большие marketing hero sections внутри operational dashboard.

## Definition of done для UI задачи

UI-задача считается завершенной, если:

- использованы design tokens и shared widgets;
- новые таблицы sortable;
- есть loading/empty/error states;
- routing идет через GoRouter;
- wide и narrow layout не ломают контент;
- timestamps/bytes/percent values форматируются shared formatter-ами;
- `dart format`, `flutter analyze`, `flutter test` проходят;
- после frontend changes собран `flutter build web --release`;
- если приложение запущено через Docker, frontend контейнер пересобран.
