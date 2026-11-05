"""Shared helpers: session, cached queries, theme, and chart conventions."""
from __future__ import annotations

import json
import os
from decimal import Decimal

import pandas as pd
import streamlit as st

DB = "DOL_MSHA_DEMO.ANALYTICS"

NAVY = "#0b2545"
TEAL = "#0e7c7b"
AMBER = "#d97706"
GREY = "#94a3b8"
CATEGORY_COLORS = {"Coal": NAVY, "Metal/Nonmetal": TEAL, "All Mines": GREY}

PARTIAL_YEAR = 2026
PARTIAL_NOTE = "2026 is partial (hours through Q2 2026); shown hollow/dashed and excluded from trend deltas."


def get_session():
    """Snowpark session in SiS, or a local session via st.connection."""
    try:
        from snowflake.snowpark.context import get_active_session

        return get_active_session()
    except Exception:
        return st.connection("snowflake").session()


def _to_float(df: pd.DataFrame) -> pd.DataFrame:
    # Only convert columns that actually hold Decimals, so text codes keep leading zeros.
    for c in df.columns:
        if df[c].dtype == object:
            s = df[c].dropna()
            if len(s) and isinstance(s.iloc[0], Decimal):
                df[c] = df[c].astype(float)
    df.columns = [c.lower() for c in df.columns]
    return df


@st.cache_data(ttl=3600, show_spinner=False)
def run_query(sql: str, params: tuple | None = None) -> pd.DataFrame:
    session = get_session()
    df = session.sql(sql, params=list(params) if params else None).to_pandas()
    return _to_float(df)


def apply_theme():
    st.markdown(
        f"""
        <style>
        .block-container {{padding-top: 2rem; max-width: 1400px;}}
        div[data-testid="stMetric"] {{
            background: #ffffff; border: 1px solid #e5e7eb; border-radius: 10px;
            padding: 14px 16px; box-shadow: 0 1px 2px rgba(11,37,69,.04);
        }}
        div[data-testid="stMetricLabel"] p {{color: #475569; font-size: .85rem;}}
        div[data-testid="stMetricValue"] {{color: {NAVY};}}
        .takeaway {{color: {NAVY}; font-weight: 600; margin: .4rem 0 .1rem 0;}}
        .prov {{color: #64748b; font-size: .75rem; margin-top: -.4rem;}}
        .proxy-callout {{
            background: #fff7ed; border: 1px solid #fdba74; border-left: 6px solid {AMBER};
            border-radius: 8px; padding: 14px 18px; color: #7c2d12; margin-bottom: 1rem;
        }}
        .verdict-good {{background:#f0fdfa; border:1px solid #99f6e4; border-radius:8px; padding:12px 16px;}}
        .verdict-bad {{background:#f8fafc; border:1px solid #e2e8f0; border-radius:8px; padding:12px 16px;}}
        .verdict-sub {{color:#64748b; font-size:.85rem; margin-top:2px;}}
        .question-box {{
            background:#ffffff; border:1px solid #e5e7eb; border-left:6px solid {NAVY}; border-radius:8px;
            padding:14px 18px; font-size:1.05rem; color:#1e293b; margin-bottom:1rem;
        }}
        .step-card {{
            background:#ffffff; border:1px solid #e5e7eb; border-radius:10px; padding:12px 14px;
            min-height:118px; font-size:.92rem; color:#334155; margin-bottom:1rem;
        }}
        .step-num {{
            display:inline-block; width:24px; height:24px; line-height:24px; text-align:center; border-radius:50%;
            background:{NAVY}; color:#fff; font-weight:700; font-size:.8rem; margin-right:8px;
        }}
        .headline {{
            background:#fff7ed; border:1px solid #fdba74; border-radius:10px; padding:14px 18px;
            font-size:1.05rem; color:#1e293b; margin-bottom:1rem;
        }}
        .ind-title {{font-weight:700; color:{NAVY}; font-size:1rem;}}
        .ind-desc {{color:#64748b; font-size:.82rem; min-height:2.4em; margin-bottom:.2rem;}}
        .badge-good, .badge-bad, .badge-warn {{
            font-size:.7rem; font-weight:600; padding:2px 8px; border-radius:10px; margin-left:6px;
            vertical-align:middle;
        }}
        .badge-good {{background:#fef3c7; color:#92400e;}}
        .badge-bad {{background:#f1f5f9; color:#475569;}}
        .badge-warn {{background:#f1f5f9; color:#475569; border:1px dashed #94a3b8;}}
        </style>
        """,
        unsafe_allow_html=True,
    )
    sidebar()


def sidebar():
    with st.sidebar:
        st.markdown(f"<h3 style='color:{NAVY};margin-bottom:0'>DOL · MSHA</h3>"
                    f"<div style='color:{TEAL};font-weight:600'>Mine Safety Analytics</div>",
                    unsafe_allow_html=True)
        asof = data_as_of()
        st.caption(f"Accidents through **{asof['acc']}** · hours through **{asof['hours']}**")
        st.info("Portal data only (data.dol.gov MSHA datasets). No methane, temperature, or sensor readings.",
                icon=":material/info:")


