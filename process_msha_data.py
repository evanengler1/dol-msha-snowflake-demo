#!/usr/bin/env python3
"""
Process the downloaded DOL MSHA bulk CSV ZIPs (data.dol.gov "Download Complete Dataset"):
  1. Read every CSV chunk inside data/MSHA_{api_name}.zip, streaming row by row
  2. Filter the 7 fact tables to 2010+ (dimension/lookup tables and assessed violations load in full)
  3. Lowercase column names and write one gzip CSV per dataset to
     output/msha-raw/{api_name}/{api_name}.csv.gz (default, for an internal stage)
     or upload it to s3://$MSHA_S3_BUCKET/msha-raw/{api_name}/{api_name}.csv.gz (--target s3)
  4. Write data/manifest.json with read/kept counts per dataset

Values are written exactly as read (raw layer, no transformation; "NaT" and blanks kept).

Usage:
    1. Place the 14 MSHA_*.zip files in data/
    2. python3 process_msha_data.py [--only accident,mines]
       then upload output/msha-raw/ to the internal stage (see sql/03_load.sql)
    or
    2. export MSHA_S3_BUCKET=<bucket> plus AWS credentials (pip install boto3)
       python3 process_msha_data.py --target s3
"""

import argparse
import csv
import gzip
import io
import json
import logging
import os
import shutil
import sys
import tempfile
import zipfile
from datetime import datetime, timezone

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
    datefmt="%H:%M:%S",
)
log = logging.getLogger(__name__)

S3_BUCKET = os.environ.get("MSHA_S3_BUCKET")  # only needed for --target s3
S3_PREFIX = "msha-raw"
OUTPUT_DIR = os.path.join("output", S3_PREFIX)
DATA_DIR = "data"
MANIFEST_PATH = os.path.join(DATA_DIR, "manifest.json")

# Some accident narratives exceed the csv module's default 128 KB field limit guard
csv.field_size_limit(sys.maxsize)

# api_name -> (filter field, cutoff, kind). Dates are ISO strings ("2010-01-01 00:00:00+00:00"),
# so comparing the first 10 characters is valid; year fields compare as 4-character strings.
# None = load in full.
DATASETS = {
    "accident": ("AI_DT", "2010-01-01", "date"),
    "inspection": ("BEG_DT", "2010-01-01", "date"),
    "violation": ("ISS_DT", "2010-01-01", "date"),
    "operator_employment_production_quarterly": ("EMPL_PROD_YR", "2010", "year"),
    "operator_employment_production_annual": ("CALENDAR_YR", "2010", "year"),
    "contractor_employment_production_quarterly": ("EMPL_PROD_YR", "2010", "year"),
    "contractor_employment_production_annual": ("CALENDAR_YR", "2010", "year"),
    "assessed_violations": None,
    "mines": None,
    "operator_history_at_mines": None,
    "contractor_history_at_mines": None,
    "controller_history": None,
    "commodity_lookup": None,
    "contractor_name_id_lookup": None,
}


def zip_path_for(api_name: str) -> str:
    return os.path.join(DATA_DIR, f"MSHA_{api_name}.zip")


def check_zips(names: list[str]) -> None:
    missing = [n for n in names if not os.path.exists(zip_path_for(n))]
    if missing:
        log.error("Missing ZIPs in %s/: %s", DATA_DIR, ", ".join(f"MSHA_{m}.zip" for m in missing))
        sys.exit(1)


def keep_row(value: str, cutoff: str, kind: str) -> bool | None:
    """True/False for the filter decision; None when the filter value is blank or NaT."""
    v = (value or "").strip()
    if v == "" or v == "NaT":
        return None
    if kind == "date":
        return v[:10] >= cutoff
    # year fields may come through as "2010" or "2010.0"
    return v[:4] >= cutoff


