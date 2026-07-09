import Foundation

// MARK: - Utilities, Apple-Native, Media, Network Tool Definitions
// Extracted from ToolDefinitions.swift for maintainability.

extension ToolDefinitions {

    // MARK: - Utilities

    nonisolated(unsafe) static let getCurrentTime: [String: Any] = [
        "type": "function",
        "function": [
            "name": "get_current_time",
            "description": "Get the current date and time in ISO 8601 format and timezone.",
            "parameters": ["type": "object", "properties": [], "required": [] as [String]] as [String: Any]
        ] as [String: Any]
    ]

    nonisolated(unsafe) static let formatDate: [String: Any] = [
        "type": "function",
        "function": [
            "name": "format_date",
            "description": "Format a date string. Parse input and output in specified format.",
            "parameters": [
                "type": "object",
                "properties": [
                    "date": ["type": "string", "description": "Input date string (ISO 8601 or common formats)"],
                    "format": ["type": "string", "description": "Output format: iso, short, long, unix"]
                ],
                "required": ["date"]
            ] as [String: Any]
        ] as [String: Any]
    ]

    nonisolated(unsafe) static let calculate: [String: Any] = [
        "type": "function",
        "function": [
            "name": "calculate",
            "description": "Evaluate a math expression. Supports +, -, *, /, %, ^, sqrt, etc.",
            "parameters": [
                "type": "object",
                "properties": [
                    "expression": ["type": "string", "description": "Math expression to evaluate (e.g. 2+3*4, sqrt(16))"]
                ],
                "required": ["expression"]
            ] as [String: Any]
        ] as [String: Any]
    ]

    nonisolated(unsafe) static let countWords: [String: Any] = [
        "type": "function",
        "function": [
            "name": "count_words",
            "description": "Count words, lines, and characters in a text string or file.",
            "parameters": [
                "type": "object",
                "properties": [
                    "text": ["type": "string", "description": "Text to count (or use path for file)"],
                    "path": ["type": "string", "description": "Path to file to count (alternative to text)"]
                ],
                "required": [] as [String]
            ] as [String: Any]
        ] as [String: Any]
    ]

    nonisolated(unsafe) static let extractUrls: [String: Any] = [
        "type": "function",
        "function": [
            "name": "extract_urls",
            "description": "Extract all URLs from a text string or file.",
            "parameters": [
                "type": "object",
                "properties": [
                    "text": ["type": "string", "description": "Text to extract URLs from"],
                    "path": ["type": "string", "description": "Path to file to extract URLs from"]
                ],
                "required": [] as [String]
            ] as [String: Any]
        ] as [String: Any]
    ]

    nonisolated(unsafe) static let jsonParse: [String: Any] = [
        "type": "function",
        "function": [
            "name": "json_parse",
            "description": "Parse JSON string and return formatted/validated output. Use to inspect JSON structure.",
            "parameters": [
                "type": "object",
                "properties": [
                    "json": ["type": "string", "description": "JSON string to parse"]
                ],
                "required": ["json"]
            ] as [String: Any]
        ] as [String: Any]
    ]

    nonisolated(unsafe) static let yamlParse: [String: Any] = [
        "type": "function",
        "function": [
            "name": "yaml_parse",
            "description": "Parse YAML string. Uses Python yaml or ruby -r yaml if available.",
            "parameters": [
                "type": "object",
                "properties": [
                    "yaml": ["type": "string", "description": "YAML string to parse"],
                    "path": ["type": "string", "description": "Path to YAML file"]
                ],
                "required": [] as [String]
            ] as [String: Any]
        ] as [String: Any]
    ]

    nonisolated(unsafe) static let diffFiles: [String: Any] = [
        "type": "function",
        "function": [
            "name": "diff_files",
            "description": "Show diff between two files. Uses diff command.",
            "parameters": [
                "type": "object",
                "properties": [
                    "path_a": ["type": "string", "description": "First file path"],
                    "path_b": ["type": "string", "description": "Second file path"]
                ],
                "required": ["path_a", "path_b"]
            ] as [String: Any]
        ] as [String: Any]
    ]

