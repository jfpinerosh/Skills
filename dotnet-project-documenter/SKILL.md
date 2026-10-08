---
name: dotnet-project-documenter
description: >
  Generates complete technical documentation for .NET solutions: a DOCUMENTATION.md file covering architecture,
  projects, components, and configuration with UML diagrams in Mermaid, plus an ONBOARDING.md guide for new developers.
  Use when the user asks to "document this .NET project", "generate documentation for my solution", "create architecture
  diagrams", "create an onboarding guide", "document my C# solution", "generate UML diagrams from code",
  "write docs for this API", or references a .sln/.csproj project and asks for documentation, diagrams, or onboarding material.
---

# .NET Project Documenter

Generates two deliverables for a .NET solution:

1. **`docs/DOCUMENTATION.md`** — full technical documentation with Mermaid UML diagrams
2. **`docs/ONBOARDING.md`** — onboarding guide for developers joining the project

Both files are written in a single consistent language chosen by the user.

## Workflow

### Step 1: Gather Inputs

Ask the user (defaults in parentheses):

1. **Documentation language** — `English` (default) or `Spanish`. All prose, headings, and diagram labels use this language consistently.
2. **Output folder** — `docs/` (default) relative to the solution root, unless the user specifies another path.
3. **Solution path** — the folder containing the `.sln` file (defaults to the current working directory).

If the solution path is ambiguous (multiple `.sln` files), list them and ask which one to document.

### Step 2: Analyze the Solution

Perform a thorough analysis before writing anything. Collect:

**Solution level**
- Locate and read the `.sln` file: all project entries and solution folders.
- For each `.csproj` / `.fsproj` / `.vbproj`: `TargetFramework`, `OutputType`, project type (Web API, MVC, Worker, Console, Class Library, Test, Blazor, MAUI, etc.), inter-project `ProjectReference`s, and `PackageReference`s (NuGet dependencies).
- External integrations: connection strings, `appsettings*.json` sections, `HttpClient`/`IHttpClientFactory` registrations, message brokers, cloud SDKs.

**Architecture level**
- Infer the architecture style (Clean Architecture, N-Layer, DDD, Vertical Slice, Minimal API monolith, etc.) from project names, folder structure, and dependency direction.
- Entry points: `Program.cs` / `Startup.cs` — middleware pipeline, DI registrations, hosted services.
- Identify layers: presentation, application/business, domain, data/infrastructure.

**Project level** (for every project)
- Folder/namespace organization.
- Key types: controllers/endpoints, services, repositories, entities, DTOs, interfaces, `DbContext`s, background jobs.
- Applied design patterns (repository, CQRS, unit of work, mediator, factory, etc.).
- Main business flows for sequence diagrams (CRUD operations, authentication, integrations, background processing). Prefer reading actual controller/service code over guessing.

**Operations level**
- Configuration: required `appsettings` keys, environment variables, user secrets.
- Build/run commands: `dotnet` CLI, launch profiles (`launchSettings.json`), Docker files.
- Testing: test frameworks (xUnit/NUnit/MSTest), test project layout, how to run tests.
- Deployment: Dockerfiles, CI/CD pipelines (`.github/workflows`, `azure-pipelines.yml`, etc.), publish profiles.

### Step 3: Generate `docs/DOCUMENTATION.md`

Read **`references/documentation-template.md`** and follow its structure exactly:

1. Header: solution name, purpose, tech stack, table of contents
2. Overall architecture: narrative + solution-level Mermaid flowchart (projects, layers, data flow, external dependencies)
3. Per-project sections: definition table (name, type, purpose, technologies, dependencies) + component `classDiagram` + `sequenceDiagram`s for main flows
4. Configuration, installation, execution, testing, deployment sections

Rules:
- Every Mermaid block MUST follow **`references/mermaid-guide.md`** syntax rules and be validated before writing.
- Diagrams must be clear, not overloaded — split large diagrams into smaller focused ones.
- Do not invent classes, methods, or flows that do not exist in the code. When uncertain, re-read the source.
- Link TOC anchors to actual headings.

### Step 4: Generate `docs/ONBOARDING.md`

Read **`references/onboarding-template.md`** and follow its structure. The onboarding guide is task-oriented for a new developer:

- Prerequisites (SDK version, tools, IDE)
- Getting the code, building, and running in < 10 minutes
- Key systems and how they connect (reuse a simplified version of the architecture diagram)
- Common tasks with walkthroughs (add an endpoint, run tests, apply a migration, etc.)
- Project structure map and where to find things
- Troubleshooting, next steps, and who to ask

### Step 5: Verify and Report

Before finishing:
- Validate every Mermaid block against the syntax rules in `references/mermaid-guide.md` (balanced quotes, valid node IDs, correct arrow tokens, no reserved keywords as identifiers).
- Verify all TOC links resolve to headings.
- Confirm no placeholder text remains (no `[TODO]`, `[AQUÍ...]`, or empty sections) — if information is genuinely missing from the codebase, state it explicitly (e.g., "No deployment pipeline found in repository").
- Print a short summary: files created, projects documented, diagram count, and any gaps found.

## Writing Principles

1. **Write for the reader** — a developer new to the project.
2. **Start with the most useful information** — don't bury the lede.
3. **Show, don't tell** — real commands, real class names, real config keys.
4. **Link, don't duplicate** — ONBOARDING.md links to DOCUMENTATION.md sections instead of repeating them.
5. **Keep it accurate** — every statement traceable to the codebase; outdated or invented documentation is worse than none.
