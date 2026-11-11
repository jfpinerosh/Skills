<#
.SYNOPSIS
    Generates a .NET 10 ASP.NET Core REST API project with clean architecture.

.DESCRIPTION
    Creates a complete project structure with REST controllers, FluentValidation,
    repository pattern, and unit tests. Supports Dapper or Entity Framework Core
    as the data access layer.

.PARAMETER ProjectName
    Full project name (e.g., 'MyCompany.OrdersApi').

.PARAMETER Database
    Database engine: 'postgresql' (default) or 'sqlserver'.

.PARAMETER ORM
    ORM choice: 'dapper' (default) or 'efcore'.

.PARAMETER Services
    Comma-separated list of third-party service names (optional).

.PARAMETER Entity
    Sample entity name (default: 'Item').

.PARAMETER EntityProperties
    Comma-separated 'Name:type' pairs (default: 'Name:string,Description:string').
    Supported types: string, int, decimal, bool, DateTime, Guid.

.PARAMETER OutputPath
    Where to create the project (default: current directory).

.EXAMPLE
    .\generate_project.ps1 -ProjectName "MyCompany.OrdersApi" -Database postgresql -Orm dapper -Entity "Order" -EntityProperties "CustomerName:string,TotalAmount:decimal,Quantity:int"
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectName,

    [ValidateSet("postgresql", "sqlserver")]
    [string]$Database = "postgresql",

    [ValidateSet("dapper", "efcore")]
    [string]$Orm = "dapper",

    [string]$Services,

    [string]$Entity = "Item",

    [string]$EntityProperties = "Name:string,Description:string",

    [string]$OutputPath = "."
)

$ErrorActionPreference = "Stop"

# ── Parse entity properties ───────────────────────────────────────
function ConvertFrom-PropertyString {
    param([string]$PropertyString)

    $properties = @()
    foreach ($entry in ($PropertyString -split ',')) {
        $parts = $entry.Trim() -split ':'
        if ($parts.Count -ne 2) { continue }
        $name = $parts[0].Trim()
        $type = $parts[1].Trim().ToLower()
        $csharpType = switch ($type) {
            "string"   { "string" }
            "int"      { "int" }
            "decimal"  { "decimal" }
            "bool"     { "bool" }
            "datetime" { "DateTime" }
            "guid"     { "Guid" }
            default    { "string" }
        }
        $defaultValue = switch ($type) {
            "string"   { ' = string.Empty;' }
            "int"      { "" }
            "decimal"  { "" }
            "bool"     { "" }
            "datetime" { "" }
            "guid"     { "" }
            default    { ' = string.Empty;' }
        }
        $properties += [PSCustomObject]@{
            Name         = $name
            DataType     = $type
            CSharpType   = $csharpType
            DefaultValue = $defaultValue
        }
    }
    return $properties
}

# ── File writer ────────────────────────────────────────────────────
function Write-ProjectFile {
    param(
        [string]$BasePath,
        [string]$RelativePath,
        [string]$Content
    )
    $fullPath = Join-Path $BasePath $RelativePath
    $dir = Split-Path $fullPath -Parent
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    Set-Content -Path $fullPath -Value $Content -Encoding UTF8 -NoNewline
    Write-Host "   + $RelativePath"
}

# ── Type mapping helpers ──────────────────────────────────────────
function Get-DbConnectorPackage {
    param([string]$Db)
    switch ($Db) {
        "sqlserver" { return '<PackageReference Include="Microsoft.Data.SqlClient" Version="6.0.2" />' }
        default     { return '<PackageReference Include="Npgsql" Version="10.0.1" />' }
    }
}

function Get-EfProviderPackage {
    param([string]$Db)
    switch ($Db) {
        "sqlserver" { return '<PackageReference Include="Microsoft.EntityFrameworkCore.SqlServer" Version="10.0.0" />' }
        default     { return '<PackageReference Include="Npgsql.EntityFrameworkCore.PostgreSQL" Version="10.0.0" />' }
    }
}

function Get-ConnectionStringTemplate {
    param([string]$Db)
    switch ($Db) {
        "sqlserver" { return "Server=localhost;Database=mydb;User Id=sa;Password=yourpassword;TrustServerCertificate=True" }
        default     { return "Host=localhost;Database=mydb;Username=postgres;Password=yourpassword" }
    }
}

function Get-DatabasePrerequisite {
    param([string]$Db)
    switch ($Db) {
        "sqlserver" { return "SQL Server 2019+" }
        default     { return "PostgreSQL 14+" }
    }
}

function Get-DapperRegistration {
    param([string]$Db)
    switch ($Db) {
        "sqlserver" { return "AddSqlServerMultiTenant();" }
        default     { return "AddPostgresMultiTenant();" }
    }
}

function Get-EfDbContextRegistration {
    param([string]$Db)
    switch ($Db) {
        "sqlserver" {
            return @"
builder.Services.AddDbContext<ApplicationDbContext>(options =>
    options.UseSqlServer(connectionString, sqlOptions =>
    {
        sqlOptions.EnableRetryOnFailure(maxRetryCount: 3, maxRetryDelay: TimeSpan.FromSeconds(5), errorNumbersToAdd: null);
        sqlOptions.CommandTimeout(30);
    }));
"@
        }
        default {
            return @"
builder.Services.AddDbContext<ApplicationDbContext>(options =>
    options.UseNpgsql(connectionString, npgsqlOptions =>
    {
        npgsqlOptions.EnableRetryOnFailure(maxRetryCount: 3, maxRetryDelay: TimeSpan.FromSeconds(5), errorCodesToAdd: null);
        npgsqlOptions.CommandTimeout(30);
    }));
"@
        }
    }
}

# ── Property code generators ─────────────────────────────────────
function Build-EntityProperties {
    param($Properties)
    $lines = @()
    foreach ($p in $Properties) {
        $lines += "    public $($p.CSharpType) $($p.Name) { get; set; }$($p.DefaultValue)"
    }
    return ($lines -join "`n")
}

function Build-DtoProperties {
    param($Properties)
    $lines = @()
    foreach ($p in $Properties) {
        $lines += "    public $($p.CSharpType) $($p.Name) { get; init; }$($p.DefaultValue)"
    }
    return ($lines -join "`n")
}

function Build-CreateDtoProperties {
    param($Properties)
    $lines = @()
    foreach ($p in $Properties) {
        $lines += "    public $($p.CSharpType) $($p.Name) { get; init; }$($p.DefaultValue)"
    }
    return ($lines -join "`n")
}

function Build-ValidatorRules {
    param($Properties)
    $lines = @()
    $first = $true
    foreach ($p in $Properties) {
        if (-not $first) { $lines += "" }
        $first = $false
        switch ($p.DataType) {
            "string" {
                $lines += "        RuleFor(x => x.$($p.Name))"
                $lines += "            .NotEmpty().WithMessage(`"$($p.Name) is required`")"
                $lines += "            .MaximumLength(200).WithMessage(`"$($p.Name) must not exceed 200 characters`");"
            }
            "int" {
                $lines += "        RuleFor(x => x.$($p.Name))"
                $lines += "            .GreaterThanOrEqualTo(0).WithMessage(`"$($p.Name) must not be negative`");"
            }
            "decimal" {
                $lines += "        RuleFor(x => x.$($p.Name))"
                $lines += "            .GreaterThan(0).WithMessage(`"$($p.Name) must be greater than 0`");"
            }
        }
    }
    return ($lines -join "`n")
}

function Build-ToDtoMapping {
    param($Properties, [string]$EntityLower)
    $lines = @()
    $lines += "        Id = ${EntityLower}.Id,"
    foreach ($p in $Properties) {
        $lines += "        $($p.Name) = ${EntityLower}.$($p.Name),"
    }
    $lines += "        Status = ${EntityLower}.Status.ToString(),"
    $lines += "        CreatedAt = ${EntityLower}.CreatedAt"
    return ($lines -join "`n")
}

function Build-CreateAssignment {
    param($Properties)
    $lines = @()
    foreach ($p in $Properties) {
        $lines += "            $($p.Name) = dto.$($p.Name),"
    }
    return ($lines -join "`n")
}

