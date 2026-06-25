import Foundation

/// A predefined MCP server that users can add with one click.
struct MCPServerPreset: Identifiable {
    let id: String
    let name: String
    let description: String
    let icon: String

    func toConfig() -> MCPServerConfig {
        let homeDir = NSHomeDirectory()
        switch id {
        case "memory":
            return MCPServerConfig(id: "memory", name: "Memory", enabled: true,
                transport: .stdio(command: "npx", args: ["-y", "@modelcontextprotocol/server-memory"]))
        case "fetch":
            return MCPServerConfig(id: "fetch", name: "Fetch", enabled: true,
                transport: .stdio(command: "npx", args: ["-y", "@modelcontextprotocol/server-fetch"]))
        case "filesystem":
            return MCPServerConfig(id: "filesystem", name: "Filesystem", enabled: true,
                transport: .stdio(command: "npx", args: ["-y", "@modelcontextprotocol/server-filesystem", homeDir]))
        case "github":
            return MCPServerConfig(id: "github", name: "GitHub", enabled: true,
                transport: .stdio(command: "npx", args: ["-y", "@modelcontextprotocol/server-github"]))
        case "postgres":
            return MCPServerConfig(id: "postgres", name: "Postgres", enabled: true,
                transport: .stdio(command: "npx", args: ["-y", "@modelcontextprotocol/server-postgres"]))
        case "puppeteer":
            return MCPServerConfig(id: "puppeteer", name: "Puppeteer", enabled: true,
                transport: .stdio(command: "npx", args: ["-y", "@modelcontextprotocol/server-puppeteer"]))
        case "brave-search":
            return MCPServerConfig(id: "brave-search", name: "Brave Search", enabled: true,
                transport: .stdio(command: "npx", args: ["-y", "@modelcontextprotocol/server-brave-search"]))
        case "sqlite":
            return MCPServerConfig(id: "sqlite", name: "SQLite", enabled: true,
                transport: .stdio(command: "npx", args: ["-y", "@modelcontextprotocol/server-sqlite"]))
        case "slack":
            return MCPServerConfig(id: "slack", name: "Slack", enabled: true,
                transport: .stdio(command: "npx", args: ["-y", "@modelcontextprotocol/server-slack"]))
        case "gdrive":
            return MCPServerConfig(id: "gdrive", name: "Google Drive", enabled: true,
                transport: .stdio(command: "npx", args: ["-y", "@modelcontextprotocol/server-gdrive"]))
        case "sentry":
            return MCPServerConfig(id: "sentry", name: "Sentry", enabled: true,
                transport: .stdio(command: "npx", args: ["-y", "@modelcontextprotocol/server-sentry"]))
        case "claude-code":
            return MCPServerConfig(id: "claude-code", name: "Claude Code", enabled: true,
                transport: .stdio(command: "claude", args: ["mcp", "serve"]))
        case "manus":
            return MCPServerConfig(id: "manus", name: "Manus", enabled: true,
                transport: .http(url: "http://localhost:8765"))
        case "linear":
            return MCPServerConfig(id: "linear", name: "Linear", enabled: true,
                transport: .stdio(command: "npx", args: ["-y", "@modelcontextprotocol/server-linear"]))
        case "notion":
            return MCPServerConfig(id: "notion", name: "Notion", enabled: true,
                transport: .stdio(command: "npx", args: ["-y", "@modelcontextprotocol/server-notion"]))
        case "jira":
            return MCPServerConfig(id: "jira", name: "Jira", enabled: true,
                transport: .stdio(command: "npx", args: ["-y", "@modelcontextprotocol/server-jira"]))
        case "figma":
            return MCPServerConfig(id: "figma", name: "Figma", enabled: true,
                transport: .stdio(command: "npx", args: ["-y", "@anthropic/mcp-server-figma"]))
        case "vercel":
            return MCPServerConfig(id: "vercel", name: "Vercel", enabled: true,
                transport: .stdio(command: "npx", args: ["-y", "@modelcontextprotocol/server-vercel"]))
        case "supabase":
            return MCPServerConfig(id: "supabase", name: "Supabase", enabled: true,
                transport: .stdio(command: "npx", args: ["-y", "@modelcontextprotocol/server-supabase"]))
        case "cloudflare":
            return MCPServerConfig(id: "cloudflare", name: "Cloudflare", enabled: true,
                transport: .stdio(command: "npx", args: ["-y", "@modelcontextprotocol/server-cloudflare"]))
        case "todoist":
            return MCPServerConfig(id: "todoist", name: "Todoist", enabled: true,
                transport: .stdio(command: "npx", args: ["-y", "@modelcontextprotocol/server-todoist"]))
        case "raycast":
            return MCPServerConfig(id: "raycast", name: "Raycast", enabled: true,
                transport: .stdio(command: "npx", args: ["-y", "@modelcontextprotocol/server-raycast"]))
        case "turso":
            return MCPServerConfig(id: "turso", name: "Turso", enabled: true,
                transport: .stdio(command: "npx", args: ["-y", "@modelcontextprotocol/server-turso"]))
        // Code & DevOps
        case "semgrep":
            return MCPServerConfig(id: "semgrep", name: "Semgrep", enabled: true,
                transport: .stdio(command: "npx", args: ["-y", "@modelcontextprotocol/server-semgrep"]))
        case "sourcegraph":
            return MCPServerConfig(id: "sourcegraph", name: "Sourcegraph", enabled: true,
                transport: .stdio(command: "npx", args: ["-y", "@modelcontextprotocol/server-sourcegraph"]))
        case "gitlab":
            return MCPServerConfig(id: "gitlab", name: "GitLab", enabled: true,
                transport: .stdio(command: "npx", args: ["-y", "@modelcontextprotocol/server-gitlab"]))
        case "buildkite":
            return MCPServerConfig(id: "buildkite", name: "Buildkite", enabled: true,
                transport: .stdio(command: "npx", args: ["-y", "@modelcontextprotocol/server-buildkite"]))
        case "circleci":
            return MCPServerConfig(id: "circleci", name: "CircleCI", enabled: true,
                transport: .stdio(command: "npx", args: ["-y", "@modelcontextprotocol/server-circleci"]))
        case "aws":
            return MCPServerConfig(id: "aws", name: "AWS", enabled: true,
                transport: .stdio(command: "npx", args: ["-y", "@modelcontextprotocol/server-aws"]))
        case "gcp":
            return MCPServerConfig(id: "gcp", name: "Google Cloud", enabled: true,
                transport: .stdio(command: "npx", args: ["-y", "@modelcontextprotocol/server-gcp"]))
        case "azure":
            return MCPServerConfig(id: "azure", name: "Azure", enabled: true,
                transport: .stdio(command: "npx", args: ["-y", "@modelcontextprotocol/server-azure"]))
        case "terraform":
            return MCPServerConfig(id: "terraform", name: "Terraform", enabled: true,
                transport: .stdio(command: "npx", args: ["-y", "@modelcontextprotocol/server-terraform"]))
        case "datadog":
            return MCPServerConfig(id: "datadog", name: "Datadog", enabled: true,
                transport: .stdio(command: "npx", args: ["-y", "@modelcontextprotocol/server-datadog"]))
        // Data
        case "mongodb":
            return MCPServerConfig(id: "mongodb", name: "MongoDB", enabled: true,
                transport: .stdio(command: "npx", args: ["-y", "@modelcontextprotocol/server-mongodb"]))
        case "redis":
            return MCPServerConfig(id: "redis", name: "Redis", enabled: true,
                transport: .stdio(command: "npx", args: ["-y", "@modelcontextprotocol/server-redis"]))
        case "elasticsearch":
            return MCPServerConfig(id: "elasticsearch", name: "Elasticsearch", enabled: true,
                transport: .stdio(command: "npx", args: ["-y", "@modelcontextprotocol/server-elasticsearch"]))
        case "bigquery":
            return MCPServerConfig(id: "bigquery", name: "BigQuery", enabled: true,
                transport: .stdio(command: "npx", args: ["-y", "@modelcontextprotocol/server-bigquery"]))
        case "snowflake":
            return MCPServerConfig(id: "snowflake", name: "Snowflake", enabled: true,
                transport: .stdio(command: "npx", args: ["-y", "@modelcontextprotocol/server-snowflake"]))
        case "airtable":
            return MCPServerConfig(id: "airtable", name: "Airtable", enabled: true,
                transport: .stdio(command: "npx", args: ["-y", "@modelcontextprotocol/server-airtable"]))
        case "prisma":
            return MCPServerConfig(id: "prisma", name: "Prisma", enabled: true,
                transport: .stdio(command: "npx", args: ["-y", "@modelcontextprotocol/server-prisma"]))
        case "planetscale":
            return MCPServerConfig(id: "planetscale", name: "PlanetScale", enabled: true,
                transport: .stdio(command: "npx", args: ["-y", "@modelcontextprotocol/server-planetscale"]))
        // Productivity
        case "asana":
            return MCPServerConfig(id: "asana", name: "Asana", enabled: true,
                transport: .stdio(command: "npx", args: ["-y", "@modelcontextprotocol/server-asana"]))
        case "monday":
            return MCPServerConfig(id: "monday", name: "Monday.com", enabled: true,
                transport: .stdio(command: "npx", args: ["-y", "@modelcontextprotocol/server-monday"]))
        case "clickup":
            return MCPServerConfig(id: "clickup", name: "ClickUp", enabled: true,
                transport: .stdio(command: "npx", args: ["-y", "@modelcontextprotocol/server-clickup"]))
        case "confluence":
            return MCPServerConfig(id: "confluence", name: "Confluence", enabled: true,
                transport: .stdio(command: "npx", args: ["-y", "@modelcontextprotocol/server-confluence"]))
        case "dropbox":
            return MCPServerConfig(id: "dropbox", name: "Dropbox", enabled: true,
                transport: .stdio(command: "npx", args: ["-y", "@modelcontextprotocol/server-dropbox"]))
        case "box":
            return MCPServerConfig(id: "box", name: "Box", enabled: true,
                transport: .stdio(command: "npx", args: ["-y", "@modelcontextprotocol/server-box"]))
        case "google-calendar":
            return MCPServerConfig(id: "google-calendar", name: "Google Calendar", enabled: true,
                transport: .stdio(command: "npx", args: ["-y", "@modelcontextprotocol/server-google-calendar"]))
        // Comms
        case "discord":
            return MCPServerConfig(id: "discord", name: "Discord", enabled: true,
                transport: .stdio(command: "npx", args: ["-y", "@modelcontextprotocol/server-discord"]))
        case "telegram":
            return MCPServerConfig(id: "telegram", name: "Telegram", enabled: true,
                transport: .stdio(command: "npx", args: ["-y", "@modelcontextprotocol/server-telegram"]))
        case "twilio":
            return MCPServerConfig(id: "twilio", name: "Twilio", enabled: true,
                transport: .stdio(command: "npx", args: ["-y", "@modelcontextprotocol/server-twilio"]))
        case "intercom":
            return MCPServerConfig(id: "intercom", name: "Intercom", enabled: true,
                transport: .stdio(command: "npx", args: ["-y", "@modelcontextprotocol/server-intercom"]))
        case "email":
            return MCPServerConfig(id: "email", name: "Email (IMAP)", enabled: true,
                transport: .stdio(command: "npx", args: ["-y", "@modelcontextprotocol/server-email"]))
        // Commerce & CRM
        case "stripe":
            return MCPServerConfig(id: "stripe", name: "Stripe", enabled: true,
                transport: .stdio(command: "npx", args: ["-y", "@modelcontextprotocol/server-stripe"]))
        case "shopify":
            return MCPServerConfig(id: "shopify", name: "Shopify", enabled: true,
                transport: .stdio(command: "npx", args: ["-y", "@modelcontextprotocol/server-shopify"]))
        case "hubspot":
            return MCPServerConfig(id: "hubspot", name: "HubSpot", enabled: true,
                transport: .stdio(command: "npx", args: ["-y", "@modelcontextprotocol/server-hubspot"]))
        case "zendesk":
            return MCPServerConfig(id: "zendesk", name: "Zendesk", enabled: true,
                transport: .stdio(command: "npx", args: ["-y", "@modelcontextprotocol/server-zendesk"]))
        // Automation
        case "zapier":
            return MCPServerConfig(id: "zapier", name: "Zapier", enabled: true,
                transport: .stdio(command: "npx", args: ["-y", "@modelcontextprotocol/server-zapier"]))
        case "n8n":
            return MCPServerConfig(id: "n8n", name: "n8n", enabled: true,
                transport: .http(url: "http://localhost:5678"))
        // New additions
        case "docker":
            return MCPServerConfig(id: "docker", name: "Docker", enabled: true,
                transport: .stdio(command: "npx", args: ["-y", "@modelcontextprotocol/server-docker"]))
        case "playwright":
            return MCPServerConfig(id: "playwright", name: "Playwright", enabled: true,
                transport: .stdio(command: "npx", args: ["-y", "@anthropic/mcp-server-playwright"]))
        case "neon":
            return MCPServerConfig(id: "neon", name: "Neon", enabled: true,
                transport: .stdio(command: "npx", args: ["-y", "@modelcontextprotocol/server-neon"]))
        case "upstash":
            return MCPServerConfig(id: "upstash", name: "Upstash", enabled: true,
                transport: .stdio(command: "npx", args: ["-y", "@modelcontextprotocol/server-upstash"]))
        case "resend":
            return MCPServerConfig(id: "resend", name: "Resend", enabled: true,
                transport: .stdio(command: "npx", args: ["-y", "@modelcontextprotocol/server-resend"]))
        case "github-actions":
            return MCPServerConfig(id: "github-actions", name: "GitHub Actions", enabled: true,
                transport: .stdio(command: "npx", args: ["-y", "@modelcontextprotocol/server-github-actions"]))
        case "grafana":
            return MCPServerConfig(id: "grafana", name: "Grafana", enabled: true,
                transport: .stdio(command: "npx", args: ["-y", "@modelcontextprotocol/server-grafana"]))
        case "weaviate":
            return MCPServerConfig(id: "weaviate", name: "Weaviate", enabled: true,
                transport: .stdio(command: "npx", args: ["-y", "@modelcontextprotocol/server-weaviate"]))
        default:
            return MCPServerConfig(id: id, name: name, enabled: true,
                transport: .stdio(command: "npx", args: ["-y", "unknown"]))
        }
    }

