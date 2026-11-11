#!/usr/bin/env python3
"""Regex lead generator for edge-case audits (read-only).

Usage:
    python scan_hotspots.py <path> [--max-per-vector 25] [--format markdown|json]

Finds lines worth reading first, grouped by the six audit vectors, and ranks
files by number of hits. These are LEADS, not findings: read the code and
prove a trigger before reporting anything.
"""
import argparse
import json
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

EXT = {".cs", ".java", ".kt", ".js", ".jsx", ".ts", ".tsx", ".mjs", ".py", ".go", ".php", ".rb"}
SKIP = {"bin", "obj", ".git", "node_modules", "dist", "build", "target", "vendor", "__pycache__",
        ".venv", "venv", ".idea", ".vs", "Migrations", "coverage"}
TEST_HINT = re.compile(r"(test|spec|mock|fixture)", re.I)

# (vector, label, regex, weight)  weight: 3 = strong lead, 2 = medium, 1 = weak
P = [
    # 1 Boundary
    ("1 Boundary", "float/double for money-like name", r"\b(float|double)\b[^;\n]*(price|amount|total|balance|cost|fee|rate|money)|(price|amount|total|balance|cost|fee)\w*\s*[:=][^;\n]*\b(float|double)\b", 2),
    ("1 Boundary", "unchecked cast/parse", r"\b(int|long|Int32|Integer)\.Parse\(|parseInt\(|\(int\)\s*\w|Number\(|atoi\(", 1),
    ("1 Boundary", "indexing/First on possibly empty", r"\.(First|Last|Single|Max|Min|Average)\(\)|\[0\]|\.get\(0\)|\.Value\b", 1),
    ("1 Boundary", "DateTime.Now / local time", r"DateTime\.(Now|Today)\b|new Date\(\)|datetime\.now\(\)|time\.Now\(\)", 1),
    ("1 Boundary", "loose equality / float equality", r"[^=!]==[^=].*\b(float|double)\b|\s==\s(?=\w)(?=.*\bNaN\b)|[^=!]==[^=]\s*null\b", 1),
    # 2 Concurrency
    ("2 Concurrency", "check-then-act on existence", r"if\s*\(\s*!?\s*\w*\.?(Any|Exists|Contains|ContainsKey|exists|has)\w*\(", 2),
    ("2 Concurrency", "static mutable state", r"\bstatic\s+(?!readonly|final|class|void|async\b)[\w<>\[\],\s?]+\s+\w+\s*(=|;)|^\s*(var|let)\s+\w+\s*=\s*(\[\]|\{\}|new Map|new Set)", 2),
    ("2 Concurrency", "lock / synchronized / mutex", r"\block\s*\(|synchronized\b|\bMutex\b|sync\.(Mutex|RWMutex)|Monitor\.Enter|SemaphoreSlim", 1),
    ("2 Concurrency", "non-thread-safe collection shared", r"\b(Dictionary|HashMap|List|ArrayList)<", 1),
    ("2 Concurrency", "read-modify-write", r"\b(\w+(\.\w+)*)\s*(\+=|-=|\+\+|--)\s*[\w(]|\b(\w+)\s*=\s*\4\s*[+-]\s*\w", 1),
    # 3 Async/Resource
    ("3 Async/Resource", "async void / fire-and-forget", r"\basync\s+void\b|\b_\s*=\s*\w+Async\(|Task\.Run\(|\bgo\s+func\(|\bgo\s+\w+\(", 3),
    ("3 Async/Resource", "blocking on async", r"\.Result\b|\.Wait\(\)|GetAwaiter\(\)\.GetResult\(\)|Thread\.Sleep\(", 3),
    ("3 Async/Resource", "new HttpClient per call", r"new\s+HttpClient\(|http\.Client\{\}|requests\.(get|post)\(", 2),
    ("3 Async/Resource", "disposable created without using", r"new\s+(StreamReader|StreamWriter|FileStream|SqlConnection|NpgsqlConnection|MemoryStream|HttpResponseMessage)\(|\bopen\(", 1),
    ("3 Async/Resource", "async in forEach / unawaited promise", r"\.forEach\(\s*async|\.then\([^)]*\)\s*;\s*$", 2),
    ("3 Async/Resource", "no timeout/cancellation visible", r"\b(GetAsync|PostAsync|SendAsync|fetch|axios\.\w+|requests\.\w+)\(", 1),
    ("3 Async/Resource", "unbounded WhenAll/Promise.all", r"Task\.WhenAll\(|Promise\.all\(|asyncio\.gather\(", 1),
    # 4 Failure
    ("4 Failure", "empty catch / swallowed", r"catch\s*(\([^)]*\))?\s*\{\s*\}|except[^:\n]*:\s*(pass|\.\.\.)\s*$|\.catch\(\s*\(\s*\w*\s*\)\s*=>\s*\{\s*\}\s*\)|recover\(\)", 3),
    ("4 Failure", "catch-all", r"catch\s*\(\s*(System\.)?Exception\b|catch\s*\{|except\s+Exception|except\s*:|catch\s*\(\s*(e|err|error)?\s*\)\s*\{|catch\s*\(Throwable", 2),
    ("4 Failure", "rethrow loses stack", r"\bthrow\s+(ex|e|err)\s*;", 3),
    ("4 Failure", "ignored error (Go)", r"\b_\s*,?\s*(err)?\s*:?=\s*\w+[\w.]*\(|,\s*_\s*:?=\s*\w+[\w.]*\(", 2),
    ("4 Failure", "retry loop", r"\b(retry|retries|attempt|backoff)\b", 1),
    ("4 Failure", "returns default on failure", r"catch[^{]*\{[^}]*return\s+(null|false|0|\"\"|\[\]|None|nil)", 2),
    # 5 Security
    ("5 Security", "SQL built from strings", r"(SELECT|INSERT|UPDATE|DELETE)\b[^\n;]*(\"\s*\+|\+\s*\"|\$\"|\{\w+\}|%s|\.format\(|f\"|`[^`]*\$\{)|FromSqlRaw|ExecuteSqlRaw|createQuery\(\s*\"[^\"]*\"\s*\+|\.raw\(", 3),
    ("5 Security", "shell/process execution", r"Process\.Start|Runtime\.getRuntime\(\)\.exec|os\.system\(|subprocess\.\w+\([^)]*shell\s*=\s*True|child_process|\bexec\(|\beval\(|shell_exec|\bsystem\(", 3),
    ("5 Security", "path from user input", r"Path\.Combine\(|File\.(Read|Write|Open|Delete)\w*\(|open\([^)]*(req|request|input|param)|sendFile\(|ZipFile|ExtractToDirectory", 2),
    ("5 Security", "unsafe deserialization", r"BinaryFormatter|TypeNameHandling\.(All|Auto|Objects)|pickle\.loads?|yaml\.load\(|ObjectInputStream|unserialize\(|Marshal\.load", 3),
    ("5 Security", "raw HTML / XSS sink", r"innerHTML|dangerouslySetInnerHTML|Html\.Raw|v-html|document\.write|\|\s*safe\b|mark_safe", 3),
    ("5 Security", "secrets / sensitive in code or logs", r"(password|passwd|secret|api[_-]?key|token|connectionstring)\s*[:=]\s*[\"'][^\"']{4,}[\"']|(log|logger|console)\.\w+\([^)]*(password|token|secret|authorization|ssn|card)", 3),
    ("5 Security", "weak crypto / non-constant compare", r"\b(MD5|SHA1)\b|new Random\(|Math\.random\(|random\.random\(|(token|hash|signature|hmac|secret)\w*\s*==", 2),
    ("5 Security", "authz attributes missing / AllowAnonymous", r"AllowAnonymous|@PermitAll|csrf_exempt|verify\s*=\s*False|ServerCertificateCustomValidationCallback|rejectUnauthorized\s*:\s*false|InsecureSkipVerify", 3),
    ("5 Security", "id from route/query used directly", r"(Route|FromRoute|FromQuery|req\.params|req\.query|request\.args|PathVariable)", 1),
    ("5 Security", "regex on user input (ReDoS)", r"new\s+Regex\(|Pattern\.compile\(|re\.compile\(|new RegExp\(", 1),
    # 6 Contract
    ("6 Contract", "silent default for missing value", r"\?\?\s*(\"\"|0|false|null|new\b|default)|\.getOrDefault\(|\bor\s+(\"\"|0|\[\]|\{\})|\|\|\s*(\"\"|0|\[\]|\{\})|FirstOrDefault\w*\(", 2),
    ("6 Contract", "switch/state without default", r"\bswitch\s*\(", 1),
    ("6 Contract", "public setter on entity", r"public\s+[\w<>?\[\]]+\s+\w+\s*\{\s*get;\s*set;\s*\}", 1),
    ("6 Contract", "TODO/HACK/impossible", r"TODO|FIXME|HACK|XXX|should never|can'?t happen|unreachable", 1),
]
COMPILED = [(v, l, re.compile(rx, re.I if v.startswith("5") and "secret" in l else 0), w) for v, l, rx, w in P]


