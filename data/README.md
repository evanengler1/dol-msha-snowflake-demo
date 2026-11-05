# data/

Put the MSHA portal downloads here if you load from ZIP files (README Step 1, Option B). Skip this folder if you use MSHA tables already in your Snowflake account (Option A).

- Save each dataset's **Download Complete Dataset** ZIP from [data.dol.gov](https://data.dol.gov/datasets?filterBy=agency&name=Mine%20Safety%20and%20Health%20Administration) here, keeping the portal's file name: `MSHA_<api_name>.zip` (for example `MSHA_accident.zip`). The root README lists all 14.
- The ZIPs are large (the Violation file alone is about 2.8 GB) and are git-ignored, so they are never committed.
- `process_msha_data.py` reads them from here and writes its extracts to `output/msha-raw/`.

## manifest.json

`manifest.json` is the record of the original load, from the portal snapshot of November 2026. For each dataset it lists the ZIP name and size, the CSV chunks, the filter applied (fact tables keep 2010 onward), rows read, rows kept and the column list.

`process_msha_data.py` rewrites this file when you run it, so after your own load it describes your data. Compare your counts with the original to see how much the portal has changed. The portal updates weekly, so some difference is expected.
