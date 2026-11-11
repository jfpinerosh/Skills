# Test project structure and packages

## Contents
- Target layout
- Packages per project
- csproj templates
- Running and filtering
- Coverage

## Target layout

```
src/
  MyApp.Api/
  MyApp.Application/
  MyApp.Domain/
  MyApp.Infrastructure/
tests/
  MyApp.UnitTests/           # no I/O, milliseconds
  MyApp.IntegrationTests/    # real DB + real pipeline pieces
  MyApp.E2ETests/            # whole app over HTTP, multi-step flows
  MyApp.Tests.Shared/        # optional: builders, fakes, auth handler, only if reused by 2+ projects
Directory.Build.props
Directory.Packages.props     # central package management (recommended)
```

Why separate projects: unit tests can run on every save in seconds, integration/e2e need Docker and take longer, and CI can run them as separate stages. In a very small solution a single test project with folders + traits is acceptable; say so in the report rather than forcing a split.

Mirror the production namespace/folder in the unit test project (`MyApp.Application/Orders/OrderService.cs` -> `MyApp.UnitTests/Application/Orders/OrderServiceTests.cs`), one test class per class under test.

## Packages per project

Match what the repo already uses (xUnit v2 vs v3). If starting fresh on .NET 10, prefer xUnit v3. Resolve the latest stable versions with `dotnet add package` rather than hardcoding versions from memory.

| Package | Unit | Integration | E2E | Notes |
|---|---|---|---|---|
| `xunit.v3` (or `xunit` v2 + `xunit.runner.visualstudio`) | yes | yes | yes | v3 projects are `OutputType` Exe |
| `Microsoft.NET.Test.Sdk` | yes | yes | yes | needed for `dotnet test` with v2 and for VS/Rider discovery |
| `NSubstitute` | yes | sometimes | rarely | faking external services |
| `NSubstitute.Analyzers.CSharp` | yes | | | catches misuse at compile time |
| `Shouldly` | yes | yes | yes | free assertion library |
| `Microsoft.Extensions.TimeProvider.Testing` | yes | yes | yes | `FakeTimeProvider` |
| `Microsoft.AspNetCore.Mvc.Testing` | | yes | yes | `WebApplicationFactory` |
| `Testcontainers.MsSql` / `.PostgreSql` / `.MySql` / `.MongoDb` | | yes | yes | pick by detected provider |
| `Respawn` | | yes | yes | fast DB reset between tests (relational) |
| `Bogus` | optional | optional | optional | realistic test data; seed it |
| `coverlet.collector` | yes | yes | yes | coverage |

Do not add: Moq or FluentAssertions to projects that do not already use them (see SKILL.md rules).

## csproj template (xUnit v3, integration)

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net10.0</TargetFramework>
    <OutputType>Exe</OutputType>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
    <IsPackable>false</IsPackable>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="xunit.v3" />
    <PackageReference Include="xunit.runner.visualstudio" />
    <PackageReference Include="Microsoft.NET.Test.Sdk" />
    <PackageReference Include="Shouldly" />
    <PackageReference Include="coverlet.collector" />
    <PackageReference Include="Microsoft.AspNetCore.Mvc.Testing" />
    <PackageReference Include="Testcontainers.PostgreSql" />
    <PackageReference Include="Respawn" />
  </ItemGroup>
  <ItemGroup>
    <ProjectReference Include="..\..\src\MyApp.Api\MyApp.Api.csproj" />
  </ItemGroup>
</Project>
```

(Versions come from `Directory.Packages.props` when central package management is on. Otherwise add them via `dotnet add package`.)

Unit test projects omit the Mvc.Testing / Testcontainers / Respawn lines and reference `Application`/`Domain` projects only. A unit test project that references the Api or Infrastructure project is a smell.

## Running and filtering

```bash
dotnet test tests/MyApp.UnitTests                         # fast loop
dotnet test --filter "Category=Integration"               # by trait
dotnet test --filter "Category!=E2E"                      # everything but e2e
dotnet test --collect:"XPlat Code Coverage" --results-directory ./TestResults
```

Document these commands in the test project's README or the repo README if they are missing.

## Coverage

`coverlet.collector` writes `coverage.cobertura.xml`. Report line and branch coverage but do not chase a number: a high percentage with weak assertions is worse than lower coverage with meaningful tests. If `reportgenerator` is installed, it can summarize the XML; otherwise parse `line-rate`/`branch-rate` attributes from the root element.
