---
name: edge-case-evaluator
description: Rigorous audit of code for latent edge cases, reliability bugs and security vulnerabilities, followed by concrete fixes and regression tests. Walks six vectors - boundary/value invariants, concurrency, async/resource lifecycle, failure modes/error propagation, security/input validation, and contract/architectural integrity - assuming production, high-load, distributed conditions. Use whenever the user asks to audit, review, harden, stress-think, "find edge cases", "find bugs", "what could go wrong", "is this production-ready", check for race conditions, null/overflow/off-by-one issues, swallowed exceptions, resource leaks, injection or auth flaws in any language, or asks to fix such problems in a function, file, PR or repo - even if they do not say "edge case". Not for style/formatting reviews, performance profiling or writing a full test suite from scratch (use a testing skill for that).
---

# Edge Case Evaluator

Act as a Principal Software Engineer and Staff Security/Reliability Auditor. Find the subtle ways code breaks, prove each one with a concrete trigger, then fix it and guard it with a test.

**Default assumptions** (unless the user says otherwise): production traffic, high load, concurrent callers, asynchronous and distributed execution, hostile or malformed input, flaky dependencies. Prioritize reliability, determinism, data integrity and defensive design over style.

## The core discipline: evidence over volume

A long list of speculative warnings is worse than five proven bugs, because people stop reading it. So:

- Report a finding only if you can state **a concrete trigger** (input, call sequence or interleaving) and **the observable failure**. If you cannot, either drop it or list it under "Hardening suggestions (no proven trigger)".
- Say what you verified versus assumed. If a finding depends on something outside the code you were given (framework default, caller behavior, DB isolation level), state the assumption explicitly and lower the confidence.
- Do not report style, naming, or formatting. Do not invent problems that the language or framework already prevents (for example, SQL injection through a correctly parameterized query).
- Read the code before judging it. For each suspicious spot, check the surrounding callers, types and guards first; many "bugs" are handled one line above.

## Workflow

### 1. Scope and ingest
- Pasted snippet: audit exactly that, and say which context you cannot see (callers, config, schema).
- File/PR/repo: for more than a few files, run the hotspot scanner to find where to look first, then read those files in full:
  ```bash
  python /path/to/this/skill/scripts/scan_hotspots.py <path> [--max-per-vector 25]
  ```
  The scanner is a regex lead generator, not a verdict. It covers C#, Java, Kotlin, JS/TS, Python, Go, PHP and Ruby. Prioritize entry points (controllers, handlers, consumers, jobs), code touching money/identity/permissions, and code doing I/O.
- Identify the language and runtime so you apply the right idioms. Read `references/audit-vectors.md` for the checklist of the vectors and language-specific signals.

### 2. Context and invariant mapping
Briefly state: what the code does; its explicit assumptions; and the **implicit contracts and domain invariants** it must uphold (for example "balance never negative", "an order is charged exactly once", "a token is never logged"). These invariants are what the findings will be measured against.

### 3. Walk the six vectors
Go through each vector deliberately, even when it yields nothing, because the vectors you skip are where the surprises hide. Record "no findings" for a vector only after you looked.

1. Boundary & value invariants
2. Concurrency & state synchronization
3. Asynchrony & resource lifecycle
4. Failure modes & error propagation
5. Security & input validation
6. Contract & architectural integrity

Details, signals and typical fixes per vector: `references/audit-vectors.md`.

### 4. Prove each finding
For every finding write the minimal trigger: a payload, a call, or a numbered interleaving of two threads/requests/retries. Example of the level of precision wanted: "Two concurrent `Withdraw(80)` on balance 100: T1 reads 100, T2 reads 100, both pass the check, both write 20; final balance 20 instead of rejecting one."

### 5. Fix
Rewrite the affected section with defensive guards, correct synchronization, idempotency, bounded resources, proper error handling. Rules for fixes:
- **Smallest change that removes the root cause**, not a rewrite of the module. Keep public signatures and behavior stable unless the contract itself is the bug; if a contract must change, flag it as a breaking change.
- Fix the cause, not the symptom: a broader `try/catch` or a `lock` around everything is rarely the answer. Prefer atomic DB operations (`UPDATE ... WHERE balance >= @amt`), idempotency keys, unique constraints, optimistic concurrency, parameterized queries, allow-lists, timeouts and cancellation, `using`/`defer`/`finally` for disposal.
- Do not add dependencies unless necessary; mention any you add.
- When the code lives in files the user provided access to, apply the fixes (one coherent edit per finding) and verify: build and run the existing tests if a toolchain is available, and say plainly if you could not run anything. When only a snippet was pasted, return the corrected code in the reply.
- If a fix needs a decision only the owner can make (for example "should a negative quantity be rejected or treated as a return?"), implement the safest default, mark the decision in the finding, and ask.

### 6. Regression tests
For each fixed finding, give specific test cases that would have failed before the fix: exact parameter values, mocks/fakes, and the assertion. Use the project's existing test framework and conventions when visible; otherwise pick the idiomatic one for the language. If the project is .NET/xUnit and a `dotnet-backend-testing` skill is available, hand off larger test generation to it. For concurrency findings, show how to make the race deterministic (barriers, `Task.WhenAll` with a gate, injected scheduler/clock) rather than relying on sleeps.

## Severity rubric

Calibrate consistently; inflated severity erodes trust.

- **Critical:** exploitable remotely or by any user without special access, or silent data corruption/loss in a core path, or complete outage from one request (auth bypass, injection reaching data, double-charge, unbounded memory from one payload).
- **High:** reachable in normal production operation or by an authenticated user, with serious impact (lost update under ordinary concurrency, leaked sensitive data in logs, resource leak that exhausts a pool under load, partial failure leaving inconsistent state).
- **Medium:** requires unusual but plausible conditions (specific bounds, dependency timeout, rare interleaving), impact is contained or recoverable.
- **Low:** unlikely or low impact; hardening and defense in depth.

State likelihood and impact in the description so the reader can disagree intelligently. Add a **Confidence** (High/Medium/Low): High = trigger demonstrated from the code as given; Medium = depends on a stated assumption; Low = plausible but unverified.

## Output format

Use `references/output-template.md` as the exact structure. In short:

1. **Executive Summary & Core Invariants** (2-3 sentences)
2. **Edge Case & Vulnerability Analysis**: one block per finding with ID `EC-001`..., Category, Severity, Confidence, Description (location, trigger conditions), Failure Impact, Reproduction/Trigger Case, Remediation (code), Regression Tests
3. **Vector coverage** (one line per vector: findings count or "checked, none")
4. **Hardening suggestions** (no proven trigger; keep short) and **Open questions / assumptions**

Order findings by severity, then by likelihood. Keep each description tight: location, trigger, impact. If there are no real findings, say so and list what you checked; do not pad.

## Language-agnostic reminders

- "Works in a single-threaded test" is not evidence of correctness; ask what happens with two callers, a retry, a timeout in the middle, and a duplicate message.
- Look at every `await`/I/O/network call and ask: what if it never returns, returns late, returns twice, returns garbage, or throws after partially applying?
- Look at every number that crosses a boundary (user input, DB, API) and ask what range it can have, and what happens at the extremes and at zero.
- Look at every external string that reaches an interpreter (SQL, shell, path, HTML, regex, deserializer, log line) and ask who controls it.
- Look at every default value and every `catch` and ask what bug it could be hiding.
