# End-to-end tests (backend / API level)

## Contents
- What e2e means here
- How e2e differs from integration tests
- Setup
- Example flow
- Selecting scenarios
- Azure Functions and out-of-process hosts
- Keeping e2e reliable

## What e2e means here

Backend-only: an e2e test exercises a **complete business flow through the public HTTP API** of the fully composed application, with a real database, as a client would. No browser, no UI automation. The test talks to the app only through `HttpClient`; it does not reach into repositories or services to arrange or verify state (a read-only database check for something the API cannot expose is the only exception).

## How e2e differs from integration tests

| | Integration | E2E |
|---|---|---|
| Unit of test | one endpoint or one repository behavior | a multi-step flow across endpoints |
| Arrange | may seed the DB directly | goes through the API (register, create, then act) |
| Assert | response + persisted state | final observable outcome across the flow |
| Count | many (one per behavior) | few (critical journeys only) |
| Failure tells you | which component broke | that a user journey is broken |

If a scenario is really one endpoint with various inputs, it is an integration test. Keep e2e small; they are the slowest and most expensive tests.

## Setup

Reuse the integration fixture (`WebApplicationFactory<Program>` + Testcontainers) in its own project `MyApp.E2ETests` so it can run on its own stage in CI. Differences from integration tests:

- Use the application's **real** service registrations as much as possible. Replace only systems outside your control (payment provider, email, third-party APIs) with fakes that can be inspected (for example a fake `IEmailSender` that records messages).
- Use the real authentication flow when it is internal to the app (register/login endpoints returning a token). If it depends on an external IdP, use the test auth handler from `integration-tests.md`.
- Start with an empty database per collection, never rely on pre-existing data.
- Tag: `[Trait("Category", "E2E")]`.

## Example flow

```csharp
[Collection(E2ECollection.Name)]
[Trait("Category", "E2E")]
public class CheckoutFlowTests(ApiFactory factory)
{
    [Fact]
    public async Task Customer_CanBrowseOrderAndSeeOrderInHistory()
    {
        var ct = TestContext.Current.CancellationToken;
        var client = factory.CreateClient();

        // Admin prepares the catalog
        var admin = await client.LoginAsync("admin@test.io", "Passw0rd!", ct);
        var product = await admin.PostJsonAsync<ProductDto>("/api/products", new { Name = "Keyboard", Price = 49.90m, Stock = 5 }, ct);

        // Customer orders
        var customer = await client.RegisterAndLoginAsync("ana@test.io", ct);
        var order = await customer.PostJsonAsync<OrderDto>("/api/orders", new { ProductId = product.Id, Quantity = 2 }, ct);

        // Observable outcomes through the API
        order.Total.ShouldBe(99.80m);
        var history = await customer.GetJsonAsync<List<OrderDto>>("/api/orders", ct);
        history.ShouldContain(o => o.Id == order.Id);

        var catalog = await customer.GetJsonAsync<ProductDto>($"/api/products/{product.Id}", ct);
        catalog.Stock.ShouldBe(3);
        factory.EmailSender.Sent.ShouldContain(m => m.To == "ana@test.io" && m.Subject.Contains("Order"));
    }
}
```

`LoginAsync`, `PostJsonAsync`, `GetJsonAsync` are small helper extensions you add to the test project (or `Tests.Shared`); they should assert success status codes and include the response body in the failure message so failures are diagnosable.

## Selecting scenarios

Choose by business criticality. Typical set for a backend:

1. **Smoke:** the app boots, `/health` is OK, migrations applied, one read endpoint works.
2. **Primary happy path** of the core domain (sign up -> create resource -> use it -> see results).
3. **Money/permission-critical path** (checkout, approval, role changes) including one negative branch (insufficient stock, forbidden action).
4. **Cross-cutting guarantee** that spans endpoints: authorization boundaries between two users (user A cannot read user B's data), idempotent retries, pagination consistency.

Typically 3-10 e2e tests for a service is plenty. State in the plan why each was chosen.

## Azure Functions and out-of-process hosts

Without `WebApplicationFactory` the app must be started as a real process:

- Start the host in the fixture (`func start --port <free port>` for Azure Functions Core Tools, or `dotnet run`/`dotnet <dll>` for a normal host) with environment variables pointing to the Testcontainers database and to fakes/emulators for external services (Azurite for storage queues/blobs).
- Poll a readiness endpoint with a timeout before running tests; kill the process in `DisposeAsync`.
- Then proceed exactly as above through `HttpClient`.
- If Core Tools or Docker are unavailable in the environment, say so in the report and limit the plan to unit tests of the services behind the functions.

## Keeping e2e reliable

- Independent flows: each test registers its own users with unique emails (for example `$"{Guid.NewGuid():N}@test.io"`) so tests can share a database without colliding.
- Never `Thread.Sleep`. For asynchronous effects (queues, outbox), poll the API until the expected state appears, with a timeout (for example 10 s) and a clear failure message.
- No assertions on timestamps against the wall clock; use `FakeTimeProvider` or assert approximately.
- Keep helper code readable: a failing e2e test must say which step failed (include step names in helper failure messages).
- Run e2e in a separate CI stage after unit and integration pass; they are allowed to be slower but not flaky. A flaky e2e test is quarantined with a tracked issue, never retried silently.
