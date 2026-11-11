# Audit checklist

Use this during Phase 1, after running the scanner. Each item says what to look for and why it matters. Rate findings High / Medium / Low.

## Contents
1. Structure and tooling
2. Test quality smells
3. Reliability (flaky/slow)
4. Coverage gaps and risk
5. Integration/E2E setup health
6. Severity guide

## 1. Structure and tooling

- Are unit, integration and e2e tests in separate projects (or at least separate folders with traits)? Mixed suites make the fast feedback loop slow. (Medium)
- Does the test project target the same framework as the app (`net10.0`)? (Low)
- xUnit v2 (`xunit`) or v3 (`xunit.v3`)? Do not mix. Note it; do not migrate unless asked. v3 test projects are executables (`OutputType Exe`), and v3 offers `TestContext.Current.CancellationToken`.
- Are `Microsoft.NET.Test.Sdk`, `xunit.runner.visualstudio` and a coverage collector (`coverlet.collector`) present? Missing coverage tooling means no objective baseline. (Medium)
- Package versions: pinned centrally (`Directory.Packages.props`) or scattered? (Low)
- Is there a CI step running `dotnet test`? Look in `.github/workflows`, `azure-pipelines.yml`, `.gitlab-ci.yml`. Tests that never run in CI rot. (High if absent)
- Licensing: FluentAssertions 8+ and some mocking/mapping libraries have commercial terms. Flag, do not remove. (Low/Medium)

## 2. Test quality smells

| Smell | How to spot it | Why it is a problem |
|---|---|---|
| No assertion | Test method with no `Assert.`/`Should`/`Received`/`Throws` | Passes whenever code does not throw; false confidence (High) |
| Tautology | `Assert.True(true)`, asserting a mock returns what it was set up to return | Tests the mock, not the code (High) |
| Assertion roulette | 5+ unrelated assertions in one test | Failure does not say what broke (Medium) |
| Over-mocking | More setup lines than assertions; mocks of types you own that have no I/O; verifying every call | Tests break on refactor, protect nothing (Medium) |
| Logic in tests | `if`, `for`, `try/catch` inside the test body | The test can be wrong itself (Medium) |
| Test depends on test | Static mutable state, shared DB rows, `[TestCaseOrderer]` hacks | Random failures in parallel runs (High) |
| Skipped/commented-out tests | `Skip =`, `// [Fact]` | Hidden debt (Medium) |
| Poor naming | `Test1`, `ShouldWork`, names not stating scenario/expectation | Failures are unreadable (Low) |
| Testing private/internal details | Reflection, `InternalsVisibleTo` used to reach private logic | Brittle (Medium) |
| Copy-paste duplicates | Same body repeated with different literals | Should be `[Theory]` (Low) |
| Giant arrange | 30+ lines to build an object | Needs a builder or a simpler design (Low) |

## 3. Reliability (flaky/slow)

- `Thread.Sleep`, `Task.Delay` used to "wait for" something. Replace with polling with timeout or deterministic signals. (High)
- `DateTime.Now/UtcNow`, `Random`, `Guid.NewGuid()` inside logic under test. Introduce `TimeProvider` / seed. (Medium)
- Real network calls (`HttpClient` to the internet), real SMTP, real cloud services in tests. (High)
- `async void` tests, `.Result` / `.Wait()` / `.GetAwaiter().GetResult()`. (Medium)
- Shared database without cleanup between tests; reliance on identity values. (High)
- EF Core `UseInMemoryDatabase` in "integration" tests. It does not enforce relational constraints, transactions or SQL translation, so passing tests may fail in production. (Medium)
- Slow tests: unit tests that start a host or container. Unit tests should be milliseconds.
- Parallelism: do tests in one collection share a container/DB? Is each collection isolated?

## 4. Coverage gaps and risk

Rank untested code by risk, not by size:

1. Business/domain rules, calculations, state machines, authorization decisions.
2. Application services / handlers / endpoints (success, validation failure, not found, conflict, unauthorized).
3. Data access: non-trivial queries, filters, projections, concurrency tokens, migrations apply cleanly.
4. Cross-cutting: exception handling middleware (ProblemDetails), validation filters, auth policies, rate limiting, serialization.
5. Infrastructure glue (DI registration, config binding). One smoke test is enough.

Name-based gap detection (class `Foo` has `FooTests`) is only a hint. Confirm by reading, since a class may be covered indirectly through an e2e test.

Each public endpoint should have, at minimum: happy path, invalid input, not found/conflict (where relevant), and an auth check (anonymous 401 / forbidden 403) if secured.

## 5. Integration/E2E setup health

- Is there a `WebApplicationFactory<Program>` and is `Program` accessible (`public partial class Program {}` for top-level programs)?
- Does the factory replace external dependencies and the database connection via `ConfigureTestServices`, rather than editing production code?
- How is authentication handled in tests? A test auth handler beats generating real tokens for most cases.
- Database strategy matches the detected provider (see `integration-tests.md`). Is schema created by migrations (`Database.MigrateAsync()`) or `EnsureCreated`? Migrations are preferable since they test what ships.
- Is data reset between tests (Respawn, transaction rollback, or per-test unique data)?
- Are containers shared per collection/assembly (fast) or started per test (slow)?

## 6. Severity guide

- **High:** tests that pass when code is broken, tests that fail randomly, no CI execution, real external side effects.
- **Medium:** meaningful untested risk, slow feedback loop, brittle over-mocked tests.
- **Low:** naming, duplication, style, tooling hygiene.

Always cite evidence (`path:line`) so the user can verify. Also list what is **good**; it guides what to preserve in Phase 2.
