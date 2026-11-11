# Audit vectors: checklists, signals and fixes

## Contents
1. Boundary & value invariants
2. Concurrency & state synchronization
3. Asynchrony & resource lifecycle
4. Failure modes & error propagation
5. Security & input validation
6. Contract & architectural integrity
7. Cross-vector combinations

For each vector: what to ask, language signals to grep for, and the usual root-cause fix.

---

## 1. Boundary & value invariants

**Ask:** What are the allowed ranges of every input and intermediate value? What happens at null, empty, whitespace, zero, negative, min/max, and one past each boundary?

| Check | Signals | Typical fix |
|---|---|---|
| Null / missing | unchecked deref, `.Value` on nullable, `Optional.get()`, `obj.prop.sub`, `dict[key]` | Validate at the boundary, fail fast with a clear error; use non-null types or `TryGet` |
| Empty / whitespace | `string.IsNullOrEmpty` where whitespace should count, `len(x) == 0` only, `split` results indexed at `[0]` | Normalize and trim, `IsNullOrWhiteSpace`, check collection count before indexing |
| Off-by-one | `<=` vs `<`, `Substring`, slicing, `i+1`, pagination (`page * size`, page 0 vs 1), inclusive/exclusive ranges | Test at n-1, n, n+1; use range helpers; name bounds explicitly |
| Overflow / underflow | `int` arithmetic on sizes/money/ids, `a + b`, `a * b`, casting `long`->`int`, JS numbers > 2^53, `unchecked` | Wider type, `checked` arithmetic / `Math.addExact` / BigInt / `Decimal`; validate before computing |
| Precision | `float`/`double` for money, `==` on floats, rounding mode, currency scale, accumulating errors | `decimal`/`BigDecimal`/integer minor units; explicit rounding mode; compare with tolerance only for non-money |
| Zero / negative | division, modulo, `Math.Abs(int.MinValue)`, negative quantity/amount/limit/offset, zero-length batch | Guard clauses; reject or define semantics explicitly |
| Type coercion | JS `==`, string->number parsing, implicit enum/int casts, `parseInt` without radix, culture-dependent parse/format | Strict parsing with invariant culture, `TryParse`, `===`, validate enum membership (`Enum.IsDefined`) |
| Dates/time | local vs UTC, DST, `DateTime.Now`, leap day, month overflow, epoch seconds vs millis, timezone-less storage | UTC internally, `DateTimeOffset`/`Instant`, injected clock |
| Unicode / encoding | length vs bytes, normalization, case-insensitive compare with culture, truncation mid-surrogate | Ordinal/invariant comparisons, normalize, limit by bytes where stored |
| Collections | empty list `.First()`/`.Max()`/`.Average()` (throws), huge lists, duplicates, mutation while iterating | `FirstOrDefault`+check, bounds, copy before iterating |

## 2. Concurrency & state synchronization

**Ask:** If two callers (threads, requests, instances, retries, duplicate messages) run this at the same time, or the same one runs twice, what breaks?

Signals: check-then-act (`if (!exists) insert`), read-modify-write (`x = x + 1`, `balance -= a` after a read), static/shared mutable fields, `Dictionary`/`HashMap`/list shared across threads, lazy init without sync, singleton holding per-request state, double-checked locking without `volatile`, `lock` held across `await`/I/O, nested locks with inconsistent order, `async` re-entrancy (callback fires while state is mid-update), event handlers mutating shared state, caches without stampede protection, background jobs run by several instances.

| Problem | Fix |
|---|---|
| Lost update in DB | Atomic statement (`UPDATE t SET b = b - @a WHERE id=@id AND b >= @a`), optimistic concurrency (row version / ETag), `SELECT ... FOR UPDATE`, serializable transaction when needed |
| Check-then-insert race | Unique constraint + handle conflict (`INSERT ... ON CONFLICT`), not an `if` |
| In-memory shared state | `ConcurrentDictionary`/`AtomicInteger`/`Interlocked`, immutable snapshots, a single owner (actor/channel), or a lock with minimal scope |
| Deadlock | Consistent lock ordering, no locks across I/O, timeouts, `SemaphoreSlim` with `WaitAsync` instead of `lock` around `await` |
| Non-idempotent operation | Idempotency key stored with the effect in the same transaction, dedupe table, natural idempotent upsert, "exactly-once effect" via outbox + inbox |
| Distributed duplicates (retries, at-least-once queues) | Treat every message handler as retry-safe; version/sequence checks; distributed lock only with fencing tokens and TTL |
| Cache stampede / double init | Single-flight (`Lazy<Task<T>>`, `sync.Once`, `singleflight`), jittered TTL |
| Re-entrancy | Do not call out (callbacks, events, virtual methods) while holding invariants broken; snapshot state before invoking |

