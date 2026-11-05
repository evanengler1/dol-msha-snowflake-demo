import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

import copy

import plotly.express as px
import pydeck as pdk
import streamlit as st

st.set_page_config(page_title="Map & Operators", page_icon=":material/map:", layout="wide")

from utils import (AMBER, DB, DECK_TOOLTIP_STYLE, GREY, NAVY, PARTIAL_YEAR, STATE_NAME_TO_CODE, TEAL, apply_theme, load_states_geojson,
                   plotly_layout, provenance, run_query, takeaway)

apply_theme()

st.title("Map & operators")

tab_map, tab_ops = st.tabs(["Map", "Operators & Penalties"])

# Sequential light-teal -> navy -> amber ramp for state fill.
TOOLTIP_HTML = ("<div style='font-size:15px;font-weight:700;margin-bottom:6px'>{t_title}</div>"
                "<div>{t1}</div><div>{t2}</div><div>{t3}</div>"
                "<div style='color:#64748b;font-size:12px;margin-top:6px'>{t_note}</div>")

RAMP = [(224, 242, 241), (153, 210, 207), (14, 124, 123), (11, 37, 69), (217, 119, 6)]


def ramp_color(t: float, alpha=200):
    t = min(max(t, 0.0), 1.0) * (len(RAMP) - 1)
    i = min(int(t), len(RAMP) - 2)
    f = t - i
    return [int(RAMP[i][k] + (RAMP[i + 1][k] - RAMP[i][k]) * f) for k in range(3)] + [alpha]


with tab_map:
    f1, f2, f3 = st.columns([1, 2, 1])
    cat = f1.segmented_control("Mine category", ["All Mines", "Coal", "Metal/Nonmetal"], default="All Mines",
                               key="map_cat") or "All Mines"
    yr = f2.slider("Year range", 2010, PARTIAL_YEAR, (2021, PARTIAL_YEAR - 1), key="map_years")
    show_mines = f3.toggle("Show active mines", value=True)

    params = (yr[0], yr[1], cat)
    states = run_query(f"""
        SELECT state, SUM(operator_injuries) injuries, SUM(operator_hours_worked) hours,
               SUM(operator_injuries) * 200000 / NULLIF(SUM(operator_hours_worked), 0) rate,
               SUM(fatalities) fatalities, SUM(ventilation_methane_violations) vent_methane
        FROM {DB}.STATE_TRENDS
        WHERE year BETWEEN ? AND ? AND mine_category = ?
        GROUP BY 1""", params)
    ranked = states[states.hours >= 2_000_000].sort_values("rate", ascending=False)
    if ranked.empty:
        st.info("No state has 2M+ operator hours for this selection.")
    else:
        top = ranked.iloc[0]
        partial = " (includes partial 2026)" if yr[1] == PARTIAL_YEAR else ""
        takeaway(f"Among states with 2M+ operator hours, {top.state} has the highest operator injury rate "
                 f"({top.rate:.2f} per 200K hours, {yr[0]}–{yr[1]}{partial}).")

        lo, hi = ranked.rate.quantile(.05), ranked.rate.quantile(.95)
        by_code = ranked.set_index("state").to_dict("index")
        gj = copy.deepcopy(load_states_geojson())
        for feat in gj["features"]:
            code = STATE_NAME_TO_CODE.get(feat["properties"]["name"])
            row = by_code.get(code)
            p = feat["properties"]
            p["code"] = code or ""
            if row:
                p["fill_color"] = ramp_color((row["rate"] - lo) / (hi - lo) if hi > lo else .5)
                p.update(t_title=p["name"],
                         t1=f"Operator injury rate: {row['rate']:.2f} per 200K hrs",
                         t2=f"Operator hours: {row['hours'] / 1e6:,.1f}M",
                         t3=f"Injuries: {int(row['injuries']):,}  ·  Fatalities: {int(row['fatalities'])}",
                         t_note=f"{cat}, {yr[0]}–{yr[1]}")
            else:
                p["fill_color"] = [241, 245, 249, 160]
                p.update(t_title=p["name"], t1="Under 2M operator hours in this period", t2="Not ranked",
                         t3="", t_note=f"{cat}, {yr[0]}–{yr[1]}")

        layers = [pdk.Layer("GeoJsonLayer", data=gj, get_fill_color="properties.fill_color",
                            get_line_color=[255, 255, 255], line_width_min_pixels=1, pickable=True)]

        if show_mines:
            mines = run_query(f"""
                SELECT mine_name, operator_name, state, mine_category, latitude lat, longitude lon,
                       last_4q_operator_hours hours, last_4q_injury_rate_per_200k_hours rate,
                       COALESCE(injury_rate_peer_percentile, 0) pct
                FROM {DB}.MINE_PROFILE
                WHERE NOT has_geo_issue AND has_recent_hours AND last_4q_operator_hours > 0
                  {"" if cat == "All Mines" else "AND mine_category = ?"}""",
                              () if cat == "All Mines" else (cat,))
            mines["radius"] = (mines.hours.clip(lower=1) ** .5) * 4
            mines["color"] = mines.pct.apply(
                lambda p: [217, 119, 6, 210] if p >= .75 else ([11, 37, 69, 170] if p >= .25 else [14, 124, 123, 150]))
            # pydeck HTML-escapes field values, so the data carries plain text and the template carries the markup.
            mines["t_title"] = mines.mine_name.astype(str)
            mines["t1"] = mines.operator_name.fillna("Unknown operator").astype(str)
            mines["t2"] = mines.state + "  ·  " + mines.mine_category
            mines["t3"] = mines.apply(lambda r: f"Last-4Q injury rate: {r.rate:.2f} per 200K hrs  ·  "
                                                f"higher than {r.pct * 100:.0f}% of peers", axis=1)
            mines["t_note"] = mines.hours.map(lambda h: f"{h:,.0f} operator hours in the last 4 quarters")
            layers.append(pdk.Layer("ScatterplotLayer", data=mines[["lon", "lat", "radius", "color", "t_title", "t1", "t2", "t3", "t_note"]],
                                    get_position=["lon", "lat"], get_radius="radius", get_fill_color="color",
                                    radius_min_pixels=1.5, radius_max_pixels=14, pickable=True))

        deck = pdk.Deck(layers=layers, map_style=pdk.map_styles.CARTO_LIGHT,
                        initial_view_state=pdk.ViewState(latitude=39, longitude=-97, zoom=3.3),
                        tooltip={"html": TOOLTIP_HTML, "style": DECK_TOOLTIP_STYLE})
        st.pydeck_chart(deck, height=560)
        st.caption("State fill: operator injury rate (teal = lower, navy/amber = higher; grey = under 2M hours). "
                   "Points: mines with recent hours, sized by last-4Q hours; amber = top-quartile injury rate vs peers, "
                   "teal = bottom quartile. Mine detail lives in the Phase 4 app.")
        provenance("STATE_TRENDS (pooled rates) · MINE_PROFILE (has_recent_hours, no geo issue)")

        with st.expander("State ranking table"):
            st.dataframe(ranked, hide_index=True, width="stretch",
                         column_config={"rate": st.column_config.NumberColumn("Operator rate", format="%.2f"),
                                        "hours": st.column_config.NumberColumn("Operator hours", format="%,.0f")})

