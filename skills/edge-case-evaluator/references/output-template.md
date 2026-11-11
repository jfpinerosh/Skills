# Output template

Use this structure. Replace bracketed text; delete nothing structural. Keep prose tight: location, trigger, impact.

````markdown
### 1. Executive Summary & Core Invariants
[2-3 sentences: overall quality, primary risks, and the operational invariants that matter most
(for example "an order is charged exactly once; stock never goes negative").]

**Scope reviewed:** [files/functions]  |  **Not visible / assumed:** [callers, config, DB isolation, etc.]

### 2. Edge Case & Vulnerability Analysis

#### [EC-001] [Short title]
- **ID:** `EC-001`
- **Category:** `[Boundary | Concurrency | Async/Resource | Error Handling | Security | State]`
- **Severity:** `[Critical | High | Medium | Low]`
- **Confidence:** `[High | Medium | Low]` - [one clause: why, or the assumption it depends on]
- **Description:** [What happens, exact location (`File.cs:42`, `Withdraw()`), and the trigger conditions.]
- **Failure Impact:** [Data corruption, deadlock, crash, unhandled panic, security compromise, ...]
- **Reproduction / Trigger Case:**
  ```<language>
  // Concrete call, payload, or numbered interleaving that triggers the bug
  ```
- **Remediation:**
  ```<language>
  // Corrected code (only the affected section), with a brief comment on why it works
  ```
  [One or two sentences on why this fixes the root cause, and any behavior/contract change to flag.]
- **Regression Tests:**
  | Case | Setup / mocks | Input | Expected |
  |---|---|---|---|
  | [name] | [fakes, state] | [exact values] | [assertion] |

(repeat for EC-002, EC-003 ... ordered by severity, then likelihood)

### 3. Vector Coverage
| Vector | Result |
|---|---|
| Boundary & Value Invariants | [N findings (IDs) or "checked, none"] |
| Concurrency & State Synchronization | ... |
| Asynchrony & Resource Lifecycle | ... |
| Failure Modes & Error Propagation | ... |
| Security & Input Validation | ... |
| Contract & Architectural Integrity | ... |

### 4. Hardening Suggestions (no proven trigger)
- [Short bullet: what and why. Keep to the few that matter.]

### 5. Open Questions & Assumptions
- [Decisions the owner must make, e.g. "Should negative quantity mean return or be rejected?"]
- [Anything you could not verify: not run, not visible, environment-dependent.]
````

## Notes

- When fixes were **applied to files**, add a short "Changes applied" list (file, finding ID, what changed) and what was run to verify (build/tests/none). Say clearly if nothing could be executed.
- For a repo-wide audit with more than ~10 findings, print a one-table index at the top of section 2 (ID, severity, category, location, title) before the detailed blocks.
- Worked mini-example of a good finding:

````markdown
#### [EC-001] Lost update on concurrent withdrawals
- **ID:** `EC-001`
- **Category:** `Concurrency`
- **Severity:** `High`
- **Confidence:** `High` - read and write are separate statements with no lock or version check.
- **Description:** `AccountService.Withdraw` (AccountService.cs:31-40) reads the balance, checks `balance >= amount` in memory, then writes `balance - amount`. Two requests interleaving between the read and the write both pass the check.
- **Failure Impact:** Overdraft; final balance reflects only one of the two withdrawals (data corruption).
- **Reproduction / Trigger Case:**
  ```csharp
  // balance = 100
  await Task.WhenAll(svc.Withdraw(id, 80), svc.Withdraw(id, 80));
  // Both read 100, both write 20. Expected: one succeeds, one is rejected.
  ```
- **Remediation:**
  ```csharp
  var rows = await db.Database.ExecuteSqlInterpolatedAsync(
      $"UPDATE Accounts SET Balance = Balance - {amount} WHERE Id = {id} AND Balance >= {amount}", ct);
  if (rows == 0) throw new InsufficientFundsException(id, amount);
  ```
  The check and the write are one atomic statement, so the database serializes concurrent callers.
- **Regression Tests:**
  | Case | Setup / mocks | Input | Expected |
  |---|---|---|---|
  | Concurrent withdrawals | real test DB, balance 100 | two parallel `Withdraw(80)` | exactly one succeeds; balance 20 |
  | Exact balance | balance 80 | `Withdraw(80)` | succeeds; balance 0 |
  | Zero/negative | balance 100 | `Withdraw(0)`, `Withdraw(-5)` | `ArgumentOutOfRangeException` |
````
