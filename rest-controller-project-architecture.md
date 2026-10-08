# REST API Project Architecture - .NET 10
## Best Practices for REST Controllers with PostgreSQL & Third-Party Services

---

## 📁 Recommended Project Structure

```
MyCompany.MyApi/
│
├── src/
│   ├── MyCompany.MyApi.Api/                     # 🔵 API Layer (Controller Layer)
│   │   ├── Program.cs                          # Application entry point & DI setup
│   │   ├── appsettings.json                    # Application configuration
│   │   ├── appsettings.Development.json        # Local development settings
│   │   │
│   │   ├── Controllers/                        # REST API Controllers
│   │   │   ├── OrdersController.cs
│   │   │   └── CustomersController.cs
│   │   │
│   │   ├── Middleware/                         # Cross-cutting concerns
│   │   │   ├── ExceptionHandlingMiddleware.cs
│   │   │   ├── LoggingMiddleware.cs
│   │   │   └── ValidationMiddleware.cs
│   │   │
│   │   └── MyCompany.MyApi.Api.csproj
│   │
│   ├── MyCompany.MyApi.Application/            # 🟢 Application Layer (Business Logic)
│   │   ├── Services/                           # Business services
│   │   │   ├── Orders/
│   │   │   │   ├── IOrderService.cs
│   │   │   │   └── OrderService.cs
│   │   │   │
│   │   │   └── Customers/
│   │   │       ├── ICustomerService.cs
│   │   │       └── CustomerService.cs
│   │   │
│   │   ├── DTOs/                               # Data Transfer Objects
│   │   │   ├── Orders/
│   │   │   │   ├── CreateOrderDto.cs
│   │   │   │   ├── OrderDto.cs
│   │   │   │   └── UpdateOrderDto.cs
│   │   │   │
│   │   │   └── Customers/
│   │   │       └── CustomerDto.cs
│   │   │
│   │   ├── Commands/                           # CQRS Commands (Optional)
│   │   │   └── Orders/
│   │   │       └── CreateOrderCommand.cs
│   │   │
│   │   ├── Queries/                            # CQRS Queries (Optional)
│   │   │   └── Orders/
│   │   │       └── GetOrderByIdQuery.cs
│   │   │
│   │   ├── Validators/                         # FluentValidation validators
│   │   │   └── Orders/
│   │   │       └── CreateOrderDtoValidator.cs
│   │   │
│   │   ├── Mappings/                           # AutoMapper profiles
│   │   │   └── OrderMappingProfile.cs
│   │   │
│   │   ├── Exceptions/                         # Custom exceptions
│   │   │   ├── NotFoundException.cs
│   │   │   ├── ValidationException.cs
│   │   │   └── ConflictException.cs
│   │   │
│   │   └── MyCompany.MyApi.Application.csproj
│   │
│   ├── MyCompany.MyApi.Domain/                 # 🟡 Domain Layer (Core Business)
│   │   ├── Entities/                           # Domain entities
│   │   │   ├── Order.cs
│   │   │   ├── Customer.cs
│   │   │   └── OrderItem.cs
│   │   │
│   │   ├── ValueObjects/                       # Value objects
│   │   │   ├── Address.cs
│   │   │   └── Money.cs
│   │   │
│   │   ├── Enums/                              # Domain enumerations
│   │   │   └── OrderStatus.cs
│   │   │
│   │   ├── Interfaces/                         # Repository interfaces
│   │   │   ├── IOrderRepository.cs
│   │   │   └── ICustomerRepository.cs
│   │   │
│   │   └── MyCompany.MyApi.Domain.csproj
│   │
│   └── MyCompany.MyApi.Infrastructure/         # 🔴 Infrastructure Layer
│       ├── Data/                               # Database context & configuration
│       │   ├── ApplicationDbContext.cs
│       │   ├── Configurations/
│       │   │   ├── OrderConfiguration.cs
│       │   │   └── CustomerConfiguration.cs
│       │   │
│       │   └── Migrations/                     # EF Core migrations
│       │
│       ├── Repositories/                       # Repository implementations
│       │   ├── OrderRepository.cs
│       │   └── CustomerRepository.cs
│       │
│       ├── ExternalServices/                   # Third-party service clients
│       │   ├── IPaymentService.cs
│       │   ├── PaymentService.cs
│       │   ├── INotificationService.cs
│       │   └── NotificationService.cs
│       │
│       ├── HttpClients/                        # Typed HTTP clients
│       │   └── PaymentApiClient.cs
│       │
│       └── MyCompany.MyApi.Infrastructure.csproj
│
└── tests/
    ├── MyCompany.MyApi.Api.Tests/
    ├── MyCompany.MyApi.Application.Tests/
    └── MyCompany.MyApi.Infrastructure.Tests/
```

