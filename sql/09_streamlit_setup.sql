-- Phase 3: Streamlit in Snowflake app schema
-- Run as DOL_MSHA_DEMO_ROLE (owns DOL_MSHA_DEMO). Never PUBLIC.
USE ROLE DOL_MSHA_DEMO_ROLE;
USE WAREHOUSE DOL_MSHA_WH;

CREATE SCHEMA IF NOT EXISTS DOL_MSHA_DEMO.APPS
  COMMENT = 'Streamlit in Snowflake apps for the DOL MSHA demo';

-- One-time, as ACCOUNTADMIN: the container runtime installs pyproject.toml packages from PyPI,
-- so the demo role needs an external access integration that allows PyPI. If your account has
-- none, create one (Snowflake docs: "External network access" / Streamlit container runtime).
-- Use its name here and in streamlit/snowflake.yml.
-- USE ROLE ACCOUNTADMIN;
-- GRANT USAGE ON INTEGRATION <YOUR_PYPI_EAI> TO ROLE DOL_MSHA_DEMO_ROLE;
-- The compute pool in streamlit/snowflake.yml (SYSTEM_COMPUTE_POOL_CPU) must be usable by the role:
-- GRANT USAGE ON COMPUTE POOL SYSTEM_COMPUTE_POOL_CPU TO ROLE DOL_MSHA_DEMO_ROLE;

-- Deploy (from streamlit/):
--   snow streamlit deploy --replace --role DOL_MSHA_DEMO_ROLE -c <connection>