Also check: transaction boundaries (is the read inside the same transaction as the write?), isolation level assumptions, and `async` code that assumes ordering.

## 3. Asynchrony & resource lifecycle

**Ask:** What happens if this operation never completes, completes late, is cancelled, or throws halfway? Who disposes what, on every path?

Signals:
- Unobserved failures: `async void`, fire-and-forget (`_ = DoAsync()`, `Task.Run` without handling, `go func()` without recovery, JS promise without `.catch`/`await`), `.then` chains without terminal catch, `Promise.all` where one rejection abandons the rest, `forEach(async ...)` (does not await).
- Blocking: `.Result`/`.Wait()`/`GetAwaiter().GetResult()` (deadlock/thread starvation), sync I/O in async path, `Thread.Sleep`.
- Cancellation/timeouts: no `CancellationToken` passed down, token ignored in loops, no timeout on `HttpClient`/DB/socket calls (default can be infinite or 100 s), `CancellationTokenSource` not disposed, swallowing `OperationCanceledException` as an error.
- Leaks: `HttpClient` created per request (socket exhaustion) or `new HttpClient()` without `IHttpClientFactory`, `IDisposable` not in `using`, streams/readers not closed on exception paths, DB connections held across slow calls, event handlers never unsubscribed, unbounded caches/queues/channels, timers never stopped, `defer` in loops (Go), listeners and goroutines that never exit.
- Unbounded work: `Task.WhenAll` over unbounded input, unbounded concurrency to a dependency, no backpressure, reading a whole file/response into memory.

Fixes: pass and honor cancellation, set explicit timeouts, `using`/`try-finally`/`defer`/context managers, `IHttpClientFactory`/shared client, bounded concurrency (`SemaphoreSlim`, `Parallel.ForEachAsync` with `MaxDegreeOfParallelism`, worker pool), bounded channels, streaming instead of buffering, await every task and surface its failure, `ConfigureAwait(false)` in libraries, never `async void` except event handlers.

## 4. Failure modes & error propagation

**Ask:** If step N of M fails, what state is the system left in? What does the caller see? What happens when the dependency is down, slow, or returns garbage?

Signals: empty `catch`, `catch (Exception)` that logs and continues, `catch` that returns a default/`null`/`false`, `except: pass`, `_ = err` (Go), `.catch(() => {})`, rethrow that loses the stack (`throw ex;`), multi-step writes without a transaction (DB + message broker + cache + external API), no compensation, retries without backoff/jitter/limit, retries of non-idempotent calls, no circuit breaker, treating HTTP 200 as success without validating the body, deserializing responses into non-nullable models blindly, error messages used for control flow, `finally` that throws and masks the original error.

Fixes:
- Catch narrowly and only where you can act; otherwise let it propagate with context (`throw;`, wrapped exception with `InnerException`, `%w` in Go).
- Make multi-step operations atomic or compensatable: single transaction, outbox pattern, saga with compensations, idempotent retry.
- External calls: timeout + bounded retry with exponential backoff and jitter only for idempotent/safe operations + circuit breaker; validate status, content type and schema; handle empty body, truncated body, wrong types, extra/missing fields, unexpected enum values.
- Fail closed: on auth/validation uncertainty deny; on a missing config value, fail at startup, not at first use.
- Make failures observable: structured log with correlation id, metric, and the right exception type, without leaking secrets.

## 5. Security & input validation

**Ask:** Who controls each value? Where does it end up? Is each caller authorized for exactly this action on exactly this object?

