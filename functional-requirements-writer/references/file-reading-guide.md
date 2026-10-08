# File Reading Guide

Reference for Phase 2 of the Functional Requirements Writer skill.
Use the correct strategy per file type to maximize content extraction.

---

## PDF Files (`.pdf`)

### Strategy
```bash
# Step 1: Extract text
pip install pdfminer.six --break-system-packages -q
python3 - <<'EOF'
from pdfminer.high_level import extract_pages
from pdfminer.layout import LTTextContainer
import sys

with open("/mnt/user-data/uploads/FILE.pdf", "rb") as f:
    for page_num, page_layout in enumerate(extract_pages(f), 1):
        print(f"\n--- Page {page_num} ---")
        for element in page_layout:
            if isinstance(element, LTTextContainer):
                print(element.get_text())
EOF
```

### What to capture
- Section headings (larger font, bold, numbered)
- Tables — note row/column structure
- Numbered lists = likely ordered process steps
- Bullet lists = likely business rules or features
- Page headers/footers — often contain document metadata (version, date, owner)

### Fallback (scanned PDF)
If text extraction yields garbage or nothing, note: *"[filename] appears to be a scanned image PDF. Text extraction is limited."* Extract any visible text from the tool output and flag uncertain items with `[OCR-UNCERTAIN]`.

---

## Word Documents (`.docx`)

### Strategy
```bash
pip install python-docx --break-system-packages -q
python3 - <<'EOF'
from docx import Document

doc = Document("/mnt/user-data/uploads/FILE.docx")

for para in doc.paragraphs:
    style = para.style.name
    text = para.text.strip()
    if text:
        print(f"[{style}] {text}")

print("\n=== TABLES ===")
for i, table in enumerate(doc.tables):
    print(f"\n-- Table {i+1} --")
    for row in table.rows:
        print(" | ".join(cell.text.strip() for cell in row.cells))
EOF
```

### What to capture
- Heading 1/2/3 styles → document structure
- Normal paragraphs → narrative rules
- Tables → structured data, decision rules, field definitions
- Bold text within paragraphs → often key terms or mandatory items
- Numbered styles → process steps

---

## Excel Files (`.xlsx`, `.xls`, `.csv`)

### Strategy
```bash
pip install openpyxl pandas --break-system-packages -q
python3 - <<'EOF'
import pandas as pd

# For xlsx
xl = pd.ExcelFile("/mnt/user-data/uploads/FILE.xlsx")
print("Sheets:", xl.sheet_names)

for sheet in xl.sheet_names:
    df = pd.read_excel(xl, sheet_name=sheet)
    print(f"\n=== Sheet: {sheet} ===")
    print(df.to_string())
EOF
```

```bash
# For CSV
python3 -c "
import pandas as pd
df = pd.read_csv('/mnt/user-data/uploads/FILE.csv')
print(df.to_string())
"
```

### What to capture
- Sheet names → often indicate functional modules (e.g., "Pricing Rules", "User Roles")
- Column headers → data field names
- Row data → rule configurations, lookup tables, validation values
- Conditional formatting hints (note: may not be visible in extraction, flag if suspected)
- Formula columns → computed business logic (describe the formula logic in plain text)

---

## Plain Text / Markdown (`.txt`, `.md`)

### Strategy
```bash
cat /mnt/user-data/uploads/FILE.txt
```

### What to capture
- Same as Word documents — look for implicit heading structure (ALL CAPS lines, numbered lines)
- Code blocks → may contain data schemas or API definitions
- Tables (Markdown format) → treat as structured data

---

## Multi-file Reading Order

When multiple files are present, read in this preferred order:

1. **Main specification document** (usually the largest PDF or docx)
2. **Business rules documents** (named "rules", "policies", "constraints")
3. **Data model / schema files** (Excel sheets with field definitions)
4. **Process / workflow documents** (named "flow", "process", "procedure")
5. **Supporting / reference documents** (named "glossary", "reference", "appendix")

If order is ambiguous, present the inventory to the user and ask which file is the "primary" specification.
