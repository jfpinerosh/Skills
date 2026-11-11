---
name: dotnet-minimal-api-generator
description: Generate a minimal REST API project in C# (.NET 10) using ASP.NET Core Minimal APIs. Use when the user asks to "create a minimal API", "scaffold a minimal API in C#", "create a .NET minimal API project", "dotnet minimal API", "create a simple REST API with minimal APIs", or wants a lightweight REST API without controllers-heavy MVC or clean architecture layers. The skill asks for the project name plus the name of the DTO/entity and its properties with data types (e.g., 'Name:string, Price:decimal', defaulting to Todo), scaffolds a solution with src/ (API project with Controllers/, Interfaces/, Services/, Models/DTOs/, and Middleware/ folders) and tests/ (xUnit) at the same level, in-memory sample CRUD, Swagger UI, and verifies it builds and tests pass.
---

# .NET Minimal API Generator

## Overview

Generate a lightweight .NET 10 minimal REST API solution using ASP.NET Core Minimal APIs. No clean-architecture layers, no database, no external services — just a runnable API with a clear `src/` + `tests/` layout.

## Workflow

### Step 1: Gather Requirements (ONLY these questions — nothing else)

ALWAYS ask the user before generating:

1. **Project Name** (Required)
   - Ask: "What is the name of your project? (e.g., 'MyMinimalApi', 'TodoApi')"
   - Validate: PascalCase letters/digits only (no spaces, dots, or hyphens). If invalid, ask again.

2. **Entity / DTO Name** (Optional — default: `Todo`)
   - Ask: "What is the name of the entity/DTO to scaffold? (e.g., 'Product', 'Customer' — press Enter for the default 'Todo')"
   - Validate: PascalCase letters/digits only. Defaults to `Todo` if empty.

3. **Entity Properties** (Optional — default: `Title:string,IsCompleted:bool`)
   - Ask: "Which properties should it have? Provide `name:type` pairs separated by commas (e.g., 'Name:string, Price:decimal' — press Enter for the default 'Title:string, IsCompleted:bool')"
   - Parse comma-separated `name:type` pairs; property names in PascalCase.
   - Supported data types (case-insensitive input):

     | Input | C# type | Entity initializer |
     |---|---|---|
     | `string`, `text` | `string` | `= string.Empty;` |
     | `int`, `integer` | `int` | none |
     | `long` | `long` | none |
     | `decimal`, `money` | `decimal` | none |
     | `double` | `double` | none |
     | `bool`, `boolean` | `bool` | none |
     | `datetime`, `date` | `DateTime` | none |
     | `guid` | `Guid` | none |

   - If the user already provided any of these in their request, do NOT ask again — use what they gave.
   - Do NOT ask about database, ORM, or external services. Use the defaults defined in this skill.

If the user answers nothing for 2 and 3, generate the default `Todo` entity exactly as shown in the templates below (they are already written for `Todo` with `Title:string, IsCompleted:bool`). For any other entity, apply the substitution rules in section 4.0.

### Step 2: Scaffold the Solution

Run the following commands from the output directory:

```powershell
# API project inside src/
dotnet new web -n {ProjectName} -o src/{ProjectName} -f net10.0
dotnet add src/{ProjectName} package Microsoft.AspNetCore.OpenApi
dotnet add src/{ProjectName} package Swashbuckle.AspNetCore.SwaggerUI

# Test project inside tests/ (same level as src/)
dotnet new xunit -n {ProjectName}.Tests -o tests/{ProjectName}.Tests -f net10.0
dotnet add tests/{ProjectName}.Tests reference src/{ProjectName}
Remove-Item "tests/{ProjectName}.Tests/UnitTest1.cs"

# Solution tying both projects together
dotnet new sln -n {ProjectName}
dotnet sln add src/{ProjectName} tests/{ProjectName}.Tests
```