with tab_ops:
    st.subheader("Operator leaderboard")
    o1, o2 = st.columns([1, 1])
    min_hours = o1.select_slider("Minimum last-4Q operator hours", [200_000, 500_000, 1_000_000, 2_000_000],
                                 value=200_000, format_func=lambda v: f"{v / 1e6:g}M" if v >= 1e6 else f"{v // 1000}K")
    sort_opts = {"Last-4Q injury rate": "last_4q_injury_rate_per_200k_hours",
                 "Fatalities since 2020": "fatalities_since_2020",
                 "Ventilation/methane citations (last 4Q)": "last_4q_ventilation_methane_violations",
                 "Open/delinquent balance": "open_delinquent_penalty_balance_usd"}
    sort_by = o2.selectbox("Sort by", list(sort_opts))
    ops = run_query(f"""
        SELECT operator_name, controller_name, mines_with_recent_hours, states, mine_categories,
               last_4q_operator_hours, last_4q_injuries, last_4q_injury_rate_per_200k_hours,
               fatalities_since_2020, last_4q_ventilation_methane_violations,
               last_4q_unwarrantable_failure_imminent_danger_actions, open_delinquent_penalty_balance_usd
        FROM {DB}.OPERATOR_PORTFOLIO
        WHERE last_4q_operator_hours >= ?
        ORDER BY {sort_opts[sort_by]} DESC NULLS LAST LIMIT 50""", (min_hours,))
    if not ops.empty:
        takeaway(f"{len(ops)} operators shown with ≥ {min_hours:,} operator hours in the last four quarters; "
                 f"top by {sort_by.lower()}: {ops.operator_name.iloc[0]}.")
    st.dataframe(ops, hide_index=True, width="stretch", height=420, column_config={
        "operator_name": "Operator", "controller_name": "Controller", "mines_with_recent_hours": "Active mines",
        "states": "States", "mine_categories": "Category",
        "last_4q_operator_hours": st.column_config.NumberColumn("Last-4Q hours", format="%,.0f"),
        "last_4q_injuries": "Last-4Q injuries",
        "last_4q_injury_rate_per_200k_hours": st.column_config.NumberColumn("Last-4Q rate", format="%.2f"),
        "fatalities_since_2020": "Fatalities since 2020",
        "last_4q_ventilation_methane_violations": "Vent/methane (4Q)",
        "last_4q_unwarrantable_failure_imminent_danger_actions": "104(d)/107(a) (4Q)",
        "open_delinquent_penalty_balance_usd": st.column_config.NumberColumn("Open balance", format="$%,.0f"),
    })
    provenance("OPERATOR_PORTFOLIO · current operator of record; pooled last-4Q rate")

    st.divider()
    st.subheader("Penalty outcomes")
    pen = run_query(f"""
        SELECT penalty_status, violations, proposed_penalties_usd proposed, current_assessment_usd assessed,
               amount_paid_usd paid, unpaid_usd unpaid
        FROM {DB}.PENALTY_OUTCOMES
        WHERE penalty_status <> 'Not Assessed'
        ORDER BY proposed DESC""")
    tot_assessed, tot_paid, tot_prop = pen.assessed.sum(), pen.paid.sum(), pen.proposed.sum()
    st_ = pen.set_index("penalty_status")
    p1, p2, p3, p4 = st.columns(4)
    # Same basis as the donut below (proposed dollars); assessed basis shown as the secondary line.
    p1.metric("Proposed dollars paid", f"{tot_paid / tot_prop * 100:.0f}%",
              f"${tot_paid / 1e6:,.0f}M of ${tot_prop / 1e6:,.0f}M proposed", delta_color="off")
    p2.metric("Assessed vs proposed", f"{tot_assessed / tot_prop * 100:.0f}%",
              f"{tot_paid / tot_assessed * 100:.0f}% of assessed dollars paid", delta_color="off")
    p3.metric("Open / delinquent", f"${st_.loc['Open-Delinquent', 'unpaid'] / 1e6:,.0f}M unpaid",
              f"${st_.loc['Open-Delinquent', 'proposed'] / 1e6:,.0f}M proposed", delta_color="off")
    p4.metric("Uncollectable / bankrupt", f"${st_.loc['Uncollectable-Bankrupt', 'unpaid'] / 1e6:,.0f}M unpaid",
              f"${st_.loc['Uncollectable-Bankrupt', 'proposed'] / 1e6:,.0f}M proposed", delta_color="off")
    provenance("PENALTY_OUTCOMES · 2010–2026 violations with an assessment")

    d1, d2 = st.columns([2, 3])
    with d1:
        takeaway(f"About {tot_paid / tot_prop * 100:.0f}% of proposed dollars are paid. Assessment lowers the total "
                 f"to {tot_assessed / tot_prop * 100:.0f}% of proposed, and most unpaid dollars sit in delinquent "
                 "and bankrupt accounts.")
        fig = px.pie(pen, names="penalty_status", values="proposed", hole=.55,
                     color="penalty_status", color_discrete_map={
                         "Paid": TEAL, "Open-Delinquent": AMBER, "Uncollectable-Bankrupt": NAVY,
                         "Contested-Other": GREY, "Vacated": "#e2e8f0"})
        fig.update_traces(textinfo="percent", sort=False,
                          hovertemplate="<b>%{label}</b><br>Proposed: $%{value:,.0f}<br>%{percent} of proposed dollars"
                                        "<extra></extra>")
        st.plotly_chart(plotly_layout(fig, height=320), width="stretch")
        st.caption("Share of proposed penalty dollars by current status.")
    with d2:
        bal = run_query(f"""
            SELECT operator_name, states, mines, open_delinquent_penalty_balance_usd balance,
                   last_4q_operator_hours hours
            FROM {DB}.OPERATOR_PORTFOLIO
            WHERE open_delinquent_penalty_balance_usd > 0
            ORDER BY balance DESC LIMIT 10""")
        takeaway(f"The 10 largest open balances total ${bal.balance.sum() / 1e6:,.1f}M.")
        fig = px.bar(bal.sort_values("balance"), x="balance", y="operator_name", orientation="h",
                     color_discrete_sequence=[AMBER], custom_data=["states", "mines"])
        fig.update_traces(hovertemplate="<b>%{y}</b><br>Open balance: $%{x:,.0f}<br>States: %{customdata[0]}<br>"
                                        "Mines: %{customdata[1]:,}<extra></extra>")
        fig.update_xaxes(tickprefix="$")
        st.plotly_chart(plotly_layout(fig, height=320, yaxis_title=None), width="stretch")
        provenance("OPERATOR_PORTFOLIO · open/delinquent balance, any activity status")
