# File-type icons (Aurum-Sequoia)

64x64 SVGs generated from category templates by `_generate.py`. Source-of-truth
mapping lives in `_manifest.json` (file types) and `_folder_manifest.json`
(folder variants); the table below is what `libs/aqua-qt/qml/Aurum/Aqua/IconProvider.qml`
hardcodes for MIME and extension lookups.

## Regenerating

```bash
python3 themes/icons/file-types/_generate.py
```

The generator is dependency-free (stdlib only) and idempotent. It writes one
SVG per entry into this directory.

## Categories

| Category   | Template                | Visual mark                  | Typical color |
|------------|-------------------------|------------------------------|---------------|
| document   | `document-base.svg`     | colored label badge only     | varies        |
| image      | `image-base.svg`        | sun + mountains              | purple        |
| video      | `video-base.svg`        | play triangle                | pink          |
| audio      | `audio-base.svg`        | music note                   | orange        |
| code       | `code-base.svg`         | angle brackets               | blue          |
| archive    | `archive-base.svg`      | zipper teeth                 | brown         |
| data       | `data-base.svg`         | mini table grid              | green/cyan    |
| model      | `model-base.svg`        | neural-net dot graph         | teal          |
| folder     | `folder-base.svg`       | macOS Sequoia cyan folder    | cyan          |

## MIME → SVG mapping

| MIME type                                                                  | SVG file                                                                              |
|----------------------------------------------------------------------------|---------------------------------------------------------------------------------------|
| text/plain                                                                 | text-plain.svg                                                                        |
| text/markdown                                                              | text-markdown.svg                                                                     |
| text/html                                                                  | text-html.svg                                                                         |
| text/css                                                                   | text-css.svg                                                                          |
| text/xml                                                                   | text-xml.svg                                                                          |
| text/csv                                                                   | x-csv.svg                                                                             |
| text/tab-separated-values                                                  | x-tsv.svg                                                                             |
| text/x-python                                                              | x-python.svg                                                                          |
| text/x-rust                                                                | x-rust.svg                                                                            |
| text/x-c                                                                   | x-c.svg                                                                               |
| text/x-c++, text/x-c++src                                                  | x-cpp.svg                                                                             |
| text/x-chdr                                                                | x-h.svg                                                                               |
| text/x-go                                                                  | x-go.svg                                                                              |
| text/x-java                                                                | x-java.svg                                                                            |
| text/x-kotlin                                                              | x-kotlin.svg                                                                          |
| text/x-swift                                                               | x-swift.svg                                                                           |
| text/x-ruby                                                                | x-ruby.svg                                                                            |
| text/x-php                                                                 | x-php.svg                                                                             |
| text/x-lua                                                                 | x-lua.svg                                                                             |
| text/x-shellscript                                                         | x-shellscript.svg                                                                     |
| text/x-makefile                                                            | x-makefile.svg                                                                        |
| text/x-dockerfile                                                          | x-dockerfile.svg                                                                      |
| text/x-cmake                                                               | x-cmake.svg                                                                           |
| text/javascript, application/javascript                                    | x-javascript.svg                                                                      |
| application/typescript                                                     | x-typescript.svg                                                                      |
| application/pdf                                                            | application-pdf.svg                                                                   |
| application/rtf                                                            | application-rtf.svg                                                                   |
| application/msword                                                         | application-msword.svg                                                                |
| application/vnd.openxmlformats-officedocument.wordprocessingml.document    | application-vnd.openxmlformats-officedocument.wordprocessingml.document.svg           |
| application/vnd.ms-excel                                                   | application-vnd.ms-excel.svg                                                          |
| application/vnd.openxmlformats-officedocument.spreadsheetml.sheet          | application-vnd.openxmlformats-officedocument.spreadsheetml.sheet.svg                 |
| application/vnd.ms-powerpoint                                              | application-vnd.ms-powerpoint.svg                                                     |
| application/vnd.openxmlformats-officedocument.presentationml.presentation  | application-vnd.openxmlformats-officedocument.presentationml.presentation.svg         |
| application/epub+zip                                                       | application-epub+zip.svg                                                              |
| application/zip                                                            | application-zip.svg                                                                   |
| application/x-7z-compressed                                                | application-x-7z-compressed.svg                                                       |
| application/x-tar                                                          | application-x-tar.svg                                                                 |
| application/gzip                                                           | application-gzip.svg                                                                  |
| application/x-xz                                                           | application-x-xz.svg                                                                  |
| application/x-bzip2                                                        | application-x-bzip2.svg                                                               |
| application/vnd.rar                                                        | application-vnd.rar.svg                                                               |
| application/json                                                           | application-json.svg                                                                  |
| application/yaml, application/x-yaml                                       | application-yaml.svg                                                                  |
| application/toml                                                           | application-toml.svg                                                                  |
| application/x-sqlite3                                                      | application-x-sqlite3.svg                                                             |
| application/x-jupyter-notebook                                             | application-x-jupyter-notebook.svg                                                    |
| image/png                                                                  | image-png.svg                                                                         |
| image/jpeg                                                                 | image-jpeg.svg                                                                        |
| image/webp                                                                 | image-webp.svg                                                                        |
| image/gif                                                                  | image-gif.svg                                                                         |
| image/svg+xml                                                              | image-svg+xml.svg                                                                     |
| image/bmp                                                                  | image-bmp.svg                                                                         |
| image/tiff                                                                 | image-tiff.svg                                                                        |
| image/heic                                                                 | image-heic.svg                                                                        |
| image/x-icon                                                               | image-x-icon.svg                                                                      |
| video/mp4                                                                  | video-mp4.svg                                                                         |
| video/x-matroska                                                           | video-x-matroska.svg                                                                  |
| video/webm                                                                 | video-webm.svg                                                                        |
| video/quicktime                                                            | video-quicktime.svg                                                                   |
| video/x-msvideo                                                            | video-x-msvideo.svg                                                                   |
| audio/mpeg                                                                 | audio-mpeg.svg                                                                        |
| audio/flac                                                                 | audio-flac.svg                                                                        |
| audio/wav, audio/x-wav                                                     | audio-wav.svg                                                                         |
| audio/ogg                                                                  | audio-ogg.svg                                                                         |
| audio/aac                                                                  | audio-aac.svg                                                                         |
| audio/opus                                                                 | audio-opus.svg                                                                        |

