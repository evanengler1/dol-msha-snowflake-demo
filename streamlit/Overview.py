import plotly.express as px
import plotly.graph_objects as go
import streamlit as st

st.set_page_config(page_title="MSHA Mine Safety Analytics", page_icon=":material/construction:", layout="wide")

from utils import (AMBER, CATEGORY_COLORS, DB, NAVY, PARTIAL_NOTE, PARTIAL_YEAR, TEAL, add_partial_trace,
                   apply_theme, plotly_layout, provenance, run_query, takeaway)

apply_theme()

st.title("Where are miners getting hurt?")
st.caption("Accident and enforcement trends across all U.S. mines, 2010 to 2026, from the DOL Open Data Portal. "
           "Hours and rates run through 2026 Q2; accident reports run later.")

nat = run_query(f"SELECT * FROM {DB}.NATIONAL_TRENDS ORDER BY year")
allm = nat[nat.mine_category == "All Mines"].set_index("year")
full_years = allm[~allm.is_partial_year.astype(bool)]
last = int(full_years.index.max())

# KPI tiles
k = st.columns(4)
with k[0]:
    r_now, r_2010 = allm.loc[last, "operator_injury_rate_per_200k_hours"], allm.loc[2010, "operator_injury_rate_per_200k_hours"]
    st.metric(f"Operator injury rate, {last}", f"{r_now:.2f}", f"{r_now - r_2010:+.2f} vs 2010 ({r_2010:.2f})",
              delta_color="inverse")
    provenance("NATIONAL_TRENDS · operator employee injuries per 200K operator hours")
with k[1]:
    f_now = int(allm.loc[last, "fatalities"])
    st.metric(f"Fatalities, {last}", f"{f_now}", f"{f_now - int(allm.loc[2010, 'fatalities']):+d} vs 2010",
              delta_color="inverse")
    provenance("NATIONAL_TRENDS · reported fatal accidents (30 CFR Part 50), operator + contractor; may differ slightly from MSHA chargeable counts")
with k[2]:
    st.metric(f"Operator hours, {last}", f"{allm.loc[last, 'operator_hours_worked'] / 1e6:,.0f}M",
              f"{allm.loc[last, 'mines_reporting_hours']:,.0f} mines reporting", delta_color="off")
    provenance("NATIONAL_TRENDS · operator employment/production reports")
with k[3]:
    v = allm.loc[last, "ventilation_methane_violations"]
    st.metric(f"Ventilation/methane citations, {last}", f"{v:,.0f}",
              f"{v - allm.loc[2010, 'ventilation_methane_violations']:+,.0f} vs 2010", delta_color="inverse")
    provenance("NATIONAL_TRENDS · 30 CFR 75 Subpart D (coal)")

st.divider()

c1, c2 = st.columns([3, 2])
cats = nat[nat.mine_category.isin(["Coal", "Metal/Nonmetal"])]
with c1:
    coal = cats[(cats.mine_category == "Coal") & (cats.year == last)].operator_injury_rate_per_200k_hours.iloc[0]
    mnm = cats[(cats.mine_category == "Metal/Nonmetal") & (cats.year == last)].operator_injury_rate_per_200k_hours.iloc[0]
    takeaway(f"Coal mines run about {coal / mnm:.1f}× the operator injury rate of metal/nonmetal mines "
             f"({coal:.2f} vs {mnm:.2f} in {last}).")
    fig = add_partial_trace(go.Figure(), cats, "year", "operator_injury_rate_per_200k_hours", "mine_category",
                            CATEGORY_COLORS, value_label="Operator injuries per 200K hrs")
    st.plotly_chart(plotly_layout(fig, yaxis_title="Operator injuries per 200K hours"), width="stretch")
    st.caption(PARTIAL_NOTE)
with c2:
    peak = full_years.fatalities.idxmax()
    takeaway(f"Fatalities peaked in {peak} ({int(full_years.fatalities.max())} deaths), driven by Upper Big Branch "
             "(29 deaths, April 2010).")
    fat = cats.copy()
    fat["period"] = fat.year.apply(lambda y: "Partial year" if y == PARTIAL_YEAR else "Full year")
    fig = px.bar(fat, x="year", y="fatalities", color="mine_category", color_discrete_map=CATEGORY_COLORS,
                 pattern_shape="period", pattern_shape_map={"Full year": "", "Partial year": "/"})
    fig.update_traces(marker_line_width=0,
                      hovertemplate="Year: %{x}<br>Fatalities: %{y}<extra>%{fullData.name}</extra>")
    st.plotly_chart(plotly_layout(fig, yaxis_title="Fatalities"), width="stretch")
    provenance("NATIONAL_TRENDS · 2026 hatched = partial year")

st.divider()
st.subheader("Accident patterns")