    nonisolated(unsafe) static let fileHash: [String: Any] = [
        "type": "function",
        "function": [
            "name": "file_hash",
            "description": "Compute hash of a file (MD5 or SHA256).",
            "parameters": [
                "type": "object",
                "properties": [
                    "path": ["type": "string", "description": "Path to file"],
                    "algorithm": ["type": "string", "description": "md5 or sha256 (default: sha256)"]
                ],
                "required": ["path"]
            ] as [String: Any]
        ] as [String: Any]
    ]

    nonisolated(unsafe) static let backupFile: [String: Any] = [
        "type": "function",
        "function": [
            "name": "backup_file",
            "description": "Create a backup copy of a file with .bak or timestamp suffix.",
            "parameters": [
                "type": "object",
                "properties": [
                    "path": ["type": "string", "description": "Path to file to backup"],
                    "suffix": ["type": "string", "description": "Backup suffix (default: .bak)"]
                ],
                "required": ["path"]
            ] as [String: Any]
        ] as [String: Any]
    ]

    nonisolated(unsafe) static let pingHost: [String: Any] = [
        "type": "function",
        "function": [
            "name": "ping_host",
            "description": "Ping a host to check connectivity.",
            "parameters": [
                "type": "object",
                "properties": [
                    "host": ["type": "string", "description": "Hostname or IP"],
                    "count": ["type": "integer", "description": "Number of pings (default: 3)"]
                ],
                "required": ["host"]
            ] as [String: Any]
        ] as [String: Any]
    ]

    nonisolated(unsafe) static let resolveDns: [String: Any] = [
        "type": "function",
        "function": [
            "name": "resolve_dns",
            "description": "Resolve hostname to IP address(es).",
            "parameters": [
                "type": "object",
                "properties": [
                    "hostname": ["type": "string", "description": "Hostname to resolve"]
                ],
                "required": ["hostname"]
            ] as [String: Any]
        ] as [String: Any]
    ]

    nonisolated(unsafe) static let hashString: [String: Any] = [
        "type": "function",
        "function": [
            "name": "hash_string",
            "description": "Compute hash of a string (MD5, SHA256).",
            "parameters": [
                "type": "object",
                "properties": [
                    "text": ["type": "string", "description": "Text to hash"],
                    "algorithm": ["type": "string", "description": "md5 or sha256"]
                ],
                "required": ["text"]
            ] as [String: Any]
        ] as [String: Any]
    ]

    nonisolated(unsafe) static let base64Encode: [String: Any] = [
        "type": "function",
        "function": [
            "name": "base64_encode",
            "description": "Encode a string to Base64. Use for encoding credentials or binary-like data for APIs.",
            "parameters": [
                "type": "object",
                "properties": [
                    "text": ["type": "string", "description": "Text to encode"]
                ],
                "required": ["text"]
            ] as [String: Any]
        ] as [String: Any]
    ]

    nonisolated(unsafe) static let base64Decode: [String: Any] = [
        "type": "function",
        "function": [
            "name": "base64_decode",
            "description": "Decode a Base64 string. Use to decode API responses or stored credentials.",
            "parameters": [
                "type": "object",
                "properties": [
                    "text": ["type": "string", "description": "Base64-encoded string to decode"]
                ],
                "required": ["text"]
            ] as [String: Any]
        ] as [String: Any]
    ]

    nonisolated(unsafe) static let generateUuid: [String: Any] = [
        "type": "function",
        "function": [
            "name": "generate_uuid",
            "description": "Generate a UUID (Universally Unique Identifier).",
            "parameters": ["type": "object", "properties": [], "required": [] as [String]] as [String: Any]
        ] as [String: Any]
    ]

    nonisolated(unsafe) static let getFileType: [String: Any] = [
        "type": "function",
        "function": [
            "name": "get_file_type",
            "description": "Get file type/extension and MIME type if determinable.",
            "parameters": [
                "type": "object",
                "properties": [
                    "path": ["type": "string", "description": "Path to file"]
                ],
                "required": ["path"]
            ] as [String: Any]
        ] as [String: Any]
    ]