NOTE: with the .NET 10 SDK, `dotnet new sln` creates `{ProjectName}.slnx` (the XML solution format). On older SDKs it creates `{ProjectName}.sln`. Either is fine — run `dotnet build` / `dotnet test` from the solution root and MSBuild locates the file automatically.

Then create the folders:

```powershell
New-Item -ItemType Directory -Path `
  "src/{ProjectName}/Controllers",`
  "src/{ProjectName}/Interfaces",`
  "src/{ProjectName}/Services",`
  "src/{ProjectName}/Models/DTOs",`
  "src/{ProjectName}/Middleware",`
  "tests/{ProjectName}.Tests/Services"
```

### Step 3: Expected Folder Structure

```
{ProjectName}/
├── {ProjectName}.slnx             # solution (.sln on SDKs < 10)
├── src/
│   └── {ProjectName}/
│       ├── Program.cs               # DI wiring, AddOpenApi(), route group registration
│       ├── {ProjectName}.csproj     # net10.0 + Microsoft.AspNetCore.OpenApi + SwaggerUI
│       ├── appsettings.json
│       ├── appsettings.Development.json
│       ├── Properties/launchSettings.json
│       ├── Controllers/             # TodoController.cs — MapGet/MapPost/MapPut/MapDelete route group
│       ├── Interfaces/              # ITodoService.cs
│       ├── Services/                # TodoService.cs (in-memory CRUD implementation)
│       ├── Models/                  # Todo.cs (entity)
│       │   └── DTOs/                # TodoDtos.cs (TodoDto, CreateTodoDto, UpdateTodoDto)
│       └── Middleware/              # ExceptionHandlingMiddleware.cs
├── tests/
│   └── {ProjectName}.Tests/
│       ├── {ProjectName}.Tests.csproj   # xUnit, references src/{ProjectName}
│       └── Services/TodoServiceTests.cs
└── README.md
```

### Step 4: Generate the Code Files

Overwrite/create each file with EXACTLY the templates below, replacing `{ProjectName}` with the actual project name. The templates are written for the default `Todo` entity (`Title:string, IsCompleted:bool`). If the user chose a different entity/properties, ALSO apply the substitution rules in 4.0.

#### 4.0 Entity Substitution Rules

Apply these rules to every template when the entity is not `Todo` (file names follow too: `Models/{Entity}.cs`, `Models/DTOs/{Entity}Dtos.cs`, `Interfaces/I{Entity}Service.cs`, `Services/{Entity}Service.cs`, `Controllers/{Entity}Controller.cs`, `tests/.../Services/{Entity}ServiceTests.cs`):

**Identifier substitutions:**

| Template text | Replace with |
|---|---|
| `Todo` (class/record/DTO names, e.g. `TodoDto`, `CreateTodoDto`) | `{Entity}` equivalents (`{Entity}Dto`, `Create{Entity}Dto`) |
| `TodoService`, `ITodoService` | `{Entity}Service`, `I{Entity}Service` |
| `TodoController`, `MapTodoEndpoints` | `{Entity}Controller`, `Map{Entity}Endpoints` |
| `TodoServiceTests` | `{Entity}ServiceTests` |
| `_todos` | `_{entity}s` (camelCase plural) |
| `todo` (local variables) | `{entity}` (camelCase) |
| `/api/todos` | `/api/{plural}` — `{plural}` = entity name lowercased + `s` (e.g., `Product` → `/api/products`). For irregular plurals (ends in `y` → `ies`, ends in `s/x/ch/sh` → `es`), use the correct English plural (e.g., `Category` → `/api/categories`) |
| `"Todos"` (WithTags) | `"{Entity}s"` |
| `TodoDto` JSON route name prefixes (`GetTodoById`, etc.) | `Get{Entity}ById`, etc. |

**Property substitutions** — the templates hardcode `Title` (string) and `IsCompleted` (bool). Replace them with the user's properties in EVERY place they appear:

1. **Entity (`Models/{Entity}.cs`)** — one auto-property per user property, between `Id` and `CreatedAt`:
   - `string` properties: `public string {PropName} { get; set; } = string.Empty;`
   - value-type properties: `public {PropType} {PropName} { get; set; }`
