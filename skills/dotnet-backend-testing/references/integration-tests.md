# Integration tests

## Contents
- Scope
- Choosing the database strategy
- Shared fixture with Testcontainers
- WebApplicationFactory
- Resetting data between tests
- Authentication in tests
- Faking external services
- What to cover
- Pitfalls

## Scope

Integration tests prove that **your code works with the real pieces it depends on**: the database (queries, constraints, migrations, transactions), the DI container, and the ASP.NET Core pipeline (routing, model binding, validation, filters, middleware, serialization, auth policies). External third-party systems are still faked.

## Choosing the database strategy

Detect the provider from the packages and connection strings (the scanner reports it), then choose:

| Detected | Preferred | Fallback if Docker is unavailable |
|---|---|---|
| SQL Server (`Microsoft.EntityFrameworkCore.SqlServer`, `Microsoft.Data.SqlClient`) | `Testcontainers.MsSql` | Ask the user for a dedicated test instance/LocalDB; do not silently swap to SQLite (SQL dialect and behavior differ) |
| PostgreSQL (`Npgsql.*`) | `Testcontainers.PostgreSql` | Dedicated test database on an existing server |
| MySQL/MariaDB (`Pomelo.*`, `MySql.*`) | `Testcontainers.MySql` | Dedicated test database |
| MongoDB | `Testcontainers.MongoDb` | Dedicated test database |
| Cosmos DB | Cosmos DB emulator container | Skip DB-bound integration tests and say so |
| SQLite (production uses SQLite) | Real SQLite file or `:memory:` with an open shared connection | n/a |
| Dapper only | Same as the underlying engine above | |
| None detected | No database fixture; integration tests cover the pipeline only | |

Why not EF Core `UseInMemoryDatabase`: it is not relational. It ignores foreign keys, unique indexes, transactions and real SQL translation, so tests can pass while production fails. Use it only for throwaway demos and say so in the audit if you find it in "integration" tests. SQLite in-memory is a better fake than the InMemory provider but still differs from SQL Server/PostgreSQL; use it only when the project itself targets SQLite.

Write the choice and the reason in the audit report (`Snapshot` section) so the user can veto it before Phase 2.

## Shared fixture with Testcontainers

Starting a container per test is far too slow. Start one per test collection (or per assembly) and isolate tests by resetting data.

```csharp
using Testcontainers.PostgreSql;

public sealed class ApiFactory : WebApplicationFactory<Program>, IAsyncLifetime
{
    private readonly PostgreSqlContainer _db = new PostgreSqlBuilder()
        .WithImage("postgres:17-alpine")
        .Build();

    public async ValueTask InitializeAsync()           // xUnit v3 signature (v2: Task InitializeAsync())
    {
        await _db.StartAsync();
        using var scope = Services.CreateScope();      // forces host creation with the container's connection string
        await scope.ServiceProvider.GetRequiredService<AppDbContext>().Database.MigrateAsync();
    }

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.UseEnvironment("Testing");
        builder.ConfigureTestServices(services =>
        {
            services.RemoveAll<DbContextOptions<AppDbContext>>();
            services.AddDbContext<AppDbContext>(o => o.UseNpgsql(_db.GetConnectionString()));
            // replace external dependencies here (see below)
        });
    }

    public override async ValueTask DisposeAsync()     // v2: override Task DisposeAsync() from IAsyncLifetime
    {
        await _db.DisposeAsync();
        await base.DisposeAsync();
    }
}

[CollectionDefinition(Name)]
public sealed class ApiCollection : ICollectionFixture<ApiFactory>
{
    public const string Name = "api";
}
```

Notes:
- Pin image versions (`postgres:17-alpine`), never `latest`, so CI is reproducible. Match the production major version.
- Apply the schema with **migrations** (`MigrateAsync`) so you test what ships. `EnsureCreated` skips migrations.
- The `IAsyncLifetime` signatures differ between xUnit v2 (`Task`) and v3 (`ValueTask`). Match the project's version.
- Connection string is injected by replacing the registration, not by editing `appsettings.json`.

## WebApplicationFactory

Requires `Program` to be visible to the test project. With top-level statements add to `Program.cs`:

```csharp
public partial class Program { }
```

Mention this as an explicit production change. Alternative that avoids touching `Program.cs` when it is already `internal`: `InternalsVisibleTo` in the Api csproj.

Test class using the shared fixture:

