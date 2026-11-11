---
name: dotnet-backend-testing
description: Audit and write backend tests for .NET 10 / C# projects using xUnit, NSubstitute and Shouldly - unit tests, integration tests and end-to-end (API) tests. First inspects the solution, validates the existing tests (coverage gaps, flaky or weak tests, test smells, wrong project layout) and reports findings; after the user approves, generates the missing tests following best practices. Make sure to use this skill whenever the user mentions unit tests, integration tests, e2e/end-to-end tests, xUnit, test coverage, WebApplicationFactory, Testcontainers, "review my tests", "add tests to this API", "improve my test suite" or "validate the tests" for a .NET, ASP.NET Core, Minimal API, Web API or Azure Functions backend, even if they do not say "skill" or name every test type. Backend only - do not use for frontend, Angular, Blazor UI or browser/Playwright testing.
---

# .NET Backend Testing (xUnit)

Audit a .NET 10 backend's test suite, then create unit, integration and end-to-end tests that follow current best practices. Backend only: never create UI/browser tests.

## Why two phases

Test suites are long-lived and shared. Writing dozens of files before the user knows what you found is expensive to review and easy to get wrong. So always work in two phases and **stop after Phase 1** to let the user choose the scope.

- **Phase 1 - Audit (read-only).** No files are created or modified in the user's project.
- **Phase 2 - Generate.** Only after the user approves the report, and only for the scope they pick.

---

## Phase 1 - Audit

### Step 1: Run the scanner

Locate the solution root (folder with `.sln`/`.slnx` or the `.csproj`), then run:

```bash
python /path/to/this/skill/scripts/audit_dotnet_tests.py <solution-root> --format markdown
```

The script is a fast static scan. It reports: projects and target frameworks, test projects and their packages (xUnit v2 vs v3, NSubstitute/Moq, Shouldly/FluentAssertions, Testcontainers, coverlet), detected database provider(s), production classes with no matching test file, test counts per category, and test smells. Treat its output as evidence, not a verdict: read the flagged files before concluding anything.

If the scanner cannot run (no Python, no filesystem access, user pasted code only), do the same analysis manually using `references/audit-checklist.md`.

### Step 2: Validate what exists

Read `references/audit-checklist.md` and apply it. Go beyond what the script can see:

- Open a sample of the largest and the most critical tests (auth, payments, domain rules) and judge quality: do they assert behavior or just that "no exception was thrown"?
- Check that the existing tests actually run. If the .NET SDK is available, run `dotnet test --no-restore` (and with `--collect:"XPlat Code Coverage"` if coverlet is present) and report pass/fail/skipped and the coverage number. If it is not available, say so; never invent a coverage number.
- Check the project layout against the target one in `references/project-structure.md`.
- Note the conventions the project already follows (naming, assertion library, mocking library). **Match the existing conventions** when they are reasonable; propose migration only when the existing choice is a real problem (for example, unmaintained or license-restricted libraries).

### Step 3: Report, then stop

Produce the report in this exact structure so users can scan it:

```markdown
# Test Audit - <SolutionName>

## Snapshot
- Target framework / test framework (xUnit v2 or v3) / libraries
- Database provider(s) detected and recommended strategy for integration tests
- Tests: N unit, N integration, N e2e, N skipped | last run: pass/fail (or "not run")
- Coverage: X% line (or "not measured")

## What is good
(2-4 bullets; be specific, this builds trust and tells Phase 2 what to preserve)

## Findings
| # | Severity | Area | Finding | Evidence (file:line) | Suggested fix |
(Severity: High = tests give false confidence or are broken; Medium = important gap; Low = style/maintainability)

## Coverage gaps (prioritized)
Ordered by risk: domain rules and business logic > endpoints/handlers > data access > infrastructure glue.
For each: class/endpoint, why it matters, which test type fits (unit / integration / e2e).

## Proposed plan
Numbered list of work packages, each small enough to review on its own,
with the number of tests expected.
```

End with a single question: which work packages should be generated (or "all")? Do not start Phase 2 until the user answers.

---

## Phase 2 - Generate

### Step 1: Pick the approach per layer

