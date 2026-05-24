# ml-jobs-tracker

Rust daemon that polls a user's MLflow tracking server every ~10 s and
republishes the recent / active runs on the session bus. Re-reads
`~/.config/aurum/mlops.toml` on every cycle so changes made via
`aurum-settings → MLOps` take effect without a restart.

| Bus name   | `org.aurumos.MlJobsTrackerService`                            |
| Object     | `/org/aurumos/MlJobsTracker`                                  |
| Interface  | `org.aurumos.MlJobsTracker`                                   |
| Methods    | `runs() → a(sssssx)`, `tracking_uri() → s`, `last_error() → s`, `poke()` |

`poke()` lets the menubar trigger an immediate refresh between polls.
Weights & Biases polling is stubbed — the `[wandb]` config keys are read but
not currently queried; that lands once W&B's REST schema settles for v2.