    nonisolated(unsafe) static let detectLanguage: [String: Any] = [
        "type": "function",
        "function": [
            "name": "detect_language",
            "description": "Detect programming language of a file from extension and/or content.",
            "parameters": [
                "type": "object",
                "properties": [
                    "path": ["type": "string", "description": "Path to file"]
                ],
                "required": ["path"]
            ] as [String: Any]
        ] as [String: Any]
    ]

    nonisolated(unsafe) static let getProcessInfo: [String: Any] = [
        "type": "function",
        "function": [
            "name": "get_process_info",
            "description": "Get process details by PID (command, args, status). macOS/Linux.",
            "parameters": [
                "type": "object",
                "properties": [
                    "pid": ["type": "integer", "description": "Process ID"]
                ],
                "required": ["pid"]
            ] as [String: Any]
        ] as [String: Any]
    ]

    // MARK: - Additional Utilities

    nonisolated(unsafe) static let regexReplace: [String: Any] = [
        "type": "function",
        "function": [
            "name": "regex_replace",
            "description": "Find and replace using regular expressions across one or more files.",
            "parameters": [
                "type": "object",
                "properties": [
                    "path": ["type": "string", "description": "File or directory path"],
                    "pattern": ["type": "string", "description": "Regular expression pattern to match"],
                    "replacement": ["type": "string", "description": "Replacement string (supports capture groups $1, $2, etc.)"],
                    "recursive": ["type": "boolean", "description": "Search subdirectories (default false)"],
                    "extensions": ["type": "string", "description": "File extensions to include (comma-separated)"]
                ],
                "required": ["path", "pattern", "replacement"]
            ] as [String: Any]
        ] as [String: Any]
    ]

    nonisolated(unsafe) static let portScan: [String: Any] = [
        "type": "function",
        "function": [
            "name": "port_scan",
            "description": "Check if a TCP port is open on a host.",
            "parameters": [
                "type": "object",
                "properties": [
                    "host": ["type": "string", "description": "Hostname or IP address"],
                    "port": ["type": "integer", "description": "Port number to check"],
                    "timeout": ["type": "integer", "description": "Timeout in seconds (default 5)"]
                ],
                "required": ["host", "port"]
            ] as [String: Any]
        ] as [String: Any]
    ]

    nonisolated(unsafe) static let sslCheck: [String: Any] = [
        "type": "function",
        "function": [
            "name": "ssl_check",
            "description": "Check SSL/TLS certificate details for a hostname. Returns issuer, expiry, validity.",
            "parameters": [
                "type": "object",
                "properties": [
                    "hostname": ["type": "string", "description": "Domain name to check"],
                    "port": ["type": "integer", "description": "Port (default 443)"]
                ],
                "required": ["hostname"]
            ] as [String: Any]
        ] as [String: Any]
    ]

    nonisolated(unsafe) static let cronParse: [String: Any] = [
        "type": "function",
        "function": [
            "name": "cron_parse",
            "description": "Parse a cron expression and show the next N scheduled run times.",
            "parameters": [
                "type": "object",
                "properties": [
                    "expression": ["type": "string", "description": "Cron expression (e.g. '0 */2 * * *')"],
                    "count": ["type": "integer", "description": "Number of next run times to show (default 5)"]
                ],
                "required": ["expression"]
            ] as [String: Any]
        ] as [String: Any]
    ]

    nonisolated(unsafe) static let jsonSchemaValidate: [String: Any] = [
        "type": "function",
        "function": [
            "name": "json_schema_validate",
            "description": "Validate a JSON document against a JSON Schema.",
            "parameters": [
                "type": "object",
                "properties": [
                    "json": ["type": "string", "description": "JSON string or file path to validate"],
                    "schema": ["type": "string", "description": "JSON Schema string or file path"]
                ],
                "required": ["json", "schema"]
            ] as [String: Any]
        ] as [String: Any]
    ]

    // MARK: - Apple-Native Tools

