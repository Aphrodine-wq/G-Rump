import Foundation

// MARK: - File Operation Tool Definitions
// Extracted from ToolDefinitions.swift for maintainability.

extension ToolDefinitions {

    // MARK: - File Operations

    nonisolated(unsafe) static let readFile: [String: Any] = [
        "type": "function",
        "function": [
            "name": "read_file",
            "description": "Read a file's contents. Returns line-numbered output. For large files, use start_line/end_line to read specific sections.",
            "parameters": [
                "type": "object",
                "properties": [
                    "path": [
                        "type": "string",
                        "description": "Absolute or relative path to the file"
                    ],
                    "start_line": [
                        "type": "integer",
                        "description": "Start line (1-indexed). Omit to read from beginning."
                    ],
                    "end_line": [
                        "type": "integer",
                        "description": "End line (1-indexed, inclusive). Omit to read to end."
                    ]
                ],
                "required": ["path"]
            ] as [String: Any]
        ] as [String: Any]
    ]

    nonisolated(unsafe) static let batchReadFiles: [String: Any] = [
        "type": "function",
        "function": [
            "name": "batch_read_files",
            "description": "Read multiple files at once. More efficient than multiple read_file calls. Returns contents of up to 10 files.",
            "parameters": [
                "type": "object",
                "properties": [
                    "paths": [
                        "type": "array",
                        "items": ["type": "string"],
                        "description": "Array of file paths to read (max 10)"
                    ]
                ],
                "required": ["paths"]
            ] as [String: Any]
        ] as [String: Any]
    ]

    nonisolated(unsafe) static let writeFile: [String: Any] = [
        "type": "function",
        "function": [
            "name": "write_file",
            "description": "Write content to a file. Creates the file and parent directories if they don't exist. Overwrites existing content. For targeted changes to existing files, prefer edit_file.",
            "parameters": [
                "type": "object",
                "properties": [
                    "path": [
                        "type": "string",
                        "description": "Absolute or relative path of the file to write"
                    ],
                    "content": [
                        "type": "string",
                        "description": "The full content to write to the file"
                    ]
                ],
                "required": ["path", "content"]
            ] as [String: Any]
        ] as [String: Any]
    ]

    nonisolated(unsafe) static let editFile: [String: Any] = [
        "type": "function",
        "function": [
            "name": "edit_file",
            "description": "Make a targeted edit to a file by finding old content and replacing it with new content. Preserves the rest of the file. old_content must be UNIQUE in the file — if it matches multiple locations the edit fails; include more surrounding lines or pass replace_all. If the exact text isn't found, a whitespace-tolerant match is attempted (applied only when unambiguous, and flagged in the result so you can verify). Always read_file first to see exact content.",
            "parameters": [
                "type": "object",
                "properties": [
                    "path": [
                        "type": "string",
                        "description": "Path to the file to edit"
                    ],
                    "old_content": [
                        "type": "string",
                        "description": "The content to find — must match exactly one location unless replace_all is true"
                    ],
                    "new_content": [
                        "type": "string",
                        "description": "The replacement content"
                    ],
                    "replace_all": [
                        "type": "boolean",
                        "description": "Replace every occurrence of old_content instead of requiring a unique match (default false)"
                    ]
                ],
                "required": ["path", "old_content", "new_content"]
            ] as [String: Any]
        ] as [String: Any]
    ]

    nonisolated(unsafe) static let createFile: [String: Any] = [
        "type": "function",
        "function": [
            "name": "create_file",
            "description": "Create a new file. Fails if the file already exists (use write_file to overwrite). Creates parent directories automatically.",
            "parameters": [
                "type": "object",
                "properties": [
                    "path": [
                        "type": "string",
                        "description": "Path for the new file"
                    ],
                    "content": [
                        "type": "string",
                        "description": "Content of the new file"
                    ]
                ],
                "required": ["path", "content"]
            ] as [String: Any]
        ] as [String: Any]
    ]

    nonisolated(unsafe) static let deleteFile: [String: Any] = [
        "type": "function",
        "function": [
            "name": "delete_file",
            "description": "Delete a file or empty directory.",
            "parameters": [
                "type": "object",
                "properties": [
                    "path": [
                        "type": "string",
                        "description": "Path to delete"
                    ]
                ],
                "required": ["path"]
            ] as [String: Any]
        ] as [String: Any]
    ]

