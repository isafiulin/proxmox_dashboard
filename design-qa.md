# Application-wide monitoring design QA

## Evidence

- Source visual truth:
  - `codex-clipboard-0485993a-c9db-4440-965b-321d2873d670.png` — monitoring overview, 814x411 px.
  - `codex-clipboard-512e223d-9c38-48a8-961d-e39488ae6cbd.png` — dense health grid, 761x428 px.
  - `codex-clipboard-64017d29-7635-402b-a28f-f3f861041b1c.png` — detail panel, 669x342 px.
- Browser-rendered implementation:
  - `design-implementation-overview.png` — overview, 1280x720 px.
  - `design-implementation-vm-health.png` — PVE VM health, 1280x720 px.
  - `design-implementation-users.png` — administration, 1280x720 px.
  - `design-implementation-redfish.png` — Redfish server detail, 1600x1000 px.
- Full comparison board: `design-comparison-global.png`.
- CSS viewports checked: 1280x720, 1024x900 and 740x900 at device scale 1.
- States checked: overview, PVE health, Redfish detail, administration, expanded navigation, collapsed navigation and drawer breakpoint.

The supplied references are directional screenshots rather than pixel-identical frames, so they were normalized into equal comparison cells. Browser chrome was excluded from all implementation captures.

## Findings

No actionable P0, P1 or P2 differences remain.

- Fonts and typography: the existing application font stack was retained. Titles, metric values, compact labels and table headers now use one consistent weight hierarchy without clipping or unintended wrapping.
- Spacing and layout rhythm: all screens share the same 8/12/16/24 rhythm, bordered white content panels, 10 px metric-card radii and dense desktop grids. Metric cards fit four columns at 1280 px and reflow without overflow.
- Colors and visual tokens: the dark sidebar, blue primary surface and green/amber/red semantic states now apply through shared theme and metric components. Health counters receive semantic colors where their data has an operational meaning.
- Image and asset quality: these screens contain no reference imagery requiring raster reproduction. Existing Material icons are sharp, consistently sized and match the monitoring-console direction.
- Copy and content: existing product terminology and mixed Russian/technical labels were preserved to avoid changing operational meaning.
- Responsiveness: the 1024 px collapsed sidebar and 740 px drawer states render without overflow; persistent actions remain available.
- Interactions: sidebar sections, PVE route navigation and administration navigation were exercised. Browser console contained no errors or warnings.

Focused comparison was not required beyond the three route captures because the design target is a reusable monitoring language rather than a single pixel-identical screen. The overview verifies KPI hierarchy, PVE verifies dense operational panels, and administration verifies shared styling outside monitoring data.

## Comparison history

- Earlier P2: the collapsed desktop sidebar overflowed at 1024 px. The brand/toggle header was reduced to one interactive icon; the 1024x900 and 740x900 post-fix captures show no overflow.
- Earlier P2: overview KPI cards wrapped as 3+1 at 1280 px. Shared metric width was reduced from 240 to 234 px; the revised 1280x720 capture shows a balanced four-column row.
- Earlier P2: only Redfish used the stronger monitoring hierarchy. Shared cards, page headers, table theme, chips and semantic health colors were moved into application-wide components; overview, PVE and administration captures confirm the same visual language.

## Follow-up polish

- P3: translate the remaining English operational labels separately if a fully Russian product vocabulary is desired.

final result: passed
