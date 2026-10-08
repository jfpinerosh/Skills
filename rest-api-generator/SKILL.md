---
name: rest-api-generator
description: Generate production-ready .NET 10 ASP.NET Core REST API projects with clean architecture. Use when users request creating a new REST API project, Web API scaffold, or ask to "create/generate/scaffold a REST API project". Supports REST controllers with PostgreSQL or SQL Server via Dapper or Entity Framework Core, third-party service integrations, and follows ASP.NET Core Web API best practices. Triggers include requests like "create a new REST API project", "scaffold a Web API with .NET", "set up a REST API with .NET 10", "generate an ASP.NET Core API solution with database", or "create a REST API with EF Core".
---

# REST API Project Generator

## Overview

Generate complete, production-ready .NET 10 ASP.NET Core REST API projects following clean architecture principles, configurable data access (Dapper or Entity Framework Core), and RESTful API best practices.

## Workflow

### Step 1: Gather Requirements

ALWAYS ask the user for these essential details before generating:

1. **Project Name** (Required)
   - Ask: "What is the name of your project? (e.g., 'MyCompany.OrdersApi')"
   - Used for solution name and namespace

2. **Database Engine** (Required)
   - Ask: "Which database engine will you use?"
   - Options: **PostgreSQL** (default) | **SQL Server**
   - Default to PostgreSQL if user doesn't specify

3. **ORM / Data Access** (Required)
   - Ask: "Which ORM would you like to use for data access?"
   - Options: **Dapper** (default) | **Entity Framework Core**
   - Default to Dapper if user doesn't specify
   - Shared abstractions: `IRepository<T>` + `IUnitOfWork` (implemented by both engines)
   - Dapper: `DapperRepository<T>` + `DapperUnitOfWork` + `TenantConnectionFactory`
   - EF Core: `EFRepository<T>` + `EfUnitOfWork` + `ApplicationDbContext` + Fluent API Configurations + Migrations
   - Persistence is owned by the Application layer: services call `IUnitOfWork.SaveChangesAsync()` then `CommitTransactionAsync()`

4. **Third-Party Services** (Optional)
   - Ask: "Will you integrate with any third-party services? If yes, please list them (e.g., 'Payment API, Notification Service, Email Provider')"
   - If none specified, skip external service scaffolding

5. **Sample Entity** (Optional)
   - Ask: "Would you like a sample entity to start with? If yes, provide:"
     a) Entity name (e.g., 'Order', 'Customer', 'Product')
     b) At least 2 properties with data types (e.g., 'Name:string, Price:decimal')
   - Default to **`Item`** with properties `Name:string, Description:string` if user says yes but doesn't specify
   - Supported data types: `string`, `int`, `decimal`, `bool`, `DateTime`, `Guid`

### Step 2: Execute Generation Script

Run the `scripts/generate_project.ps1` PowerShell script with collected parameters:

```powershell
.\scripts\generate_project.ps1 `
  -ProjectName "MyCompany.OrdersApi" `
  -Database "postgresql" `
  -Orm "dapper" `
  -Services "Payment API,Notification Service" `
  -Entity "Order" `
  -EntityProperties "CustomerName:string,TotalAmount:decimal,Quantity:int" `
  -OutputPath "."
```

**Script Parameters:**
- `-ProjectName`: Full project name (required)
- `-Database`: Database engine choice (`postgresql` | `sqlserver`, default: `postgresql`)
- `-Orm`: ORM choice (`dapper` | `efcore`, default: `dapper`)
- `-Services`: Comma-separated list of service names (optional)
- `-Entity`: Sample entity name (optional, default: `Item`)
- `-EntityProperties`: Comma-separated `Name:type` pairs (optional, default: `Name:string,Description:string`)
- `-OutputPath`: Where to create the project (default: current directory)

**Database packages resolved automatically by ORM + Database combination:**

| ORM | Database | Packages |
|---|---|---|
| `dapper` | `postgresql` | Dapper 2.1.66, Dapper.Contrib 2.0.78, Npgsql 10.0.1 |
| `dapper` | `sqlserver` | Dapper 2.1.66, Dapper.Contrib 2.0.78, Microsoft.Data.SqlClient 6.0.2 |
| `efcore` | `postgresql` | Microsoft.EntityFrameworkCore 10.0.0, Microsoft.EntityFrameworkCore.Tools 10.0.0, Npgsql.EntityFrameworkCore.PostgreSQL 10.0.0 |
| `efcore` | `sqlserver` | Microsoft.EntityFrameworkCore 10.0.0, Microsoft.EntityFrameworkCore.Tools 10.0.0, Microsoft.EntityFrameworkCore.SqlServer 10.0.0 |

### Step 3: Verify Generation

After script execution:
1. Confirm all directories were created successfully
2. Verify the project structure matches the expected layout
3. List generated files to the user

### Step 4: Provide Next Steps

#### For Dapper projects:

```markdown
## Project Generated Successfully!