f1, f2 = st.columns([1, 2])
cat_sel = f1.segmented_control("Mine category", ["All Mines", "Coal", "Metal/Nonmetal"], default="All Mines")
yr = f2.slider("Year range", 2010, PARTIAL_YEAR, (2010, last))
cat_sel = cat_sel or "All Mines"
cat_clause = "" if cat_sel == "All Mines" else "AND mine_category = ?"
params = (yr[0], yr[1]) + (() if cat_sel == "All Mines" else (cat_sel,))

p1, p2 = st.columns(2)
for col, dim, label in [(p1, "accident_classification", "classifications"), (p2, "injury_source", "injury sources")]:
    df = run_query(f"""
        SELECT {dim} label, SUM(reportable_injuries) injuries, SUM(fatalities) fatalities
        FROM {DB}.ACCIDENT_PATTERNS
        WHERE year BETWEEN ? AND ? {cat_clause} AND {dim} IS NOT NULL
        GROUP BY 1 ORDER BY 2 DESC LIMIT 10""", params)
    with col:
        if df.empty:
            st.info("No accidents for this selection.")
            continue
        share = df.injuries.iloc[0] / df.injuries.sum() * 100
        takeaway(f"Top {label}: {df.label.iloc[0].title()} leads ({share:.0f}% of the top 10).")
        fig = px.bar(df.sort_values("injuries"), x="injuries", y="label", orientation="h",
                     color_discrete_sequence=[NAVY], custom_data=["fatalities"])
        fig.update_traces(hovertemplate="<b>%{y}</b><br>Reportable injuries: %{x:,}<br>"
                                        "Fatalities: %{customdata[0]:,}<extra></extra>")
        st.plotly_chart(plotly_layout(fig, height=380, yaxis_title=None), width="stretch")
provenance("ACCIDENT_PATTERNS · reportable injuries (degree 01–06)")

st.markdown("##### How the mix has shifted: 2010–12 vs 2023–25")
mix = run_query(f"""
    WITH p AS (
        SELECT IFF(year <= 2012, '2010–12', '2023–25') period, accident_classification label,
               SUM(reportable_injuries) n
        FROM {DB}.ACCIDENT_PATTERNS
        WHERE (year BETWEEN 2010 AND 2012 OR year BETWEEN 2023 AND 2025) {cat_clause}
          AND accident_classification IS NOT NULL
        GROUP BY 1, 2)
    SELECT period, label, 100 * n / SUM(n) OVER (PARTITION BY period) share FROM p""",
                (() if cat_sel == "All Mines" else (cat_sel,)))
wide = mix.pivot(index="label", columns="period", values="share").fillna(0)
wide = wide.loc[wide.max(axis=1).sort_values(ascending=False).index[:10]]
wide["change"] = wide["2023–25"] - wide["2010–12"]
mover_up, mover_dn = wide.change.idxmax(), wide.change.idxmin()
takeaway(f"{mover_dn.title()} fell from {wide.loc[mover_dn, '2010–12']:.1f}% to {wide.loc[mover_dn, '2023–25']:.1f}% "
         f"of injuries; {mover_up.title()} rose from {wide.loc[mover_up, '2010–12']:.1f}% to "
         f"{wide.loc[mover_up, '2023–25']:.1f}%.")
long = mix[mix.label.isin(wide.index)]
fig = px.bar(long, x="share", y="label", color="period", orientation="h", barmode="group",
             color_discrete_map={"2010–12": "#cbd5e1", "2023–25": NAVY},
             category_orders={"label": list(wide.index)})
fig.update_xaxes(ticksuffix="%")
fig.update_traces(hovertemplate="<b>%{y}</b><br>%{fullData.name}: %{x:.1f}% of injuries<extra></extra>")
st.plotly_chart(plotly_layout(fig, height=420, yaxis_title=None), width="stretch")
provenance("ACCIDENT_PATTERNS · share of reportable injuries in each period (ignores the year slider)")

with st.expander("About this data"):
    st.markdown(f"""
- **Portal data only.** Every figure comes from the MSHA datasets on the DOL Open Data Portal (data.dol.gov):
  accidents, mines, inspections, violations, assessed violations, and operator/contractor employment.
  The portal has **no methane, temperature, or sensor readings**; hazard categories are compliance proxies.
- **Rates** are pooled: `SUM(injuries) × 200,000 / SUM(hours)`. Per-row rates are never averaged.
  - *Operator* rate = operator injuries / operator hours (mine and state level).
  - *All workers* rate = operator + contractor injuries / operator + contractor hours (national only).
- **Definitions:** reportable injury = degree of injury 01–06; lost-time = 02–05. These have **not yet been
  confirmed against MSHA's published methodology**.
- **Partial year:** {PARTIAL_NOTE}
- Rankings require ≥ 200K hours/year for mines and ≥ 2M hours for states.
""")
