# Testing Guide for REST API Projects

## Test Project Structure

```
tests/
├── ProjectName.Tests.Unit/          # Unit tests
│   └── Services/
│       └── OrderServiceTests.cs
```

## Unit Testing

### Testing Application Services (exception-based)

Services throw exceptions instead of returning result wrappers. Tests use `FluentAssertions` async exception assertions.

```csharp
public class OrderServiceTests
{
    private readonly IOrderRepository _orderRepository;
    private readonly IUnitOfWork _unitOfWork;
    private readonly ILogger<OrderService> _logger;
    private readonly OrderService _sut;

    public OrderServiceTests()
    {
        _orderRepository = Substitute.For<IOrderRepository>();
        _unitOfWork = Substitute.For<IUnitOfWork>();
        _logger = Substitute.For<ILogger<OrderService>>();
        var validator = new CreateOrderDtoValidator();
        _sut = new OrderService(_orderRepository, _unitOfWork, validator, _logger);
    }

    // ── Success cases — assert returned DTO directly ─────────

    [Fact]
    public async Task GetAllOrdersAsync_WhenItemsExist_ReturnsAll()
    {
        // Arrange
        var items = new List<Order>
        {
            new() { Id = Guid.NewGuid(), Name = "Alpha", Status = OrderStatus.Active, CreatedAt = DateTime.UtcNow },
            new() { Id = Guid.NewGuid(), Name = "Beta",  Status = OrderStatus.Inactive, CreatedAt = DateTime.UtcNow }
        };
        _orderRepository.GetAllAsync().Returns(items);

        // Act
        var result = await _sut.GetAllOrdersAsync();

        // Assert
        result.Should().HaveCount(2);
    }

    [Fact]
    public async Task GetOrderByIdAsync_WhenEntityExists_ReturnsDto()
    {
        // Arrange
        var id = Guid.NewGuid();
        var order = new Order { Id = id, Name = "Test", Status = OrderStatus.Active, CreatedAt = DateTime.UtcNow };
        _orderRepository.GetByIdAsync(id).Returns(order);

        // Act
        var result = await _sut.GetOrderByIdAsync(id);

        // Assert
        result.Id.Should().Be(id);
        result.Name.Should().Be("Test");
    }

    [Fact]
    public async Task CreateOrderAsync_WithValidDto_ReturnsCreatedDto()
    {
        // Arrange
        var dto = new CreateOrderDto { Name = "New Order" };
        _orderRepository.CreateAsync(Arg.Any<Order>()).Returns(true);

        // Act
        var result = await _sut.CreateOrderAsync(dto);

        // Assert
        result.Name.Should().Be("New Order");
        await _orderRepository.Received(1).CreateAsync(Arg.Any<Order>());
        await _unitOfWork.Received(1).SaveChangesAsync(Arg.Any<CancellationToken>());
        await _unitOfWork.Received(1).CommitTransactionAsync(Arg.Any<CancellationToken>());
    }

    [Fact]
    public async Task DeleteOrderAsync_WhenEntityExists_DeletesSuccessfully()
    {
        // Arrange
        var id = Guid.NewGuid();
        var order = new Order { Id = id, Name = "To Delete", Status = OrderStatus.Active };
        _orderRepository.GetByIdAsync(id).Returns(order);
        _orderRepository.DeleteAsync(id).Returns(true);

        // Act
        await _sut.DeleteOrderAsync(id);

        // Assert
        await _orderRepository.Received(1).DeleteAsync(id);
    }

    // ── Not-found cases — assert NotFoundException ────────────

    [Fact]
    public async Task GetOrderByIdAsync_WhenEntityNotFound_ThrowsNotFoundException()
    {
        // Arrange
        var id = Guid.NewGuid();
        _orderRepository.GetByIdAsync(id).Returns((Order?)null);

        // Act
        Func<Task> act = () => _sut.GetOrderByIdAsync(id);

        // Assert
        await act.Should().ThrowAsync<NotFoundException>()
            .WithMessage($"*{id}*");
    }

    [Fact]
    public async Task DeleteOrderAsync_WhenEntityNotFound_ThrowsNotFoundException()
    {
        // Arrange
        var id = Guid.NewGuid();
        _orderRepository.GetByIdAsync(id).Returns((Order?)null);

        // Act
        Func<Task> act = () => _sut.DeleteOrderAsync(id);

        // Assert
        await act.Should().ThrowAsync<NotFoundException>();
        await _orderRepository.DidNotReceive().DeleteAsync(Arg.Any<Guid>());
    }

    // ── Validation failure cases — assert ValidationException ─

    [Fact]
    public async Task CreateOrderAsync_WithEmptyName_ThrowsValidationException()
    {
        // Arrange
        var dto = new CreateOrderDto { Name = string.Empty };

        // Act
        Func<Task> act = () => _sut.CreateOrderAsync(dto);

        // Assert
        await act.Should().ThrowAsync<FluentValidation.ValidationException>();
        await _orderRepository.DidNotReceive().CreateAsync(Arg.Any<Order>());
    }

    [Fact]
    public async Task CreateOrderAsync_WithNameExceeding200Chars_ThrowsValidationException()
    {
        // Arrange — border case
        var dto = new CreateOrderDto { Name = new string('X', 201) };

        // Act
        Func<Task> act = () => _sut.CreateOrderAsync(dto);

        // Assert
        await act.Should().ThrowAsync<FluentValidation.ValidationException>();
    }

    // ── Repository failure cases — assert propagation ─────────

    [Fact]
    public async Task GetAllOrdersAsync_WhenRepositoryThrows_PropagatesException()
    {
        // Arrange
        _orderRepository.GetAllAsync().ThrowsAsync(new Exception("DB error"));

        // Act
        Func<Task> act = () => _sut.GetAllOrdersAsync();

        // Assert
        await act.Should().ThrowAsync<Exception>().WithMessage("DB error");
    }
}
```

## Required Test Packages

```xml
<PackageReference Include="xunit" Version="2.9.3" />
<PackageReference Include="xunit.runner.visualstudio" Version="2.8.2" />
<PackageReference Include="NSubstitute" Version="5.3.0" />
<PackageReference Include="FluentAssertions" Version="8.4.0" />
<PackageReference Include="coverlet.collector" Version="6.0.4" />
```

## Test Coverage Goals

- **Application Services**: 90%+ coverage
- **Domain Logic**: 95%+ coverage

## Best Practices

1. **Arrange-Act-Assert** pattern for all tests
2. **One assertion per test** when possible
3. **Descriptive test names** (`MethodName_Scenario_ExpectedResult`)
4. **Use NSubstitute** for mocking dependencies
5. **Use FluentAssertions** `.ThrowAsync<T>()` for exception assertions
6. **Isolate tests** (no shared state, each test uses a fresh `_sut`)
7. **Fast tests** (under 100ms for unit tests)
8. **Test border cases**: empty values, max-length strings, `Guid.Empty`
9. **Mock `IUnitOfWork`** and assert `SaveChangesAsync` / `CommitTransactionAsync` on write operations (and `RollbackAsync` on failure)