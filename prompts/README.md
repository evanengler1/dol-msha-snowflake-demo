# Build prompts

These are the five [Cortex Code](https://docs.snowflake.com/en/user-guide/cortex-code/cortex-code) prompts that built this demo, one per phase. The finished code in this repo is what they produced, so you don't need them to run the demo. They're here if you want to rebuild it, adapt it to other data, or see how the work was split up.

| Prompt | Builds |
|---|---|
| `phase1-prompt.md` | Ingestion: portal ZIPs to RAW tables |
| `phase2-prompt.md` | Transformation, mine-quarter fact, analytical views, EDA |
| `phase3-prompt.md` | Streamlit in Snowflake dashboard |
| `phase4-prompt.md` | Next.js app on Snowflake App Runtime |
| `phase5-prompt.md` | Semantic view, Cortex Search, Cortex Agent in CoWork |

Notes:

- Run them in order, each in a fresh session, from the repo root. Each prompt assumes the earlier phases exist.
- Replace placeholders such as `<your account>`, `<connection>`, `<your-bucket>` and `<your_s3_integration>` first.
- Phase 1 was written for the S3 load path. To use the internal stage or tables already in your account instead, say so at the top of the prompt, or skip Phase 1 and use `sql/03a`, `sql/03_load.sql` or `sql/03b` directly.
- Figures quoted in the prompts (row counts, rates) come from the November 2026 portal snapshot. Yours will differ as the portal updates.
