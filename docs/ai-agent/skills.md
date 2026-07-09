# Skills

Skills teach the AI agent specific workflows and domain knowledge via SKILL.md files. Each skill is a structured markdown file that gets injected into the system prompt when enabled.

## How Skills Work

When enabled, a skill's content is injected into the system prompt, giving the agent specialized knowledge for tasks like SwiftUI development, code review, or Kubernetes deployment. Skills include a persona, core expertise, patterns, best practices, anti-patterns, and verification criteria.

## Skill Locations

| Scope | Path | Priority |
|---|---|---|
| **Built-in** | `Sources/GRump/Resources/Skills/` | Bundled with app |
| **Global** | `~/.grump/skills/` | Available in all projects |
| **Project** | `.grump/skills/` | Project-specific |

## 60+ Bundled Skills

### Swift/Apple
- **Swift & iOS Development** — SwiftUI, Apple frameworks, Xcode, HIG
- **Async/Await Conversion** — Combine and callback migration to modern Swift concurrency
- **SwiftUI Migration** — UIKit-to-SwiftUI migration patterns
- **SwiftData Migration** — Core Data to SwiftData migration
- **Core ML Conversion** — PyTorch/TensorFlow to Core ML format
- **MLX Training** — Fine-tuning models on Apple Silicon
- **App Store Prep** — Review guidelines, metadata, privacy manifests
- **Privacy Manifest Audit** — PrivacyInfo.xcprivacy compliance

### Web & Frontend
- **React & Next.js** — Server Components, App Router, TypeScript
- **Full-Stack Development** — End-to-end web application architecture
- **Flutter & Dart** — Cross-platform mobile and desktop development

### AI & Agents
- **AI Agent Design** — Autonomous agents with tool use, memory, and planning loops
- **MCP Server Building** — Model Context Protocol servers for AI integration
- **RAG Pipeline Design** — Retrieval-augmented generation with embeddings and vector search
- **Fine-Tuning & Eval** — LLM fine-tuning, dataset curation, and evaluation
- **LLM Observability** — Cost tracking, latency analysis, and quality monitoring
- **Prompt Engineering** — System prompts, few-shot patterns, tool descriptions

### Security & Offensive
- **Security Audit** — OWASP coverage, vulnerability scanning, remediation
- **Penetration Testing** — Structured pentesting with proof-of-concept exploitation
- **Exploit Analysis** — CVE assessment, attack chains, mitigation strategies
- **Network Forensics** — Packet analysis, incident investigation, digital forensics
- **Reverse Engineering** — Binary analysis, protocol deconstruction, API exploration

### Infrastructure & DevOps
- **DevOps** — CI/CD pipelines, Docker, deployment infrastructure
- **Kubernetes** — Deployments, services, operational patterns
- **Terraform IaC** — Infrastructure as code, modules, state management
- **AWS Serverless** — Lambda, API Gateway, DynamoDB, CDK
- **Docker & Container Deployment** — Containerization and orchestration
- **CI/CD Pipeline Design** — GitHub Actions, matrix builds, artifact management
- **Edge Computing** — CDN workers, edge functions, distributed caching
- **Observability** — Structured logging, distributed tracing, metrics, alerting
- **Incident Response** — Triage, communication, resolution, post-mortems
- **Platform Engineering** — Internal developer platforms, golden paths, DevEx
- **Cloud Cost Optimization** — Right-sizing, reserved capacity, FinOps

### Architecture & Design
- **System Design** — Distributed systems, scalability, reliability patterns
- **API Design** — REST/GraphQL conventions, versioning, error handling
- **Database Design** — Schema modeling, migrations, query optimization
- **GraphQL Design** — Schema design, resolvers, subscriptions, security
- **Monorepo Management** — Multi-package repos, build systems, versioning

### Development Practices
- **Code Review** — Systematic code review methodology
- **PR Code Review** — Pull request review with structured feedback
- **Testing** — Unit, integration, and E2E test design
- **Test Generation** — Auto-generating test suites from code
- **Debugging** — Systematic root cause analysis
- **Refactoring** — Safe code transformation patterns
- **Performance** — Profiling, benchmarking, optimization
- **Documentation** — Technical docs, API references, guides
- **Technical Writing** — RFCs, ADRs, developer guides
- **Code Migration** — Framework and language migration strategies

### Business & Strategy
- **Competitive Analysis** — Market positioning and differentiation
- **Competitive Intelligence** — Systematic competitor research and monitoring
- **Product Strategy** — Vision, roadmaps, and prioritization
- **Pricing & Monetization** — Pricing models, tiers, monetization strategy
- **Growth Analytics** — Funnels, experimentation, retention analysis
- **Pitch Deck Review** — Fundraising deck evaluation
- **Technical Due Diligence** — Codebase and team assessment for M&A

### General
- **Research** — Systematic information gathering and synthesis
- **Writing** — Clear, effective technical and business writing
- **Planning** — Project scoping, breakdown, and risk assessment
- **Specification** — Requirements gathering and spec writing
- **Argumentation** — Structured reasoning and argument construction
- **Rapid Prototyping** — MVP scaffolding and validation
- **Regex Expert** — Pattern design across engines
- **Data Science** — ML pipelines, statistics, visualization

### Languages & Frameworks
- **Rust Systems** — Ownership, concurrency, performance
- **Unity Game Dev** — C# scripting, engine best practices

### Meta-Skills (Combos)
- **Architect Mode** — System design + API design + database + security
- **Ship It Mode** — Rapid prototyping + full-stack + testing + DevOps
- **War Room Mode** — Incident response + debugging + performance + observability
- **Deep Dive Mode** — Research + documentation + code review + testing
- **Teacher Mode** — Research + writing + documentation + examples
- **Red Team Mode** — Security audit + pentesting + exploits + reverse engineering

## SKILL.md Format

Every skill follows the elite template:

```markdown
---
name: Skill Name
description: One-line description of what this skill enables.
tags: [tag1, tag2, tag3]
---

You are an expert [role] who [specializes in what].

## Core Expertise
- Bullet list of domain knowledge areas

## Patterns & Workflow
1. **Step** — Description of each step in the workflow

## Best Practices
- Actionable guidelines for high-quality work

## Anti-Patterns
- Common mistakes to avoid with explanation of why

## Verification
- Checkable criteria to confirm work quality

## Examples
- **Scenario**: Concrete example showing the skill in action
```

## ClawHub

ClawHub is a shared skill registry between G-Rump and OpenClaw. Skills installed via ClawHub are stored in `~/.grump/skills/` and accessible from both systems.

Browse and manage hub skills in **Settings → Workspace → Skills → ClawHub**.

## Managing Skills

- **Settings → Workspace → Skills** — Toggle skills on/off, add/edit/remove
- Skills can be enabled/disabled per-conversation via workflow presets
- The agent sees only enabled skills in its system prompt
- Meta-skills (combos) activate multiple skills simultaneously for complex workflows