    nonisolated(unsafe) static let spotlightSearch: [String: Any] = [
        "type": "function",
        "function": [
            "name": "spotlight_search",
            "description": "Search files, emails, messages, and content on the local Mac using Spotlight (CoreSpotlight/mdfind). Returns file paths, types, and metadata.",
            "parameters": [
                "type": "object",
                "properties": [
                    "query": ["type": "string", "description": "Search query (supports natural language and metadata filters like 'kind:pdf')"],
                    "directory": ["type": "string", "description": "Optional directory to scope the search to"],
                    "limit": ["type": "integer", "description": "Max results to return (default: 20)"]
                ],
                "required": ["query"]
            ] as [String: Any]
        ] as [String: Any]
    ]

    nonisolated(unsafe) static let keychainRead: [String: Any] = [
        "type": "function",
        "function": [
            "name": "keychain_read",
            "description": "Read a value from the macOS Keychain. Only reads items created by G-Rump (service: com.grump.*). Returns the stored string value.",
            "parameters": [
                "type": "object",
                "properties": [
                    "key": ["type": "string", "description": "The key/account name to look up"],
                    "service": ["type": "string", "description": "Optional service identifier (default: com.grump.agent)"]
                ],
                "required": ["key"]
            ] as [String: Any]
        ] as [String: Any]
    ]

    nonisolated(unsafe) static let keychainStore: [String: Any] = [
        "type": "function",
        "function": [
            "name": "keychain_store",
            "description": "Store a key-value pair in the macOS Keychain under G-Rump's service. Use for API keys, tokens, or secrets that should persist securely.",
            "parameters": [
                "type": "object",
                "properties": [
                    "key": ["type": "string", "description": "The key/account name to store under"],
                    "value": ["type": "string", "description": "The secret value to store"],
                    "service": ["type": "string", "description": "Optional service identifier (default: com.grump.agent)"]
                ],
                "required": ["key", "value"]
            ] as [String: Any]
        ] as [String: Any]
    ]

    nonisolated(unsafe) static let calendarEvents: [String: Any] = [
        "type": "function",
        "function": [
            "name": "calendar_events",
            "description": "List or create calendar events using EventKit. Can query events in a date range or create new events.",
            "parameters": [
                "type": "object",
                "properties": [
                    "action": ["type": "string", "description": "'list' to query events, 'create' to add a new event"],
                    "start_date": ["type": "string", "description": "Start date (ISO 8601 format, e.g. 2025-01-15T09:00:00)"],
                    "end_date": ["type": "string", "description": "End date (ISO 8601 format)"],
                    "title": ["type": "string", "description": "Event title (required for create)"],
                    "notes": ["type": "string", "description": "Event notes/description"],
                    "calendar": ["type": "string", "description": "Calendar name (default: default calendar)"]
                ],
                "required": ["action"]
            ] as [String: Any]
        ] as [String: Any]
    ]

    nonisolated(unsafe) static let remindersList: [String: Any] = [
        "type": "function",
        "function": [
            "name": "reminders_list",
            "description": "List or create reminders using EventKit. Query incomplete reminders or add new ones with optional due dates.",
            "parameters": [
                "type": "object",
                "properties": [
                    "action": ["type": "string", "description": "'list' to query reminders, 'create' to add a new reminder"],
                    "title": ["type": "string", "description": "Reminder title (required for create)"],
                    "due_date": ["type": "string", "description": "Due date (ISO 8601 format)"],
                    "list_name": ["type": "string", "description": "Reminders list name (default: default list)"],
                    "show_completed": ["type": "boolean", "description": "Include completed reminders (default: false)"]
                ],
                "required": ["action"]
            ] as [String: Any]
        ] as [String: Any]
    ]

    nonisolated(unsafe) static let contactsSearch: [String: Any] = [
        "type": "function",
        "function": [
            "name": "contacts_search",
            "description": "Search the macOS Contacts (address book) by name, email, or phone number. Returns matching contact info.",
            "parameters": [
                "type": "object",
                "properties": [
                    "query": ["type": "string", "description": "Search query (name, email, or phone number)"],
                    "limit": ["type": "integer", "description": "Max results (default: 10)"]
                ],
                "required": ["query"]
            ] as [String: Any]
        ] as [String: Any]
    ]

