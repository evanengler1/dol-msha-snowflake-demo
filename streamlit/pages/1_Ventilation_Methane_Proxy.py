import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

import plotly.express as px
import plotly.graph_objects as go
import streamlit as st

st.set_page_config(page_title="Ventilation & Methane Proxy", page_icon=":material/air:", layout="wide")

from utils import (AMBER, DB, GREY, NAVY, PARTIAL_NOTE, PARTIAL_YEAR, TEAL, add_partial_trace, apply_theme,
                   plotly_layout, provenance, run_query, takeaway)

apply_theme()

st.title("Ventilation & methane: compliance proxies")
st.markdown(
    "<div class='proxy-callout'><b>The DOL portal contains no methane, temperature, or sensor readings.</b> "
    "This page uses cited 30 CFR sections as <b>compliance proxies</b>: ventilation and methane citations "
    "(30 CFR 75 Subpart D) and ignition, explosion, and fire accidents. The one methane-related mine field "
    "(<code>methn_librtn</code>, methane liberation) is populated for only 0.27% of mines, so it is not used.</div>",
    unsafe_allow_html=True,
)

# Ventilation/methane citation intensity (coal)
nat = run_query(f"""
    SELECT year, mine_category, ventilation_methane_violations_per_200k_hours rate, ventilation_methane_violations n
    FROM {DB}.NATIONAL_TRENDS WHERE mine_category = 'Coal' ORDER BY year""")
full = nat[nat.year < PARTIAL_YEAR]
first, last = full.iloc[0], full.iloc[-1]
c1, c2 = st.columns(2)
with c1:
    takeaway(f"Ventilation/methane citations per 200K coal operator hours fell from {first.rate:.1f} "
             f"({int(first.year)}) to {last.rate:.1f} ({int(last.year)}).")
    fig = add_partial_trace(go.Figure(), nat, "year", "rate", "mine_category", {"Coal": NAVY},
                            value_label="Vent/methane citations per 200K hrs", fmt=".1f")
    st.plotly_chart(plotly_layout(fig, yaxis_title="Citations per 200K operator hours"), width="stretch")
    provenance("NATIONAL_TRENDS · coal only; Subpart D applies to underground coal")

haz = run_query(f"""
    SELECT year, hazard_category, hazard_sort_order, violations_per_200k_operator_hours rate
    FROM {DB}.HAZARD_TRENDS
    WHERE mine_category = 'Coal' AND hazard_sort_order <= 7
    ORDER BY year, hazard_sort_order""")
with c2:
    lastyr = haz[haz.year == last.year].sort_values("rate", ascending=False).reset_index(drop=True)
    rank = int(lastyr.index[lastyr.hazard_category == "Ventilation & Methane"][0]) + 1
    takeaway(f"Ventilation & methane ranks #{rank} of {len(lastyr)} coal citation categories by rate in {int(last.year)}.")
    fig = px.line(haz[haz.year < PARTIAL_YEAR], x="year", y="rate", color="hazard_category",
                  color_discrete_sequence=[AMBER, NAVY, TEAL, "#64748b", "#a78bfa", "#cbd5e1", "#94a3b8"])
    fig.update_traces(hovertemplate="<b>%{fullData.name}</b><br>Year: %{x}<br>"
                                    "Citations per 200K hrs: %{y:.2f}<extra></extra>")
    st.plotly_chart(plotly_layout(fig, yaxis_title="Citations per 200K coal operator hours"), width="stretch")
    provenance("HAZARD_TRENDS · coal hazard categories; 2026 omitted (partial)")

st.divider()

# Profile: vent/methane vs all other coal citations
st.subheader("How ventilation/methane citations differ from other coal citations")
prof = run_query(f"""
    SELECT IFF(hazard_category = 'Ventilation & Methane', 'Ventilation & Methane', 'All other coal citations') grp,
           SUM(violations) violations,
           100 * SUM(significant_substantial_violations) / SUM(violations) ss,
           100 * SUM(high_negligence_violations) / SUM(violations) hn,
           100 * SUM(unwarrantable_failure_or_imminent_danger_actions) / SUM(violations) uwf
    FROM {DB}.HAZARD_TRENDS WHERE mine_category = 'Coal' GROUP BY 1""").rename(
    columns={"ss": "S&S share", "hn": "High negligence", "uwf": "104(d)/107(a) actions"})
