#!/usr/bin/env python3
"""Static audit of a .NET solution's tests (read-only).

Usage:
    python audit_dotnet_tests.py <solution-root> [--format markdown|json]

Reports projects, test stack, detected database provider, test counts by
category, production classes without a matching test class, and test smells.
It is a heuristic scan (regex based): treat results as leads to verify.
"""
import argparse
import json
import re
import sys
from pathlib import Path

SKIP_DIRS = {"bin", "obj", ".git", "node_modules", ".vs", ".idea", "TestResults", "packages"}

DB_SIGNATURES = {
    "SQL Server": ["Microsoft.EntityFrameworkCore.SqlServer", "Microsoft.Data.SqlClient", "System.Data.SqlClient"],
    "PostgreSQL": ["Npgsql"],
    "MySQL/MariaDB": ["Pomelo.EntityFrameworkCore.MySql", "MySql.Data", "MySqlConnector", "MySql.EntityFrameworkCore"],
    "SQLite": ["Microsoft.EntityFrameworkCore.Sqlite", "Microsoft.Data.Sqlite"],
    "MongoDB": ["MongoDB.Driver"],
    "Cosmos DB": ["Microsoft.EntityFrameworkCore.Cosmos", "Microsoft.Azure.Cosmos"],
    "Oracle": ["Oracle.EntityFrameworkCore", "Oracle.ManagedDataAccess"],
}

TEST_LIBS = {
    "xunit.v3": "xUnit v3",
    "xunit": "xUnit v2",
    "NSubstitute": "NSubstitute",
    "Moq": "Moq",
    "FakeItEasy": "FakeItEasy",
    "Shouldly": "Shouldly",
    "FluentAssertions": "FluentAssertions",
    "Testcontainers": "Testcontainers",
    "Microsoft.AspNetCore.Mvc.Testing": "WebApplicationFactory",
    "Respawn": "Respawn",
    "Bogus": "Bogus",
    "AutoFixture": "AutoFixture",
    "coverlet.collector": "coverlet.collector",
    "coverlet.msbuild": "coverlet.msbuild",
    "Microsoft.Extensions.TimeProvider.Testing": "FakeTimeProvider",
    "Microsoft.EntityFrameworkCore.InMemory": "EF InMemory provider",
    "MSTest": "MSTest",
    "NUnit": "NUnit",
    "Verify.Xunit": "Verify",
}

PROD_KIND = re.compile(
    r"(Service|Handler|Controller|Endpoint|Endpoints|Repository|Validator|Mapper|Command|Query|Processor|UseCase|Manager|Factory|Policy|Calculator|Function)$"
)

ATTR_TEST = re.compile(r"\[\s*(Fact|Theory)\b([^\]]*)\]")
METHOD_SIG = re.compile(
    r"(?:public|internal)\s+(?:async\s+)?(?:static\s+)?([\w<>\[\],.?]+)\s+(\w+)\s*\([^)]*\)\s*(?:=>|\{)",
    re.S,
)
CLASS_RE = re.compile(r"\bclass\s+(\w+)")
ASSERT_TOKENS = re.compile(
    r"\b(Assert\.\w+|Should\w*|ShouldBe\w*|ShouldNotBe\w*|Received\s*\(|DidNotReceive\s*\(|Throws|ThrowsAsync|Verify\s*\(|Should\.\w+)",
)


def walk(root: Path):
    for p in root.rglob("*"):
        if any(part in SKIP_DIRS for part in p.parts):
            continue
        if p.is_file():
            yield p


def read(p: Path) -> str:
    try:
        return p.read_text(encoding="utf-8-sig", errors="replace")
    except OSError:
        return ""


def parse_csproj(p: Path):
    text = read(p)
    tfm = re.findall(r"<TargetFrameworks?>([^<]+)</TargetFrameworks?>", text)
    pkgs = re.findall(r'<PackageReference\s+Include="([^"]+)"', text)
    refs = re.findall(r'<ProjectReference\s+Include="([^"]+)"', text)
    sdk = re.search(r'<Project\s+Sdk="([^"]+)"', text)
    return {
        "path": p,
        "name": p.stem,
        "tfm": tfm[0] if tfm else "?",
        "packages": pkgs,
        "refs": [Path(r.replace("\\", "/")).stem for r in refs],
        "sdk": sdk.group(1) if sdk else "",
        "text": text,
    }


def central_packages(root: Path):
    pkgs = []
    for p in walk(root):
        if p.name == "Directory.Packages.props":
            pkgs += re.findall(r'<PackageVersion\s+Include="([^"]+)"', read(p))
    return pkgs


