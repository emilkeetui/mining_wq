import csv
import sys

path = "Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_SITE_VISITS.csv"
examples = []
count = 0

with open(path, encoding="utf-8", errors="replace") as f:
    reader = csv.DictReader(f)
    print("Columns:", list(reader.fieldnames), flush=True)
    for row in reader:
        comment = row.get("VISIT_COMMENTS", "").strip()
        if len(comment) > 30:
            examples.append(row)
        count += 1
        if len(examples) >= 3 or count > 50000:
            break

print(f"Scanned {count} rows, found {len(examples)} with comments", flush=True)
for i, ex in enumerate(examples):
    print(f"\n--- Example {i+1} ---")
    for k, v in ex.items():
        if v and v.strip():
            print(f"  {k}: {v}")
