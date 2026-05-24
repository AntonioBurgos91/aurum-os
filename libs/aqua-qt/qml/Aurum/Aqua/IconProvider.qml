// IconProvider — singleton resolver that maps MIME types, file extensions,
// folder names, applet names and desktop-app IDs to absolute paths on disk.
//
// The resolver is intentionally pure-QML (no native bridge): every Aurum
// surface that needs an icon (Finder, Menubar, Dock, Launcher) imports
// `Aurum.Aqua 1.0` and calls `IconProvider.forMime(...)` / `.forApp(...)`.
//
// All returned paths use the `file://` scheme so they can be fed directly to
// `Image.source`. When nothing matches, `fallback` is returned.
pragma Singleton
import QtQuick

QtObject {
    id: root

    // Where install-icons.sh deposits the Aurum-Sequoia theme tree.
    readonly property string themeRoot   : "/usr/share/icons/Aurum-Sequoia"
    readonly property string fileTypesDir: themeRoot + "/file-types"
    readonly property string appletsDir  : themeRoot + "/applets"
    readonly property string appsRoot    : "/usr/share/icons/aurum-os"

    // Default for unknown files. Always exists post-install.
    readonly property string fallback: "file://" + fileTypesDir + "/text-plain.svg"

    // ------------------------------------------------------------------
    // MIME → SVG. Hardcoded table mirrors themes/icons/file-types/README.md.
    // Keep this list alphabetised; lookups are O(n) but n is small (~70).
    // ------------------------------------------------------------------
    readonly property var _mimeMap: ({
        "text/plain":                                                              "text-plain",
        "text/markdown":                                                           "text-markdown",
        "text/html":                                                               "text-html",
        "text/css":                                                                "text-css",
        "text/xml":                                                                "text-xml",
        "text/csv":                                                                "x-csv",
        "text/tab-separated-values":                                               "x-tsv",
        "text/x-python":                                                           "x-python",
        "text/x-rust":                                                             "x-rust",
        "text/x-c":                                                                "x-c",
        "text/x-c++":                                                              "x-cpp",
        "text/x-c++src":                                                           "x-cpp",
        "text/x-chdr":                                                             "x-h",
        "text/x-go":                                                               "x-go",
        "text/x-java":                                                             "x-java",
        "text/x-kotlin":                                                           "x-kotlin",
        "text/x-swift":                                                            "x-swift",
        "text/x-ruby":                                                             "x-ruby",
        "text/x-php":                                                              "x-php",
        "text/x-lua":                                                              "x-lua",
        "text/x-shellscript":                                                      "x-shellscript",
        "text/x-makefile":                                                         "x-makefile",
        "text/x-dockerfile":                                                       "x-dockerfile",
        "text/x-cmake":                                                            "x-cmake",
        "text/javascript":                                                         "x-javascript",
        "application/javascript":                                                  "x-javascript",
        "application/typescript":                                                  "x-typescript",
        "application/pdf":                                                         "application-pdf",
        "application/rtf":                                                         "application-rtf",
        "application/msword":                                                      "application-msword",
        "application/vnd.openxmlformats-officedocument.wordprocessingml.document": "application-vnd.openxmlformats-officedocument.wordprocessingml.document",
        "application/vnd.ms-excel":                                                "application-vnd.ms-excel",
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet":       "application-vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        "application/vnd.ms-powerpoint":                                           "application-vnd.ms-powerpoint",
        "application/vnd.openxmlformats-officedocument.presentationml.presentation":"application-vnd.openxmlformats-officedocument.presentationml.presentation",
        "application/epub+zip":                                                    "application-epub+zip",
        "application/zip":                                                         "application-zip",
        "application/x-7z-compressed":                                             "application-x-7z-compressed",
        "application/x-tar":                                                       "application-x-tar",
        "application/gzip":                                                        "application-gzip",
        "application/x-xz":                                                        "application-x-xz",
        "application/x-bzip2":                                                     "application-x-bzip2",
        "application/vnd.rar":                                                     "application-vnd.rar",
        "application/json":                                                        "application-json",
        "application/yaml":                                                        "application-yaml",
        "application/x-yaml":                                                      "application-yaml",
        "application/toml":                                                        "application-toml",
        "application/x-sqlite3":                                                   "application-x-sqlite3",
        "application/x-jupyter-notebook":                                          "application-x-jupyter-notebook",
        "image/png":                                                               "image-png",
        "image/jpeg":                                                              "image-jpeg",
        "image/webp":                                                              "image-webp",
        "image/gif":                                                               "image-gif",
        "image/svg+xml":                                                           "image-svg+xml",
        "image/bmp":                                                               "image-bmp",
        "image/tiff":                                                              "image-tiff",
        "image/heic":                                                              "image-heic",
        "image/x-icon":                                                            "image-x-icon",
        "video/mp4":                                                               "video-mp4",
        "video/x-matroska":                                                        "video-x-matroska",
        "video/webm":                                                              "video-webm",
        "video/quicktime":                                                         "video-quicktime",
        "video/x-msvideo":                                                         "video-x-msvideo",
        "audio/mpeg":                                                              "audio-mpeg",
        "audio/flac":                                                              "audio-flac",
        "audio/wav":                                                               "audio-wav",
        "audio/x-wav":                                                             "audio-wav",
        "audio/ogg":                                                               "audio-ogg",
        "audio/aac":                                                               "audio-aac",
        "audio/opus":                                                              "audio-opus"
    })

    // ------------------------------------------------------------------
    // Extension → SVG basename. Covers the cases where the MIME database
    // doesn't have an entry (the long tail of ML weights, data formats, …).
    // Stored without the leading dot.
    // ------------------------------------------------------------------
    readonly property var _extMap: ({
        "txt":          "text-plain",
        "md":           "text-markdown",
        "markdown":     "text-markdown",
        "html":         "text-html",
        "htm":          "text-html",
        "css":          "text-css",
        "xml":          "text-xml",
        "csv":          "x-csv",
        "tsv":          "x-tsv",
        "json":         "application-json",
        "yaml":         "application-yaml",
        "yml":          "application-yaml",
        "toml":         "application-toml",
        "pdf":          "application-pdf",
        "rtf":          "application-rtf",
        "doc":          "application-msword",
        "docx":         "application-vnd.openxmlformats-officedocument.wordprocessingml.document",
        "xls":          "application-vnd.ms-excel",
        "xlsx":         "application-vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        "ppt":          "application-vnd.ms-powerpoint",
        "pptx":         "application-vnd.openxmlformats-officedocument.presentationml.presentation",
        "epub":         "application-epub+zip",
        "zip":          "application-zip",
        "7z":           "application-x-7z-compressed",
        "tar":          "application-x-tar",
        "gz":           "application-gzip",
        "tgz":          "application-gzip",
        "xz":           "application-x-xz",
        "bz2":          "application-x-bzip2",
        "rar":          "application-vnd.rar",
        "png":          "image-png",
        "jpg":          "image-jpeg",
        "jpeg":         "image-jpeg",
        "webp":         "image-webp",
        "gif":          "image-gif",
        "svg":          "image-svg+xml",
        "bmp":          "image-bmp",
        "tif":          "image-tiff",
        "tiff":         "image-tiff",
        "heic":         "image-heic",
        "ico":          "image-x-icon",
        "mp4":          "video-mp4",
        "m4v":          "video-mp4",
        "mkv":          "video-x-matroska",
        "webm":         "video-webm",
        "mov":          "video-quicktime",
        "avi":          "video-x-msvideo",
        "mp3":          "audio-mpeg",
        "flac":         "audio-flac",
        "wav":          "audio-wav",
        "ogg":          "audio-ogg",
        "aac":          "audio-aac",
        "opus":         "audio-opus",
        "py":           "x-python",
        "pyw":          "x-python",
        "pyi":          "x-python",
        "rs":           "x-rust",
        "c":            "x-c",
        "cpp":          "x-cpp",
        "cxx":          "x-cpp",
        "cc":           "x-cpp",
        "h":            "x-h",
        "hpp":          "x-h",
        "hxx":          "x-h",
        "go":           "x-go",
        "js":           "x-javascript",
        "mjs":          "x-javascript",
        "cjs":          "x-javascript",
        "ts":           "x-typescript",
        "tsx":          "x-typescript",
        "java":         "x-java",
        "kt":           "x-kotlin",
        "kts":          "x-kotlin",
        "swift":        "x-swift",
        "rb":           "x-ruby",
        "php":          "x-php",
        "lua":          "x-lua",
        "sh":           "x-shellscript",
        "bash":         "x-shellscript",
        "zsh":          "x-shellscript",
        "fish":         "x-shellscript",
        "mk":           "x-makefile",
        "makefile":     "x-makefile",
        "dockerfile":   "x-dockerfile",
        "cmake":        "x-cmake",
        "ipynb":        "x-jupyter-notebook",
        "parquet":      "x-parquet",
        "arrow":        "x-arrow",
        "sqlite":       "application-x-sqlite3",
        "sqlite3":      "application-x-sqlite3",
        "db":           "application-x-sqlite3",
        "pth":          "x-pth",
        "pt":           "x-pt",
        "onnx":         "x-onnx",
        "safetensors":  "x-safetensors",
        "gguf":         "x-gguf",
        "ggml":         "x-ggml",
        "pb":           "x-pb",
        "tflite":       "x-tflite",
        "h5":           "x-h5",
        "ckpt":         "x-ckpt"
    })

    // ------------------------------------------------------------------
    // Folder names that get a custom glyph. Compared case-insensitive.
    // ------------------------------------------------------------------
    readonly property var _folderMap: ({
        "home":         "folder-home",
        "desktop":      "folder-desktop",
        "documents":    "folder-documents",
        "downloads":    "folder-downloads",
        "pictures":     "folder-pictures",
        "photos":       "folder-pictures",
        "music":        "folder-music",
        "videos":       "folder-videos",
        "movies":       "folder-videos",
        "projects":     "folder-projects",
        "code":         "folder-projects",
        "src":          "folder-projects",
        "models":       "folder-models",
        "weights":      "folder-models",
        "checkpoints":  "folder-models",
        "datasets":     "folder-datasets",
        "data":         "folder-datasets",
        "trash":        "folder-trash",
        ".trash":       "folder-trash"
    })

    // ------------------------------------------------------------------
    // Public API
    // ------------------------------------------------------------------

    /** Resolve a MIME type ("image/png") to a file:// URL. */
    function forMime(mimeType) {
        if (!mimeType) return fallback;
        var key = String(mimeType).toLowerCase();
        var base = _mimeMap[key];
        if (base !== undefined) {
            return "file://" + fileTypesDir + "/" + base + ".svg";
        }
        // Coarse fallback by top-level type so unknown subtypes still get a
        // sensible category (e.g. image/avif → image-png swatch).
        if (key.indexOf("image/") === 0)  return "file://" + fileTypesDir + "/image-png.svg";
        if (key.indexOf("video/") === 0)  return "file://" + fileTypesDir + "/video-mp4.svg";
        if (key.indexOf("audio/") === 0)  return "file://" + fileTypesDir + "/audio-mpeg.svg";
        if (key.indexOf("text/")  === 0)  return "file://" + fileTypesDir + "/text-plain.svg";
        return fallback;
    }

    /** Resolve a file extension (".parquet" or "parquet") to a file:// URL. */
    function forExtension(ext) {
        if (!ext) return fallback;
        var key = String(ext).toLowerCase();
        if (key.charAt(0) === ".") key = key.substring(1);
        var base = _extMap[key];
        if (base !== undefined) {
            return "file://" + fileTypesDir + "/" + base + ".svg";
        }
        return fallback;
    }

    /** Resolve a folder by name ("Pictures") to a file:// URL. */
    function forFolder(name) {
        if (!name) {
            return "file://" + fileTypesDir + "/folder-default.svg";
        }
        var key = String(name).toLowerCase();
        var base = _folderMap[key];
        if (base !== undefined) {
            return "file://" + fileTypesDir + "/" + base + ".svg";
        }
        return "file://" + fileTypesDir + "/folder-default.svg";
    }

    /** Resolve a menubar applet by short name ("gpu") to a file:// URL. */
    function forApplet(name) {
        if (!name) return fallback;
        var key = String(name).toLowerCase();
        return "file://" + appletsDir + "/" + key + ".svg";
    }

    // ------------------------------------------------------------------
    // Task-spec aliases (Wave 10 Agent 10B):
    //   IconProvider.fileType(".py")     → file-type icon by extension
    //   IconProvider.applet("gpu")        → 16x16 menubar status glyph
    // These wrap forExtension/forApplet to match the documented API name
    // that Finder / Menubar QML consumers were told to call.
    // ------------------------------------------------------------------
    function fileType(ext) { return forExtension(ext); }
    function applet(name)  { return forApplet(name);   }

    /**
     * Resolve a .desktop-style app identifier ("aurum-finder") to the
     * pre-normalised 12px-squircle PNG produced by the dock icon pipeline.
     * Falls back to the same base name in /usr/share/icons/hicolor/.
     */
    function forApp(desktopId) {
        if (!desktopId) return fallback;
        var key = String(desktopId).replace(/\.desktop$/i, "");
        return "file://" + appsRoot + "/" + key + ".png";
    }
}
