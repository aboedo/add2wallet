# Known Issues — add2wallet backend

Last updated: 2026-03-05  
Source: eval run with real AI pipeline against Ignacio's feedback PDFs.

---

## 🔴 Bug: Multiple passes generated for single-ticket PDFs

**Affected:** Reina Sofía (3 passes), Monasterio Lisboa (2 passes), Orsay (2 passes), JO Paris (2 passes), Málaga-Madrid (?)  
**File:** `backend/app/services/pass_generator.py` → `_consolidate_barcodes_for_single_pass()`  
**Root cause:** When a PDF contains multiple distinct barcodes (e.g. 2 DataMatrix + 1 QR, or 2 CODE128 with different data), the consolidator treats each as a separate ticket. It should detect that these are redundant codes for the same entry (e.g. adult/child variants, duplicate scan points) and emit 1 pass using the primary barcode.  
**Evidence from logs:**
- Reina Sofía: `Found 3 barcodes in PDF` → `Consolidating 3 barcodes for single-pass document` → `Detected 3 ticket(s)` — consolidation is logging but not consolidating
- Orsay: `Found 2 barcodes in PDF` → `CODE128 - 53693432964580` and `CODE128 - 53693432964601` (different data, same ticket)
- Monasterio: similar pattern

**Note on JO Paris:** 2 passes may actually be correct (2 separate entries for same event). Needs human review.

---

## 🔴 Bug: `date` field missing from `ticket_info` return value

**Affected:** Catedral Málaga, Oppenheimer, Cine Gladiador, JO Paris, Peñarol, Oppenheimer — all PDFs where date comes from AI metadata  
**File:** `backend/app/services/pass_generator.py` → `create_pass_from_pdf_data()` return value  
**Root cause:** The AI extracts the date correctly (visible in logs: `Date: 2024-01-20`) and it gets added to the pass fields ("Added date: 2024-01-20"), but `ticket_info[0].get("date")` returns empty/None. The `ticket_info` dict being returned doesn't include `date` from ai_metadata — it only propagates some fields.  
**Impact:** The eval test reads date from `ticket_info`; the actual pass.json has the date correctly. So the pass itself is correct but the API response metadata is incomplete. Clients that rely on `ticket_info` in the API response won't see the date.

---

## 🟡 Bug: `TypeError: bytes not JSON serializable` in ticket_info

**Affected:** Madrid-Medellín (and potentially any PDF with PDF417/binary barcodes)  
**File:** `backend/app/services/pass_generator.py` — `ticket_info` dict includes `primary_barcode` which contains `raw_bytes: bytes`  
**Root cause:** `ticket_info` returned by the pipeline contains the full barcode dict including `raw_bytes` (type `bytes`). Any code that tries to JSON-serialize `ticket_info` (e.g. tests, API response serialization) will crash.  
**Fix:** Strip or base64-encode `raw_bytes` before including in `ticket_info`, or exclude it entirely (it's already in the pass).

---

## 🟡 Incorrect eval expectations (test bugs, not code bugs)

These tests fail because the expectation in `test_ignacio_eval.py` is wrong, not the code:

- **Peñarol title:** Expected `"peñarol"` in title, but AI correctly returns `"Semifinal Campeonato Uruguayo"`. Fix: change expected_title to `"semifinal"` or `"uruguayo"`.
- **Notre-Dame title:** Expected `"notre"` but AI may return a different form. Fix: broaden the check or update expected_title after reviewing actual AI output.
- **Madrid-Medellín origin check:** The `json.dumps(ticket_info)` call crashes on `raw_bytes`. Fix: use the bytes serialization fix above, then re-check origin logic.

---

## 🟡 Orsay: date not extractable (image-only PDF)

**Affected:** 11-Orsay.pdf  
**Root cause:** `Extracted 0 characters of text` — the PDF is a scanned image with no embedded text. AI has nothing to work with. Date cannot be extracted without OCR.  
**Current behavior:** Pass is generated without date field.  
**Possible fix:** Add OCR fallback (e.g. pytesseract on the rendered page image) when text extraction yields 0 chars. Out of scope for now.

---

## 🟡 Abu Dhabi-Madrid: sparse data (no date/time)

**Affected:** 2-AbuDhabi-Madrid.pdf  
**Root cause:** Flight PDF likely has date in a non-standard format or embedded in barcode data. AI doesn't extract it reliably.  
**Status:** Barcode (PDF417) now correctly detected via zxing-cpp. Data quality issue remains.

---

## ✅ Fixed today (2026-03-05)

- **Peñarol (12):** 6 QR false positives → 1 PDF417 correct barcode. Fix: added zxing-cpp engine; zxing takes priority over pyzbar QRCODE when both scan same page. Required adding `g++` + `cmake` to Dockerfile.
- **HTTP 400 on Málaga-Madrid (3):** Was failing at upload. Now generates 1 pass.
- **Benfica (4):** Was "data couldn't be read". Now generates pass.

---

## 🏗️ Architecture debt

- **v1 pass_generator.py** is 1882 lines and growing. Every fix is a patch on top of patches.
- **v2 pipeline** (`backend/app/services/v2/`) was scaffolded (~1440 lines) but never completed or connected to any endpoint. Decision pending: finish v2 properly or keep maintaining v1.
- **pyzbar limitations:** pyzbar cannot read many PDF417 barcodes. zxing-cpp is more capable but requires C++ build tooling. Consider making zxing the primary engine.

---

## How to run the eval suite

```bash
cd backend
OPENAI_API_KEY=sk-... pytest tests/eval/test_ignacio_eval.py -v
```

Results saved to `tests/eval/results/YYYY-MM-DD_HH-MM.json`.

Current score: **1/13 passing** (only 2-AbuDhabi-Madrid passes — 1 pass, correct PDF417 barcode).