def iter_files(root: Path):
    if root.is_file():
        yield root
        return
    for p in root.rglob("*"):
        if p.is_file() and p.suffix in EXT and not any(part in SKIP for part in p.parts):
            yield p


def scan(root: Path, max_per_vector: int, include_tests: bool):
    hits = defaultdict(list)
    file_score = Counter()
    n_files = 0
    for f in iter_files(root):
        if not include_tests and TEST_HINT.search(f.name):
            continue
        try:
            lines = f.read_text(encoding="utf-8-sig", errors="replace").splitlines()
        except OSError:
            continue
        n_files += 1
        rel = str(f.relative_to(root)) if root.is_dir() else f.name
        for i, line in enumerate(lines, 1):
            s = line.strip()
            if not s or s.startswith(("//", "#", "*", "/*")):
                continue
            for vec, label, rx, w in COMPILED:
                if rx.search(line):
                    hits[vec].append({"file": rel, "line": i, "label": label, "weight": w, "code": s[:140]})
                    file_score[rel] += w
    for vec in hits:
        hits[vec].sort(key=lambda h: (-h["weight"], h["file"], h["line"]))
    return hits, file_score, n_files


def to_markdown(hits, file_score, n_files, cap):
    out = [f"# Hotspot scan ({n_files} files)\n",
           "> Leads only. Read the code and prove a trigger before reporting. Weight: 3 strong, 2 medium, 1 weak.\n",
           "## Top files by hotspot score"]
    for f, s in file_score.most_common(12):
        out.append(f"- {f}: {s}")
    for vec in sorted(hits):
        out.append(f"\n## {vec} ({len(hits[vec])} leads)")
        for h in hits[vec][:cap]:
            out.append(f"- [w{h['weight']}] {h['file']}:{h['line']} - {h['label']}: `{h['code']}`")
        if len(hits[vec]) > cap:
            out.append(f"- ...{len(hits[vec]) - cap} more (use --max-per-vector or --format json)")
    return "\n".join(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("path")
    ap.add_argument("--max-per-vector", type=int, default=25)
    ap.add_argument("--format", choices=["markdown", "json"], default="markdown")
    ap.add_argument("--include-tests", action="store_true", help="also scan test files")
    a = ap.parse_args()
    root = Path(a.path).resolve()
    if not root.exists():
        print(f"Path not found: {root}", file=sys.stderr)
        sys.exit(2)
    hits, fs, n = scan(root, a.max_per_vector, a.include_tests)
    if a.format == "json":
        print(json.dumps({"files": n, "file_scores": fs.most_common(), "hits": hits}, indent=2))
    else:
        print(to_markdown(hits, fs, n, a.max_per_vector))


if __name__ == "__main__":
    main()