| Layer | Test type | What is real | What is faked |
|---|---|---|---|
| Domain, application services, validators, mappers | **Unit** | the class under test | every collaborator (NSubstitute), time (`TimeProvider`) |
| Repositories, EF Core queries/migrations, HTTP pipeline pieces (filters, middleware, auth, serialization) | **Integration** | real DB, real DI container, real HTTP pipeline | external third-party services |
| Complete user-visible flows across several endpoints | **End-to-end (API level)** | whole app via `WebApplicationFactory`, real DB | only external systems outside your control (payment gateways, email) |

Read the matching reference **before writing that kind of test**:

- `references/unit-tests.md`
- `references/integration-tests.md` (includes the database decision table)
- `references/e2e-tests.md`
- `references/project-structure.md` (project names, packages, csproj templates)

### Step 2: Write tests in small batches

1. Create or update test projects only as needed (`tests/<Solution>.UnitTests`, `.IntegrationTests`, `.E2ETests`).
2. Generate one work package at a time. After each package, run `dotnet build` and `dotnet test --filter` for the new tests if the SDK is available.
3. If a test fails, decide whether the **test** or the **production code** is wrong. Never weaken an assertion just to make it green. If you find a genuine bug, report it to the user instead of silently fixing production code, unless they asked for fixes.
4. Do not modify production code except for the minimum needed to make it testable (for example `public partial class Program { }` for `WebApplicationFactory`, or registering `TimeProvider`). Mention every such change explicitly.

### Step 3: Close the loop

Finish with a short summary: tests added per type, how to run each category, coverage before/after if measurable, and anything left in the plan. Re-running the scanner at the end and comparing with the Phase 1 snapshot is a good way to show progress.

---

## Rules that apply to every test you write

These exist because each one prevents a specific, common failure of test suites (flaky, slow, or meaningless tests).

- **One behavior per test, Arrange-Act-Assert**, with blank lines separating the sections. Tests that check many things fail for unclear reasons.
- **Name:** `Method_Scenario_ExpectedResult` (for example `CreateOrder_WhenStockIsInsufficient_ReturnsConflict`). The name is the failure message people read first.
- **Deterministic:** no `DateTime.Now/UtcNow`, `Guid.NewGuid()` in assertions, `Random`, `Thread.Sleep`, or real network. Inject `TimeProvider` (use `FakeTimeProvider`) and await conditions instead of sleeping.
- **Independent:** tests never depend on execution order or on data left by another test. Each test creates the data it needs.
- **Assert outcomes, not implementation.** Verify returned values, persisted state and HTTP responses. Use `Received()` only for side effects that *are* the behavior (an email is sent, a message is published), not for every internal call.
- **Do not test the framework or trivial code** (auto-properties, EF Core itself, DTO constructors). Coverage percentage is a signal, not the goal.
- **Use `[Theory]` for the same behavior with different data;** use separate `[Fact]`s when the behaviors differ.
- **Pass the cancellation token** from the test context (xUnit v3: `TestContext.Current.CancellationToken`) to async calls.
- **Categorize with traits** so each type can run alone: `[Trait("Category", "Unit")]`, `"Integration"`, `"E2E"`. Never rely on project names alone for filtering.
- **Libraries:** xUnit + NSubstitute + Shouldly (all free for commercial use). Do not introduce FluentAssertions 8+ (commercial license) or Moq into projects that do not already use them; if they already do, follow the project's convention and mention the license consideration in the audit.
- **No `[Fact(Skip = ...)]` without a linked reason** and no commented-out tests. Either fix or delete.

## When the project is unusual

- **Azure Functions (isolated worker):** there is no `WebApplicationFactory`. Keep functions thin, unit-test the services they call (and the function classes with faked dependencies), and for integration/e2e start the app with Azure Functions Core Tools (`func start`) from a fixture and call the HTTP triggers with a real `HttpClient`, as described in `references/e2e-tests.md`.
- **No tests at all:** audit still runs; the plan should start with the highest-risk layer plus a thin e2e "smoke" test that proves the app boots and one happy path works.
- **Legacy code that is hard to unit test** (static calls, `new` inside methods): prefer integration tests around it first; propose refactors in the report rather than doing them.
- **Docker unavailable:** follow the fallback in the database decision table instead of skipping integration tests.
