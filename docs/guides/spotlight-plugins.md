# Spotlight plugins

`Cmd+Space` opens the AurumOS Spotlight overlay. Out of the box it ships
five plugins; each owns a category and surfaces results in priority order.

## Built-in plugins

| Plugin       | Trigger                              | What it does                                      |
|--------------|--------------------------------------|---------------------------------------------------|
| Applications | bare keyword                         | Fuzzy-matches installed `.desktop` entries        |
| Files        | bare keyword (2+ chars)              | Queries `aurum-spotlight-indexer` (tantivy index) |
| Calculator   | math expression                      | `QJSEngine`-evaluated; copies result on Enter     |
| Hugging Face | `hf:`, `hf `, or `model:` prefix     | Searches `huggingface.co/api/models`              |
| arXiv        | `arxiv:`, `arxiv `, or `paper:`      | Searches `export.arxiv.org` (Atom XML)            |

## Examples

```
hf llama-3.1                       → top 8 Hugging Face models matching
arxiv attention is all you need    → top 8 arXiv papers
paper:diffusion priors             → same; alternate trigger
2**10 + 24                         → 1048 (Enter copies to clipboard)
jupyter                            → JupyterLab .desktop launcher
welcome.py                         → file in ~/notebooks (indexer match)
```

The files plugin only indexes the workspace paths:
`~/datasets`, `~/models`, `~/notebooks`, `~/Documents`, `~/Downloads`, `~/Desktop`.
Add more by editing `daemons/spotlight-indexer/src/main.rs::default_roots()`.

## Network plugins and offline behavior
The `hf:` and `arxiv:` plugins debounce 250 ms / 350 ms respectively and
silently emit no results when the host is offline. They never block the
overlay — local plugins (apps, files, calculator) render immediately and
the web rows pop in when the responses arrive.

## Writing a new plugin

Plugins live in-process under `desktop/spotlight/plugins/`. The contract is
[plugin.h](../../desktop/spotlight/plugins/plugin.h):

```cpp
class MyPlugin : public aurum::spotlight::SpotlightPlugin {
    Q_OBJECT
public:
    QString id() const override          { return "my"; }
    QString displayName() const override { return "My Plugin"; }
    int     priority() const override    { return 10; }
    void    search(const QString& q, int generation) override;
};
```

Wire it up in [main.cpp](../../desktop/spotlight/main.cpp):
```cpp
aggregator.addPlugin(new MyPlugin);
```

In-process is the right call: a Spotlight query budget of 100 ms can't
absorb a process spawn (~30 ms cold, ~10 ms warm) on top of plugin work.
If your plugin needs to call out to a long-running service, do it via D-Bus
or HTTP from within the plugin.