def is_test_project(proj) -> bool:
    n = proj["name"].lower()
    has_runner = any(x in proj["packages"] for x in ("xunit", "xunit.v3", "NUnit", "MSTest.TestFramework", "MSTest")) or \
        "Microsoft.NET.Test.Sdk" in proj["packages"]
    return has_runner or n.endswith((".tests", ".test", ".unittests", ".integrationtests", ".e2etests"))


def classify_test_project(proj) -> str:
    n = proj["name"].lower()
    if "e2e" in n or "endtoend" in n or "end-to-end" in n:
        return "e2e"
    if "integration" in n:
        return "integration"
    if "unit" in n:
        return "unit"
    pk = proj["packages"]
    if any(p.startswith("Testcontainers") or p == "Microsoft.AspNetCore.Mvc.Testing" for p in pk):
        return "integration"
    return "unit/unknown"


def find_test_methods(text: str):
    """Return list of (name, line, body, attr_args) for [Fact]/[Theory] methods."""
    out = []
    for m in ATTR_TEST.finditer(text):
        sig = METHOD_SIG.search(text, m.end())
        if not sig or sig.start() - m.end() > 600:
            continue
        name = sig.group(2)
        start = sig.end() - 1
        if text[start] == "{":
            depth, i = 0, start
            while i < len(text):
                if text[i] == "{":
                    depth += 1
                elif text[i] == "}":
                    depth -= 1
                    if depth == 0:
                        break
                i += 1
            body = text[start:i + 1]
        else:  # expression-bodied
            end = text.find(";", start)
            body = text[start:end if end != -1 else start + 400]
        line = text.count("\n", 0, m.start()) + 1
        out.append({"name": name, "line": line, "body": body, "attr": m.group(0), "ret": sig.group(1),
                    "kind": m.group(1)})
    return out