---

## 🏗️ Layer Responsibilities

### 1. **API Layer** (Controller Layer)
**Responsibility:** Handle HTTP requests ONLY
- Receive HTTP requests
- Validate route parameters
- Delegate to Application Layer
- Return HTTP responses
- **NO business logic here**

### 2. **Application Layer** (Orchestration)
**Responsibility:** Business logic orchestration
- Coordinate business workflows
- Data transformation (Entity ↔ DTO)
- Validation
- Transaction management
- Call domain services and repositories

### 3. **Domain Layer** (Core Business)
**Responsibility:** Pure business logic
- Domain entities
- Business rules
- Domain services
- Repository interfaces (contracts)
- **NO infrastructure dependencies**

### 4. **Infrastructure Layer** (Technical Details)
**Responsibility:** External concerns
- Database access (EF Core with PostgreSQL)
- Third-party API clients
- File system access
- Caching
- External service integrations

---

## 📦 Essential NuGet Packages

### **API Project**
```xml
<PackageReference Include="Microsoft.AspNetCore.OpenApi" Version="10.0.0" />
<PackageReference Include="Swashbuckle.AspNetCore" Version="7.0.0" />
<PackageReference Include="Microsoft.ApplicationInsights.AspNetCore" Version="2.22.0" />
```

### **Application Project**
```xml
<PackageReference Include="AutoMapper" Version="13.0.1" />
<PackageReference Include="FluentValidation" Version="11.9.0" />
<PackageReference Include="FluentValidation.DependencyInjectionExtensions" Version="11.9.0" />
```

### **Infrastructure Project**
```xml
<!-- PostgreSQL with EF Core -->
<PackageReference Include="Npgsql.EntityFrameworkCore.PostgreSQL" Version="9.0.0" />
<PackageReference Include="Microsoft.EntityFrameworkCore.Design" Version="9.0.0" />

<!-- HTTP Client -->
<PackageReference Include="Microsoft.Extensions.Http.Polly" Version="9.0.0" />
<PackageReference Include="Polly" Version="8.4.0" />
<PackageReference Include="Polly.Extensions.Http" Version="3.0.0" />
```

---

## 🔧 Complete Implementation Examples

### **1. Program.cs - Modern DI Setup**