function Build-DtoTestProperties {
    param($Properties)
    $lines = @()
    foreach ($p in $Properties) {
        $val = switch ($p.DataType) {
            "string"   { "`"Test$($p.Name)`"" }
            "int"      { "42" }
            "decimal"  { "99.99m" }
            "bool"     { "true" }
            "datetime" { "DateTime.UtcNow" }
            "guid"     { "Guid.NewGuid()" }
            default    { "`"Test$($p.Name)`"" }
        }
        $lines += "            $($p.Name) = $val,"
    }
    return ($lines -join "`n")
}

function Build-DtoCreateEmptyProperties {
    param($Properties)
    $lines = @()
    foreach ($p in $Properties) {
        $val = switch ($p.DataType) {
            "string"   { "string.Empty" }
            "int"      { "0" }
            "decimal"  { "0m" }
            "bool"     { "false" }
            "datetime" { "DateTime.MinValue" }
            "guid"     { "Guid.Empty" }
            default    { "string.Empty" }
        }
        $lines += "            $($p.Name) = $val,"
    }
    return ($lines -join "`n")
}

# ── Generate .csproj files ────────────────────────────────────────
function New-ApiCsproj {
    return @"
<Project Sdk="Microsoft.NET.Sdk.Web">
  <PropertyGroup>
    <TargetFramework>net10.0</TargetFramework>
    <ImplicitUsings>enable</ImplicitUsings>
    <Nullable>enable</Nullable>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="Swashbuckle.AspNetCore" Version="7.0.0" />
    <PackageReference Include="Microsoft.ApplicationInsights.AspNetCore" Version="2.22.0" />
    <PackageReference Include="Microsoft.Extensions.Logging.Abstractions" Version="10.0.2" />
  </ItemGroup>
  <ItemGroup>
    <ProjectReference Include="..\$ProjectName.Application\$ProjectName.Application.csproj" />
    <ProjectReference Include="..\$ProjectName.Infrastructure\$ProjectName.Infrastructure.csproj" />
  </ItemGroup>
</Project>
"@
}

function New-ApplicationCsproj {
    return @"
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net10.0</TargetFramework>
    <ImplicitUsings>enable</ImplicitUsings>
    <Nullable>enable</Nullable>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="FluentValidation" Version="12.1.1" />
    <PackageReference Include="FluentValidation.DependencyInjectionExtensions" Version="12.1.1" />
    <PackageReference Include="Microsoft.Extensions.Logging.Abstractions" Version="10.0.2" />
  </ItemGroup>
  <ItemGroup>
    <ProjectReference Include="..\$ProjectName.Domain\$ProjectName.Domain.csproj" />
  </ItemGroup>
</Project>
"@
}

function New-DomainCsproj {
    return @"
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net10.0</TargetFramework>
    <ImplicitUsings>enable</ImplicitUsings>
    <Nullable>enable</Nullable>
  </PropertyGroup>
</Project>
"@
}

function New-InfrastructureCsproj {
    param([string]$OrmChoice, [string]$DbChoice)

    $providerPkg = Get-EfProviderPackage -Db $DbChoice
    $connectorPkg = Get-DbConnectorPackage -Db $DbChoice

    if ($OrmChoice -eq "efcore") {
        $ormPackages = @"
    <PackageReference Include="Microsoft.EntityFrameworkCore" Version="10.0.0" />
    <PackageReference Include="Microsoft.EntityFrameworkCore.Tools" Version="10.0.0" />
    $providerPkg
"@
    }
    else {
        $ormPackages = @"
    <PackageReference Include="Dapper" Version="2.1.66" />
    <PackageReference Include="Dapper.Contrib" Version="2.0.78" />
    $connectorPkg
"@
    }

    return @"
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net10.0</TargetFramework>
    <ImplicitUsings>enable</ImplicitUsings>
    <Nullable>enable</Nullable>
  </PropertyGroup>
  <ItemGroup>
$ormPackages
    <PackageReference Include="Microsoft.Extensions.Http.Polly" Version="10.0.2" />
    <PackageReference Include="Polly" Version="8.6.5" />
    <PackageReference Include="Microsoft.Extensions.Logging.Abstractions" Version="10.0.2" />
  </ItemGroup>
  <ItemGroup>
    <ProjectReference Include="..\$ProjectName.Domain\$ProjectName.Domain.csproj" />
  </ItemGroup>
</Project>
"@
}

function New-TestsCsproj {
    return @"
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net10.0</TargetFramework>
    <ImplicitUsings>enable</ImplicitUsings>
    <Nullable>enable</Nullable>
    <IsPackable>false</IsPackable>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="Microsoft.NET.Test.Sdk" Version="17.14.0" />
    <PackageReference Include="xunit" Version="2.9.3" />
    <PackageReference Include="xunit.runner.visualstudio" Version="2.8.2">
      <IncludeAssets>runtime; build; native; contentfiles; analyzers; buildtransitive</IncludeAssets>
      <PrivateAssets>all</PrivateAssets>
    </PackageReference>
    <PackageReference Include="NSubstitute" Version="5.3.0" />
    <PackageReference Include="FluentAssertions" Version="8.4.0" />
    <PackageReference Include="coverlet.collector" Version="6.0.4">
      <IncludeAssets>runtime; build; native; contentfiles; analyzers; buildtransitive</IncludeAssets>
      <PrivateAssets>all</PrivateAssets>
    </PackageReference>
  </ItemGroup>
  <ItemGroup>
    <ProjectReference Include="..\..\src\$ProjectName.Application\$ProjectName.Application.csproj" />
    <ProjectReference Include="..\..\src\$ProjectName.Domain\$ProjectName.Domain.csproj" />
  </ItemGroup>
</Project>
"@
}

# ── Generate API layer ────────────────────────────────────────────
function New-ProgramCs {
    param([string]$OrmChoice, [string]$DbChoice)

    if ($OrmChoice -eq "efcore") {
        $efRegistration = Get-EfDbContextRegistration -Db $DbChoice
        $dbRegistration = @"
// Database (EF Core)
var connectionString = builder.Configuration.GetConnectionString("DatabaseConnectionString");
$efRegistration

// Unit of Work
builder.Services.AddScoped<IUnitOfWork, EfUnitOfWork>();
"@
    }
    else {
        $dapperReg = Get-DapperRegistration -Db $DbChoice
        $dbRegistration = @"
// Database (Dapper)
builder.Services.$dapperReg
"@
    }

    $servicesReg = ""
    if ($Services) {
        $svcLines = @("// External Services")
        foreach ($svc in ($Services -split ',')) {
            $safeName = $svc.Trim().Replace(' ', '')
            $svcLines += "builder.Services.AddHttpClient<I${safeName}Service, ${safeName}Service>(client =>"
            $svcLines += "{"
            $svcLines += "    client.BaseAddress = new Uri(builder.Configuration[`"${safeName}:BaseUrl`"]!);"
            $svcLines += "    client.Timeout = TimeSpan.FromSeconds(30);"
            $svcLines += "});"
        }
        $servicesReg = ($svcLines -join "`n") + "`n"
    }

    $externalUsing = ""
    if ($Services) {
        $externalUsing = "using $ProjectName.Infrastructure.ExternalServices;"
    }

    $infraUsing = if ($OrmChoice -eq "efcore") {
        "using Microsoft.EntityFrameworkCore;`nusing $ProjectName.Infrastructure.Data;"
    }
    else {
        "using $ProjectName.Infrastructure.Data.Configurations;"
    }

    return @"
using $ProjectName.Application.Services;
using $ProjectName.Application.Validators;
using $ProjectName.Domain.Interfaces;
using $ProjectName.Domain.Interfaces.Repository;
using $ProjectName.Infrastructure.Repositories;
$externalUsing
$infraUsing
using $ProjectName.Api.Middleware;
using FluentValidation;

var builder = WebApplication.CreateBuilder(args);

// Controllers + Swagger
builder.Services.AddControllers();
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen(options =>
{
    options.SwaggerDoc("v1", new() { Title = "$ProjectName", Version = "v1" });
});

$dbRegistration

// Repositories
builder.Services.AddScoped<I${Entity}Repository, ${Entity}Repository>();

// Application Services
builder.Services.AddScoped<I${Entity}Service, ${Entity}Service>();

// FluentValidation
builder.Services.AddValidatorsFromAssemblyContaining<Create${Entity}DtoValidator>();
$servicesReg
// Application Insights
builder.Services.AddApplicationInsightsTelemetry();

var app = builder.Build();

if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

app.UseHttpsRedirection();
app.UseMiddleware<ExceptionHandlingMiddleware>();
app.UseAuthorization();
app.MapControllers();

app.Run();
"@
}

function New-Middleware {
    return @"
using System.Net;
using FluentValidation;
using $ProjectName.Application.Exceptions;

namespace $ProjectName.Api.Middleware;

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

    private static async Task HandleValidationExceptionAsync(HttpContext context, ValidationException exception)
    {
        context.Response.StatusCode = (int)HttpStatusCode.BadRequest;
        context.Response.ContentType = "application/json";

        var errors = exception.Errors
            .GroupBy(e => e.PropertyName)
            .ToDictionary(g => g.Key, g => g.Select(e => e.ErrorMessage).ToArray());

        await context.Response.WriteAsJsonAsync(new { message = "Validation failed", errors });
    }

    private static async Task HandleExceptionAsync(HttpContext context, HttpStatusCode statusCode, string message)
    {
        context.Response.StatusCode = (int)statusCode;
        context.Response.ContentType = "application/json";
        await context.Response.WriteAsJsonAsync(new { message, statusCode = (int)statusCode });
    }
}
"@
}

function New-Controller {
    $entityLower = $Entity.ToLower()
    return @"
using Microsoft.AspNetCore.Mvc;
using $ProjectName.Application.Services;
using $ProjectName.Domain.DTOs;

namespace $ProjectName.Api.Controllers;

[ApiController]
[Route("api/[controller]")]
[Produces("application/json")]
public class ${Entity}sController : ControllerBase
{
    private readonly I${Entity}Service _${entityLower}Service;
    private readonly ILogger<${Entity}sController> _logger;

    public ${Entity}sController(I${Entity}Service ${entityLower}Service, ILogger<${Entity}sController> logger)
    {
        _${entityLower}Service = ${entityLower}Service;
        _logger = logger;
    }

    /// <summary>Get all ${Entity}s</summary>
    [HttpGet]
    [ProducesResponseType(typeof(IEnumerable<${Entity}Dto>), StatusCodes.Status200OK)]
    public async Task<IActionResult> GetAll${Entity}s()
    {
        _logger.LogInformation("GET all ${Entity}s");
        var result = await _${entityLower}Service.GetAll${Entity}sAsync();
        return Ok(result);
    }

    /// <summary>Get a ${Entity} by ID</summary>
    [HttpGet("{id:guid}")]
    [ProducesResponseType(typeof(${Entity}Dto), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> Get${Entity}(Guid id)
    {
        _logger.LogInformation("GET ${Entity} by ID: {Id}", id);
        var result = await _${entityLower}Service.Get${Entity}ByIdAsync(id);
        return Ok(result);
    }

    /// <summary>Create a new ${Entity}</summary>
    [HttpPost]
    [ProducesResponseType(typeof(${Entity}Dto), StatusCodes.Status201Created)]
    [ProducesResponseType(typeof(ValidationProblemDetails), StatusCodes.Status400BadRequest)]
    public async Task<IActionResult> Create${Entity}([FromBody] Create${Entity}Dto dto)
    {
        _logger.LogInformation("POST create ${Entity}");
        var result = await _${entityLower}Service.Create${Entity}Async(dto);
        return CreatedAtAction(nameof(Get${Entity}), new { id = result.Id }, result);
    }

    /// <summary>Delete a ${Entity}</summary>
    [HttpDelete("{id:guid}")]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> Delete${Entity}(Guid id)
    {
        _logger.LogInformation("DELETE ${Entity}: {Id}", id);
        await _${entityLower}Service.Delete${Entity}Async(id);
        return NoContent();
    }
}
"@
}

# ── Generate Application layer ────────────────────────────────────
function New-Exceptions {
    return @"
namespace $ProjectName.Application.Exceptions;

public class NotFoundException : Exception
{
    public NotFoundException(string message) : base(message) { }
}

public class ConflictException : Exception
{
    public ConflictException(string message) : base(message) { }
    public ConflictException(string message, Exception innerException) : base(message, innerException) { }
}
"@
}

function New-Service {
    $entityLower = $Entity.ToLower()
    $props = ConvertFrom-PropertyString -PropertyString $EntityProperties
    $toDtoMapping = Build-ToDtoMapping -Properties $props -EntityLower $entityLower
    $createAssignment = Build-CreateAssignment -Properties $props

    return @"
using FluentValidation;
using $ProjectName.Application.Exceptions;
using $ProjectName.Domain.DTOs;
using $ProjectName.Domain.Entities;
using $ProjectName.Domain.Enums;
using $ProjectName.Domain.Interfaces;
using $ProjectName.Domain.Interfaces.Repository;
using Microsoft.Extensions.Logging;

namespace $ProjectName.Application.Services;

public interface I${Entity}Service
{
    Task<IEnumerable<${Entity}Dto>> GetAll${Entity}sAsync();
    Task<${Entity}Dto> Get${Entity}ByIdAsync(Guid id);
    Task<${Entity}Dto> Create${Entity}Async(Create${Entity}Dto dto);
    Task Delete${Entity}Async(Guid id);
}

public class ${Entity}Service : I${Entity}Service
{
    private readonly I${Entity}Repository _${entityLower}Repository;
    private readonly IUnitOfWork _unitOfWork;
    private readonly IValidator<Create${Entity}Dto> _validator;
    private readonly ILogger<${Entity}Service> _logger;

    public ${Entity}Service(
        I${Entity}Repository ${entityLower}Repository,
        IUnitOfWork unitOfWork,
        IValidator<Create${Entity}Dto> validator,
        ILogger<${Entity}Service> logger)
    {
        _${entityLower}Repository = ${entityLower}Repository;
        _unitOfWork = unitOfWork;
        _validator = validator;
        _logger = logger;
    }

    public async Task<IEnumerable<${Entity}Dto>> GetAll${Entity}sAsync()
    {
        var items = await _${entityLower}Repository.GetAllAsync();
        return items.Select(ToDto);
    }

    public async Task<${Entity}Dto> Get${Entity}ByIdAsync(Guid id)
    {
        var ${entityLower} = await _${entityLower}Repository.GetByIdAsync(id);
        if (${entityLower} is null)
            throw new NotFoundException("${Entity} with ID {id} not found");

        return ToDto(${entityLower});
    }

    public async Task<${Entity}Dto> Create${Entity}Async(Create${Entity}Dto dto)
    {
        var validation = await _validator.ValidateAsync(dto);
        if (!validation.IsValid)
            throw new ValidationException(validation.Errors);

        var ${entityLower} = new ${Entity}
        {
            Id = Guid.NewGuid(),
$createAssignment
            Status = ${Entity}Status.Active,
            CreatedAt = DateTime.UtcNow
        };

        await _unitOfWork.BeginTransactionAsync();
        try
        {
            await _${entityLower}Repository.CreateAsync(${entityLower});
            await _unitOfWork.SaveChangesAsync();
            await _unitOfWork.CommitTransactionAsync();
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error creating ${Entity}");
            await _unitOfWork.RollbackAsync();
            throw;
        }

        _logger.LogInformation("${Entity} created with ID: {Id}", ${entityLower}.Id);
        return ToDto(${entityLower});
    }

    public async Task Delete${Entity}Async(Guid id)
    {
        var existing = await _${entityLower}Repository.GetByIdAsync(id);
        if (existing is null)
            throw new NotFoundException("${Entity} with ID {id} not found");

        await _unitOfWork.BeginTransactionAsync();
        try
        {
            await _${entityLower}Repository.DeleteAsync(id);
            await _unitOfWork.SaveChangesAsync();
            await _unitOfWork.CommitTransactionAsync();
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error deleting ${Entity} {Id}", id);
            await _unitOfWork.RollbackAsync();
            throw;
        }

        _logger.LogInformation("${Entity} deleted with ID: {Id}", id);
    }

    // -- Manual mapping --
    private static ${Entity}Dto ToDto(${Entity} ${entityLower}) => new()
    {
$toDtoMapping
    };
}
"@
}

function New-Validator {
    $props = ConvertFrom-PropertyString -PropertyString $EntityProperties
    $rules = Build-ValidatorRules -Properties $props

    return @"
using FluentValidation;
using $ProjectName.Domain.DTOs;

namespace $ProjectName.Application.Validators;

public class Create${Entity}DtoValidator : AbstractValidator<Create${Entity}Dto>
{
    public Create${Entity}DtoValidator()
    {
$rules
    }
}
"@
}

# ── Generate Domain layer ─────────────────────────────────────────
function New-Entity {
    $props = ConvertFrom-PropertyString -PropertyString $EntityProperties
    $entityProps = Build-EntityProperties -Properties $props

    return @"
using $ProjectName.Domain.Enums;

namespace $ProjectName.Domain.Entities;

public class $Entity
{
    public Guid Id { get; set; }
$entityProps
    public ${Entity}Status Status { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime? UpdatedAt { get; set; }
}
"@
}

function New-Dtos {
    $props = ConvertFrom-PropertyString -PropertyString $EntityProperties
    $dtoProps = Build-DtoProperties -Properties $props
    $createDtoProps = Build-CreateDtoProperties -Properties $props

    return @"
namespace $ProjectName.Domain.DTOs;

public record ${Entity}Dto
{
    public Guid Id { get; init; }
$dtoProps
    public string Status { get; init; } = string.Empty;
    public DateTime CreatedAt { get; init; }
}

public record Create${Entity}Dto
{
$createDtoProps
}
"@
}

function New-Enum {
    return @"
namespace $ProjectName.Domain.Enums;

public enum ${Entity}Status
{
    Active,
    Inactive,
    Pending
}
"@
}

function New-RepositoryInterface {
    return @"
using $ProjectName.Domain.Entities;

namespace $ProjectName.Domain.Interfaces;

public interface I${Entity}Repository
{
    Task<${Entity}?> GetByIdAsync(Guid id);
    Task<IEnumerable<${Entity}>> GetAllAsync();
    Task<bool> CreateAsync(${Entity} entity);
    Task<bool> UpdateAsync(${Entity} entity);
    Task<bool> DeleteAsync(Guid id);
}
"@
}

function New-SharedInterfaces {
    $repository = @"
using System.Linq.Expressions;

namespace $ProjectName.Domain.Interfaces.Repository;

public interface IRepository<T> where T : class
{
    Task<T?> GetByIdAsync(Guid id);
    Task<T?> FindAsync(Expression<Func<T, bool>> predicate, CancellationToken cancellationToken = default);
    Task<IEnumerable<T>> GetAllAsync();
    Task<bool> CreateAsync(T entity);
    Task<bool> UpdateAsync(T entity);
    Task<bool> DeleteAsync(Guid id);
    Task<int> ExecuteAsync(string sql, object? parameters = null, CancellationToken cancellationToken = default);
}
"@

    $unitOfWork = @"
namespace $ProjectName.Domain.Interfaces.Repository;

public interface IUnitOfWork : IAsyncDisposable
{
    IRepository<T> Repository<T>() where T : class;
    Task<int> SaveChangesAsync(CancellationToken cancellationToken = default);
    Task BeginTransactionAsync(CancellationToken cancellationToken = default);
    Task CommitTransactionAsync(CancellationToken cancellationToken = default);
    Task RollbackAsync(CancellationToken cancellationToken = default);
}
"@

    return @{
        Repository = $repository
        UnitOfWork = $unitOfWork
    }
}

function New-DapperInterfaces {
    $connectionFactory = @"
using System.Data;

namespace $ProjectName.Domain.Interfaces.Data;

public interface ITenantConnectionFactory
{
    Task<IDbConnection> CreateConnectionAsync();
}
"@

    return @{
        ConnectionFactory = $connectionFactory
    }
}

# ── Generate Infrastructure layer ─────────────────────────────────
function New-TenantConnectionFactory {
    if ($Database -eq 'sqlserver') {
        $usingLine = "using Microsoft.Data.SqlClient;"
        $connectionLine = "var connection = new SqlConnection(connectionString);"
    }
    else {
        $usingLine = "using Npgsql;"
        $connectionLine = "var connection = new NpgsqlConnection(connectionString);"
    }

    return @"
$usingLine
using $ProjectName.Domain.Interfaces.Data;
using Microsoft.Extensions.Configuration;
using System.Data;

namespace $ProjectName.Infrastructure.Data;

public class TenantConnectionFactory : ITenantConnectionFactory
{
    private readonly IConfiguration _configuration;

    public TenantConnectionFactory(IConfiguration configuration)
    {
        _configuration = configuration;
    }

    public async Task<IDbConnection> CreateConnectionAsync()
    {
        var connectionString = _configuration.GetConnectionString("DatabaseConnectionString")
            ?? throw new InvalidOperationException("DatabaseConnectionString is not configured.");

        $connectionLine
        await connection.OpenAsync();
        return connection;
    }
}
"@
}

function New-ServiceCollectionExtensions {
    $methodName = if ($Database -eq 'postgresql') { "AddPostgresMultiTenant" } else { "AddSqlServerMultiTenant" }

    return @"
using $ProjectName.Domain.Interfaces.Data;
using $ProjectName.Domain.Interfaces.Repository;
using $ProjectName.Infrastructure.Data;
using $ProjectName.Infrastructure.Repositories;
using Microsoft.Extensions.DependencyInjection;

namespace $ProjectName.Infrastructure.Data.Configurations;

public static class ServiceCollectionExtensions
{
    public static IServiceCollection ${methodName}(this IServiceCollection services)
    {
        services.AddScoped<ITenantConnectionFactory, TenantConnectionFactory>();
        services.AddScoped<IUnitOfWork, DapperUnitOfWork>();
        return services;
    }
}
"@
}

function New-DapperRepository {
    return @"
using Dapper;
using Dapper.Contrib.Extensions;
using $ProjectName.Domain.Interfaces.Repository;
using System.Data;
using System.Linq.Expressions;

namespace $ProjectName.Infrastructure.Repositories;

public class DapperRepository<T> : IRepository<T> where T : class
{
    private readonly DapperUnitOfWork _uow;

    private static readonly string _tableName =
        typeof(T).GetCustomAttributes(typeof(TableAttribute), inherit: false)
                 .OfType<TableAttribute>()
                 .FirstOrDefault()?.Name
        ?? typeof(T).Name.ToLowerInvariant();

    public DapperRepository(DapperUnitOfWork uow) => _uow = uow;

    private IDbConnection Conn => _uow.Connection;
    private IDbTransaction? Tx => _uow.Transaction;

    public async Task<T?> GetByIdAsync(Guid id) =>
        await Conn.QueryFirstOrDefaultAsync<T>(
            $"SELECT * FROM {_tableName} WHERE id = @Id", new { Id = id }, Tx);

    public async Task<T?> FindAsync(Expression<Func<T, bool>> predicate, CancellationToken cancellationToken = default)
    {
        var all = await GetAllAsync();
        return all.FirstOrDefault(predicate.Compile());
    }

    public async Task<IEnumerable<T>> GetAllAsync() =>
        await Conn.QueryAsync<T>($"SELECT * FROM {_tableName}", transaction: Tx);

    public async Task<bool> CreateAsync(T entity)
    {
        await _uow.EnsureTransactionAsync();
        await Conn.InsertAsync(entity, _uow.Transaction);
        return true;
    }

    public async Task<bool> UpdateAsync(T entity)
    {
        await _uow.EnsureTransactionAsync();
        await Conn.UpdateAsync(entity, _uow.Transaction);
        return true;
    }

    public async Task<bool> DeleteAsync(Guid id)
    {
        await _uow.EnsureTransactionAsync();
        var rows = await Conn.ExecuteAsync(
            $"DELETE FROM {_tableName} WHERE id = @Id", new { Id = id }, _uow.Transaction);
        return rows > 0;
    }

    public async Task<int> ExecuteAsync(string sql, object? parameters = null, CancellationToken cancellationToken = default) =>
        await Conn.ExecuteAsync(new CommandDefinition(sql, parameters, _uow.Transaction, cancellationToken: cancellationToken));
}
"@
}

function New-DapperUnitOfWork {
    return @"
using $ProjectName.Domain.Interfaces.Data;
using $ProjectName.Domain.Interfaces.Repository;
using System.Data;

namespace $ProjectName.Infrastructure.Repositories;

public sealed class DapperUnitOfWork : IUnitOfWork
{
    private readonly ITenantConnectionFactory _connectionFactory;
    private readonly Dictionary<Type, object> _repositories = [];

    public IDbConnection Connection { get; private set; } = default!;
    public IDbTransaction? Transaction { get; private set; }

    public DapperUnitOfWork(ITenantConnectionFactory connectionFactory)
    {
        _connectionFactory = connectionFactory;
    }

    internal async Task<IDbConnection> EnsureConnectionAsync()
    {
        if (Connection is null || Connection.State != ConnectionState.Open)
            Connection = await _connectionFactory.CreateConnectionAsync();
        return Connection;
    }

    internal async Task<IDbTransaction> EnsureTransactionAsync()
    {
        var connection = await EnsureConnectionAsync();
        Transaction ??= connection.BeginTransaction();
        return Transaction;
    }

    public IRepository<T> Repository<T>() where T : class
    {
        var type = typeof(T);
        if (!_repositories.TryGetValue(type, out var repo))
        {
            repo = new DapperRepository<T>(this);
            _repositories[type] = repo;
        }
        return (IRepository<T>)repo;
    }

    public Task<int> SaveChangesAsync(CancellationToken cancellationToken = default)
    {
        return Task.FromResult(0);
    }

    public async Task BeginTransactionAsync(CancellationToken cancellationToken = default)
    {
        await EnsureTransactionAsync();
    }

    public Task CommitTransactionAsync(CancellationToken cancellationToken = default)
    {
        Transaction?.Commit();
        Transaction?.Dispose();
        Transaction = null;
        return Task.CompletedTask;
    }

    public Task RollbackAsync(CancellationToken cancellationToken = default)
    {
        Transaction?.Rollback();
        Transaction?.Dispose();
        Transaction = null;
        return Task.CompletedTask;
    }

    public async ValueTask DisposeAsync()
    {
        Transaction?.Dispose();
        Connection?.Dispose();
        await ValueTask.CompletedTask;
    }
}
"@
}

function New-EfUnitOfWork {
    return @"
using $ProjectName.Domain.Interfaces.Repository;
using $ProjectName.Infrastructure.Data;
using Microsoft.EntityFrameworkCore.Storage;

namespace $ProjectName.Infrastructure.Repositories;

public sealed class EfUnitOfWork : IUnitOfWork
{
    private readonly ApplicationDbContext _context;
    private readonly Dictionary<Type, object> _repositories = [];
    private IDbContextTransaction? _transaction;

    public EfUnitOfWork(ApplicationDbContext context) => _context = context;

    public IRepository<T> Repository<T>() where T : class
    {
        var type = typeof(T);
        if (!_repositories.TryGetValue(type, out var repo))
        {
            repo = new EFRepository<T>(_context);
            _repositories[type] = repo;
        }
        return (IRepository<T>)repo;
    }

    public Task<int> SaveChangesAsync(CancellationToken cancellationToken = default) =>
        _context.SaveChangesAsync(cancellationToken);

    public async Task BeginTransactionAsync(CancellationToken cancellationToken = default)
    {
        _transaction ??= await _context.Database.BeginTransactionAsync(cancellationToken);
    }

    public async Task CommitTransactionAsync(CancellationToken cancellationToken = default)
    {
        if (_transaction is null) return;

        await _transaction.CommitAsync(cancellationToken);
        await _transaction.DisposeAsync();
        _transaction = null;
    }

    public async Task RollbackAsync(CancellationToken cancellationToken = default)
    {
        if (_transaction is null) return;

        await _transaction.RollbackAsync(cancellationToken);
        await _transaction.DisposeAsync();
        _transaction = null;
    }

    public async ValueTask DisposeAsync()
    {
        if (_transaction is not null)
        {
            await _transaction.RollbackAsync();
            await _transaction.DisposeAsync();
            _transaction = null;
        }
    }
}
"@
}

function New-ApplicationDbContext {
    return @"
using Microsoft.EntityFrameworkCore;
using $ProjectName.Domain.Entities;
using $ProjectName.Infrastructure.Data.Configurations;

namespace $ProjectName.Infrastructure.Data;

public class ApplicationDbContext : DbContext
{
    public ApplicationDbContext(DbContextOptions<ApplicationDbContext> options) : base(options) { }

    public DbSet<${Entity}> ${Entity}s => Set<${Entity}>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        base.OnModelCreating(modelBuilder);
        modelBuilder.ApplyConfiguration(new ${Entity}Configuration());
    }
}
"@
}

function New-EfEntityConfiguration {
    $props = ConvertFrom-PropertyString -PropertyString $EntityProperties
    $entityLower = $Entity.ToLower()
    $tableName = if ($Database -eq "postgresql") { "${entityLower}s" } else { "${Entity}s" }

    $propertyConfigs = @()
    foreach ($p in $props) {
        switch ($p.DataType) {
            "string" {
                $propertyConfigs += "        builder.Property(e => e.$($p.Name))"
                $propertyConfigs += "            .HasMaxLength(200)"
                $propertyConfigs += "            .IsRequired();"
            }
            "decimal" {
                $propertyConfigs += "        builder.Property(e => e.$($p.Name))"
                $propertyConfigs += "            .HasPrecision(18, 2);"
            }
        }
    }
    $propConfigBlock = ($propertyConfigs -join "`n")

    return @"
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using $ProjectName.Domain.Entities;

namespace $ProjectName.Infrastructure.Data.Configurations;

public class ${Entity}Configuration : IEntityTypeConfiguration<${Entity}>
{
    public void Configure(EntityTypeBuilder<${Entity}> builder)
    {
        builder.ToTable("$tableName");
        builder.HasKey(e => e.Id);

$propConfigBlock

        builder.Property(e => e.Status)
            .HasConversion<string>()
            .HasMaxLength(50);

        builder.Property(e => e.CreatedAt)
            .IsRequired();
    }
}
"@
}

function New-EfRepository {
    return @"
using Microsoft.EntityFrameworkCore;
using $ProjectName.Domain.Interfaces.Repository;
using $ProjectName.Infrastructure.Data;
using System.Linq.Expressions;

namespace $ProjectName.Infrastructure.Repositories;

public class EFRepository<T> : IRepository<T> where T : class
{
    protected readonly ApplicationDbContext _context;
    protected readonly DbSet<T> _dbSet;

    public EFRepository(ApplicationDbContext context)
    {
        _context = context;
        _dbSet = context.Set<T>();
    }

    public async Task<T?> GetByIdAsync(Guid id)
    {
        return await _dbSet.FindAsync(id);
    }

    public async Task<T?> FindAsync(Expression<Func<T, bool>> predicate, CancellationToken cancellationToken = default)
    {
        return await _dbSet.FirstOrDefaultAsync(predicate, cancellationToken);
    }

    public async Task<IEnumerable<T>> GetAllAsync()
    {
        return await _dbSet.ToListAsync();
    }

    public async Task<bool> CreateAsync(T entity)
    {
        await _dbSet.AddAsync(entity);
        return true;
    }

    public async Task<bool> UpdateAsync(T entity)
    {
        _dbSet.Update(entity);
        return true;
    }

    public async Task<bool> DeleteAsync(Guid id)
    {
        var entity = await _dbSet.FindAsync(id);
        if (entity is null) return false;

        _dbSet.Remove(entity);
        return true;
    }

    public async Task<int> ExecuteAsync(string sql, object? parameters = null, CancellationToken cancellationToken = default)
    {
        if (parameters is null)
            return await _context.Database.ExecuteSqlRawAsync(sql, cancellationToken);

        var values = parameters is IEnumerable<object> sequence ? sequence.ToArray() : [parameters];
        return await _context.Database.ExecuteSqlRawAsync(sql, values, cancellationToken);
    }
}
"@
}

function New-EntityRepository {
    $entityLower = $Entity.ToLower()

    return @"
using $ProjectName.Domain.Entities;
using $ProjectName.Domain.Interfaces;
using $ProjectName.Domain.Interfaces.Repository;
using Microsoft.Extensions.Logging;

namespace $ProjectName.Infrastructure.Repositories;

public class ${Entity}Repository : I${Entity}Repository
{
    private readonly IUnitOfWork _unitOfWork;
    private readonly ILogger<${Entity}Repository> _logger;

    public ${Entity}Repository(IUnitOfWork unitOfWork, ILogger<${Entity}Repository> logger)
    {
        _unitOfWork = unitOfWork;
        _logger = logger;
    }

    public async Task<${Entity}?> GetByIdAsync(Guid id)
    {
        try
        {
            return await _unitOfWork.Repository<${Entity}>().GetByIdAsync(id);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting ${Entity} by ID {Id}", id);
            throw;
        }
    }

    public async Task<IEnumerable<${Entity}>> GetAllAsync()
    {
        try
        {
            return await _unitOfWork.Repository<${Entity}>().GetAllAsync();
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting all ${Entity}s");
            throw;
        }
    }

    public async Task<bool> CreateAsync(${Entity} ${entityLower})
    {
        try
        {
            return await _unitOfWork.Repository<${Entity}>().CreateAsync(${entityLower});
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error creating ${Entity}");
            throw;
        }
    }

    public async Task<bool> UpdateAsync(${Entity} ${entityLower})
    {
        try
        {
            return await _unitOfWork.Repository<${Entity}>().UpdateAsync(${entityLower});
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error updating ${Entity}");
            throw;
        }
    }

    public async Task<bool> DeleteAsync(Guid id)
    {
        try
        {
            return await _unitOfWork.Repository<${Entity}>().DeleteAsync(id);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error deleting ${Entity} {Id}", id);
            throw;
        }
    }
}
"@
}

function New-ExternalService {
    param([string]$ServiceName)
    $safeName = $ServiceName.Trim().Replace(' ', '')

    return @"
using System.Net.Http.Json;
using Microsoft.Extensions.Logging;

namespace $ProjectName.Infrastructure.ExternalServices;

public interface I${safeName}Service
{
    Task<string> CallServiceAsync(string data);
}

public class ${safeName}Service : I${safeName}Service
{
    private readonly HttpClient _httpClient;
    private readonly ILogger<${safeName}Service> _logger;

    public ${safeName}Service(HttpClient httpClient, ILogger<${safeName}Service> logger)
    {
        _httpClient = httpClient;
        _logger = logger;
    }

    public async Task<string> CallServiceAsync(string data)
    {
        _logger.LogInformation("Calling ${ServiceName}...");

        var response = await _httpClient.PostAsJsonAsync("/api/endpoint", new { data });
        response.EnsureSuccessStatusCode();

        return await response.Content.ReadAsStringAsync();
    }
}
"@
}

# ── Generate Tests ────────────────────────────────────────────────
function New-ServiceTests {
    $entityLower = $Entity.ToLower()
    $props = ConvertFrom-PropertyString -PropertyString $EntityProperties

    $dtoTestProps = Build-DtoTestProperties -Properties $props
    $emptyDtoProps = Build-DtoCreateEmptyProperties -Properties $props
    $firstPropName = $props[0].Name
    $longStringProp = ($props | Where-Object { $_.DataType -eq "string" } | Select-Object -First 1).Name

    return @"
using FluentAssertions;
using NSubstitute;
using NSubstitute.ExceptionExtensions;
using Xunit;
using $ProjectName.Application.Exceptions;
using $ProjectName.Application.Services;
using $ProjectName.Application.Validators;
using $ProjectName.Domain.DTOs;
using $ProjectName.Domain.Entities;
using $ProjectName.Domain.Enums;
using $ProjectName.Domain.Interfaces;
using $ProjectName.Domain.Interfaces.Repository;
using Microsoft.Extensions.Logging;

namespace $ProjectName.Tests.Unit.Services;

public class ${Entity}ServiceTests
{
    private readonly I${Entity}Repository _${entityLower}Repository;
    private readonly IUnitOfWork _unitOfWork;
    private readonly ILogger<${Entity}Service> _logger;
    private readonly ${Entity}Service _sut;

    public ${Entity}ServiceTests()
    {
        _${entityLower}Repository = Substitute.For<I${Entity}Repository>();
        _unitOfWork = Substitute.For<IUnitOfWork>();
        _logger = Substitute.For<ILogger<${Entity}Service>>();
        var validator = new Create${Entity}DtoValidator();
        _sut = new ${Entity}Service(_${entityLower}Repository, _unitOfWork, validator, _logger);
    }

    // -- GetAll${Entity}sAsync --

    [Fact]
    public async Task GetAll${Entity}sAsync_WhenItemsExist_ReturnsAll()
    {
        var items = new List<${Entity}>
        {
            new() { Id = Guid.NewGuid(), ${firstPropName} = "Alpha", Status = ${Entity}Status.Active, CreatedAt = DateTime.UtcNow },
            new() { Id = Guid.NewGuid(), ${firstPropName} = "Beta",  Status = ${Entity}Status.Inactive, CreatedAt = DateTime.UtcNow }
        };
        _${entityLower}Repository.GetAllAsync().Returns(items);

        var result = await _sut.GetAll${Entity}sAsync();

        result.Should().HaveCount(2);
    }

    [Fact]
    public async Task GetAll${Entity}sAsync_WhenRepositoryReturnsEmpty_ReturnsEmptyList()
    {
        _${entityLower}Repository.GetAllAsync().Returns(Enumerable.Empty<${Entity}>());

        var result = await _sut.GetAll${Entity}sAsync();

        result.Should().BeEmpty();
    }

    [Fact]
    public async Task GetAll${Entity}sAsync_WhenRepositoryThrows_PropagatesException()
    {
        _${entityLower}Repository.GetAllAsync().ThrowsAsync(new Exception("DB error"));

        Func<Task> act = () => _sut.GetAll${Entity}sAsync();

        await act.Should().ThrowAsync<Exception>().WithMessage("DB error");
    }

    // -- Get${Entity}ByIdAsync --

    [Fact]
    public async Task Get${Entity}ByIdAsync_WhenEntityExists_ReturnsDto()
    {
        var id = Guid.NewGuid();
        var entity = new ${Entity} { Id = id, ${firstPropName} = "Test", Status = ${Entity}Status.Active, CreatedAt = DateTime.UtcNow };
        _${entityLower}Repository.GetByIdAsync(id).Returns(entity);

        var result = await _sut.Get${Entity}ByIdAsync(id);

        result.Id.Should().Be(id);
        result.${firstPropName}.Should().Be("Test");
    }

    [Fact]
    public async Task Get${Entity}ByIdAsync_WhenEntityNotFound_ThrowsNotFoundException()
    {
        var id = Guid.NewGuid();
        _${entityLower}Repository.GetByIdAsync(id).Returns((${Entity}?)null);

        Func<Task> act = () => _sut.Get${Entity}ByIdAsync(id);

        await act.Should().ThrowAsync<NotFoundException>();
    }

    [Fact]
    public async Task Get${Entity}ByIdAsync_WithEmptyGuid_ThrowsNotFoundException()
    {
        _${entityLower}Repository.GetByIdAsync(Guid.Empty).Returns((${Entity}?)null);

        Func<Task> act = () => _sut.Get${Entity}ByIdAsync(Guid.Empty);

        await act.Should().ThrowAsync<NotFoundException>();
    }

    // -- Create${Entity}Async --

    [Fact]
    public async Task Create${Entity}Async_WithValidDto_ReturnsCreatedDto()
    {
        var dto = new Create${Entity}Dto
        {
$dtoTestProps
        };
        _${entityLower}Repository.CreateAsync(Arg.Any<${Entity}>()).Returns(true);

        var result = await _sut.Create${Entity}Async(dto);

        result.${firstPropName}.Should().NotBeEmpty();
        await _${entityLower}Repository.Received(1).CreateAsync(Arg.Any<${Entity}>());
        await _unitOfWork.Received(1).SaveChangesAsync(Arg.Any<CancellationToken>());
        await _unitOfWork.Received(1).CommitTransactionAsync(Arg.Any<CancellationToken>());
    }

    [Fact]
    public async Task Create${Entity}Async_WithEmptyName_ThrowsValidationException()
    {
        var dto = new Create${Entity}Dto
        {
$emptyDtoProps
        };

        Func<Task> act = () => _sut.Create${Entity}Async(dto);

        await act.Should().ThrowAsync<FluentValidation.ValidationException>();
        await _${entityLower}Repository.DidNotReceive().CreateAsync(Arg.Any<${Entity}>());
    }

    [Fact]
    public async Task Create${Entity}Async_WithNameExceeding200Chars_ThrowsValidationException()
    {
        var dto = new Create${Entity}Dto
        {
            $longStringProp = new string('X', 201)
        };

        Func<Task> act = () => _sut.Create${Entity}Async(dto);

        await act.Should().ThrowAsync<FluentValidation.ValidationException>();
    }

    // -- Delete${Entity}Async --

    [Fact]
    public async Task Delete${Entity}Async_WhenEntityExists_DeletesSuccessfully()
    {
        var id = Guid.NewGuid();
        var entity = new ${Entity} { Id = id, ${firstPropName} = "To Delete", Status = ${Entity}Status.Active };
        _${entityLower}Repository.GetByIdAsync(id).Returns(entity);
        _${entityLower}Repository.DeleteAsync(id).Returns(true);

        await _sut.Delete${Entity}Async(id);

        await _${entityLower}Repository.Received(1).DeleteAsync(id);
        await _unitOfWork.Received(1).SaveChangesAsync(Arg.Any<CancellationToken>());
        await _unitOfWork.Received(1).CommitTransactionAsync(Arg.Any<CancellationToken>());
    }

    [Fact]
    public async Task Delete${Entity}Async_WhenEntityNotFound_ThrowsNotFoundException()
    {
        var id = Guid.NewGuid();
        _${entityLower}Repository.GetByIdAsync(id).Returns((${Entity}?)null);

        Func<Task> act = () => _sut.Delete${Entity}Async(id);

        await act.Should().ThrowAsync<NotFoundException>();
        await _${entityLower}Repository.DidNotReceive().DeleteAsync(Arg.Any<Guid>());
    }
}
"@
}

# ── Generate Solution file ────────────────────────────────────────
function New-SolutionFile {
    return @"
Microsoft Visual Studio Solution File, Format Version 12.00
# Visual Studio Version 17
VisualStudioVersion = 17.0.31903.59
MinimumVisualStudioVersion = 10.0.40219.1
Project("{2150E333-8FDC-42A3-9474-1A3956D46DE8}") = "src", "src", "{SRC-GUID}"
EndProject
Project("{2150E333-8FDC-42A3-9474-1A3956D46DE8}") = "tests", "tests", "{TESTS-GUID}"
EndProject
Project("{FAE04EC0-301F-11D3-BF4B-00C04F79EFBC}") = "$ProjectName.Api", "src\$ProjectName.Api\$ProjectName.Api.csproj", "{API-GUID}"
EndProject
Project("{FAE04EC0-301F-11D3-BF4B-00C04F79EFBC}") = "$ProjectName.Application", "src\$ProjectName.Application\$ProjectName.Application.csproj", "{APP-GUID}"
EndProject
Project("{FAE04EC0-301F-11D3-BF4B-00C04F79EFBC}") = "$ProjectName.Domain", "src\$ProjectName.Domain\$ProjectName.Domain.csproj", "{DOMAIN-GUID}"
EndProject
Project("{FAE04EC0-301F-11D3-BF4B-00C04F79EFBC}") = "$ProjectName.Infrastructure", "src\$ProjectName.Infrastructure\$ProjectName.Infrastructure.csproj", "{INFRA-GUID}"
EndProject
Project("{FAE04EC0-301F-11D3-BF4B-00C04F79EFBC}") = "$ProjectName.Tests.Unit", "tests\$ProjectName.Tests.Unit\$ProjectName.Tests.Unit.csproj", "{TESTS-UNIT-GUID}"
EndProject
Global
	GlobalSection(SolutionConfigurationPlatforms) = preSolution
		Debug|Any CPU = Debug|Any CPU
		Release|Any CPU = Release|Any CPU
	EndGlobalSection
	GlobalSection(SolutionProperties) = preSolution
		HideSolutionNode = FALSE
	EndGlobalSection
EndGlobal
"@
}

# ── Generate config files ─────────────────────────────────────────
function New-ConfigFiles {
    $connStr = Get-ConnectionStringTemplate -Db $Database

    $appsettings = @"
{
  "Logging": {
    "LogLevel": {
      "Default": "Information",
      "Microsoft.AspNetCore": "Warning"
    }
  },
  "AllowedHosts": "*",
  "ConnectionStrings": {
    "DatabaseConnectionString": "$connStr"
  },
  "ExternalServices": {
    "SampleApiBaseUrl": "https://api.example.com"
  }
}
"@

    $appsettingsDev = @"
{
  "Logging": {
    "LogLevel": {
      "Default": "Debug",
      "Microsoft.AspNetCore": "Information"
    }
  },
  "ConnectionStrings": {
    "DatabaseConnectionString": "$connStr"
  }
}
"@

    return @{
        AppSettings         = $appsettings
        AppSettingsDev      = $appsettingsDev
    }
}

# ── Generate README ───────────────────────────────────────────────
function New-Readme {
    $dbPrereq = Get-DatabasePrerequisite -Db $Database
    $entityLower = $Entity.ToLower()

    if ($Orm -eq "efcore") {
        $infraDesc = "EF Core DbContext, EFRepository<T>, EfUnitOfWork, Fluent API Configurations"
        $keyFiles = @"
- Program.cs - DI setup with Swagger, EF Core DbContext and the Unit of Work
- ${Entity}sController.cs - REST controllers with full CRUD
- ${Entity}Service.cs - Business logic with exception-based error handling (owns SaveChanges + commit)
- ApplicationDbContext.cs - EF Core DbContext with entity configurations
- ${Entity}Configuration.cs - Fluent API entity mapping
- IRepository.cs - Generic repository contract (CRUD + FindAsync + ExecuteAsync)
- IUnitOfWork.cs - Unit of Work contract (repository factory + SaveChanges + transactions)
- EFRepository.cs - Generic EF Core repository (IRepository<T>)
- EfUnitOfWork.cs - Unit of Work implementation
- ${Entity}Repository.cs - Entity-specific repository
- ${Entity}ServiceTests.cs - xUnit unit tests (AAA pattern, FIRST principles)
"@
        $nextSteps = @"
1. Restore packages: dotnet restore
2. Update connection string: Edit src/$ProjectName.Api/appsettings.Development.json
3. Create initial migration: dotnet ef migrations add InitialCreate --project src/$ProjectName.Infrastructure --startup-project src/$ProjectName.Api
4. Apply migration: dotnet ef database update --project src/$ProjectName.Infrastructure --startup-project src/$ProjectName.Api
5. Run the API: dotnet run in src/$ProjectName.Api
6. Browse Swagger UI: Open https://localhost:5001/swagger
"@
        $features = @"
- .NET 10 with C# 14
- ASP.NET Core Web API
- Clean Architecture
- RESTful API Standards
- Swagger / OpenAPI
- Entity Framework Core with $Database
- Fluent API entity configurations
- EF Core Migrations
- Repository + Unit of Work pattern (IRepository<T> / IUnitOfWork)
- SaveChanges + transaction coordination in the service layer
- Manual mapping (no AutoMapper)
- Exception-based error handling
- Global Exception Middleware
- FluentValidation
- xUnit + NSubstitute + FluentAssertions + Coverlet
"@
        $structure = @"
$ProjectName/
  src/
    $ProjectName.Api/             - Controllers + Middleware + Program.cs
    $ProjectName.Application/     - Services, Validators, Exceptions
    $ProjectName.Domain/          - Entities, Interfaces, DTOs, Enums
    $ProjectName.Infrastructure/  - EF Core DbContext, EFRepository
  tests/
    $ProjectName.Tests.Unit/      - xUnit + NSubstitute + FluentAssertions
  README.md
"@
    }
    else {
        $infraDesc = "Dapper, DapperRepository<T>, DapperUnitOfWork"
        $keyFiles = @"
- Program.cs - DI setup with Swagger and multi-tenant Dapper
- ${Entity}sController.cs - REST controllers with full CRUD
- ${Entity}Service.cs - Business logic with exception-based error handling (owns SaveChanges + commit)
- IRepository.cs - Generic repository contract (CRUD + FindAsync + ExecuteAsync)
- IUnitOfWork.cs - Unit of Work contract (repository factory + SaveChanges + transactions)
- DapperUnitOfWork.cs - Unit of Work (shared connection + transaction)
- ${Entity}Repository.cs - Dapper queries
- ${Entity}ServiceTests.cs - xUnit unit tests (AAA pattern, FIRST principles)
"@
        $nextSteps = @"
1. Restore packages: dotnet restore
2. Update connection string: Edit src/$ProjectName.Api/appsettings.Development.json
3. Update entity model: Modify ${Entity}.cs in Domain/Entities
4. Run the API: dotnet run in src/$ProjectName.Api
5. Browse Swagger UI: Open https://localhost:5001/swagger
"@
        $features = @"
- .NET 10 with C# 14
- ASP.NET Core Web API
- Clean Architecture
- RESTful API Standards
- Swagger / OpenAPI
- Dapper with $Database
- Repository + Unit of Work pattern (IRepository<T> / IUnitOfWork)
- SaveChanges + transaction coordination in the service layer
- Manual mapping (no AutoMapper)
- Exception-based error handling
- Global Exception Middleware
- FluentValidation
- xUnit + NSubstitute + FluentAssertions + Coverlet
"@
        $structure = @"
$ProjectName/
  src/
    $ProjectName.Api/             - Controllers + Middleware + Program.cs
    $ProjectName.Application/     - Services, Validators, Exceptions
    $ProjectName.Domain/          - Entities, Interfaces, DTOs, Enums
    $ProjectName.Infrastructure/  - Dapper Repositories
  tests/
    $ProjectName.Tests.Unit/      - xUnit + NSubstitute + FluentAssertions
  README.md
"@
    }

    $props = ConvertFrom-PropertyString -PropertyString $EntityProperties
    $firstPropName = $props[0].Name

    return @"
# $ProjectName

Production-ready .NET 10 REST API with Clean Architecture and ASP.NET Core.

## Architecture

| Layer | Responsibility |
|---|---|
| Api | REST Controllers + Middleware |
| Application | Business logic, FluentValidation, exception-based results, manual mapping |
| Domain | Entities, Interfaces, DTOs, Enums |
| Infrastructure | $infraDesc |
| Tests.Unit | xUnit + NSubstitute + FluentAssertions + Coverlet |

## Prerequisites

- .NET 10 SDK
- $dbPrereq

## Quick Start

$nextSteps

## Test the API

``````bash
# Create $Entity
curl -X POST https://localhost:5001/api/${entityLower}s -H "Content-Type: application/json" -d '{"${firstPropName}": "Test $Entity"}'

# Get all ${Entity}s
curl https://localhost:5001/api/${entityLower}s
``````

## Project Structure

$structure

## Key Files to Review

$keyFiles

## Key Features

$features

## Run Tests

``````bash
dotnet test --collect:"XPlat Code Coverage"
``````

## Configuration

Update appsettings.Development.json:
- ConnectionStrings:DatabaseConnectionString - Your $Database connection string

## Next Steps

1. Add more entities and controllers
2. Implement authentication/authorization (e.g., JWT Bearer)
3. Add more validators and test cases
4. Configure Application Insights
5. Set up CI/CD pipeline

## License

MIT
"@
}

# ══════════════════════════════════════════════════════════════════
# MAIN EXECUTION
# ══════════════════════════════════════════════════════════════════

$projectRoot = (Resolve-Path $OutputPath).Path
$projectRoot = Join-Path $projectRoot $ProjectName

Write-Host ""
Write-Host "Generating REST API Project: $ProjectName" -ForegroundColor Cyan
Write-Host "   Database: $Database"
Write-Host "   ORM: $Orm"
Write-Host "   Entity: $Entity"
Write-Host "   Properties: $EntityProperties"
if ($Services) { Write-Host "   Services: $Services" }
Write-Host ""

# ── Create directories ────────────────────────────────────────────
Write-Host "Creating directories..." -ForegroundColor Yellow

$dirs = @(
    "src/$ProjectName.Api/Controllers"
    "src/$ProjectName.Api/Middleware"
    "src/$ProjectName.Application/Services"
    "src/$ProjectName.Application/Exceptions"
    "src/$ProjectName.Application/Validators"
    "src/$ProjectName.Domain/DTOs"
    "src/$ProjectName.Domain/Entities"
    "src/$ProjectName.Domain/Interfaces"
    "src/$ProjectName.Domain/Interfaces/Repository"
    "src/$ProjectName.Domain/Enums"
    "src/$ProjectName.Infrastructure/Data"
    "src/$ProjectName.Infrastructure/Data/Configurations"
    "src/$ProjectName.Infrastructure/Repositories"
    "tests/$ProjectName.Tests.Unit/Services"
)

if ($Orm -eq "dapper") {
    $dirs += "src/$ProjectName.Domain/Interfaces/Data"
}

if ($Services) {
    $dirs += "src/$ProjectName.Infrastructure/ExternalServices"
}

foreach ($dir in $dirs) {
    $fullDir = Join-Path $projectRoot $dir
    if (-not (Test-Path $fullDir)) {
        New-Item -ItemType Directory -Path $fullDir -Force | Out-Null
    }
}

# ── Generate API layer ────────────────────────────────────────────
Write-Host "`nGenerating API layer..." -ForegroundColor Yellow

Write-ProjectFile -BasePath $projectRoot -RelativePath "src/$ProjectName.Api/$ProjectName.Api.csproj" -Content (New-ApiCsproj)
Write-ProjectFile -BasePath $projectRoot -RelativePath "src/$ProjectName.Api/Program.cs" -Content (New-ProgramCs -OrmChoice $Orm -DbChoice $Database)
Write-ProjectFile -BasePath $projectRoot -RelativePath "src/$ProjectName.Api/Controllers/${Entity}sController.cs" -Content (New-Controller)
Write-ProjectFile -BasePath $projectRoot -RelativePath "src/$ProjectName.Api/Middleware/ExceptionHandlingMiddleware.cs" -Content (New-Middleware)

# ── Generate Application layer ────────────────────────────────────
Write-Host "`nGenerating Application layer..." -ForegroundColor Yellow

Write-ProjectFile -BasePath $projectRoot -RelativePath "src/$ProjectName.Application/$ProjectName.Application.csproj" -Content (New-ApplicationCsproj)
Write-ProjectFile -BasePath $projectRoot -RelativePath "src/$ProjectName.Application/Services/${Entity}Service.cs" -Content (New-Service)
Write-ProjectFile -BasePath $projectRoot -RelativePath "src/$ProjectName.Application/Validators/Create${Entity}DtoValidator.cs" -Content (New-Validator)
Write-ProjectFile -BasePath $projectRoot -RelativePath "src/$ProjectName.Application/Exceptions/AppExceptions.cs" -Content (New-Exceptions)

# ── Generate Domain layer ─────────────────────────────────────────
Write-Host "`nGenerating Domain layer..." -ForegroundColor Yellow

Write-ProjectFile -BasePath $projectRoot -RelativePath "src/$ProjectName.Domain/$ProjectName.Domain.csproj" -Content (New-DomainCsproj)
Write-ProjectFile -BasePath $projectRoot -RelativePath "src/$ProjectName.Domain/DTOs/${Entity}Dto.cs" -Content (New-Dtos)
Write-ProjectFile -BasePath $projectRoot -RelativePath "src/$ProjectName.Domain/Entities/${Entity}.cs" -Content (New-Entity)
Write-ProjectFile -BasePath $projectRoot -RelativePath "src/$ProjectName.Domain/Enums/${Entity}Status.cs" -Content (New-Enum)
Write-ProjectFile -BasePath $projectRoot -RelativePath "src/$ProjectName.Domain/Interfaces/I${Entity}Repository.cs" -Content (New-RepositoryInterface)

$sharedInterfaces = New-SharedInterfaces
Write-ProjectFile -BasePath $projectRoot -RelativePath "src/$ProjectName.Domain/Interfaces/Repository/IRepository.cs" -Content $sharedInterfaces.Repository
Write-ProjectFile -BasePath $projectRoot -RelativePath "src/$ProjectName.Domain/Interfaces/Repository/IUnitOfWork.cs" -Content $sharedInterfaces.UnitOfWork

if ($Orm -eq "dapper") {
    $dapperInterfaces = New-DapperInterfaces
    Write-ProjectFile -BasePath $projectRoot -RelativePath "src/$ProjectName.Domain/Interfaces/Data/ITenantConnectionFactory.cs" -Content $dapperInterfaces.ConnectionFactory
}

# ── Generate Infrastructure layer ─────────────────────────────────
Write-Host "`nGenerating Infrastructure layer..." -ForegroundColor Yellow

Write-ProjectFile -BasePath $projectRoot -RelativePath "src/$ProjectName.Infrastructure/$ProjectName.Infrastructure.csproj" -Content (New-InfrastructureCsproj -OrmChoice $Orm -DbChoice $Database)
Write-ProjectFile -BasePath $projectRoot -RelativePath "src/$ProjectName.Infrastructure/Repositories/${Entity}Repository.cs" -Content (New-EntityRepository)

if ($Orm -eq "efcore") {
    Write-ProjectFile -BasePath $projectRoot -RelativePath "src/$ProjectName.Infrastructure/Data/ApplicationDbContext.cs" -Content (New-ApplicationDbContext)
    Write-ProjectFile -BasePath $projectRoot -RelativePath "src/$ProjectName.Infrastructure/Data/Configurations/${Entity}Configuration.cs" -Content (New-EfEntityConfiguration)
    Write-ProjectFile -BasePath $projectRoot -RelativePath "src/$ProjectName.Infrastructure/Repositories/EFRepository.cs" -Content (New-EfRepository)
    Write-ProjectFile -BasePath $projectRoot -RelativePath "src/$ProjectName.Infrastructure/Repositories/EfUnitOfWork.cs" -Content (New-EfUnitOfWork)
}
else {
    Write-ProjectFile -BasePath $projectRoot -RelativePath "src/$ProjectName.Infrastructure/Data/TenantConnectionFactory.cs" -Content (New-TenantConnectionFactory)
    Write-ProjectFile -BasePath $projectRoot -RelativePath "src/$ProjectName.Infrastructure/Data/Configurations/ServiceCollectionExtensions.cs" -Content (New-ServiceCollectionExtensions)
    Write-ProjectFile -BasePath $projectRoot -RelativePath "src/$ProjectName.Infrastructure/Repositories/DapperRepository.cs" -Content (New-DapperRepository)
    Write-ProjectFile -BasePath $projectRoot -RelativePath "src/$ProjectName.Infrastructure/Repositories/DapperUnitOfWork.cs" -Content (New-DapperUnitOfWork)
}

if ($Services) {
    foreach ($svc in ($Services -split ',')) {
        $safeName = $svc.Trim().Replace(' ', '')
        Write-ProjectFile -BasePath $projectRoot -RelativePath "src/$ProjectName.Infrastructure/ExternalServices/${safeName}Service.cs" -Content (New-ExternalService -ServiceName $svc)
    }
}

# ── Generate Tests ────────────────────────────────────────────────
Write-Host "`nGenerating Tests..." -ForegroundColor Yellow

Write-ProjectFile -BasePath $projectRoot -RelativePath "tests/$ProjectName.Tests.Unit/$ProjectName.Tests.Unit.csproj" -Content (New-TestsCsproj)
Write-ProjectFile -BasePath $projectRoot -RelativePath "tests/$ProjectName.Tests.Unit/Services/${Entity}ServiceTests.cs" -Content (New-ServiceTests)

# ── Generate Solution file ────────────────────────────────────────
Write-Host "`nGenerating Solution file..." -ForegroundColor Yellow

Write-ProjectFile -BasePath $projectRoot -RelativePath "$ProjectName.sln" -Content (New-SolutionFile)

# ── Generate Config files ─────────────────────────────────────────
Write-Host "`nGenerating Config files..." -ForegroundColor Yellow

$configs = New-ConfigFiles
Write-ProjectFile -BasePath $projectRoot -RelativePath "src/$ProjectName.Api/appsettings.json" -Content $configs.AppSettings
Write-ProjectFile -BasePath $projectRoot -RelativePath "src/$ProjectName.Api/appsettings.Development.json" -Content $configs.AppSettingsDev

# ── Generate README ───────────────────────────────────────────────
Write-Host "`nGenerating README..." -ForegroundColor Yellow

Write-ProjectFile -BasePath $projectRoot -RelativePath "README.md" -Content (New-Readme)

# ── Done ──────────────────────────────────────────────────────────
Write-Host ""
Write-Host "Project '$ProjectName' generated successfully!" -ForegroundColor Green
Write-Host "Location: $projectRoot" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  1. cd $projectRoot"
Write-Host "  2. dotnet restore"
Write-Host "  3. dotnet build"
if ($Orm -eq "efcore") {
    Write-Host "  4. dotnet ef migrations add InitialCreate --project src/$ProjectName.Infrastructure --startup-project src/$ProjectName.Api"
    Write-Host "  5. dotnet ef database update --project src/$ProjectName.Infrastructure --startup-project src/$ProjectName.Api"
}
Write-Host ""