def scan(root: Path):
    csprojs = [parse_csproj(p) for p in walk(root) if p.suffix == ".csproj"]
    central = central_packages(root)
    slns = [str(p.relative_to(root)) for p in walk(root) if p.suffix in (".sln", ".slnx")]
    cpm = bool(central)

    test_projects = [c for c in csprojs if is_test_project(c)]
    prod_projects = [c for c in csprojs if c not in test_projects]

    # test stack
    stack = set()
    for proj in test_projects:
        for pk in proj["packages"]:
            for key, label in TEST_LIBS.items():
                if pk == key or pk.startswith(key + ".") and key in ("Testcontainers",):
                    stack.add(label)
    stack_list = sorted(stack)

    # database detection from production projects (+ appsettings hints)
    db = {}
    for proj in prod_projects + test_projects:
        for label, sigs in DB_SIGNATURES.items():
            if any(pk == s or pk.startswith(s + ".") for pk in proj["packages"] for s in sigs):
                db.setdefault(label, set()).add(proj["name"])
    for p in walk(root):
        if p.name.startswith("appsettings") and p.suffix == ".json":
            t = read(p).lower()
            if "server=" in t and ("initial catalog" in t or "database=" in t) and "SQL Server" not in db:
                db.setdefault("SQL Server (connection string)", set()).add(p.name)
            if "host=" in t and "username=" in t:
                db.setdefault("PostgreSQL (connection string)", set()).add(p.name)
            if "mongodb://" in t:
                db.setdefault("MongoDB (connection string)", set()).add(p.name)
    uses_ef = any("EntityFrameworkCore" in pk for pj in prod_projects for pk in pj["packages"])
    uses_dapper = any(pk == "Dapper" for pj in prod_projects for pk in pj["packages"])

    # app type
    app_kinds = set()
    for proj in prod_projects:
        t = proj["text"]
        if "Microsoft.NET.Sdk.Web" in proj["sdk"]:
            app_kinds.add("ASP.NET Core")
        if any("Microsoft.Azure.Functions.Worker" in pk for pk in proj["packages"]):
            app_kinds.add("Azure Functions (isolated worker)")

    # per test project scan
    tests = []
    smells = []
    counts = {"unit/unknown": 0, "unit": 0, "integration": 0, "e2e": 0}
    skipped = 0
    test_classes = set()
    trait_counts = {}
    for proj in test_projects:
        kind = classify_test_project(proj)
        pdir = proj["path"].parent
        for f in pdir.rglob("*.cs"):
            if any(part in SKIP_DIRS for part in f.parts):
                continue
            text = read(f)
            for c in CLASS_RE.findall(text):
                test_classes.add(c)
            methods = find_test_methods(text)
            rel = str(f.relative_to(root))
            for t in methods:
                counts[kind] = counts.get(kind, 0) + 1
                body = t["body"]
                loc = t["line"]
                tests.append(t["name"])
                if re.search(r"Skip\s*=", t["attr"]):
                    skipped += 1
                    smells.append(("Medium", "Skipped test", rel, loc, t["name"]))
                if not ASSERT_TOKENS.search(body):
                    smells.append(("High", "No assertion", rel, loc, t["name"]))
                if re.search(r"Assert\.True\(\s*true\s*\)|Assert\.False\(\s*false\s*\)|Should\(\)\.BeTrue\(\)\s*;\s*//", body):
                    smells.append(("High", "Tautological assertion", rel, loc, t["name"]))
                if re.search(r"Thread\.Sleep\s*\(", body) or re.search(r"Task\.Delay\s*\(", body):
                    smells.append(("High", "Sleep/Delay in test (flaky)", rel, loc, t["name"]))
                if re.search(r"\bDateTime(Offset)?\.(Now|UtcNow)\b", body):
                    smells.append(("Medium", "Wall-clock time in test", rel, loc, t["name"]))
                if re.search(r"\.Result\b|\.Wait\s*\(|GetAwaiter\(\)\.GetResult\(\)", body):
                    smells.append(("Medium", "Blocking on async (.Result/.Wait)", rel, loc, t["name"]))
                if t["ret"] == "void" and re.search(r"async\s+void", text[max(0, text.find(t['name']) - 40):text.find(t['name'])]):
                    smells.append(("Medium", "async void test", rel, loc, t["name"]))
                if re.search(r"\btry\s*\{", body) or re.search(r"\bcatch\s*[\({]", body):
                    smells.append(("Medium", "try/catch inside test", rel, loc, t["name"]))
                if re.search(r"\b(if|for|foreach|while)\s*\(", body):
                    smells.append(("Low", "Control flow in test body", rel, loc, t["name"]))
                if "Console.Write" in body:
                    smells.append(("Low", "Console output in test", rel, loc, t["name"]))
                n_assert = len(re.findall(r"\b(Assert\.\w+|\.Should\w+\(|\.ShouldBe\w*\()", body))
                if n_assert >= 7:
                    smells.append(("Medium", f"Assertion roulette ({n_assert} assertions)", rel, loc, t["name"]))
                if not re.match(r"^[A-Za-z0-9]+(_[A-Za-z0-9]+){1,}$", t["name"]) and not re.match(r"^[A-Z][A-Za-z0-9]+$", t["name"]) :
                    smells.append(("Low", "Test name does not follow Method_Scenario_Expected", rel, loc, t["name"]))
                elif re.match(r"^(Test\d*|Should(Work|Pass)|Test[A-Z]?\w*)$", t["name"]):
                    smells.append(("Low", "Non-descriptive test name", rel, loc, t["name"]))
            if "UseInMemoryDatabase" in text and kind in ("integration", "e2e"):
                smells.append(("Medium", "EF InMemory used in integration/e2e tests (not relational)", rel, 1, f.stem))
            if re.search(r"\[\s*(Fact|Theory)\b", text) and "Trait(" not in text and kind != "unit/unknown":
                pass  # trait absence reported at project level below

    # traits
    all_text = "".join(read(f) for pj in test_projects for f in pj["path"].parent.rglob("*.cs")
                       if not any(part in SKIP_DIRS for part in f.parts))
    for m in re.finditer(r'Trait\(\s*"Category"\s*,\s*"(\w+)"\s*\)', all_text):
        trait_counts[m.group(1)] = trait_counts.get(m.group(1), 0) + 1

    # production classes vs tests
    untested = []
    prod_classes = []
    for proj in prod_projects:
        pdir = proj["path"].parent
        for f in pdir.rglob("*.cs"):
            if any(part in SKIP_DIRS for part in f.parts):
                continue
            if f.name.endswith((".g.cs", ".Designer.cs")) or "Migrations" in f.parts:
                continue
            text = read(f)
            for c in CLASS_RE.findall(text):
                if PROD_KIND.search(c) and not c.startswith("I"):
                    prod_classes.append((c, str(f.relative_to(root))))
    for c, rel in prod_classes:
        candidates = {c + "Tests", c + "Test", c + "Should", c + "Specs"}
        if not (candidates & test_classes):
            untested.append((c, rel))

    # CI
    ci = []
    for p in walk(root):
        s = str(p.relative_to(root)).replace("\\", "/")
        if s.startswith(".github/workflows/") or p.name in ("azure-pipelines.yml", ".gitlab-ci.yml", "Jenkinsfile", "bitbucket-pipelines.yml"):
            if "dotnet test" in read(p) or "dotnet-test" in read(p):
                ci.append(s)

    # layout notes
    layout = []
    if not test_projects:
        layout.append("No test project found.")
    names = {classify_test_project(t) for t in test_projects}
    if test_projects and "integration" not in names and "e2e" not in names:
        layout.append("No integration or e2e test project detected.")
    for t in test_projects:
        if classify_test_project(t) == "unit" and any(
            x.startswith(("Microsoft.AspNetCore.Mvc.Testing", "Testcontainers")) for x in t["packages"]
        ):
            layout.append(f"{t['name']} looks like a unit project but references integration packages.")
    if "xUnit v2" in stack and "xUnit v3" in stack:
        layout.append("Both xUnit v2 and v3 packages found.")
    if not any("coverlet" in s for s in stack_list):
        layout.append("No coverage collector (coverlet) found in test projects.")
    if "Moq" in stack and "NSubstitute" in stack:
        layout.append("Both Moq and NSubstitute are used; pick one.")
    if not ci:
        layout.append("No CI file running `dotnet test` was found.")

    return {
        "root": str(root),
        "solutions": slns,
        "central_package_management": cpm,
        "app_kinds": sorted(app_kinds),
        "projects": {
            "production": [{"name": p["name"], "tfm": p["tfm"]} for p in prod_projects],
            "test": [{"name": p["name"], "tfm": p["tfm"], "kind": classify_test_project(p)} for p in test_projects],
        },
        "test_stack": stack_list,
        "database": {k: sorted(v) for k, v in db.items()},
        "uses_ef_core": uses_ef,
        "uses_dapper": uses_dapper,
        "test_counts": {**counts, "total": len(tests), "skipped": skipped},
        "traits": trait_counts,
        "untested_production_classes": untested,
        "smells": smells,
        "ci_files_running_tests": ci,
        "layout_notes": layout,
    }