```csharp
using Microsoft.EntityFrameworkCore;
using MyCompany.MyApi.Application.Services.Orders;
using MyCompany.MyApi.Domain.Interfaces;
using MyCompany.MyApi.Infrastructure.Data;
using MyCompany.MyApi.Infrastructure.Repositories;
using MyCompany.MyApi.Infrastructure.ExternalServices;
using MyCompany.MyApi.Api.Middleware;
using FluentValidation;
using Polly;
using Polly.Extensions.Http;

var builder = WebApplication.CreateBuilder(args);

// Controllers
builder.Services.AddControllers();

// Swagger / OpenAPI
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen(options =>
{
    options.SwaggerDoc("v1", new() { Title = "MyCompany.MyApi", Version = "v1" });
});

// Database - PostgreSQL with EF Core
var connectionString = builder.Configuration["PostgreSQL:ConnectionString"];
builder.Services.AddDbContext<ApplicationDbContext>(options =>
    options.UseNpgsql(connectionString, npgsqlOptions =>
    {
        npgsqlOptions.EnableRetryOnFailure(
            maxRetryCount: 3,
            maxRetryDelay: TimeSpan.FromSeconds(5),
            errorCodesToAdd: null);
        npgsqlOptions.CommandTimeout(30);
    }));

// Repositories
builder.Services.AddScoped<IOrderRepository, OrderRepository>();
builder.Services.AddScoped<ICustomerRepository, CustomerRepository>();

// Application Services
builder.Services.AddScoped<IOrderService, OrderService>();
builder.Services.AddScoped<ICustomerService, CustomerService>();

// AutoMapper
builder.Services.AddAutoMapper(typeof(OrderMappingProfile).Assembly);

// FluentValidation
builder.Services.AddValidatorsFromAssemblyContaining<CreateOrderDtoValidator>();

// Third-Party HTTP Clients with Polly Retry Policy
builder.Services.AddHttpClient<IPaymentService, PaymentService>(client =>
{
    client.BaseAddress = new Uri(builder.Configuration["PaymentApi:BaseUrl"]!);
    client.Timeout = TimeSpan.FromSeconds(30);
})
.AddPolicyHandler(GetRetryPolicy())
.AddPolicyHandler(GetCircuitBreakerPolicy());

builder.Services.AddHttpClient<INotificationService, NotificationService>(client =>
{
    client.BaseAddress = new Uri(builder.Configuration["NotificationApi:BaseUrl"]!);
    client.Timeout = TimeSpan.FromSeconds(15);
})
.AddPolicyHandler(GetRetryPolicy());

// Logging
builder.Services.AddApplicationInsightsTelemetry();

var app = builder.Build();

// Configure middleware pipeline
if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

app.UseHttpsRedirection();

// Register middleware in order
app.UseMiddleware<ExceptionHandlingMiddleware>();
app.UseMiddleware<LoggingMiddleware>();

app.UseAuthorization();
app.MapControllers();

app.Run();

// Polly Policies
static IAsyncPolicy<HttpResponseMessage> GetRetryPolicy()
{
    return HttpPolicyExtensions
        .HandleTransientHttpError()
        .WaitAndRetryAsync(3, retryAttempt =>
            TimeSpan.FromSeconds(Math.Pow(2, retryAttempt)));
}

static IAsyncPolicy<HttpResponseMessage> GetCircuitBreakerPolicy()
{
    return HttpPolicyExtensions
        .HandleTransientHttpError()
        .CircuitBreakerAsync(5, TimeSpan.FromSeconds(30));
}
```

### **2. REST Controller Example - OrdersController.cs**

```csharp
using Microsoft.AspNetCore.Mvc;
using MyCompany.MyApi.Application.DTOs.Orders;
using MyCompany.MyApi.Application.Services.Orders;

namespace MyCompany.MyApi.Api.Controllers;

[ApiController]
[Route("api/[controller]")]
[Produces("application/json")]
public class OrdersController : ControllerBase
{
    private readonly IOrderService _orderService;
    private readonly ILogger<OrdersController> _logger;

    public OrdersController(
        IOrderService orderService,
        ILogger<OrdersController> logger)
    {
        _orderService = orderService;
        _logger = logger;
    }

    /// <summary>Create a new order</summary>
    [HttpPost]
    [ProducesResponseType(typeof(OrderDto), StatusCodes.Status201Created)]
    [ProducesResponseType(typeof(ValidationProblemDetails), StatusCodes.Status400BadRequest)]
    public async Task<IActionResult> CreateOrder([FromBody] CreateOrderDto createOrderDto)
    {
        _logger.LogInformation("Creating new order");

        var orderDto = await _orderService.CreateOrderAsync(createOrderDto);

        return CreatedAtAction(nameof(GetOrder), new { id = orderDto.Id }, orderDto);
    }

    /// <summary>Get an order by ID</summary>
    [HttpGet("{id:guid}")]
    [ProducesResponseType(typeof(OrderDto), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> GetOrder(Guid id)
    {
        _logger.LogInformation("Getting order {OrderId}", id);

        var orderDto = await _orderService.GetOrderByIdAsync(id);

        return Ok(orderDto);
    }

    /// <summary>Update an existing order</summary>
    [HttpPut("{id:guid}")]
    [ProducesResponseType(typeof(OrderDto), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ValidationProblemDetails), StatusCodes.Status400BadRequest)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> UpdateOrder(Guid id, [FromBody] UpdateOrderDto updateOrderDto)
    {
        _logger.LogInformation("Updating order {OrderId}", id);

        var orderDto = await _orderService.UpdateOrderAsync(id, updateOrderDto);

        return Ok(orderDto);
    }

    /// <summary>Delete an order</summary>
    [HttpDelete("{id:guid}")]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> DeleteOrder(Guid id)
    {
        _logger.LogInformation("Deleting order {OrderId}", id);

        await _orderService.DeleteOrderAsync(id);

        return NoContent();
    }
}
```