    nonisolated(unsafe) static let speechTranscribe: [String: Any] = [
        "type": "function",
        "function": [
            "name": "speech_transcribe",
            "description": "Transcribe an audio file to text using Apple's Speech framework. Supports WAV, M4A, MP3, CAF formats. Runs entirely on-device.",
            "parameters": [
                "type": "object",
                "properties": [
                    "path": ["type": "string", "description": "Path to audio file"],
                    "language": ["type": "string", "description": "Language code (default: en-US)"]
                ],
                "required": ["path"]
            ] as [String: Any]
        ] as [String: Any]
    ]

    nonisolated(unsafe) static let ocrExtract: [String: Any] = [
        "type": "function",
        "function": [
            "name": "ocr_extract",
            "description": "Extract text from an image using Apple's Vision framework (VNRecognizeTextRequest). Runs entirely on-device. Supports PNG, JPEG, TIFF, HEIC.",
            "parameters": [
                "type": "object",
                "properties": [
                    "path": ["type": "string", "description": "Path to image file"],
                    "language": ["type": "string", "description": "Recognition language (default: en-US)"],
                    "level": ["type": "string", "description": "'fast' or 'accurate' (default: accurate)"]
                ],
                "required": ["path"]
            ] as [String: Any]
        ] as [String: Any]
    ]

    nonisolated(unsafe) static let imageClassify: [String: Any] = [
        "type": "function",
        "function": [
            "name": "image_classify",
            "description": "Classify image contents using Apple's Vision framework (VNClassifyImageRequest). Returns labels with confidence scores. Runs on-device.",
            "parameters": [
                "type": "object",
                "properties": [
                    "path": ["type": "string", "description": "Path to image file"],
                    "max_results": ["type": "integer", "description": "Max classification results (default: 5)"]
                ],
                "required": ["path"]
            ] as [String: Any]
        ] as [String: Any]
    ]

    nonisolated(unsafe) static let shortcutsRun: [String: Any] = [
        "type": "function",
        "function": [
            "name": "shortcuts_run",
            "description": "Run a named macOS Shortcut via the 'shortcuts' CLI. Can pass input text and receive output.",
            "parameters": [
                "type": "object",
                "properties": [
                    "name": ["type": "string", "description": "Name of the Shortcut to run"],
                    "input": ["type": "string", "description": "Optional input text to pass to the Shortcut"]
                ],
                "required": ["name"]
            ] as [String: Any]
        ] as [String: Any]
    ]

    nonisolated(unsafe) static let systemAppearance: [String: Any] = [
        "type": "function",
        "function": [
            "name": "system_appearance",
            "description": "Get or set macOS system appearance settings. Can read current dark/light mode, accent color, and highlight color.",
            "parameters": [
                "type": "object",
                "properties": [
                    "action": ["type": "string", "description": "'get' to read current appearance, 'set' to change it"],
                    "dark_mode": ["type": "boolean", "description": "Set dark mode on/off (only for action=set)"]
                ],
                "required": ["action"]
            ] as [String: Any]
        ] as [String: Any]
    ]

    // MARK: - Advanced Code (Apple Toolchain)

    nonisolated(unsafe) static let xcodebuildTool: [String: Any] = [
        "type": "function",
        "function": [
            "name": "xcodebuild",
            "description": "Build Xcode projects or workspaces. Reports build errors, warnings, and test results. Supports build, test, clean, and archive actions.",
            "parameters": [
                "type": "object",
                "properties": [
                    "action": ["type": "string", "description": "'build', 'test', 'clean', or 'archive'"],
                    "project": ["type": "string", "description": "Path to .xcodeproj file"],
                    "workspace": ["type": "string", "description": "Path to .xcworkspace file (use instead of project)"],
                    "scheme": ["type": "string", "description": "Build scheme name"],
                    "destination": ["type": "string", "description": "Build destination (e.g. 'platform=macOS' or 'platform=iOS Simulator,name=iPhone 16')"],
                    "configuration": ["type": "string", "description": "'Debug' or 'Release' (default: Debug)"]
                ],
                "required": ["action"]
            ] as [String: Any]
        ] as [String: Any]
    ]