### Project Structure Created:
- API Layer (REST Controllers + Swagger UI)
- Application Layer (Business Logic, FluentValidation, manual mapping)
- Domain Layer (Entities, DTOs, Interfaces, Enums)
- Infrastructure Layer (Dapper, IRepository<T>, IUnitOfWork, DapperRepository<T>, DapperUnitOfWork)
- Tests Layer (xUnit + NSubstitute + FluentAssertions + Coverlet)

### Next Steps:
1. **Restore packages**: `dotnet restore`
2. **Configure connection string**: Update `appsettings.json` with your database connection
3. **Update entity model**: Modify `{Entity}.cs` in Domain/Entities
4. **Run the API**: `dotnet run` in `src/{ProjectName}.Api`

### Key Files to Review:
- `Program.cs` — DI setup with Swagger and multi-tenant Dapper
- `{Entity}sController.cs` — REST controllers with full CRUD
- `{Entity}Service.cs` — Business logic; owns SaveChanges + transaction commit
- `IRepository.cs` / `IUnitOfWork.cs` — Shared repository + unit of work contracts
- `DapperUnitOfWork.cs` — Shared connection + transaction
- `{Entity}Repository.cs` — Dapper queries
- `{Entity}ServiceTests.cs` — xUnit unit tests (AAA pattern, FIRST principles)

### Run Tests:
`dotnet test --collect:"XPlat Code Coverage"`
```

#### For Entity Framework Core projects:

```markdown
## Project Generated Successfully!

### Project Structure Created:
- API Layer (REST Controllers + Swagger UI)
- Application Layer (Business Logic, FluentValidation, manual mapping)
- Domain Layer (Entities, DTOs, Interfaces, Enums)
- Infrastructure Layer (EF Core DbContext, IRepository<T>, IUnitOfWork, EFRepository<T>, EfUnitOfWork, Fluent API Configurations)
- Tests Layer (xUnit + NSubstitute + FluentAssertions + Coverlet)

### Next Steps:
1. **Restore packages**: `dotnet restore`
2. **Configure connection string**: Update `appsettings.json` with your database connection
3. **Create initial migration**: `dotnet ef migrations add InitialCreate --project src/{ProjectName}.Infrastructure --startup-project src/{ProjectName}.Api`
4. **Apply migration**: `dotnet ef database update --project src/{ProjectName}.Infrastructure --startup-project src/{ProjectName}.Api`
5. **Run the API**: `dotnet run` in `src/{ProjectName}.Api`

### Key Files to Review:
- `Program.cs` — DI setup with Swagger, EF Core DbContext and the Unit of Work
- `{Entity}sController.cs` — REST controllers with full CRUD
- `{Entity}Service.cs` — Business logic; owns SaveChanges + transaction commit
- `IRepository.cs` / `IUnitOfWork.cs` — Shared repository + unit of work contracts
- `ApplicationDbContext.cs` — EF Core DbContext with entity configurations
- `{Entity}Configuration.cs` — Fluent API entity mapping
- `EFRepository.cs` — Generic EF Core repository (IRepository<T>)
- `EfUnitOfWork.cs` — Unit of Work implementation
- `{Entity}Repository.cs` — Entity-specific repository
- `{Entity}ServiceTests.cs` — xUnit unit tests (AAA pattern, FIRST principles)

