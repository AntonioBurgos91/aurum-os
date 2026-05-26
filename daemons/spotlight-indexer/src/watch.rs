//! Live filesystem watcher.
//!
//! Wraps the `notify` crate to forward inotify events into a tokio channel so
//! the index task can apply incremental upserts/deletes without blocking the
//! filesystem watcher thread.

use std::path::PathBuf;

use notify::{
    event::{EventKind, ModifyKind},
    Event, RecommendedWatcher, RecursiveMode, Watcher,
};
use tokio::sync::mpsc;

#[derive(Debug)]
pub enum FsChange {
    Touched(PathBuf), // create / modify / data write
    Removed(PathBuf), // delete / rename-away
}

pub struct WatchHandle {
    // Keep the watcher alive for the lifetime of the daemon.
    _watcher: RecommendedWatcher,
    pub rx: mpsc::UnboundedReceiver<FsChange>,
}

pub fn watch(roots: &[PathBuf]) -> notify::Result<WatchHandle> {
    let (tx, rx) = mpsc::unbounded_channel();

    // notify uses a blocking callback that runs on its own thread; we only
    // care about turning events into a sequence of FsChange messages.
    let mut watcher = notify::recommended_watcher(move |res: notify::Result<Event>| {
        let Ok(event) = res else { return };

        // Some kinds we want to ignore wholesale (access-time updates etc.).
        let push = |c: FsChange| {
            let _ = tx.send(c);
        };

        match event.kind {
            EventKind::Create(_)
            | EventKind::Modify(ModifyKind::Data(_))
            | EventKind::Modify(ModifyKind::Name(_)) => {
                for p in event.paths {
                    push(FsChange::Touched(p));
                }
            }
            EventKind::Remove(_) => {
                for p in event.paths {
                    push(FsChange::Removed(p));
                }
            }
            _ => {}
        }
    })?;

    for root in roots {
        if !root.exists() {
            log::warn!("watch root {} does not exist; skipping", root.display());
            continue;
        }
        watcher.watch(root, RecursiveMode::Recursive)?;
    }

    Ok(WatchHandle {
        _watcher: watcher,
        rx,
    })
}