## Extension-only mappings (no canonical MIME)

| Extension                          | SVG file               |
|------------------------------------|------------------------|
| .ipynb                             | x-jupyter-notebook.svg |
| .parquet                           | x-parquet.svg          |
| .arrow                             | x-arrow.svg            |
| .pth, .pt                          | x-pth.svg / x-pt.svg   |
| .onnx                              | x-onnx.svg             |
| .safetensors                       | x-safetensors.svg      |
| .gguf, .ggml                       | x-gguf.svg / x-ggml.svg|
| .pb, .tflite                       | x-pb.svg / x-tflite.svg|
| .h5, .ckpt                         | x-h5.svg / x-ckpt.svg  |

## Folder variants

| Folder name (case-insensitive)        | SVG file              |
|---------------------------------------|-----------------------|
| (anything else)                       | folder-default.svg    |
| Home                                  | folder-home.svg       |
| Desktop                               | folder-desktop.svg    |
| Documents                             | folder-documents.svg  |
| Downloads                             | folder-downloads.svg  |
| Pictures, Photos                      | folder-pictures.svg   |
| Music                                 | folder-music.svg      |
| Videos, Movies                        | folder-videos.svg     |
| Projects, Code, src                   | folder-projects.svg   |
| Models, Weights, Checkpoints          | folder-models.svg     |
| Datasets, Data                        | folder-datasets.svg   |
| Trash, .Trash                         | folder-trash.svg      |
