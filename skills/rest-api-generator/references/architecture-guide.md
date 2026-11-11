# REST API Architecture Guide

## Clean Architecture Layers

### API Layer (Controller Layer)
Purpose Handle HTTP requests only
Responsibilities
- Receive HTTP requests via REST controllers
- Extract route/query/body parameters
- Delegate to Application Layer
- Return HTTP responses with proper status codes
- NO business logic

### Application Layer
Purpose Business logic orchestration
Responsibilities
- Coordinate workflows
- Data transformation (Entity ↔ DTO)
- Input validation with FluentValidation
- Transaction management
- Call repositories and external services

### Domain Layer
Purpose Core business logic
Responsibilities
- Domain entities (business models)
- Business rules and invariants
- Repository interfaces (contracts)
- Domain services
- Value objects
- NO infrastructure dependencies

### Infrastructure Layer
Purpose Technical implementation details
Responsibilities
- Database access (EF Core)
- Repository implementations
- Third-party API clients
- File system operations
- Caching
- External service integrations

## Dependency Flow

```
Api → Application → Domain ← Infrastructure
```

- Api depends on Application
- Application depends on Domain
- Infrastructure depends on Domain
- Domain has NO dependencies (pure business logic)

## Best Practices

### Slim Controllers Pattern
Controllers should ONLY
1. Receive the HTTP request
2. Extract request data
3. Call application service
4. Return HTTP response (`Ok`, `Created`, `NoContent`)

### Repository Pattern
- Define interfaces in Domain layer
- Implement in Infrastructure layer
- Always use async operations
- Return entities, not DTOs
- The generic contract is `IRepository<T>` (`GetByIdAsync`, `FindAsync(predicate)`, `GetAllAsync`, `CreateAsync`, `UpdateAsync`, `DeleteAsync`, `ExecuteAsync(rawSql, parameters)`)
- Entity-specific repositories (`I{Entity}Repository`) compose the generic repository through the Unit of Work

### Unit of Work Pattern
- `IUnitOfWork` lives in `Domain/Interfaces/Repository` and is implemented per engine (`DapperUnitOfWork`, `EfUnitOfWork`)
- Exposes `Repository<T>()`, `SaveChangesAsync()`, `BeginTransactionAsync()`, `CommitTransactionAsync()`, `RollbackAsync()`
- Repositories never commit; the Application service opens the transaction, calls `SaveChangesAsync()`, then `CommitTransactionAsync()`, and calls `RollbackAsync()` on failure
- EF Core: `SaveChangesAsync()` flushes the `DbContext`; Dapper: statements execute immediately and `SaveChangesAsync()` is a no-op (`0`)
- `CommitTransactionAsync()` commits the active transaction for both engines

### DTO Pattern
- Never expose domain entities directly via API
- Use DTOs for data transfer
- Use manual mapping (explicit `ToDto()` methods), no AutoMapper
- Separate DTOs for CreateUpdate operations

### Exception Handling
- Use custom exceptions (NotFoundException, ConflictException)
- Let middleware handle all exceptions globally
- Return appropriate HTTP status codes
- Log exceptions with proper severity

### Validation
- Use FluentValidation for all input
- Validate in Application layer
- Return 400 Bad Request for validation failures
- Include detailed error messages

## Database Patterns

### PostgreSQL Best Practices
- Use snake_case for column names
- Enable retry on failure (3 attempts)
- Set command timeout (30 seconds)
- Use connection pooling
- Index foreign keys and frequently queried columns

### Entity Configuration
- Use IEntityTypeConfiguration for each entity
- Configure in InfrastructureDataConfigurations
- Define relationships explicitly
- Set constraints and indexes

### Migrations
- Create meaningful migration names
- Review generated migration code
- Test migrations on development database
- Never modify existing migrations in production