@st.cache_data(ttl=3600, show_spinner=False)
def data_as_of() -> dict:
    df = run_query(f"""
        SELECT (SELECT MAX(accident_date) FROM {DB}.ACCIDENT_DETAIL) acc,
               (SELECT MAX(year_quarter) FROM {DB}.MINE_QUARTER_TRENDS WHERE has_hours) hrs""")
    return {"acc": str(df["acc"].iloc[0]), "hours": str(df["hrs"].iloc[0])}


def takeaway(text: str):
    st.markdown(f"<div class='takeaway'>{text}</div>", unsafe_allow_html=True)


def provenance(text: str):
    st.markdown(f"<div class='prov'>Source: {text}</div>", unsafe_allow_html=True)


def plotly_layout(fig, height=360, yaxis_title=None):
    fig.update_layout(
        height=height, margin=dict(l=10, r=10, t=30, b=10),
        paper_bgcolor="white", plot_bgcolor="white",
        font=dict(color="#1e293b"), legend=dict(orientation="h", y=1.1, x=0),
        yaxis_title=yaxis_title,
        hoverlabel=dict(bgcolor="white", bordercolor=NAVY, font=dict(size=14, color=NAVY, family="sans-serif"),
                        align="left"),
    )
    fig.update_xaxes(showgrid=False, linecolor="#e5e7eb")
    fig.update_yaxes(gridcolor="#f1f5f9", zeroline=False)
    return fig


def add_partial_trace(fig, df, x, y, color_col, colors, value_label="Rate", fmt=".2f"):
    """Draw each series solid through the last full year and dashed into the partial year."""
    import plotly.graph_objects as go

    for cat, g in df.groupby(color_col):
        g = g.sort_values(x)
        full = g[g[x] < PARTIAL_YEAR]
        tail = g[g[x] >= PARTIAL_YEAR - 1]
        c = colors.get(cat, GREY)
        fig.add_trace(go.Scatter(x=full[x], y=full[y], name=cat, mode="lines+markers",
                                 line=dict(color=c, width=2.5), marker=dict(size=6),
                                 hovertemplate=f"<b>{cat}</b><br>Year: %{{x}}<br>{value_label}: %{{y:{fmt}}}<extra></extra>"))
        if (tail[x] == PARTIAL_YEAR).any():
            fig.add_trace(go.Scatter(x=tail[x], y=tail[y], name=f"{cat} (2026 partial)", mode="lines+markers",
                                     line=dict(color=c, width=2, dash="dash"),
                                     marker=dict(size=8, symbol="circle-open", color=c),
                                     showlegend=False,
                                     hovertemplate=f"<b>{cat}</b> (partial year)<br>Year: %{{x}}<br>{value_label}: "
                                                   f"%{{y:{fmt}}}<extra></extra>"))
    return fig


DECK_TOOLTIP_STYLE = {
    "backgroundColor": "white", "color": NAVY, "fontSize": "14px", "lineHeight": "1.45",
    "padding": "10px 14px", "border": f"1px solid {NAVY}", "borderRadius": "8px",
    "boxShadow": "0 4px 14px rgba(11,37,69,.18)", "fontFamily": "sans-serif", "maxWidth": "320px",
}


@st.cache_data(show_spinner=False)
def load_states_geojson() -> dict:
    path = os.path.join(os.path.dirname(__file__), "assets", "us-states.json")
    with open(path) as f:
        return json.load(f)


STATE_NAME_TO_CODE = {
    "Alabama": "AL", "Alaska": "AK", "Arizona": "AZ", "Arkansas": "AR", "California": "CA", "Colorado": "CO",
    "Connecticut": "CT", "Delaware": "DE", "District of Columbia": "DC", "Florida": "FL", "Georgia": "GA",
    "Hawaii": "HI", "Idaho": "ID", "Illinois": "IL", "Indiana": "IN", "Iowa": "IA", "Kansas": "KS",
    "Kentucky": "KY", "Louisiana": "LA", "Maine": "ME", "Maryland": "MD", "Massachusetts": "MA",
    "Michigan": "MI", "Minnesota": "MN", "Mississippi": "MS", "Missouri": "MO", "Montana": "MT",
    "Nebraska": "NE", "Nevada": "NV", "New Hampshire": "NH", "New Jersey": "NJ", "New Mexico": "NM",
    "New York": "NY", "North Carolina": "NC", "North Dakota": "ND", "Ohio": "OH", "Oklahoma": "OK",
    "Oregon": "OR", "Pennsylvania": "PA", "Rhode Island": "RI", "South Carolina": "SC", "South Dakota": "SD",
    "Tennessee": "TN", "Texas": "TX", "Utah": "UT", "Vermont": "VT", "Virginia": "VA", "Washington": "WA",
    "West Virginia": "WV", "Wisconsin": "WI", "Wyoming": "WY", "Puerto Rico": "PR",
}