def process_dataset(api_name: str, tmp_path: str) -> dict:
    zip_path = zip_path_for(api_name)
    spec = DATASETS[api_name]
    log.info("=== %s (%s) ===", api_name, zip_path)

    with zipfile.ZipFile(zip_path, "r") as zf:
        chunks = sorted(
            (n for n in zf.namelist() if n.lower().endswith(".csv")),
            key=lambda n: int(n.rsplit("_", 1)[-1].split(".")[0]) if n.rsplit("_", 1)[-1].split(".")[0].isdigit() else n,
        )
        if not chunks:
            raise RuntimeError(f"No CSV files in {zip_path}")
        log.info("  %d chunk(s): %s", len(chunks), ", ".join(chunks))

        header = None
        rows_read = rows_kept = rows_null_filter = 0
        with gzip.open(tmp_path, "wt", encoding="utf-8", newline="") as out:
            writer = csv.writer(out, quoting=csv.QUOTE_MINIMAL)
            for chunk in chunks:
                log.info("  Reading %s ...", chunk)
                with zf.open(chunk) as f:
                    # utf-8-sig strips the BOM at the start of each chunk's header
                    reader = csv.reader(io.TextIOWrapper(f, encoding="utf-8-sig", newline=""))
                    chunk_header = next(reader)
                    if header is None:
                        header = chunk_header
                        writer.writerow([c.lower() for c in header])
                        filter_idx = header.index(spec[0]) if spec else None
                        log.info("  %d columns", len(header))
                    elif chunk_header != header:
                        raise RuntimeError(f"{api_name}: header in {chunk} differs from first chunk")

                    for row in reader:
                        rows_read += 1
                        if len(row) != len(header):
                            raise RuntimeError(
                                f"{api_name}: row {rows_read} in {chunk} has {len(row)} fields, expected {len(header)}"
                            )
                        if spec:
                            decision = keep_row(row[filter_idx], spec[1], spec[2])
                            if decision is None:
                                rows_null_filter += 1
                                continue
                            if not decision:
                                continue
                        writer.writerow(row)
                        rows_kept += 1
                        if rows_read % 500_000 == 0:
                            log.info("    ... %d read, %d kept", rows_read, rows_kept)

    st = os.stat(zip_path)
    log.info("  DONE: %d read, %d kept, %d null/NaT filter value", rows_read, rows_kept, rows_null_filter)
    return {
        "zip_file": os.path.basename(zip_path),
        "zip_size_bytes": st.st_size,
        "zip_modified": datetime.fromtimestamp(st.st_mtime, timezone.utc).isoformat(),
        "chunks": chunks,
        "filter": None if not spec else {"field": spec[0], "cutoff": spec[1]},
        "rows_read": rows_read,
        "rows_kept": rows_kept,
        "rows_dropped_null_filter": rows_null_filter,
        "columns": [c.lower() for c in header],
    }


def upload(s3, tmp_path: str, api_name: str) -> str:
    key = f"{S3_PREFIX}/{api_name}/{api_name}.csv.gz"
    log.info("  Uploading %.1f MB to s3://%s/%s ...", os.path.getsize(tmp_path) / 1e6, S3_BUCKET, key)
    s3.upload_file(tmp_path, S3_BUCKET, key)  # multipart for large files
    return f"s3://{S3_BUCKET}/{key}"


def save_local(tmp_path: str, api_name: str) -> str:
    dest_dir = os.path.join(OUTPUT_DIR, api_name)
    os.makedirs(dest_dir, exist_ok=True)
    dest = os.path.join(dest_dir, f"{api_name}.csv.gz")
    shutil.move(tmp_path, dest)
    log.info("  Wrote %.1f MB to %s", os.path.getsize(dest) / 1e6, dest)
    return dest


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--only", help="comma-separated api_names to (re)process")
    parser.add_argument("--target", choices=["stage", "s3"], default="stage",
                        help="stage (default): write files under output/ for an internal stage; "
                             "s3: upload to $MSHA_S3_BUCKET")
    args = parser.parse_args()

    names = list(DATASETS)
    if args.only:
        names = [n.strip() for n in args.only.split(",") if n.strip()]
        unknown = [n for n in names if n not in DATASETS]
        if unknown:
            log.error("Unknown dataset(s): %s", ", ".join(unknown))
            sys.exit(1)
    check_zips(names)

    # Merge into an existing manifest so --only reruns keep the other entries
    manifest = {}
    if os.path.exists(MANIFEST_PATH):
        with open(MANIFEST_PATH) as f:
            manifest = json.load(f)
    datasets = manifest.setdefault("datasets", {})

    s3 = None
    if args.target == "s3":
        if not S3_BUCKET:
            log.error("Set MSHA_S3_BUCKET to use --target s3")
            sys.exit(1)
        import boto3  # only needed for the S3 path
        s3 = boto3.client("s3")

    for api_name in names:
        fd, tmp_path = tempfile.mkstemp(suffix=".csv.gz", prefix=f"msha_{api_name}_")
        os.close(fd)
        try:
            entry = process_dataset(api_name, tmp_path)
            if s3:
                entry["output"] = upload(s3, tmp_path, api_name)
            else:
                entry["output"] = save_local(tmp_path, api_name)
            entry["processed_at"] = datetime.now(timezone.utc).isoformat()
            datasets[api_name] = entry
        finally:
            if os.path.exists(tmp_path):
                os.remove(tmp_path)
        with open(MANIFEST_PATH, "w") as f:
            json.dump(manifest, f, indent=2)

    log.info("=" * 92)
    log.info("%-45s %12s %12s %10s %5s", "dataset", "rows_read", "rows_kept", "null_filt", "cols")
    for api_name in names:
        d = datasets[api_name]
        log.info("%-45s %12d %12d %10d %5d", api_name, d["rows_read"], d["rows_kept"],
                 d["rows_dropped_null_filter"], len(d["columns"]))
    log.info("=" * 92)


if __name__ == "__main__":
    main()