### **3. Application Service - OrderService.cs**

```csharp
using AutoMapper;
using FluentValidation;
using Microsoft.Extensions.Logging;
using MyCompany.MyApi.Application.DTOs.Orders;
using MyCompany.MyApi.Application.Exceptions;
using MyCompany.MyApi.Domain.Entities;
using MyCompany.MyApi.Domain.Interfaces;
using MyCompany.MyApi.Infrastructure.ExternalServices;

namespace MyCompany.MyApi.Application.Services.Orders;

public interface IOrderService
{
    Task<OrderDto> CreateOrderAsync(CreateOrderDto createOrderDto);
    Task<OrderDto?> GetOrderByIdAsync(Guid id);
    Task<OrderDto> UpdateOrderAsync(Guid id, UpdateOrderDto updateOrderDto);
    Task DeleteOrderAsync(Guid id);
}

public class OrderService : IOrderService
{
    private readonly IOrderRepository _orderRepository;
    private readonly ICustomerRepository _customerRepository;
    private readonly IPaymentService _paymentService;
    private readonly INotificationService _notificationService;
    private readonly IMapper _mapper;
    private readonly IValidator<CreateOrderDto> _createOrderValidator;
    private readonly ILogger<OrderService> _logger;

    public OrderService(
        IOrderRepository orderRepository,
        ICustomerRepository customerRepository,
        IPaymentService paymentService,
        INotificationService notificationService,
        IMapper mapper,
        IValidator<CreateOrderDto> createOrderValidator,
        ILogger<OrderService> logger)
    {
        _orderRepository = orderRepository;
        _customerRepository = customerRepository;
        _paymentService = paymentService;
        _notificationService = notificationService;
        _mapper = mapper;
        _createOrderValidator = createOrderValidator;
        _logger = logger;
    }

    public async Task<OrderDto> CreateOrderAsync(CreateOrderDto createOrderDto)
    {
        // Validate
        var validationResult = await _createOrderValidator.ValidateAsync(createOrderDto);
        if (!validationResult.IsValid)
        {
            throw new ValidationException(validationResult.Errors);
        }

        // Check if customer exists
        var customer = await _customerRepository.GetByIdAsync(createOrderDto.CustomerId);
        if (customer is null)
        {
            throw new NotFoundException($"Customer with ID {createOrderDto.CustomerId} not found");
        }

        // Map DTO to Entity
        var order = _mapper.Map<Order>(createOrderDto);
        order.Id = Guid.NewGuid();
        order.CreatedAt = DateTime.UtcNow;

        // Process payment via third-party service
        try
        {
            var paymentResult = await _paymentService.ProcessPaymentAsync(new PaymentRequest
            {
                Amount = order.TotalAmount,
                Currency = "USD",
                CustomerId = customer.Id.ToString()
            });

            order.PaymentId = paymentResult.TransactionId;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Payment processing failed for order");
            throw new ConflictException("Payment processing failed", ex);
        }

        // Save to database
        await _orderRepository.AddAsync(order);
        await _orderRepository.SaveChangesAsync();

        // Send notification (fire-and-forget)
        _ = Task.Run(async () =>
        {
            try
            {
                await _notificationService.SendOrderConfirmationAsync(customer.Email, order.Id);
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Failed to send order confirmation email");
            }
        });

        return _mapper.Map<OrderDto>(order);
    }

    public async Task<OrderDto?> GetOrderByIdAsync(Guid id)
    {
        var order = await _orderRepository.GetByIdAsync(id);
        if (order is null)
        {
            throw new NotFoundException($"Order with ID {id} not found");
        }

        return _mapper.Map<OrderDto>(order);
    }

    public async Task<OrderDto> UpdateOrderAsync(Guid id, UpdateOrderDto updateOrderDto)
    {
        var order = await _orderRepository.GetByIdAsync(id);
        if (order is null)
        {
            throw new NotFoundException($"Order with ID {id} not found");
        }

        // Update entity
        _mapper.Map(updateOrderDto, order);
        order.UpdatedAt = DateTime.UtcNow;

        await _orderRepository.UpdateAsync(order);
        await _orderRepository.SaveChangesAsync();

        return _mapper.Map<OrderDto>(order);
    }

    public async Task DeleteOrderAsync(Guid id)
    {
        var order = await _orderRepository.GetByIdAsync(id);
        if (order is null)
        {
            throw new NotFoundException($"Order with ID {id} not found");
        }

        await _orderRepository.DeleteAsync(order);
        await _orderRepository.SaveChangesAsync();
    }
}
```