2. **DTOs (`Models/DTOs/{Entity}Dtos.cs`)** — positional record parameters:
   - `{Entity}Dto(Guid Id, {all user props with types}, DateTime CreatedAt)`
   - `Create{Entity}Dto({user props with types})`
   - `Update{Entity}Dto({user props with types})`
3. **Service** — `Create` initializes every property (`new {Entity} { {Prop} = dto.{Prop}, ... }`), `Update` assigns every property (`{entity}.{Prop} = dto.{Prop};`), and `ToDto` maps every property.
4. **Controller validation** — generate a `string.IsNullOrWhiteSpace` check + `ValidationProblem` entry for EACH `string` property in the Create and Update handlers. If the entity has NO string properties, remove the validation blocks entirely and drop `ProducesValidationProblem()` from those endpoints.
5. **Tests** — construct DTOs with sample values for each property and assert on the first two properties. Use sensible sample values: strings → `"..."`, decimals → `9.99m`, ints → `10`, bools → `true`, DateTime → `DateTime.UtcNow`, Guid → `Guid.NewGuid()`.

**Worked example** — entity `Product` with `Name:string, Price:decimal, Stock:int`:

```csharp
// Models/Product.cs
public class Product
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string Name { get; set; } = string.Empty;
    public decimal Price { get; set; }
    public int Stock { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}

// Models/DTOs/ProductDtos.cs
public record ProductDto(Guid Id, string Name, decimal Price, int Stock, DateTime CreatedAt);
public record CreateProductDto(string Name, decimal Price, int Stock);
public record UpdateProductDto(string Name, decimal Price, int Stock);

// Services/ProductService.cs (Create + ToDto)
public ProductDto Create(CreateProductDto dto)
{
    var product = new Product { Name = dto.Name, Price = dto.Price, Stock = dto.Stock };
    _products[product.Id] = product;
    return ToDto(product);
}

private static ProductDto ToDto(Product product) =>
    new(product.Id, product.Name, product.Price, product.Stock, product.CreatedAt);

// Controllers/ProductController.cs (route + validation for the string property)
var group = app.MapGroup("/api/products")
    .WithTags("Products");

if (string.IsNullOrWhiteSpace(dto.Name))
    return TypedResults.ValidationProblem(
        new Dictionary<string, string[]>
        {
            ["name"] = ["Name is required."]
        });
```

#### 4.1 `src/{ProjectName}/Models/Todo.cs`

```csharp
namespace {ProjectName}.Models;

public class Todo
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string Title { get; set; } = string.Empty;
    public bool IsCompleted { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}
```

#### 4.2 `src/{ProjectName}/Models/DTOs/TodoDtos.cs`

```csharp
namespace {ProjectName}.Models.DTOs;

public record TodoDto(Guid Id, string Title, bool IsCompleted, DateTime CreatedAt);
public record CreateTodoDto(string Title);
public record UpdateTodoDto(string Title, bool IsCompleted);
```

#### 4.3 `src/{ProjectName}/Interfaces/ITodoService.cs`

```csharp
using {ProjectName}.Models.DTOs;

namespace {ProjectName}.Interfaces;

public interface ITodoService
{
    IEnumerable<TodoDto> GetAll();
    TodoDto? GetById(Guid id);
    TodoDto Create(CreateTodoDto dto);
    TodoDto? Update(Guid id, UpdateTodoDto dto);
    bool Delete(Guid id);
}
```

#### 4.4 `src/{ProjectName}/Services/TodoService.cs`

In-memory implementation using `ConcurrentDictionary`:

```csharp
using System.Collections.Concurrent;
using {ProjectName}.Interfaces;
using {ProjectName}.Models;
using {ProjectName}.Models.DTOs;

namespace {ProjectName}.Services;

public class TodoService : ITodoService
{
    private readonly ConcurrentDictionary<Guid, Todo> _todos = new();

    public IEnumerable<TodoDto> GetAll() =>
        _todos.Values
            .OrderBy(t => t.CreatedAt)
            .Select(ToDto);

    public TodoDto? GetById(Guid id) =>
        _todos.TryGetValue(id, out var todo) ? ToDto(todo) : null;

    public TodoDto Create(CreateTodoDto dto)
    {
        var todo = new Todo { Title = dto.Title };
        _todos[todo.Id] = todo;
        return ToDto(todo);
    }

    public TodoDto? Update(Guid id, UpdateTodoDto dto)
    {
        if (!_todos.TryGetValue(id, out var todo))
            return null;

        todo.Title = dto.Title;
        todo.IsCompleted = dto.IsCompleted;
        return ToDto(todo);
    }

    public bool Delete(Guid id) => _todos.TryRemove(id, out _);

    private static TodoDto ToDto(Todo todo) =>
        new(todo.Id, todo.Title, todo.IsCompleted, todo.CreatedAt);
}
```

#### 4.5 `src/{ProjectName}/Controllers/TodoController.cs`

Minimal-API style route group (NOT an MVC `[ApiController]` class). The class is static, holds the endpoint mapping extension, and lives in `Controllers/` by convention:

```csharp
using {ProjectName}.Interfaces;
using {ProjectName}.Models.DTOs;
using Microsoft.AspNetCore.Http.HttpResults;

namespace {ProjectName}.Controllers;

public static class TodoController
{
    public static IEndpointRouteBuilder MapTodoEndpoints(this IEndpointRouteBuilder app)
    {
        var group = app.MapGroup("/api/todos")
            .WithTags("Todos");

        group.MapGet("/", GetAllTodos)
            .WithName("GetAllTodos")
            .Produces<List<TodoDto>>(StatusCodes.Status200OK);

        group.MapGet("/{id:guid}", GetTodoById)
            .WithName("GetTodoById")
            .Produces<TodoDto>(StatusCodes.Status200OK)
            .Produces(StatusCodes.Status404NotFound);

        group.MapPost("/", CreateTodo)
            .WithName("CreateTodo")
            .Accepts<CreateTodoDto>("application/json")
            .ProducesValidationProblem()
            .Produces<TodoDto>(StatusCodes.Status201Created);

        group.MapPut("/{id:guid}", UpdateTodo)
            .WithName("UpdateTodo")
            .Accepts<UpdateTodoDto>("application/json")
            .ProducesValidationProblem()
            .Produces<TodoDto>(StatusCodes.Status200OK)
            .Produces(StatusCodes.Status404NotFound);

        group.MapDelete("/{id:guid}", DeleteTodo)
            .WithName("DeleteTodo")
            .Produces(StatusCodes.Status204NoContent)
            .Produces(StatusCodes.Status404NotFound);

        return app;
    }

    private static Ok<List<TodoDto>> GetAllTodos(ITodoService service) =>
        TypedResults.Ok(service.GetAll().ToList());

    private static Results<Ok<TodoDto>, NotFound> GetTodoById(Guid id, ITodoService service) =>
        service.GetById(id) is { } todo
            ? TypedResults.Ok(todo)
            : TypedResults.NotFound();

    private static Results<CreatedAtRoute<TodoDto>, ValidationProblem> CreateTodo(
        CreateTodoDto dto, ITodoService service)
    {
        if (string.IsNullOrWhiteSpace(dto.Title))
            return TypedResults.ValidationProblem(
                new Dictionary<string, string[]>
                {
                    ["title"] = ["Title is required."]
                });

        var created = service.Create(dto);
        return TypedResults.CreatedAtRoute(
            created, "GetTodoById", new { id = created.Id });
    }

    private static Results<Ok<TodoDto>, NotFound, ValidationProblem> UpdateTodo(
        Guid id, UpdateTodoDto dto, ITodoService service)
    {
        if (string.IsNullOrWhiteSpace(dto.Title))
            return TypedResults.ValidationProblem(
                new Dictionary<string, string[]>
                {
                    ["title"] = ["Title is required."]
                });

        return service.Update(id, dto) is { } todo
            ? TypedResults.Ok(todo)
            : TypedResults.NotFound();
    }

    private static Results<NoContent, NotFound> DeleteTodo(Guid id, ITodoService service) =>
        service.Delete(id)
            ? TypedResults.NoContent()
            : TypedResults.NotFound();
    }
}
```