def to_markdown(r) -> str:
    L = []
    a = L.append
    a(f"# Scanner output - {r['root']}\n")
    a(f"- Solutions: {', '.join(r['solutions']) or 'none found'}")
    a(f"- App type: {', '.join(r['app_kinds']) or 'unknown'}")
    a(f"- Central package management: {'yes' if r['central_package_management'] else 'no'}")
    a("\n## Projects")
    a("Production: " + (", ".join(f"{p['name']} ({p['tfm']})" for p in r["projects"]["production"]) or "none"))
    a("Test: " + (", ".join(f"{p['name']} ({p['tfm']}, {p['kind']})" for p in r["projects"]["test"]) or "none"))
    a("\n## Test stack")
    a(", ".join(r["test_stack"]) or "none detected")
    a("\n## Database detection")
    if r["database"]:
        for k, v in r["database"].items():
            a(f"- {k}: {', '.join(v)}")
    else:
        a("- none detected")
    a(f"- EF Core: {'yes' if r['uses_ef_core'] else 'no'} | Dapper: {'yes' if r['uses_dapper'] else 'no'}")
    c = r["test_counts"]
    a("\n## Test counts")
    a(f"- total {c['total']} | unit {c.get('unit', 0)} | unit/unknown {c.get('unit/unknown', 0)} | "
      f"integration {c.get('integration', 0)} | e2e {c.get('e2e', 0)} | skipped {c['skipped']}")
    if r["traits"]:
        a("- Category traits: " + ", ".join(f"{k}={v}" for k, v in r["traits"].items()))
    else:
        a("- No `Trait(\"Category\", ...)` usage found")
    a("\n## Layout / tooling notes")
    for n in r["layout_notes"] or ["none"]:
        a(f"- {n}")
    a("\n## Test smells")
    if r["smells"]:
        order = {"High": 0, "Medium": 1, "Low": 2}
        sm = sorted(r["smells"], key=lambda s: (order[s[0]], s[1], s[2], s[3]))
        a("| Severity | Smell | Location | Test |")
        a("|---|---|---|---|")
        for sev, name, rel, line, t in sm[:80]:
            a(f"| {sev} | {name} | {rel}:{line} | {t} |")
        if len(sm) > 80:
            a(f"\n...and {len(sm) - 80} more (use --format json for all).")
    else:
        a("none found")
    a("\n## Production classes with no matching test class (name heuristic)")
    if r["untested_production_classes"]:
        for c_, rel in r["untested_production_classes"][:80]:
            a(f"- {c_}  ({rel})")
        extra = len(r["untested_production_classes"]) - 80
        if extra > 0:
            a(f"- ...and {extra} more")
    else:
        a("none")
    a("\n## CI files running `dotnet test`")
    a(", ".join(r["ci_files_running_tests"]) or "none found")
    a("\n> Heuristic scan: verify each finding by reading the code before reporting it.")
    return "\n".join(L)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("root")
    ap.add_argument("--format", choices=["markdown", "json"], default="markdown")
    args = ap.parse_args()
    root = Path(args.root).resolve()
    if not root.exists():
        print(f"Path not found: {root}", file=sys.stderr)
        sys.exit(2)
    result = scan(root)
    if args.format == "json":
        print(json.dumps(result, indent=2, default=str))
    else:
        print(to_markdown(result))


if __name__ == "__main__":
    main()
