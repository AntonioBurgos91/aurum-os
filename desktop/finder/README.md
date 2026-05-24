# aurum-finder

File browser with the AurumOS ML sidebar (`~/datasets`, `~/models`,
`~/notebooks`) and a Quick Look preview pane.

| File              | Role                                              |
|-------------------|---------------------------------------------------|
| `main.cpp`        | Qt entry                                          |
| `finder_model.*`  | Browse model + `previewJson()` bridge             |
| `sidebar_model.*` | Two sections: Favorites (XDG) + ML (AurumOS)      |
| `Finder.qml`      | `SplitView` (sidebar / list / preview)            |

Quick Look format renderers live in `Finder.qml::nbComp` / `stComp` / `pqComp`;
the actual parsing happens in [`libs/ml-integrations`](../../libs/ml-integrations/).