    nonisolated(unsafe) static let moveFile: [String: Any] = [
        "type": "function",
        "function": [
            "name": "move_file",
            "description": "Move or rename a file or directory. Creates parent directories of destination if needed.",
            "parameters": [
                "type": "object",
                "properties": [
                    "source": ["type": "string", "description": "Source path"],
                    "destination": ["type": "string", "description": "Destination path (file or directory)"]
                ],
                "required": ["source", "destination"]
            ] as [String: Any]
        ] as [String: Any]
    ]

    nonisolated(unsafe) static let copyFile: [String: Any] = [
        "type": "function",
        "function": [
            "name": "copy_file",
            "description": "Copy a file or directory to a new location. Use for backups or duplicating files. Does not overwrite by default; set overwrite true to replace.",
            "parameters": [
                "type": "object",
                "properties": [
                    "source": ["type": "string", "description": "Source path"],
                    "destination": ["type": "string", "description": "Destination path"],
                    "overwrite": ["type": "boolean", "description": "Overwrite if destination exists (default: false)"]
                ],
                "required": ["source", "destination"]
            ] as [String: Any]
        ] as [String: Any]
    ]

    nonisolated(unsafe) static let fileInfo: [String: Any] = [
        "type": "function",
        "function": [
            "name": "file_info",
            "description": "Get metadata for a file or directory: size, is_directory, modification date, extension. Use to check existence and stats before reading or editing.",
            "parameters": [
                "type": "object",
                "properties": [
                    "path": ["type": "string", "description": "Path to the file or directory"]
                ],
                "required": ["path"]
            ] as [String: Any]
        ] as [String: Any]
    ]

    nonisolated(unsafe) static let pathExists: [String: Any] = [
        "type": "function",
        "function": [
            "name": "path_exists",
            "description": "Check if a path exists and whether it is a file or directory. Returns exists, is_directory.",
            "parameters": [
                "type": "object",
                "properties": [
                    "path": ["type": "string", "description": "Path to check"]
                ],
                "required": ["path"]
            ] as [String: Any]
        ] as [String: Any]
    ]

    nonisolated(unsafe) static let countLines: [String: Any] = [
        "type": "function",
        "function": [
            "name": "count_lines",
            "description": "Count lines in a text file. Fast way to get file size in lines without reading content. Useful for deciding whether to use read_file with ranges.",
            "parameters": [
                "type": "object",
                "properties": [
                    "path": ["type": "string", "description": "Path to the file"]
                ],
                "required": ["path"]
            ] as [String: Any]
        ] as [String: Any]
    ]

    // MARK: - Directory & Search

    nonisolated(unsafe) static let listDirectory: [String: Any] = [
        "type": "function",
        "function": [
            "name": "list_directory",
            "description": "List files and directories with sizes. Supports recursive listing. Automatically hides .git, node_modules, and dotfiles unless show_hidden is true.",
            "parameters": [
                "type": "object",
                "properties": [
                    "path": [
                        "type": "string",
                        "description": "Directory path to list"
                    ],
                    "recursive": [
                        "type": "boolean",
                        "description": "List all files recursively (default: false)"
                    ],
                    "show_hidden": [
                        "type": "boolean",
                        "description": "Show hidden/dot files (default: false)"
                    ]
                ],
                "required": ["path"]
            ] as [String: Any]
        ] as [String: Any]
    ]

    nonisolated(unsafe) static let treeView: [String: Any] = [
        "type": "function",
        "function": [
            "name": "tree_view",
            "description": "Show a tree view of a directory structure. Automatically excludes .git, node_modules, __pycache__, .build directories. Great for understanding project layout.",
            "parameters": [
                "type": "object",
                "properties": [
                    "path": [
                        "type": "string",
                        "description": "Root directory to show tree for"
                    ],
                    "max_depth": [
                        "type": "integer",
                        "description": "Maximum depth to traverse (default: 4)"
                    ]
                ],
                "required": ["path"]
            ] as [String: Any]
        ] as [String: Any]
    ]