#### 4.6 `src/{ProjectName}/Middleware/ExceptionHandlingMiddleware.cs`

```csharp
namespace {ProjectName}.Middleware;

public class ExceptionHandlingMiddleware
{
    private readonly RequestDelegate _next;
    private readonly ILogger<ExceptionHandlingMiddleware> _logger;

    public ExceptionHandlingMiddleware(
        RequestDelegate next, ILogger<ExceptionHandlingMiddleware> logger)
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
        catch (Exception ex)
        {
            _logger.LogError(ex, "Unhandled exception for {Method} {Path}",
                context.Request.Method, context.Request.Path);

            context.Response.StatusCode = StatusCodes.Status500InternalServerError;
            context.Response.ContentType = "application/json";
            await context.Response.WriteAsJsonAsync(
                new { error = "An unexpected error occurred." });
        }
    }
}

public static class ExceptionHandlingMiddlewareExtensions
{
    public static IApplicationBuilder UseExceptionHandling(this IApplicationBuilder app) =>
        app.UseMiddleware<ExceptionHandlingMiddleware>();
}
```

#### 4.7 `src/{ProjectName}/Program.cs` (overwrite the scaffolded one)

```csharp
using {ProjectName}.Controllers;
using {ProjectName}.Interfaces;
using {ProjectName}.Middleware;
using {ProjectName}.Services;

var builder = WebApplication.CreateBuilder(args);

// Services / DI
builder.Services.AddSingleton<ITodoService, TodoService>();

// OpenAPI
builder.Services.AddOpenApi();

var app = builder.Build();

// Middleware pipeline
app.UseExceptionHandling();

if (app.Environment.IsDevelopment())
{
    app.MapOpenApi();       // /openapi/v1.json
    app.UseSwaggerUI(options =>
    {
        options.SwaggerEndpoint("/openapi/v1.json", "v1");
    });
}

// Endpoint groups
app.MapTodoEndpoints();

app.Run();
```

#### 4.8 `tests/{ProjectName}.Tests/Services/TodoServiceTests.cs`

xUnit tests following the AAA pattern (Arrange / Act / Assert):

```csharp
using {ProjectName}.Models.DTOs;
using {ProjectName}.Services;
using Xunit;

namespace {ProjectName}.Tests.Services;

public class TodoServiceTests
{
    private readonly TodoService _service = new();

    [Fact]
    public void Create_WithValidTitle_ReturnsTodoDto()
    {
        var dto = new CreateTodoDto("Write tests");

        var result = _service.Create(dto);

        Assert.Equal("Write tests", result.Title);
        Assert.False(result.IsCompleted);
    }

    [Fact]
    public void GetById_WithUnknownId_ReturnsNull()
    {
        var result = _service.GetById(Guid.NewGuid());

        Assert.Null(result);
    }

    [Fact]
    public void Update_WithExistingId_UpdatesFields()
    {
        var created = _service.Create(new CreateTodoDto("Old title"));

        var result = _service.Update(created.Id, new UpdateTodoDto("New title", true));

        Assert.NotNull(result);
        Assert.Equal("New title", result!.Title);
        Assert.True(result.IsCompleted);
    }

    [Fact]
    public void Delete_WithExistingId_ReturnsTrueAndRemovesTodo()
    {
        var created = _service.Create(new CreateTodoDto("To delete"));

        var deleted = _service.Delete(created.Id);

        Assert.True(deleted);
        Assert.Null(_service.GetById(created.Id));
    }
}
```