### **4. Repository Implementation - OrderRepository.cs**

```csharp
using Microsoft.EntityFrameworkCore;
using MyCompany.MyApi.Domain.Entities;
using MyCompany.MyApi.Domain.Interfaces;
using MyCompany.MyApi.Infrastructure.Data;

namespace MyCompany.MyApi.Infrastructure.Repositories;

public class OrderRepository : IOrderRepository
{
    private readonly ApplicationDbContext _context;

    public OrderRepository(ApplicationDbContext context)
    {
        _context = context;
    }

    public async Task<Order?> GetByIdAsync(Guid id)
    {
        return await _context.Orders
            .Include(o => o.OrderItems)
            .Include(o => o.Customer)
            .FirstOrDefaultAsync(o => o.Id == id);
    }

    public async Task<IEnumerable<Order>> GetAllAsync()
    {
        return await _context.Orders
            .Include(o => o.OrderItems)
            .Include(o => o.Customer)
            .ToListAsync();
    }

    public async Task AddAsync(Order order)
    {
        await _context.Orders.AddAsync(order);
    }

    public Task UpdateAsync(Order order)
    {
        _context.Orders.Update(order);
        return Task.CompletedTask;
    }

    public Task DeleteAsync(Order order)
    {
        _context.Orders.Remove(order);
        return Task.CompletedTask;
    }

    public async Task<int> SaveChangesAsync()
    {
        return await _context.SaveChangesAsync();
    }
}
```

### **5. DbContext Configuration - ApplicationDbContext.cs**

```csharp
using Microsoft.EntityFrameworkCore;
using MyCompany.MyApi.Domain.Entities;
using MyCompany.MyApi.Infrastructure.Data.Configurations;

namespace MyCompany.MyApi.Infrastructure.Data;

public class ApplicationDbContext : DbContext
{
    public ApplicationDbContext(DbContextOptions<ApplicationDbContext> options)
        : base(options)
    {
    }

    public DbSet<Order> Orders => Set<Order>();
    public DbSet<Customer> Customers => Set<Customer>();
    public DbSet<OrderItem> OrderItems => Set<OrderItem>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        base.OnModelCreating(modelBuilder);

        // Apply configurations
        modelBuilder.ApplyConfiguration(new OrderConfiguration());
        modelBuilder.ApplyConfiguration(new CustomerConfiguration());

        // PostgreSQL specific configurations
        modelBuilder.HasDefaultSchema("public");
    }
}
```

### **6. Entity Configuration - OrderConfiguration.cs**