    nonisolated(unsafe) static let xcrunSimctl: [String: Any] = [
        "type": "function",
        "function": [
            "name": "xcrun_simctl",
            "description": "Manage iOS/watchOS/tvOS simulators via xcrun simctl. List, boot (bootstatus waits until usable), shutdown, install/launch/terminate apps, read an app's recent logs, take screenshots — the same loop the Run button drives.",
            "parameters": [
                "type": "object",
                "properties": [
                    "action": ["type": "string", "description": "'list', 'boot', 'bootstatus', 'shutdown', 'install', 'launch', 'terminate', 'app_log', 'screenshot', 'delete'"],
                    "device_id": ["type": "string", "description": "Simulator device UUID (required for everything except list)"],
                    "app_path": ["type": "string", "description": "Path to .app bundle (required for install)"],
                    "bundle_id": ["type": "string", "description": "App bundle identifier (required for launch/terminate)"],
                    "process_name": ["type": "string", "description": "App process name (required for app_log)"],
                    "last": ["type": "string", "description": "app_log lookback window, e.g. '2m', '30s', '1h' (default: 2m)"],
                    "output_path": ["type": "string", "description": "Screenshot output path (for screenshot action)"]
                ],
                "required": ["action"]
            ] as [String: Any]
        ] as [String: Any]
    ]

    nonisolated(unsafe) static let swiftFormatTool: [String: Any] = [
        "type": "function",
        "function": [
            "name": "swift_format",
            "description": "Format Swift source files using swift-format. Applies consistent style rules.",
            "parameters": [
                "type": "object",
                "properties": [
                    "path": ["type": "string", "description": "File or directory to format"],
                    "in_place": ["type": "boolean", "description": "Modify files in place (default: false, prints to stdout)"],
                    "config": ["type": "string", "description": "Path to .swift-format configuration file"]
                ],
                "required": ["path"]
            ] as [String: Any]
        ] as [String: Any]
    ]

    nonisolated(unsafe) static let swiftLintTool: [String: Any] = [
        "type": "function",
        "function": [
            "name": "swift_lint",
            "description": "Run SwiftLint on Swift source files. Returns violations with file, line, severity, and rule name.",
            "parameters": [
                "type": "object",
                "properties": [
                    "path": ["type": "string", "description": "File or directory to lint"],
                    "fix": ["type": "boolean", "description": "Auto-correct fixable violations (default: false)"],
                    "config": ["type": "string", "description": "Path to .swiftlint.yml configuration"]
                ],
                "required": ["path"]
            ] as [String: Any]
        ] as [String: Any]
    ]

    nonisolated(unsafe) static let swiftPackageTool: [String: Any] = [
        "type": "function",
        "function": [
            "name": "swift_package",
            "description": "Run Swift Package Manager commands: resolve, update, show-dependencies, generate-xcodeproj, dump-package.",
            "parameters": [
                "type": "object",
                "properties": [
                    "action": ["type": "string", "description": "'resolve', 'update', 'show-dependencies', 'generate-xcodeproj', 'dump-package', 'init', 'reset'"],
                    "directory": ["type": "string", "description": "Package directory (default: current working directory)"]
                ],
                "required": ["action"]
            ] as [String: Any]
        ] as [String: Any]
    ]

    // MARK: - Media Tools

    nonisolated(unsafe) static let pdfExtract: [String: Any] = [
        "type": "function",
        "function": [
            "name": "pdf_extract",
            "description": "Extract text content from a PDF file using PDFKit. Returns text from all pages or a specific page range.",
            "parameters": [
                "type": "object",
                "properties": [
                    "path": ["type": "string", "description": "Path to PDF file"],
                    "start_page": ["type": "integer", "description": "Start page (1-indexed, default: 1)"],
                    "end_page": ["type": "integer", "description": "End page (default: last page)"]
                ],
                "required": ["path"]
            ] as [String: Any]
        ] as [String: Any]
    ]

