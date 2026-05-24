# aurum-notifications

Notification tray with DL-specific widgets (training-job progress from
`aurum-ml-jobs-tracker`).

**Status:** stub for v0.1.0-beta. The system uses `mako` (already in
`system.list`) for `org.freedesktop.Notifications`, which is sufficient for
the beta deliverable. The AurumOS-native tray that consumes the ml-jobs
tracker D-Bus surface is planned for v0.2.

| File         | Role                                            |
|--------------|-------------------------------------------------|
| `main.cpp`   | Qt entry (placeholder)                          |

When implemented, this binary will:
- Subscribe to `org.freedesktop.Notifications` like a regular notification daemon.
- Promote MLflow `RUNNING → FINISHED / FAILED` transitions to bubbles.
- Surface a right-side tray panel keyed to `Cmd+N`.
