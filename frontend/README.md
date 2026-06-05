# Frontend

Flutter Web dashboard.

## First screens

- Login
- Users management
- Global dashboard
- Sources list
- Add source dialog
- Proxmox VE source page
- Proxmox Backup Server source page
- VM/LXC detail page
- Backup timeline
- Audit/events page

## Suggested package layout

```text
lib/
  main.dart
  app/
  core/
    api/
    auth/
    users/
    routing/
    theme/
  features/
    dashboard/
    sources/
    proxmox_ve/
    proxmox_backup/
    guests/
    backups/
    audit/
  shared/
    widgets/
    models/
test/
```

## UI rule

Frontend receives normalized data from backend. It does not know Proxmox tokens and does not call Proxmox directly.