    static let all: [MCPServerPreset] = [
        MCPServerPreset(id: "memory", name: "Memory", description: "Persistent context and recall across conversations", icon: "brain.head.profile"),
        MCPServerPreset(id: "fetch", name: "Fetch", description: "Fetch and read web URLs", icon: "link"),
        MCPServerPreset(id: "filesystem", name: "Filesystem", description: "Read/write files in a directory", icon: "folder"),
        MCPServerPreset(id: "github", name: "GitHub", description: "Issues, PRs, repos, and code search", icon: "chevron.left.forwardslash.chevron.right"),
        MCPServerPreset(id: "postgres", name: "Postgres", description: "Query and manage PostgreSQL databases", icon: "cylinder.split.1x2"),
        MCPServerPreset(id: "puppeteer", name: "Puppeteer", description: "Browser automation, screenshots, and scraping", icon: "safari"),
        MCPServerPreset(id: "brave-search", name: "Brave Search", description: "Web search powered by Brave", icon: "magnifyingglass"),
        MCPServerPreset(id: "sqlite", name: "SQLite", description: "Query local SQLite databases", icon: "tablecells"),
        MCPServerPreset(id: "slack", name: "Slack", description: "Send and read Slack messages", icon: "bubble.left.and.bubble.right"),
        MCPServerPreset(id: "gdrive", name: "Google Drive", description: "Access and search Google Drive files", icon: "icloud"),
        MCPServerPreset(id: "sentry", name: "Sentry", description: "Error tracking and issue management", icon: "exclamationmark.triangle"),
        MCPServerPreset(id: "claude-code", name: "Claude Code", description: "Anthropic's autonomous coding agent — runs locally via CLI", icon: "terminal"),
        MCPServerPreset(id: "manus", name: "Manus", description: "General-purpose AI agent platform for complex tasks", icon: "hand.raised"),
        MCPServerPreset(id: "linear", name: "Linear", description: "Issue tracking, project management, and roadmaps", icon: "list.bullet.rectangle"),
        MCPServerPreset(id: "notion", name: "Notion", description: "Docs, databases, wikis, and knowledge bases", icon: "doc.text"),
        MCPServerPreset(id: "jira", name: "Jira", description: "Atlassian issue tracking and agile boards", icon: "ticket"),
        MCPServerPreset(id: "figma", name: "Figma", description: "Design tokens, components, and layout inspection", icon: "paintpalette"),
        MCPServerPreset(id: "vercel", name: "Vercel", description: "Deploy, manage, and monitor Vercel projects", icon: "arrow.up.right.circle"),
        MCPServerPreset(id: "supabase", name: "Supabase", description: "Postgres database, auth, and edge functions", icon: "bolt.fill"),
        MCPServerPreset(id: "cloudflare", name: "Cloudflare", description: "Workers, DNS, KV storage, and R2", icon: "cloud.fill"),
        MCPServerPreset(id: "todoist", name: "Todoist", description: "Task management and to-do lists", icon: "checklist"),
        MCPServerPreset(id: "raycast", name: "Raycast", description: "Local macOS automation and shortcuts", icon: "rays"),
        MCPServerPreset(id: "turso", name: "Turso", description: "Edge-distributed SQLite database", icon: "arrow.triangle.branch"),
        // Code & DevOps
        MCPServerPreset(id: "semgrep", name: "Semgrep", description: "Static analysis and code security scanning", icon: "shield.lefthalf.filled"),
        MCPServerPreset(id: "sourcegraph", name: "Sourcegraph", description: "Universal code search across repositories", icon: "magnifyingglass.circle"),
        MCPServerPreset(id: "gitlab", name: "GitLab", description: "GitLab issues, merge requests, and pipelines", icon: "chevron.left.forwardslash.chevron.right"),
        MCPServerPreset(id: "buildkite", name: "Buildkite", description: "CI/CD pipeline management and build status", icon: "hammer.fill"),
        MCPServerPreset(id: "circleci", name: "CircleCI", description: "Continuous integration pipeline control", icon: "arrow.triangle.2.circlepath"),
        MCPServerPreset(id: "aws", name: "AWS", description: "S3, Lambda, EC2, and other AWS services", icon: "cloud"),
        MCPServerPreset(id: "gcp", name: "Google Cloud", description: "GCS, Cloud Run, BigQuery, and GCP services", icon: "cloud.fill"),
        MCPServerPreset(id: "azure", name: "Azure", description: "Azure Blob, Functions, and cloud services", icon: "cloud.bolt.fill"),
        MCPServerPreset(id: "terraform", name: "Terraform", description: "Infrastructure as Code management", icon: "square.stack.3d.up"),
        MCPServerPreset(id: "datadog", name: "Datadog", description: "Monitoring, metrics, and alerting", icon: "chart.bar.fill"),
        // Data
        MCPServerPreset(id: "mongodb", name: "MongoDB", description: "Document database queries and management", icon: "leaf.fill"),
        MCPServerPreset(id: "redis", name: "Redis", description: "In-memory data store and cache", icon: "bolt.horizontal.fill"),
        MCPServerPreset(id: "elasticsearch", name: "Elasticsearch", description: "Full-text search and analytics engine", icon: "magnifyingglass"),
        MCPServerPreset(id: "bigquery", name: "BigQuery", description: "Google's serverless data warehouse", icon: "chart.pie.fill"),
        MCPServerPreset(id: "snowflake", name: "Snowflake", description: "Cloud data warehouse platform", icon: "snowflake"),
        MCPServerPreset(id: "airtable", name: "Airtable", description: "Spreadsheet-database hybrid platform", icon: "tablecells.fill"),
        MCPServerPreset(id: "prisma", name: "Prisma", description: "Next-gen ORM for Node.js and TypeScript", icon: "diamond.fill"),
        MCPServerPreset(id: "planetscale", name: "PlanetScale", description: "Serverless MySQL-compatible database", icon: "globe.americas.fill"),
        // Productivity
        MCPServerPreset(id: "asana", name: "Asana", description: "Project and task management", icon: "list.bullet.clipboard.fill"),
        MCPServerPreset(id: "monday", name: "Monday.com", description: "Work OS for team collaboration", icon: "calendar.badge.clock"),
        MCPServerPreset(id: "clickup", name: "ClickUp", description: "All-in-one project management platform", icon: "checkmark.circle.fill"),
        MCPServerPreset(id: "confluence", name: "Confluence", description: "Atlassian team wiki and documentation", icon: "book.fill"),
        MCPServerPreset(id: "dropbox", name: "Dropbox", description: "Cloud file storage and sync", icon: "arrow.down.doc.fill"),
        MCPServerPreset(id: "box", name: "Box", description: "Enterprise content management and sharing", icon: "shippingbox.fill"),
        MCPServerPreset(id: "google-calendar", name: "Google Calendar", description: "Calendar events and scheduling", icon: "calendar"),
        // Comms
        MCPServerPreset(id: "discord", name: "Discord", description: "Send and read Discord messages and channels", icon: "message.fill"),
        MCPServerPreset(id: "telegram", name: "Telegram", description: "Telegram messaging and bot interactions", icon: "paperplane.fill"),
        MCPServerPreset(id: "twilio", name: "Twilio", description: "SMS, voice, and communication APIs", icon: "phone.fill"),
        MCPServerPreset(id: "intercom", name: "Intercom", description: "Customer messaging and support platform", icon: "bubble.left.fill"),
        MCPServerPreset(id: "email", name: "Email (IMAP)", description: "Read and send emails via IMAP/SMTP", icon: "envelope.fill"),
        // Commerce & CRM
        MCPServerPreset(id: "stripe", name: "Stripe", description: "Payment processing and billing", icon: "creditcard.fill"),
        MCPServerPreset(id: "shopify", name: "Shopify", description: "E-commerce store management", icon: "cart.fill"),
        MCPServerPreset(id: "hubspot", name: "HubSpot", description: "CRM, marketing, and sales automation", icon: "person.2.fill"),
        MCPServerPreset(id: "zendesk", name: "Zendesk", description: "Customer support and ticketing", icon: "questionmark.circle.fill"),
        // Automation
        MCPServerPreset(id: "zapier", name: "Zapier", description: "Connect and automate 5000+ apps", icon: "bolt.fill"),
        MCPServerPreset(id: "n8n", name: "n8n", description: "Self-hosted workflow automation", icon: "point.3.connected.trianglepath.dotted"),
        // Infrastructure & Testing
        MCPServerPreset(id: "docker", name: "Docker", description: "Container management, images, and compose", icon: "shippingbox"),
        MCPServerPreset(id: "playwright", name: "Playwright", description: "Browser automation and E2E testing", icon: "theatermasks"),
        MCPServerPreset(id: "neon", name: "Neon", description: "Serverless Postgres with branching", icon: "bolt.horizontal"),
        MCPServerPreset(id: "upstash", name: "Upstash", description: "Serverless Redis and Kafka", icon: "arrow.up.message"),
        MCPServerPreset(id: "resend", name: "Resend", description: "Modern email sending API", icon: "envelope.badge"),
        MCPServerPreset(id: "github-actions", name: "GitHub Actions", description: "CI/CD workflow management on GitHub", icon: "gearshape.2"),
        MCPServerPreset(id: "grafana", name: "Grafana", description: "Observability dashboards and alerting", icon: "chart.xyaxis.line"),
        MCPServerPreset(id: "weaviate", name: "Weaviate", description: "Vector database for AI-native search", icon: "cube.transparent")
    ]
}

