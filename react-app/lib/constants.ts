export const APP_TITLE = "MSHA Mine Early-Warning"
export const APP_SHORT = "Mine Early-Warning"
export const LOGO_SRC = "/icon.svg"

/**
 * Phase 3 Streamlit dashboard (industry trends live there, not here).
 * Replace the default below with your dashboard's Snowsight URL before `snow app deploy`
 * (Projects > Streamlit > MSHA_SAFETY_DASHBOARD, copy the address bar). app.yml does not
 * upload .env* files, so NEXT_PUBLIC_DASHBOARD_URL only overrides it for local dev.
 */
export const DASHBOARD_URL =
  process.env.NEXT_PUBLIC_DASHBOARD_URL || "https://app.snowflake.com/"

/**
 * Compare example, picked via SQL on 2026-11-04 from one peer group
 * (Coal | Underground | 100-499 employees): Oak Grove Mine (Elevated),
 * Ohio County Mine (Watch), Leer Mine (Typical).
 */
export const COMPARE_EXAMPLE = ["0100851", "4601436", "4609192"]

export const SOURCE_LINE = "Source: U.S. Department of Labor, MSHA datasets on the DOL Open Data Portal (data.dol.gov)"