    nonisolated(unsafe) static let ttsSpeak: [String: Any] = [
        "type": "function",
        "function": [
            "name": "tts_speak",
            "description": "Speak text aloud using AVSpeechSynthesizer. Uses system voices. Can also save speech to audio file.",
            "parameters": [
                "type": "object",
                "properties": [
                    "text": ["type": "string", "description": "Text to speak"],
                    "voice": ["type": "string", "description": "Voice identifier (e.g. 'com.apple.voice.compact.en-US.Samantha')"],
                    "rate": ["type": "number", "description": "Speech rate 0.0-1.0 (default: 0.5)"],
                    "output_path": ["type": "string", "description": "Optional path to save audio file instead of speaking"]
                ],
                "required": ["text"]
            ] as [String: Any]
        ] as [String: Any]
    ]

    nonisolated(unsafe) static let qrGenerate: [String: Any] = [
        "type": "function",
        "function": [
            "name": "qr_generate",
            "description": "Generate a QR code image from text using CoreImage CIQRCodeGenerator. Saves as PNG.",
            "parameters": [
                "type": "object",
                "properties": [
                    "content": ["type": "string", "description": "Text or URL to encode in the QR code"],
                    "output_path": ["type": "string", "description": "Path to save the QR code PNG image"],
                    "size": ["type": "integer", "description": "Image size in pixels (default: 512)"]
                ],
                "required": ["content", "output_path"]
            ] as [String: Any]
        ] as [String: Any]
    ]

    // MARK: - Network Tools

    nonisolated(unsafe) static let websocketSend: [String: Any] = [
        "type": "function",
        "function": [
            "name": "websocket_send",
            "description": "Connect to a WebSocket endpoint, send a message, and return the response. Uses URLSessionWebSocketTask.",
            "parameters": [
                "type": "object",
                "properties": [
                    "url": ["type": "string", "description": "WebSocket URL (ws:// or wss://)"],
                    "message": ["type": "string", "description": "Message to send"],
                    "timeout": ["type": "integer", "description": "Timeout in seconds (default: 10)"]
                ],
                "required": ["url", "message"]
            ] as [String: Any]
        ] as [String: Any]
    ]

    nonisolated(unsafe) static let graphqlQuery: [String: Any] = [
        "type": "function",
        "function": [
            "name": "graphql_query",
            "description": "Execute a GraphQL query or mutation against an endpoint. Returns JSON response.",
            "parameters": [
                "type": "object",
                "properties": [
                    "url": ["type": "string", "description": "GraphQL endpoint URL"],
                    "query": ["type": "string", "description": "GraphQL query or mutation string"],
                    "variables": ["type": "string", "description": "JSON string of variables"],
                    "headers": ["type": "string", "description": "JSON string of additional headers (e.g. authorization)"]
                ],
                "required": ["url", "query"]
            ] as [String: Any]
        ] as [String: Any]
    ]

    nonisolated(unsafe) static let bonjourDiscover: [String: Any] = [
        "type": "function",
        "function": [
            "name": "bonjour_discover",
            "description": "Discover local network services using Bonjour/mDNS (NetServiceBrowser). Finds services like web servers, printers, AirPlay devices.",
            "parameters": [
                "type": "object",
                "properties": [
                    "service_type": ["type": "string", "description": "Bonjour service type (e.g. '_http._tcp.', '_airplay._tcp.', '_ssh._tcp.')"],
                    "domain": ["type": "string", "description": "Domain to search (default: 'local.')"],
                    "timeout": ["type": "integer", "description": "Discovery timeout in seconds (default: 5)"]
                ],
                "required": ["service_type"]
            ] as [String: Any]
        ] as [String: Any]
    ]

    // MARK: - Swift IDE Intelligence Tools

    nonisolated(unsafe) static let appleDocsSearch: [String: Any] = [
        "type": "function",
        "function": [
            "name": "apple_docs_search",
            "description": "Search Apple Developer Documentation for APIs, frameworks, guides, and sample code. Returns structured results with titles, types, summaries, and URLs from developer.apple.com.",
            "parameters": [
                "type": "object",
                "properties": [
                    "query": ["type": "string", "description": "Search query (e.g. 'SwiftUI NavigationStack', 'URLSession async', 'Core Data migration')"]
                ],
                "required": ["query"]
            ] as [String: Any]
        ] as [String: Any]
    ]