```csharp
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using MyCompany.MyApi.Domain.Entities;

namespace MyCompany.MyApi.Infrastructure.Data.Configurations;

public class OrderConfiguration : IEntityTypeConfiguration<Order>
{
    public void Configure(EntityTypeBuilder<Order> builder)
    {
        builder.ToTable("orders");

        builder.HasKey(o => o.Id);

        builder.Property(o => o.Id)
            .HasColumnName("id")
            .IsRequired();

        builder.Property(o => o.OrderNumber)
            .HasColumnName("order_number")
            .HasMaxLength(50)
            .IsRequired();

        builder.Property(o => o.TotalAmount)
            .HasColumnName("total_amount")
            .HasColumnType("decimal(18,2)")
            .IsRequired();

        builder.Property(o => o.Status)
            .HasColumnName("status")
            .HasConversion<string>()
            .HasMaxLength(50)
            .IsRequired();

        builder.Property(o => o.CreatedAt)
            .HasColumnName("created_at")
            .IsRequired();

        builder.Property(o => o.UpdatedAt)
            .HasColumnName("updated_at");

        // Relationships
        builder.HasOne(o => o.Customer)
            .WithMany()
            .HasForeignKey("customer_id")
            .OnDelete(DeleteBehavior.Restrict);

        builder.HasMany(o => o.OrderItems)
            .WithOne()
            .HasForeignKey("order_id")
            .OnDelete(DeleteBehavior.Cascade);

        // Indexes
        builder.HasIndex(o => o.OrderNumber)
            .IsUnique();

        builder.HasIndex(o => o.CreatedAt);
    }
}
```

### **7. Third-Party Service - PaymentService.cs**

```csharp
using System.Net.Http.Json;
using Microsoft.Extensions.Logging;

namespace MyCompany.MyApi.Infrastructure.ExternalServices;

public interface IPaymentService
{
    Task<PaymentResponse> ProcessPaymentAsync(PaymentRequest request);
}

public class PaymentService : IPaymentService
{
    private readonly HttpClient _httpClient;
    private readonly ILogger<PaymentService> _logger;

    public PaymentService(HttpClient httpClient, ILogger<PaymentService> logger)
    {
        _httpClient = httpClient;
        _logger = logger;
    }

    public async Task<PaymentResponse> ProcessPaymentAsync(PaymentRequest request)
    {
        _logger.LogInformation("Processing payment for amount: {Amount}", request.Amount);

        try
        {
            var response = await _httpClient.PostAsJsonAsync("/api/payments", request);
            response.EnsureSuccessStatusCode();

            var paymentResponse = await response.Content.ReadFromJsonAsync<PaymentResponse>();
            
            _logger.LogInformation("Payment processed successfully. Transaction ID: {TransactionId}", 
                paymentResponse?.TransactionId);

            return paymentResponse!;
        }
        catch (HttpRequestException ex)
        {
            _logger.LogError(ex, "HTTP error occurred while processing payment");
            throw;
        }
    }
}

public record PaymentRequest
{
    public decimal Amount { get; init; }
    public string Currency { get; init; } = "USD";
    public string CustomerId { get; init; } = string.Empty;
}

public record PaymentResponse
{
    public string TransactionId { get; init; } = string.Empty;
    public string Status { get; init; } = string.Empty;
    public DateTime ProcessedAt { get; init; }
}
```

### **8. Exception Handling Middleware**

```csharp
using System.Net;
using FluentValidation;
using MyCompany.MyApi.Application.Exceptions;

namespace MyCompany.MyApi.Api.Middleware;

public class ExceptionHandlingMiddleware
{
    private readonly RequestDelegate _next;
    private readonly ILogger<ExceptionHandlingMiddleware> _logger;

    public ExceptionHandlingMiddleware(RequestDelegate next, ILogger<ExceptionHandlingMiddleware> logger)
    {
        _next = next;
        _logger = logger;
    }

    public async Task InvokeAsync(HttpContext context)
    {
        try
        {
            await _next(context);
        }
        catch (ValidationException ex)
        {
            _logger.LogWarning(ex, "Validation error occurred");
            await HandleValidationExceptionAsync(context, ex);
        }
        catch (NotFoundException ex)
        {
            _logger.LogWarning(ex, "Resource not found: {Message}", ex.Message);
            await HandleExceptionAsync(context, HttpStatusCode.NotFound, ex.Message);
        }
        catch (ConflictException ex)
        {
            _logger.LogWarning(ex, "Conflict occurred: {Message}", ex.Message);
            await HandleExceptionAsync(context, HttpStatusCode.Conflict, ex.Message);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Unhandled exception occurred");
            await HandleExceptionAsync(context, HttpStatusCode.InternalServerError,
                "An unexpected error occurred. Please try again later.");
        }
    }

    private static async Task HandleValidationExceptionAsync(
        HttpContext context,
        ValidationException exception)
    {
        context.Response.StatusCode = (int)HttpStatusCode.BadRequest;
        context.Response.ContentType = "application/json";

        var errors = exception.Errors
            .GroupBy(e => e.PropertyName)
            .ToDictionary(
                g => g.Key,
                g => g.Select(e => e.ErrorMessage).ToArray()
            );

        await context.Response.WriteAsJsonAsync(new ValidationErrorResponse
        {
            Message = "One or more validation errors occurred",
            Errors = errors
        });
    }

    private static async Task HandleExceptionAsync(
        HttpContext context,
        HttpStatusCode statusCode,
        string message)
    {
        context.Response.StatusCode = (int)statusCode;
        context.Response.ContentType = "application/json";

        await context.Response.WriteAsJsonAsync(new ErrorResponse
        {
            Message = message,
            StatusCode = (int)statusCode
        });
    }
}

public record ErrorResponse
{
    public string Message { get; init; } = string.Empty;
    public int StatusCode { get; init; }
}

public record ValidationErrorResponse
{
    public string Message { get; init; } = string.Empty;
    public Dictionary<string, string[]> Errors { get; init; } = new();
}
```