### Run Tests:
`dotnet test --collect:"XPlat Code Coverage"`
```

### Step 5: Offer Customization

Ask if the user needs:
- Additional entities/controllers
- Custom validators
- More xUnit test cases
- Additional external HTTP services

## Generation Script Details

The `scripts/generate_project.ps1` creates:

### Dapper Project Structure
```
{ProjectName}/
├── src/
│   ├── {ProjectName}.Api/
│   │   ├── Program.cs
│   │   ├── appsettings.json
│   │   ├── appsettings.Development.json
│   │   ├── Controllers/{Entity}sController.cs
│   │   └── Middleware/ExceptionHandlingMiddleware.cs
│   ├── {ProjectName}.Application/
│   │   ├── Services/{Entity}Service.cs
│   │   ├── Validators/Create{Entity}DtoValidator.cs
│   │   └── Exceptions/AppExceptions.cs
│   ├── {ProjectName}.Domain/
│   │   ├── DTOs/{Entity}Dto.cs
│   │   ├── Entities/{Entity}.cs
│   │   ├── Enums/{Entity}Status.cs
│   │   └── Interfaces/
│   │       ├── I{Entity}Repository.cs
│   │       ├── Data/ITenantConnectionFactory.cs
│   │       └── Repository/
│   │           ├── IRepository.cs
│   │           └── IUnitOfWork.cs
│   └── {ProjectName}.Infrastructure/
│       ├── Data/TenantConnectionFactory.cs
│       ├── Data/Configurations/ServiceCollectionExtensions.cs
│       ├── Repositories/DapperRepository.cs
│       ├── Repositories/DapperUnitOfWork.cs
│       ├── Repositories/{Entity}Repository.cs
│       └── ExternalServices/ (if services specified)
├── tests/
│   └── {ProjectName}.Tests.Unit/
│       └── Services/{Entity}ServiceTests.cs
└── README.md
```

### Entity Framework Core Project Structure
```
{ProjectName}/
├── src/
│   ├── {ProjectName}.Api/
│   │   ├── Program.cs
│   │   ├── appsettings.json
│   │   ├── appsettings.Development.json
│   │   ├── Controllers/{Entity}sController.cs
│   │   └── Middleware/ExceptionHandlingMiddleware.cs
│   ├── {ProjectName}.Application/
│   │   ├── Services/{Entity}Service.cs
│   │   ├── Validators/Create{Entity}DtoValidator.cs
│   │   └── Exceptions/AppExceptions.cs
│   ├── {ProjectName}.Domain/
│   │   ├── DTOs/{Entity}Dto.cs
│   │   ├── Entities/{Entity}.cs
│   │   ├── Enums/{Entity}Status.cs
│   │   └── Interfaces/
│   │       ├── I{Entity}Repository.cs
│   │       └── Repository/
│   │           ├── IRepository.cs
│   │           └── IUnitOfWork.cs
│   └── {ProjectName}.Infrastructure/
│       ├── Data/ApplicationDbContext.cs
│       ├── Data/Configurations/{Entity}Configuration.cs
│       ├── Repositories/EFRepository.cs
│       ├── Repositories/EfUnitOfWork.cs
│       ├── Repositories/{Entity}Repository.cs
│       └── ExternalServices/ (if services specified)
├── tests/
│   └── {ProjectName}.Tests.Unit/
│       └── Services/{Entity}ServiceTests.cs
└── README.md
```

### Controllers — REST Pattern

Every controller follows the standard ASP.NET Core pattern:

```csharp
[ApiController]
[Route("api/[controller]")]
[Produces("application/json")]
public class ItemsController : ControllerBase
{
    [HttpGet]
    [ProducesResponseType(typeof(IEnumerable<ItemDto>), StatusCodes.Status200OK)]
    public async Task<IActionResult> GetAllItems()
    {
        _logger.LogInformation("GET all Items");
        var result = await _itemService.GetAllItemsAsync();
        return Ok(result);
    }
}
```

**Key attributes used:**
- `[ApiController]` — always on the class, enables model validation + binding
- `[Route("api/[controller]")]` — convention-based route
- `[HttpGet]`, `[HttpPost]`, `[HttpDelete]` — verb attributes
- `[ProducesResponseType]` — documents response types for Swagger
- `[FromBody]` — on POST/PUT action parameters
- `CreatedAtAction(...)` — returns 201 with Location header

### DTOs — Location Rule

**All DTOs live in `{ProjectName}.Domain/DTOs/`**, not in Application:
- `{Entity}Dto` — response/read DTO
- `Create{Entity}Dto` — input DTO for creation

### Services — Exception-Based Pattern

All service methods throw exceptions for error cases:

```csharp
public async Task<ItemDto> GetItemByIdAsync(Guid id)
{
    var item = await _itemRepository.GetByIdAsync(id);
    if (item is null)
        throw new NotFoundException($"Item with ID {id} not found");

    return ToDto(item);
}

