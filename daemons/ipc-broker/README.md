# ipc-broker (deferred)

The original spec listed `ipc-broker` as a fourth Rust daemon to coordinate
messages between desktop modules and backends. **For v0.1.0-beta the role is
filled by the session D-Bus**: every AurumOS daemon publishes a well-known
service name and every UI component talks to it directly.

| Producer                       | Consumers                                |
|--------------------------------|------------------------------------------|
| `org.aurumos.GpuMonitorService` | aurum-dock, aurum-menubar, aurum-settings |
| `org.aurumos.SpotlightIndexerService`  | aurum-spotlight (files plugin)            |
| `org.aurumos.MlJobsTrackerService`     | aurum-menubar, aurum-settings             |

A dedicated broker becomes useful once we need topic-based pub/sub or
cross-machine IPC (e.g. multi-host training dashboards). Until then,
introducing one would only add a hop. Re-open this when an ADR justifies it.