long = prof.melt(id_vars=["grp", "violations"], var_name="measure", value_name="pct")
vm = prof.set_index("grp").loc["Ventilation & Methane"]
oth = prof.set_index("grp").loc["All other coal citations"]
takeaway(f"Ventilation/methane citations are less often S&S ({vm['S&S share']:.0f}% vs {oth['S&S share']:.0f}%) "
         f"but about {vm['High negligence'] / oth['High negligence']:.1f}× as likely to be high negligence and "
         f"{vm['104(d)/107(a) actions'] / oth['104(d)/107(a) actions']:.1f}× as likely to carry a 104(d)/107(a) action.")
fig = px.bar(long, x="measure", y="pct", color="grp", barmode="group", text_auto=".1f",
             color_discrete_map={"Ventilation & Methane": AMBER, "All other coal citations": GREY})
fig.update_yaxes(ticksuffix="%")
fig.update_traces(hovertemplate="<b>%{fullData.name}</b><br>%{x}: %{y:.1f}% of citations<extra></extra>")
st.plotly_chart(plotly_layout(fig, height=340, yaxis_title="% of citations"), width="stretch")
provenance("HAZARD_TRENDS · coal, 2010–2026; 104(d) = unwarrantable failure, 107(a) = imminent danger")

st.divider()

# Ignition / explosion / fire accidents
st.subheader("Ignition, explosion, and fire accidents")
ign = run_query(f"""
    SELECT accident_year year, accident_classification classification,
           COUNT(DISTINCT accident_document_number) accidents, COUNT_IF(is_fatal) fatalities
    FROM {DB}.ACCIDENT_DETAIL WHERE is_ignition_explosion_fire
    GROUP BY 1, 2 ORDER BY 1""")
i1, i2 = st.columns([3, 2])
with i1:
    tot = ign.groupby("classification").accidents.sum().sort_values(ascending=False)
    takeaway(f"{tot.index[0].title()} is the most common type ({int(tot.iloc[0]):,} accidents since 2010).")
    ign["period"] = ign.year.apply(lambda y: "Partial year" if y == PARTIAL_YEAR else "Full year")
    fig = px.bar(ign, x="year", y="accidents", color="classification", pattern_shape="period",
                 pattern_shape_map={"Full year": "", "Partial year": "/"},
                 color_discrete_sequence=[AMBER, NAVY, TEAL])
    fig.update_traces(hovertemplate="<b>%{fullData.name}</b><br>Year: %{x}<br>Accidents: %{y:,}<extra></extra>")
    st.plotly_chart(plotly_layout(fig, yaxis_title="Accidents"), width="stretch")
    provenance("ACCIDENT_DETAIL · distinct accidents; 2026 hatched = partial year")
with i2:
    states = run_query(f"""
        SELECT state,
               COUNT(DISTINCT IFF(accident_classification = 'IGNITION OR EXPLOSION OF GAS OR DUST',
                                  accident_document_number, NULL)) gas_dust_ignitions,
               COUNT(DISTINCT accident_document_number) all_ignition_fire,
               COUNT_IF(is_fatal) fatalities
        FROM {DB}.ACCIDENT_DETAIL WHERE is_ignition_explosion_fire
        GROUP BY 1 ORDER BY 2 DESC LIMIT 10""")
    fat_lead = states.sort_values("fatalities", ascending=False).iloc[0]
    takeaway(f"{states.state.iloc[0]} leads gas/dust ignitions ({int(states.gas_dust_ignitions.iloc[0])}); "
             f"{fat_lead.state} leads ignition/fire fatalities ({int(fat_lead.fatalities)}).")
    st.dataframe(states, hide_index=True, width="stretch",
                 column_config={"state": "State", "gas_dust_ignitions": "Gas/dust ignitions",
                                "all_ignition_fire": "All ignition/fire", "fatalities": "Fatalities"})
    provenance("ACCIDENT_DETAIL · 2010–2026")

st.markdown("##### Recent ignition narratives")
narr = run_query(f"""
    SELECT accident_date, state, mine_name, mine_category, accident_classification, degree_of_injury, narrative
    FROM {DB}.ACCIDENT_DETAIL
    WHERE is_ignition_explosion_fire AND narrative IS NOT NULL
      AND accident_classification = 'IGNITION OR EXPLOSION OF GAS OR DUST'
    QUALIFY ROW_NUMBER() OVER (PARTITION BY accident_document_number ORDER BY narrative) = 1
    ORDER BY accident_date DESC LIMIT 6""")
for _, r in narr.iterrows():
    with st.container(border=True):
        st.markdown(f"**{r.accident_date} · {r.mine_name} ({r.state}, {r.mine_category})** · {r.degree_of_injury}")
        st.caption(r.narrative)
provenance("ACCIDENT_DETAIL · portal narratives are truncated at 384 characters")