// Manual mapping — no AutoMapper
private static ItemDto ToDto(Item item) => new()
{
    Id = item.Id,
    Name = item.Name,
    Status = item.Status.ToString(),
    CreatedAt = item.CreatedAt
};
```

### Unit of Work — Persistence in the Application Layer

Repositories never commit. Every write operation is coordinated by the service through `IUnitOfWork`:

```csharp
public async Task<ItemDto> CreateItemAsync(CreateItemDto dto)
{
    var validation = await _validator.ValidateAsync(dto);
    if (!validation.IsValid)
        throw new ValidationException(validation.Errors);

    var item = new Item { Id = Guid.NewGuid(), Name = dto.Name, Status = ItemStatus.Active, CreatedAt = DateTime.UtcNow };

    await _unitOfWork.BeginTransactionAsync();
    try
    {
        await _itemRepository.CreateAsync(item);
        await _unitOfWork.SaveChangesAsync();
        await _unitOfWork.CommitTransactionAsync();
    }
    catch (Exception ex)
    {
        _logger.LogError(ex, "Error creating Item");
        await _unitOfWork.RollbackAsync();
        throw;
    }

    return ToDto(item);
}
```

- `IRepository<T>` exposes `GetByIdAsync`, `FindAsync(predicate)`, `GetAllAsync`, `CreateAsync`, `UpdateAsync`, `DeleteAsync`, and `ExecuteAsync(rawSql, parameters)`.
- `IUnitOfWork` exposes `Repository<T>()`, `SaveChangesAsync()`, `BeginTransactionAsync()`, `CommitTransactionAsync()`, and `RollbackAsync()`.
- EF Core: `SaveChangesAsync` flushes the `DbContext`; Dapper: statements execute immediately and `SaveChangesAsync` is a no-op (`0`). `CommitTransactionAsync` commits the active transaction for both engines.

### Entity Properties

Entities are generated with user-defined properties. Given input `-Entity "Product" -EntityProperties "Name:string,Price:decimal,Stock:int"`:

```csharp
public class Product
{
    public Guid Id { get; set; }
    public string Name { get; set; } = string.Empty;
    public decimal Price { get; set; }
    public int Stock { get; set; }
    public ProductStatus Status { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime? UpdatedAt { get; set; }
}
```

DTOs, validators, and tests are generated to include all defined properties.

### Database-Specific Configuration

**PostgreSQL:**
- Dapper: `Npgsql 10.0.1` connector, `AddPostgresMultiTenant()`
- EF Core: `Npgsql.EntityFrameworkCore.PostgreSQL 10.0.0`
- Connection string: `Host=...;Database=...;Username=...;Password=...`
- Table names: `snake_case`

**SQL Server:**
- Dapper: `Microsoft.Data.SqlClient 6.0.2`, `AddSqlServerMultiTenant()`
- EF Core: `Microsoft.EntityFrameworkCore.SqlServer 10.0.0`
- Connection string: `Server=...;Database=...;User Id=...;Password=...;TrustServerCertificate=True`
- Table names: `PascalCase`

### EF Core Migrations

```bash
# Create migration
dotnet ef migrations add MigrationName \
  --project src/ProjectName.Infrastructure \
  --startup-project src/ProjectName.Api

# Apply migration
dotnet ef database update \
  --project src/ProjectName.Infrastructure \
  --startup-project src/ProjectName.Api

# Generate SQL script
dotnet ef migrations script \
  --project src/ProjectName.Infrastructure \
  --startup-project src/ProjectName.Api \
  --output migration.sql
```

### Test Project — Compile-Safe

The generated `{ProjectName}.Tests.Unit` project:
- References both `{ProjectName}.Application` and `{ProjectName}.Domain`
- Uses `xUnit` + `NSubstitute` + `FluentAssertions` + `coverlet.collector`
- All tests follow **AAA pattern** (Arrange / Act / Assert)
- All tests follow **FIRST principles** (Fast, Isolated, Repeatable, Self-validating, Timely)
- Covers **border cases**: empty input, Guid.Empty, name too long, repository failures
- Compiles and runs `dotnet test` without errors

## Best Practices Applied

All generated code follows these standards:

- **Clean Architecture** — DTOs in Domain; Application references Domain only
- **OpenAPI Documentation** — Swagger with response attributes
- **Manual Mapping** — No AutoMapper; explicit `ToDto()` private methods in each service
- **Repository Pattern** — All DB access via `I{Entity}Repository` backed by a generic `IRepository<T>`
- **Unit of Work** — Shared `IUnitOfWork` (repository factory + `SaveChangesAsync` + transactions); persistence coordinated in the Application layer
- **Dapper** (when selected) — `DapperRepository<T>` + `DapperUnitOfWork`
- **Entity Framework Core** (when selected) — `DbContext` + `EFRepository<T>` + `EfUnitOfWork` + Fluent API + Migrations
- **Global Exception Handling** — Middleware-based; NotFoundException, ConflictException, ValidationException
- **Async/Await** — Throughout entire codebase
- **Dependency Injection** — Constructor injection everywhere
- **Unit Tests** — Compile-safe xUnit project generated alongside the solution

## Troubleshooting

If generation fails:
1. Check write permissions in output directory
2. Ensure valid project name (no special characters except dots/hyphens)
3. Confirm database choice is `postgresql` or `sqlserver`

If `dotnet build` shows NU1900 warnings about a private NuGet feed, those are expected in environments outside the corporate network and do not affect compilation.

If `dotnet ef` is not found (EF Core projects), install the EF Core tools:
```bash
dotnet tool install --global dotnet-ef
```