    nonisolated(unsafe) static let lspDiagnostics: [String: Any] = [
        "type": "function",
        "function": [
            "name": "lsp_diagnostics",
            "description": "Get current SourceKit-LSP diagnostics (errors and warnings) for the workspace. Returns structured compiler errors with file, line, column, severity, and message.",
            "parameters": [
                "type": "object",
                "properties": [
                    "file": ["type": "string", "description": "Optional: filter diagnostics to a specific file path. Omit to get all diagnostics."]
                ],
                "required": [] as [String]
            ] as [String: Any]
        ] as [String: Any]
    ]

    nonisolated(unsafe) static let accessibilityAudit: [String: Any] = [
        "type": "function",
        "function": [
            "name": "accessibility_audit",
            "description": "Scan Swift files in the workspace for accessibility issues: missing accessibility labels, small touch targets, hardcoded font sizes, missing Dynamic Type support, and poor contrast patterns.",
            "parameters": [
                "type": "object",
                "properties": [
                    "directory": ["type": "string", "description": "Directory to scan (defaults to working directory)"]
                ],
                "required": [] as [String]
            ] as [String: Any]
        ] as [String: Any]
    ]

    nonisolated(unsafe) static let localizationAudit: [String: Any] = [
        "type": "function",
        "function": [
            "name": "localization_audit",
            "description": "Scan Swift files for hardcoded user-facing strings that should use NSLocalizedString or String(localized:). Also reports .xcstrings/.strings coverage and missing translations.",
            "parameters": [
                "type": "object",
                "properties": [
                    "directory": ["type": "string", "description": "Directory to scan (defaults to working directory)"]
                ],
                "required": [] as [String]
            ] as [String: Any]
        ] as [String: Any]
    ]

    nonisolated(unsafe) static let spmResolve: [String: Any] = [
        "type": "function",
        "function": [
            "name": "spm_resolve",
            "description": "Resolve or update Swift Package Manager dependencies. Parses Package.swift and Package.resolved to report dependency versions, then optionally runs 'swift package resolve' or 'swift package update'.",
            "parameters": [
                "type": "object",
                "properties": [
                    "action": ["type": "string", "description": "Action to perform: 'status' (default), 'resolve', or 'update'"],
                    "directory": ["type": "string", "description": "Project directory containing Package.swift"]
                ],
                "required": [] as [String]
            ] as [String: Any]
        ] as [String: Any]
    ]

    nonisolated(unsafe) static let appStoreChecklist: [String: Any] = [
        "type": "function",
        "function": [
            "name": "app_store_checklist",
            "description": "Run App Store submission pre-flight checks: verify app icons, privacy manifest, Info.plist keys, entitlements, and deployment targets. Returns a pass/fail/warning checklist.",
            "parameters": [
                "type": "object",
                "properties": [
                    "directory": ["type": "string", "description": "Project directory to check (defaults to working directory)"]
                ],
                "required": [] as [String]
            ] as [String: Any]
        ] as [String: Any]
    ]

    // MARK: - User Interaction

    nonisolated(unsafe) static let askUser: [String: Any] = [
        "type": "function",
        "function": [
            "name": "ask_user",
            "description": "Present a question to the user with multiple-choice options. The user will see a clickable grid of option cards (A, B, C, D format) and can select their answer with a single click. Use this whenever you need the user to choose between specific options.",
            "parameters": [
                "type": "object",
                "properties": [
                    "question": [
                        "type": "string",
                        "description": "The question to ask the user"
                    ],
                    "options": [
                        "type": "array",
                        "items": [
                            "type": "object",
                            "properties": [
                                "label": ["type": "string", "description": "Short label for the option (e.g. 'Option A')"],
                                "description": ["type": "string", "description": "Longer description of what this option means"]
                            ],
                            "required": ["label", "description"]
                        ] as [String: Any],
                        "description": "2-4 options for the user to choose from"
                    ] as [String: Any]
                ],
                "required": ["question", "options"]
            ] as [String: Any]
        ] as [String: Any]
    ]
}