struct MCPServerConfig: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var enabled: Bool
    var transport: Transport
}

extension MCPServerConfig {
    enum Transport: Codable, Equatable {
        case stdio(command: String, args: [String])
        case http(url: String)
        case websocket(url: String)

        enum CodingKeys: String, CodingKey {
            case type
            case command
            case args
            case url
        }

        var displayName: String {
            switch self {
            case .stdio: return "stdio"
            case .http: return "HTTP"
            case .websocket: return "WebSocket"
            }
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let type = try c.decode(String.self, forKey: .type)
            switch type {
            case "stdio":
                let command = try c.decode(String.self, forKey: .command)
                let args = try c.decodeIfPresent([String].self, forKey: .args) ?? []
                self = .stdio(command: command, args: args)
            case "http":
                let url = try c.decode(String.self, forKey: .url)
                self = .http(url: url)
            case "websocket":
                let url = try c.decode(String.self, forKey: .url)
                self = .websocket(url: url)
            default:
                throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "Unknown transport: \(type)")
            }
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .stdio(let command, let args):
                try c.encode("stdio", forKey: .type)
                try c.encode(command, forKey: .command)
                try c.encode(args, forKey: .args)
            case .http(let url):
                try c.encode("http", forKey: .type)
                try c.encode(url, forKey: .url)
            case .websocket(let url):
                try c.encode("websocket", forKey: .type)
                try c.encode(url, forKey: .url)
            }
        }
    }
}

struct MCPServersFile: Codable {
    var servers: [MCPServerConfig]
}

enum MCPServerConfigStorage {
    private static var configDirectory: String {
        (NSHomeDirectory() as NSString)
            .appendingPathComponent(".grump")
    }

    private static var configPath: String {
        (configDirectory as NSString).appendingPathComponent("mcp-servers.json")
    }

    static func load() -> [MCPServerConfig] {
        let path = configPath
        guard FileManager.default.fileExists(atPath: path),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let decoded = try? JSONDecoder().decode(MCPServersFile.self, from: data) else {
            return []
        }
        return decoded.servers
    }

    static func save(_ servers: [MCPServerConfig]) {
        try? FileManager.default.createDirectory(atPath: configDirectory, withIntermediateDirectories: true)
        let file = MCPServersFile(servers: servers)
        let data = (try? JSONEncoder().encode(file)) ?? Data()
        try? data.write(to: URL(fileURLWithPath: configPath))
    }
}
