# FRD Quality Checklist

Reference for Phase 7 of the Functional Requirements Writer skill.
Run through this checklist before delivering the final document.

---

## ✅ Completeness Checks

- [ ] Every actor identified in source documents has a section or is listed in the Actors table
- [ ] Every feature/module from the Feature Map has a corresponding FRD section
- [ ] Every business rule from source documents is captured (check source file coverage)
- [ ] All data entities have field tables with types and validations
- [ ] Every workflow with 3+ steps has a Mermaid diagram
- [ ] All exceptions are documented under the relevant feature or in Section 7
- [ ] Glossary covers all domain-specific terms used in the document
- [ ] All assumptions are listed in Appendix A
- [ ] All open questions are listed in Section 9
- [ ] Source Document Index (Appendix B) lists every input file used

---

## ✅ Clarity Checks

- [ ] No requirement bundles two distinct rules in one sentence
- [ ] All requirements use MUST / SHOULD / MAY consistently
- [ ] No passive voice ("is done by the system" → "the system does")
- [ ] No jargon used without definition in the Glossary
- [ ] All requirement IDs are unique and follow the `[MODULE-TYPE-NNN]` format
- [ ] Every requirement cites its source document

---

## ✅ Structure Checks

- [ ] Document has a Title, Version, Date, and Author/Prepared By header
- [ ] Table of Contents is present and accurate
- [ ] Section numbering is consistent
- [ ] Tables are used for data fields (not prose)
- [ ] Mermaid code blocks are properly fenced (```mermaid)

---

## ✅ Coverage Check — Source Traceability

For each input document, verify at least one requirement was extracted:

| Source File | Requirements Extracted | Status |
|-------------|----------------------|--------|
| [file 1] | [count] | ✅ / ⚠️ Empty |
| [file 2] | [count] | ✅ / ⚠️ Empty |

If a file produced zero requirements, note the reason (e.g., "duplicate of file 1", "appendix only", "unreadable").

---

## ✅ Final Output Checks

- [ ] File saved to `/mnt/user-data/outputs/functional-requirements-document.md`
- [ ] Summary card presented to user (section count, requirement count, open questions count)
- [ ] User asked if they want revisions or export to Word/PDF

---

## Common Quality Issues to Fix Before Delivery

| Issue | Fix |
|-------|-----|
| Vague requirement: "The system should be fast" | Rewrite as: "The system MUST load the dashboard in under 2 seconds for up to 1,000 concurrent users." |
| Missing source citation | Add *(Source: filename, location)* to every requirement |
| Undocumented assumption | Move to Appendix A with rationale |
| Workflow described only in prose | Add Mermaid diagram |
| Two rules in one sentence | Split into separate numbered requirements |
| Jargon without definition | Add term to Glossary |