#### 4.9 `README.md`

```markdown
# {ProjectName}

Minimal REST API built with ASP.NET Core Minimal APIs (.NET 10).

## Run

​```bash
dotnet run --project src/{ProjectName}
​``​

- API base: http://localhost:5000/api/todos (see console output for the actual port)
- Swagger UI (Development only): http://localhost:PORT/swagger

## Endpoints

| Method   | Route             | Description        |
| -------- | ----------------- | ------------------ |
| GET      | /api/todos        | List all todos     |
| GET      | /api/todos/{id}   | Get todo by id     |
| POST     | /api/todos        | Create a todo      |
| PUT      | /api/todos/{id}   | Update a todo      |
| DELETE   | /api/todos/{id}   | Delete a todo      |

## Structure

- `{ProjectName}.slnx` — solution file tying both projects together (.sln on SDKs < 10)
- `src/{ProjectName}/` — the API project
  - `Controllers/` — endpoint route groups (minimal API style)
  - `Interfaces/` — service abstractions
  - `Services/` — business logic (in-memory storage)
  - `Models/` — entities
  - `Models/DTOs/` — data transfer objects
  - `Middleware/` — global exception handling
- `tests/{ProjectName}.Tests/` — xUnit unit tests

## Tests

​```bash
dotnet test
​``​
```

(Note: when writing README.md, use real triple-backtick fences — the escaped ones above are only to nest them inside this skill file.)

### Step 5: Verify

1. From the solution root, run `dotnet build` — MUST succeed with no errors.
2. Run `dotnet test` — MUST pass (all generated tests: 4 with the default entity).
3. If build or tests fail, fix the issues before reporting to the user.
4. Optionally confirm structure matches Step 3.

### Step 6: Report to the User

```markdown
## Project {ProjectName} generated successfully!

### Structure created:
{ProjectName}.slnx — solution file (.sln on SDKs < 10)
src/{ProjectName}/ — Controllers/ · Interfaces/ · Services/ · Models/DTOs/ · Middleware/
tests/{ProjectName}.Tests/ — xUnit unit tests

### Next steps:
1. `cd {ProjectName}`
2. `dotnet run --project src/{ProjectName}`
3. Open the Swagger UI URL shown in the console (Development only)
4. `dotnet test` to run the unit tests

### Quick test:
curl -X POST http://localhost:PORT/api/todos \
     -H "Content-Type: application/json" \
     -d '{"title": "My first todo"}'
```

## Conventions

- **Minimal API style** — endpoint groups via extension methods (`Map{Entity}Endpoints`), typed `Results<T>`, no `[ApiController]` classes
- **Custom entity support** — entity name and properties (name + data type) are asked in Step 1; `Todo` with `Title:string, IsCompleted:bool` is the default
- **Interface segregation** — abstractions in `Interfaces/`, implementations in `Services/`
- **DTO separation** — entities in `Models/`, DTOs in `Models/DTOs/` under the `{ProjectName}.Models.DTOs` namespace
- **DI** — constructor/method injection; `AddSingleton` for in-memory storage
- **Async-free on purpose** — in-memory service uses sync methods to stay minimal; switch to async when a database is added
- **No database, no external services** — this skill is intentionally minimal; suggest the `rest-api-generator` skill if the user later needs a database, Dapper/EF Core, or clean architecture

## Troubleshooting

- If `dotnet new web` does not accept `-f net10.0`, verify the installed SDK with `dotnet --version` and use the closest available target framework
- If `UseSwaggerUI` fails to resolve, confirm the `Swashbuckle.AspNetCore.SwaggerUI` package was added
- If the port is unknown, check `src/{ProjectName}/Properties/launchSettings.json` for the configured applicationUrl
- If the solution file is `.slnx` and a tool rejects it, either run `dotnet build`/`dotnet test` without arguments (they locate it automatically) or target the project files directly (e.g., `dotnet build src/{ProjectName}`)