```csharp
[Collection(ApiCollection.Name)]
[Trait("Category", "Integration")]
public class ProductsEndpointTests(ApiFactory factory) : IAsyncLifetime
{
    private readonly HttpClient _client = factory.CreateClient();

    public ValueTask InitializeAsync() => new(factory.ResetDatabaseAsync());
    public ValueTask DisposeAsync() => ValueTask.CompletedTask;

    [Fact]
    public async Task GetById_WhenProductExists_Returns200WithProduct()
    {
        // Arrange
        var id = await factory.SeedAsync(new Product { Name = "Keyboard", Price = 49.90m });

        // Act
        var response = await _client.GetAsync($"/api/products/{id}", TestContext.Current.CancellationToken);

        // Assert
        response.StatusCode.ShouldBe(HttpStatusCode.OK);
        var body = await response.Content.ReadFromJsonAsync<ProductDto>(TestContext.Current.CancellationToken);
        body!.Name.ShouldBe("Keyboard");
    }

    [Fact]
    public async Task Create_WithInvalidBody_Returns400ProblemDetails()
    {
        var response = await _client.PostAsJsonAsync("/api/products", new { Name = "" }, TestContext.Current.CancellationToken);

        response.StatusCode.ShouldBe(HttpStatusCode.BadRequest);
        var problem = await response.Content.ReadFromJsonAsync<ValidationProblemDetails>(TestContext.Current.CancellationToken);
        problem!.Errors.ShouldContainKey("Name");
    }
}
```

Separate classes for separate concerns (`ProductsEndpointTests`, `ProductRepositoryTests`), each in the shared collection.

## Resetting data between tests

Options, in order of preference for relational DBs:

1. **Respawn** - deletes all rows in FK-safe order, very fast; call in `InitializeAsync` of each test class (or via a `ResetDatabaseAsync` on the factory). Exclude `__EFMigrationsHistory`.
2. **Unique data per test** (random names/ids) with no reset, valid only when tests never list or count whole tables.
3. **Transaction rollback per test**, only for repository tests that use the `DbContext` directly (does not work through the HTTP pipeline).

Never rely on test execution order or on ids from other tests.

Collections run sequentially against the shared DB; different collections run in parallel, so give each collection its own database/container, or put all DB-touching tests in one collection.

## Authentication in tests

Prefer a test authentication handler that creates a principal from request headers, so each test chooses its user/roles and the real authorization policies still run:

```csharp
builder.ConfigureTestServices(s =>
    s.AddAuthentication("Test").AddScheme<AuthenticationSchemeOptions, TestAuthHandler>("Test", _ => { }));
```

Use `X-Test-User` / `X-Test-Roles` style headers (or a helper `CreateClientAs(userId, roles)`). Always include tests for: anonymous -> 401, authenticated without permission -> 403, authorized -> success. If the app validates JWTs from an external IdP, do not call the real IdP; replace the scheme as above.

## Faking external services

Replace outbound dependencies (payment gateway, email, other microservices) in `ConfigureTestServices` with NSubstitute fakes or simple hand-written fakes. For outbound HTTP, register a `HttpClient` with a stub `HttpMessageHandler` rather than hitting the network. Faking a boundary is fine; faking your own repository in an "integration" test defeats the purpose.

Also replace `TimeProvider` with `FakeTimeProvider` when behavior depends on time. Replace background workers (`IHostedService`) with no-ops unless they are what you test.

## What to cover

- Every endpoint: success, validation errors, not found, conflict, auth (see checklist).
- Repository/query behavior that is non-trivial: filtering, sorting, paging, includes, projections, unique constraints, optimistic concurrency, soft delete filters.
- Migrations apply on an empty database (the fixture proves this implicitly; add one explicit test if useful).
- Global error handling returns `ProblemDetails` with the right status code and no stack trace in non-Development environments.
- Serialization contract on a couple of key endpoints (property names, enums as strings, date format) so accidental API breaks are caught.
- Idempotency/concurrency rules where the system promises them.

## Pitfalls

- Forgetting `UseEnvironment("Testing")` and then hitting production configuration/secrets.
- Letting tests share one `HttpClient` that carries cookies/headers from earlier tests. Create clients per test class and per user.
- `Thread.Sleep` for async background work: poll with a timeout helper instead.
- Asserting full JSON string equality; deserialize and assert on the fields you care about.
- Leaving containers running: always dispose in `DisposeAsync` (Testcontainers' Ryuk also cleans up).
- Making tests depend on the developer's machine (local SQL Server instance, ports). Everything the test needs must be created by the test run.