    nonisolated(unsafe) static let searchFiles: [String: Any] = [
        "type": "function",
        "function": [
            "name": "search_files",
            "description": "Search for files by name pattern within a directory tree. Uses glob patterns. Excludes .git and node_modules.",
            "parameters": [
                "type": "object",
                "properties": [
                    "directory": [
                        "type": "string",
                        "description": "Root directory to search in"
                    ],
                    "pattern": [
                        "type": "string",
                        "description": "Glob pattern to match file names (e.g. '*.swift', 'package.json')"
                    ]
                ],
                "required": ["directory", "pattern"]
            ] as [String: Any]
        ] as [String: Any]
    ]

    nonisolated(unsafe) static let grepSearch: [String: Any] = [
        "type": "function",
        "function": [
            "name": "grep_search",
            "description": "Search for text patterns in file contents across a directory. Returns matching lines with file paths and line numbers. Excludes .git, node_modules, .build directories.",
            "parameters": [
                "type": "object",
                "properties": [
                    "query": [
                        "type": "string",
                        "description": "Search term or regex pattern"
                    ],
                    "path": [
                        "type": "string",
                        "description": "Directory or file to search within"
                    ],
                    "is_regex": [
                        "type": "boolean",
                        "description": "Treat query as regex (default: false, uses literal/fixed string matching)"
                    ],
                    "include": [
                        "type": "string",
                        "description": "Glob pattern to filter files (e.g. '*.py', '*.swift')"
                    ]
                ],
                "required": ["query", "path"]
            ] as [String: Any]
        ] as [String: Any]
    ]

    nonisolated(unsafe) static let findAndReplace: [String: Any] = [
        "type": "function",
        "function": [
            "name": "find_and_replace",
            "description": "Find and replace a string across all files in a directory. Useful for renaming symbols, updating imports, or project-wide refactoring. Supports dry_run to preview changes.",
            "parameters": [
                "type": "object",
                "properties": [
                    "directory": [
                        "type": "string",
                        "description": "Root directory to search in"
                    ],
                    "find": [
                        "type": "string",
                        "description": "The exact string to find"
                    ],
                    "replace": [
                        "type": "string",
                        "description": "The replacement string"
                    ],
                    "include": [
                        "type": "string",
                        "description": "File extension filter (e.g. '*.swift', '*.ts')"
                    ],
                    "dry_run": [
                        "type": "boolean",
                        "description": "Preview changes without modifying files (default: false)"
                    ]
                ],
                "required": ["directory", "find", "replace"]
            ] as [String: Any]
        ] as [String: Any]
    ]

    nonisolated(unsafe) static let appendFile: [String: Any] = [
        "type": "function",
        "function": [
            "name": "append_file",
            "description": "Append content to an existing file. Creates the file if it doesn't exist. Does not overwrite.",
            "parameters": [
                "type": "object",
                "properties": [
                    "path": ["type": "string", "description": "Path to the file"],
                    "content": ["type": "string", "description": "Content to append"]
                ],
                "required": ["path", "content"]
            ] as [String: Any]
        ] as [String: Any]
    ]

    nonisolated(unsafe) static let createDirectory: [String: Any] = [
        "type": "function",
        "function": [
            "name": "create_directory",
            "description": "Create a directory (and parent directories if needed). Fails if path exists and is not a directory.",
            "parameters": [
                "type": "object",
                "properties": [
                    "path": ["type": "string", "description": "Path of directory to create"]
                ],
                "required": ["path"]
            ] as [String: Any]
        ] as [String: Any]
    ]

    nonisolated(unsafe) static let compressFiles: [String: Any] = [
        "type": "function",
        "function": [
            "name": "compress_files",
            "description": "Compress files or a directory into a zip archive.",
            "parameters": [
                "type": "object",
                "properties": [
                    "paths": ["type": "array", "items": ["type": "string"], "description": "Paths to compress"],
                    "output": ["type": "string", "description": "Output zip path"]
                ],
                "required": ["paths", "output"]
            ] as [String: Any]
        ] as [String: Any]
    ]

    nonisolated(unsafe) static let extractArchive: [String: Any] = [
        "type": "function",
        "function": [
            "name": "extract_archive",
            "description": "Extract a zip or tar archive to a directory.",
            "parameters": [
                "type": "object",
                "properties": [
                    "path": ["type": "string", "description": "Path to the archive"],
                    "destination": ["type": "string", "description": "Destination directory"]
                ],
                "required": ["path", "destination"]
            ] as [String: Any]
        ] as [String: Any]
    ]
}
