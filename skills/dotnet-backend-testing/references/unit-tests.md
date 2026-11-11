# Unit tests (xUnit + NSubstitute + Shouldly)

## Contents
- What a unit test is here
- Template
- Fakes: NSubstitute
- Time
- Theories
- Exceptions and async
- Test data builders
- What to test per kind of class
- Anti-patterns

## What a unit test is here

A test of one class (or a tight cluster of pure domain objects) with **no I/O**: no database, no HTTP, no file system, no clock. It should run in milliseconds and never need Docker. If you need a `DbContext`, a `WebApplicationFactory` or a container, it is an integration test (see `integration-tests.md`).

## Template

```csharp
using NSubstitute;
using Shouldly;

namespace MyApp.UnitTests.Application.Orders;

[Trait("Category", "Unit")]
public class OrderServiceTests
{
    private readonly IOrderRepository _orders = Substitute.For<IOrderRepository>();
    private readonly IInventoryClient _inventory = Substitute.For<IInventoryClient>();
    private readonly FakeTimeProvider _time = new(new DateTimeOffset(2026, 1, 15, 10, 0, 0, TimeSpan.Zero));
    private readonly OrderService _sut;

    public OrderServiceTests()   // xUnit creates a new instance per test: fields are isolated
    {
        _sut = new OrderService(_orders, _inventory, _time);
    }

    [Fact]
    public async Task CreateOrder_WhenStockIsAvailable_PersistsOrderAndReturnsId()
    {
        // Arrange
        var request = new CreateOrderRequest(ProductId: 7, Quantity: 2);
        _inventory.GetStockAsync(7, Arg.Any<CancellationToken>()).Returns(10);

        // Act
        var result = await _sut.CreateAsync(request, TestContext.Current.CancellationToken);

        // Assert
        result.IsSuccess.ShouldBeTrue();
        await _orders.Received(1).AddAsync(
            Arg.Is<Order>(o => o.ProductId == 7 && o.Quantity == 2 && o.CreatedAt == _time.GetUtcNow()),
            Arg.Any<CancellationToken>());
    }
}
```

Use `CancellationToken.None` in xUnit v2 projects (`TestContext.Current` exists only in v3).

Conventions:
- The class under test is named `_sut`.
- Constructor builds the SUT; no `[SetUp]`-style shared mutable state. xUnit creates a new class instance per test, which gives isolation for free.
- Make fakes in fields, configure them in the test that needs them.

## Fakes: NSubstitute

- Stub with `.Returns(...)`, `.Returns(Task.FromResult(...))` is unnecessary for `Task<T>` (NSubstitute handles `.Returns(value)` for async members).
- Throw: `_repo.GetAsync(1, default).Throws(new TimeoutException())` or `ThrowsAsync` for async members.
- Verify only side effects that are the behavior: `Received(1)`, `DidNotReceive()`. Do not verify query calls (`GetAsync`) when the returned value already proves they happened.
- Use `Arg.Is<T>(predicate)` for important properties; avoid `Arg.Any<T>()` for the thing you are actually checking.
- Prefer a hand-written fake (simple class) over a complicated NSubstitute setup when the same fake is reused in many tests (for example an in-memory `IClock`/`IEmailSender`).
- Do not fake types you do not own when a real one is cheap (`Options.Create(new MySettings{...})`, `NullLogger<T>.Instance`).
- Do not assert on logger calls unless logging is the feature.

## Time

Inject `TimeProvider`. In tests use `FakeTimeProvider` (package `Microsoft.Extensions.TimeProvider.Testing`):

```csharp
_time.Advance(TimeSpan.FromMinutes(31));
```

If production code uses `DateTime.UtcNow` directly, report it as a testability finding and propose the `TimeProvider` change; apply it only with the user's approval.

## Theories

```csharp
[Theory]
[InlineData("", false)]
[InlineData("a@b", false)]
[InlineData("user@example.com", true)]
public void IsValid_ReturnsExpected(string email, bool expected) =>
    EmailValidator.IsValid(email).ShouldBe(expected);
```

Use `MemberData`/`TheoryData<>` for complex objects. Keep one behavior per theory; if branches need different assertions, use separate facts.

## Exceptions and async

```csharp
var ex = await Should.ThrowAsync<NotFoundException>(() => _sut.GetAsync(99, ct));
ex.Message.ShouldContain("99");
```

Always `await` async code; never `.Result`. Test methods return `Task`, never `async void`.

## Test data builders

When arranging an object takes more than ~5 lines or is repeated, add a builder with sensible defaults so each test states only what matters:

```csharp
internal sealed class OrderBuilder
{
    private int _quantity = 1;
    private OrderStatus _status = OrderStatus.Pending;
    public OrderBuilder WithQuantity(int q) { _quantity = q; return this; }
    public OrderBuilder Shipped() { _status = OrderStatus.Shipped; return this; }
    public Order Build() => new(Guid.NewGuid(), _quantity, _status);
}
```

If using Bogus, always set a seed (`Randomizer.Seed = new Random(8675309)`) so failures are reproducible.

## What to test per kind of class

- **Domain entities/value objects:** invariants, state transitions, equality, boundary values, invalid states rejected.
- **Application services/handlers:** success path, each validation/business-rule failure, each collaborator failure that has defined behavior (not found, conflict), and side effects (event published, email requested).
- **Validators (FluentValidation or DataAnnotations):** each rule with a valid and invalid case, boundaries.
- **Mappers:** only non-trivial mapping (computed fields, conditionals). Skip trivial 1:1 maps, or cover them with one test using a fully populated source.
- **Controllers/endpoint handlers:** if they contain logic, extract it to a service and test that; otherwise cover through integration tests. Do not unit-test `ControllerBase` plumbing.
- **Middleware/filters:** prefer integration tests through the pipeline.

## Anti-patterns to avoid

- Mocking everything including pure helpers and value objects.
- Asserting `Received` on every collaborator call ("mirror tests" that restate the implementation).
- Asserting on exact exception messages for unrelated text.
- Sharing state in `static` fields or `IClassFixture` for mutable things.
- Making a unit test project reference infrastructure, EF Core providers or the web project.
- Tests whose name does not say scenario + expectation.