| Class | Signals | Fix |
|---|---|---|
| SQL injection | string concatenation/interpolation/format into SQL, dynamic `ORDER BY`/column/table names, `FromSqlRaw($"...")`, ORM `raw()` | Parameters always; allow-list identifiers |
| Command injection | `Process.Start`, `Runtime.exec`, `os.system`, `subprocess(shell=True)`, backticks, `exec` with user-built strings | Avoid the shell, pass argument arrays, allow-list |
| Path traversal | user input in file paths, `Path.Combine(base, user)` (absolute path overrides base), `../`, zip entries (zip-slip), symlinks | Canonicalize and verify the result stays under the base directory; generate server-side filenames |
| XSS / output injection | unescaped HTML, `innerHTML`, `dangerouslySetInnerHTML`, templates with raw output, header injection (CRLF), log injection | Context-aware encoding, CSP, sanitize with a vetted library, strip CR/LF in headers/logs |
| SSRF / open redirect | server fetches user-supplied URL, redirect to `returnUrl` param | Allow-list hosts, block private/link-local ranges after DNS resolution, validate redirect targets |
| Deserialization | `BinaryFormatter`, `pickle.loads`, `yaml.load`, Java `ObjectInputStream`, `TypeNameHandling` != None, `eval`, polymorphic JSON from untrusted source | Safe formats and safe loaders, explicit DTOs, allow-listed types |
| AuthN/AuthZ | missing `[Authorize]`, check only in UI, IDOR (`/orders/{id}` without ownership check), mass assignment (binding client JSON straight to entity incl. `isAdmin`), role from client, JWT without signature/expiry/audience checks, default-allow | Server-side authorization on every action and object, DTOs with allow-listed fields, deny by default |
| Secrets & data leakage | secrets in code/config/logs, PII or tokens in logs and exception messages, stack traces returned to clients, verbose errors | Secret store, redact, generic client errors with correlation id |
| Timing / crypto | `==` on secrets/tokens/MACs, `Random` for tokens, MD5/SHA1 for passwords, home-made crypto, static IV, no salt | Constant-time compare (`CryptographicOperations.FixedTimeEquals`, `hmac.compare_digest`), CSPRNG, bcrypt/scrypt/argon2, vetted libraries |
| Resource abuse | regex with catastrophic backtracking (ReDoS), no request size limit, zip bombs, unbounded pagination (`pageSize=1e9`), no rate limit | Size limits, timeouts on regex, cap page sizes, rate limiting |
| CSRF / CORS | state change on GET, wildcard CORS with credentials | Anti-forgery tokens/SameSite, strict origins |

Validate at the boundary (type, range, length, format, allow-list), then treat validated data as trusted internally.

## 6. Contract & architectural integrity

**Ask:** What must be true before, during and after each operation, and does the code enforce it or merely hope?

Signals: functions that return a default (`0`, `""`, `null`, empty list) on failure so callers cannot tell "none" from "error"; `?? default` hiding a missing required value; `Enum` switch without default/exhaustiveness (new state silently ignored); state machines with no transition validation (`Shipped -> Pending` possible); public setters allowing invalid objects; invariants checked in one code path but not another; DTO/schema drift (new column or field not mapped, optional field becoming required, enum values added by another service); preconditions documented but not checked; postconditions (sorted, unique, non-empty, totals equal) not verified; "impossible" branches that do nothing; leaky abstractions (callers must know call order); boolean flags that create illegal combinations.

Fixes: make illegal states unrepresentable (constructors/factories that validate, immutable types, private setters), explicit state-transition tables with rejection of invalid transitions, exhaustive switches that throw on unknown, `Result`/`Option` types or exceptions instead of magic defaults, assertions on postconditions at boundaries, schema validation and versioning for payloads, unique/foreign-key/check constraints in the database as the last line of defense.

## 7. Cross-vector combinations

Real incidents are usually combinations; look for them explicitly:
- Retry (failure vector) + non-idempotent write (concurrency) = duplicate charge.
- Timeout missing (async) + connection pool (resource) = whole service stalls from one slow dependency.
- Swallowed exception (failure) + silent default (contract) = wrong data accepted as valid.
- Missing authorization (security) + sequential ids (boundary) = enumeration of all records.
- Catch-and-continue in a loop (failure) + partial commit (state) = half-processed batch with no way to resume.
- Cancellation ignored (async) + holding a lock (concurrency) = lock never released under shutdown.
