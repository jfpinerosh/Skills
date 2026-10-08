# Database Patterns and Configuration

## PostgreSQL Configuration

### Connection String
```
Host=localhost;Database=mydb;Username=postgres;Password=yourpassword
```

### DbContext Setup
```csharp
builder.Services.AddDbContext<ApplicationDbContext>(options =>
    options.UseNpgsql(connectionString, npgsqlOptions =>
    {
        npgsqlOptions.EnableRetryOnFailure(
            maxRetryCount: 3,
            maxRetryDelay: TimeSpan.FromSeconds(5),
            errorCodesToAdd: null);
        npgsqlOptions.CommandTimeout(30);
    }));
```

### Naming Conventions
- Tables: `snake_case` (e.g., `order_items`)
- Columns: `snake_case` (e.g., `created_at`)
- Indexes: `idx_{table}_{column}`

### Entity Configuration Example
```csharp
builder.Property(e => e.CreatedAt)
    .HasColumnName("created_at")
    .IsRequired();
```

## SQL Server Configuration

### Connection String
```
Server=localhost;Database=mydb;User Id=sa;Password=yourpassword;TrustServerCertificate=True
```

### DbContext Setup
```csharp
builder.Services.AddDbContext<ApplicationDbContext>(options =>
    options.UseSqlServer(connectionString, sqlOptions =>
    {
        sqlOptions.EnableRetryOnFailure(
            maxRetryCount: 3,
            maxRetryDelay: TimeSpan.FromSeconds(5),
            errorNumbersToAdd: null);
        sqlOptions.CommandTimeout(30);
    }));
```

### Naming Conventions
- Tables: `PascalCase` (e.g., `OrderItems`)
- Columns: `PascalCase` (e.g., `CreatedAt`)
- Use standard SQL Server naming

## Cosmos DB Configuration

### Connection String
```
AccountEndpoint=https://your-account.documents.azure.com:443/;AccountKey=your-key==
```

### DbContext Setup
```csharp
builder.Services.AddDbContext<ApplicationDbContext>(options =>
    options.UseCosmos(
        accountEndpoint: "https://your-account.documents.azure.com:443/",
        accountKey: "your-key",
        databaseName: "DatabaseName"));
```

### Special Considerations
- Define partition keys
- Use optimistic concurrency
- Consider eventual consistency
- Minimize cross-partition queries

## Migration Commands

### Create Migration
```bash
dotnet ef migrations add MigrationName \
  --project src/ProjectName.Infrastructure \
  --startup-project src/ProjectName.Functions
```

### Apply Migration
```bash
dotnet ef database update \
  --project src/ProjectName.Infrastructure \
  --startup-project src/ProjectName.Functions
```

### Remove Last Migration
```bash
dotnet ef migrations remove \
  --project src/ProjectName.Infrastructure \
  --startup-project src/ProjectName.Functions
```

### Generate SQL Script
```bash
dotnet ef migrations script \
  --project src/ProjectName.Infrastructure \
  --startup-project src/ProjectName.Functions \
  --output migration.sql
```

## Performance Optimization

### Indexing Strategy
- Index foreign keys
- Index frequently filtered columns
- Composite indexes for complex queries
- Don't over-index (impacts write performance)

### Query Optimization
- Use AsNoTracking() for read-only queries
- Project to DTOs directly in queries
- Avoid N+1 queries (use Include/ThenInclude)
- Use compiled queries for repeated operations

### Connection Pooling
- Enabled by default in EF Core
- Configure max pool size if needed
- Monitor connection usage
- Properly dispose DbContext (use DI with scoped lifetime)