---

## ⚙️ Configuration Files

### **appsettings.json**
```json
{
  "ConnectionStrings": {},
  "PostgreSQL": {
    "ConnectionString": "Host=localhost;Database=myapi;Username=postgres;Password=yourpassword"
  },
  "PaymentApi": {
    "BaseUrl": "https://payment-api.example.com"
  },
  "NotificationApi": {
    "BaseUrl": "https://notification-api.example.com"
  },
  "Logging": {
    "LogLevel": {
      "Default": "Information",
      "Microsoft.AspNetCore": "Warning"
    }
  },
  "AllowedHosts": "*"
}
```

### **appsettings.Development.json**
```json
{
  "PostgreSQL": {
    "ConnectionString": "Host=localhost;Database=myapi_dev;Username=postgres;Password=yourpassword"
  },
  "Logging": {
    "LogLevel": {
      "Default": "Debug",
      "Microsoft.AspNetCore": "Information"
    }
  }
}
```

---

## 🎯 Key Architectural Benefits

### ✅ **Separation of Concerns**
- Each layer has a single, well-defined responsibility
- Easy to test each layer independently
- Changes in one layer don't affect others

### ✅ **Testability**
- Mock repositories and external services easily
- Unit test business logic without infrastructure
- Integration tests for database operations

### ✅ **Maintainability**
- Clear project structure
- Easy to locate and modify code
- New developers can navigate quickly

### ✅ **Performance**
- Connection pooling with EF Core
- Retry policies with Polly
- Async/await throughout

### ✅ **Scalability**
- Stateless controllers scale horizontally
- Database connection pooling
- External service resilience with circuit breakers

---

## 🚀 Best Practices Summary

1. **Keep Controllers Slim** - Only handle HTTP request/response, delegate everything else
2. **Use Dependency Injection** - Register all services in Program.cs
3. **Implement Retry Logic** - Use Polly for third-party HTTP calls
4. **Validate Early** - Use FluentValidation in Application Layer
5. **Use DTOs** - Never expose domain entities directly
6. **Handle Errors Globally** - Middleware-based exception handling
7. **Log Everything** - Structured logging with correlation IDs
8. **Use Async/Await** - Throughout the entire stack
9. **Configure PostgreSQL Properly** - Connection pooling, retry on failure
10. **Document with OpenAPI** - Every endpoint fully documented

---

## 📊 Migration Commands

```bash
# Add initial migration
dotnet ef migrations add InitialCreate --project src/MyCompany.MyApi.Infrastructure --startup-project src/MyCompany.MyApi.Api

# Update database
dotnet ef database update --project src/MyCompany.MyApi.Infrastructure --startup-project src/MyCompany.MyApi.Api
```

---

This architecture provides a **solid foundation** for building enterprise-grade REST APIs with .NET 10, PostgreSQL, and third-party service integrations. It follows SOLID principles, clean architecture, and ASP.NET Core Web API best practices.
