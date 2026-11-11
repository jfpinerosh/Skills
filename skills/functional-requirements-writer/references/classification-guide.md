# Classification Guide

Reference for Phase 3 of the Functional Requirements Writer skill.
Use these definitions and patterns to classify every extracted item correctly.

---

## Classification Types

### 🧑 ACTOR
A person, system, or external service that interacts with the software.

**Signals in text:** "the user", "admin", "manager", "the system", "third-party API", "customer"

**Examples:**
- "Customers can place orders" → Actor: Customer
- "Admins can deactivate accounts" → Actor: Admin
- "The payment gateway returns a token" → Actor: Payment Gateway (External System)

**Output format:**
```
Actor: Customer
Description: A registered user who browses and purchases products
Permissions: Browse catalog, place orders, view own order history
```

---

### ⚙️ FUNCTIONAL REQUIREMENT (FR)
Something the system must DO — a capability, behavior, or function.

**Signals in text:** "the system allows", "users can", "the application must", "it should be possible to"

**Decision test:** Can you write "The system SHALL ___" and have it make sense? → FR.

**Examples:**
- "Users can reset their password via email" → FR: Password Reset
- "The system exports reports in PDF and CSV" → FR: Report Export

---

### 📋 BUSINESS RULE (BR)
A constraint, condition, policy, or decision logic that governs behavior.

**Signals in text:** "only if", "must not", "cannot", "is required when", "applies when", "except when", percentage/threshold values, time limits, conditional logic.

**Decision test:** Does it constrain or condition something rather than describe a feature? → BR.

**Examples:**
- "Discounts only apply to orders over $50" → BR: Discount Threshold
- "Users under 18 cannot purchase alcohol items" → BR: Age Restriction
- "Invoices must be paid within 30 days" → BR: Payment Terms

---

### 🗄️ DATA REQUIREMENT (DR)
Fields, entities, types, formats, or validation rules for data.

**Signals in text:** field names, data types, "must be", "format:", "max characters", "required field", "unique", table column headers.

**Decision test:** Does it describe what data is stored, its format, or how it's validated? → DR.

**Examples:**
- "Email must be unique per account" → DR: Email Uniqueness
- "Phone number: 10 digits, numeric only" → DR: Phone Format
- "Order date defaults to today's date" → DR: Order Date Default

---

### 🔄 WORKFLOW (WF)
An ordered sequence of steps, states, or transitions.

**Signals in text:** numbered steps, "first... then... finally", flowchart descriptions, status transitions ("from X to Y"), "the process is:", "the flow is:".

**Decision test:** Is there a defined sequence of events or states? → WF.

**Examples:**
- "Order goes through: Draft → Submitted → Approved → Shipped → Delivered" → WF: Order Status Lifecycle
- "1. User fills form, 2. System validates, 3. Email is sent" → WF: Registration Flow

---

### ⚠️ EXCEPTION / ERROR HANDLING (EX)
What happens when something goes wrong, a rule is violated, or a condition is not met.

**Signals in text:** "if not", "when invalid", "in case of error", "on failure", "otherwise", "if missing".

**Examples:**
- "If payment fails, show error code and retry option" → EX: Payment Failure
- "If email already exists, display: 'This email is already registered'" → EX: Duplicate Email

---

### 🚀 NON-FUNCTIONAL HINT (NF)
Performance, security, availability, compliance, or scalability notes found in business documents.
*(Not the main focus of an FRD, but must be captured and surfaced.)*

**Signals in text:** "must respond within", "must be available 99.9%", "GDPR compliant", "encrypted", "auditable", "scalable to N users".

---

## Priority Assignment

Assign priority to every item using these keywords from the source text:

| Source Signal | Assigned Priority |
|---------------|-------------------|
| "must", "shall", "required", "mandatory" | **MUST** |
| "should", "recommended", "preferred" | **SHOULD** |
| "may", "can", "optional", "nice to have" | **MAY** |
| No signal / ambiguous | **TBD** — flag for user |

---

## Feature Map Building

After classifying all items, group them into **Feature Modules** — logical areas of the application.

**Approach:**
1. Look for natural clusters of actors + FRs + BRs that reference the same domain concept.
2. Name each module concisely (e.g., "User Authentication", "Product Catalog", "Billing").
3. Each module becomes a section in the FRD (Section 3.x).

**Example Feature Map:**
```
Module: User Authentication
  Actors: User, Admin
  FRs: Login, Logout, Password Reset, 2FA
  BRs: Lockout Policy, Password Complexity, Session Timeout
  DRs: Email format, Password hash storage
  WFs: Login Flow, Password Reset Flow
  EXs: Invalid credentials, Account locked

Module: Order Management
  Actors: Customer, Warehouse Staff, System
  FRs: Place Order, Cancel Order, Track Order
  BRs: Minimum order value, Stock availability check
  ...
```

---

## Contradiction Detection

As you build the feature map, flag contradictions:

| Type | Example |
|------|---------|
| **Rule conflict** | Doc A: "Sessions expire after 30 min" / Doc B: "Sessions expire after 1 hour" |
| **Permission conflict** | Doc A: "Only admins can delete" / Doc B: "Managers can also delete records" |
| **Data conflict** | Spec says "phone is optional" / Form shows phone as required field |

Flag format:
```
⚡ CONTRADICTION: [MODULE] — [short description]
  Source A: [file, location] → "[text]"
  Source B: [file, location] → "[text]"
  Resolution needed: Yes / Assumed: [your assumption]
```
