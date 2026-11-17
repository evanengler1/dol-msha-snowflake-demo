import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

import pandas as pd
import plotly.express as px
import streamlit as st

st.set_page_config(page_title="Leading Indicators", page_icon=":material/trending_up:", layout="wide")

from utils import AMBER, DB, GREY, NAVY, TEAL, apply_theme, plotly_layout, provenance, run_query, takeaway

apply_theme()

st.title("Which warning signs come before injuries?")
st.markdown(
    "<div class='question-box'>If a mine racked up a lot of a certain kind of citation, or a lot of injuries, over the "
    "past year, were its miners <b>more likely to get hurt in the next quarter</b>? This page tests seven candidate "
    "warning signs across every mine in the portal and shows which ones actually line up with later injuries.</div>",
    unsafe_allow_html=True)

s1, s2, s3 = st.columns(3)
for col, num, head, body in [
    (s1, "1", "Look back one year", "For every mine and quarter, total up the mine's citations and injuries over the "
                                     "<b>previous four quarters</b>, scaled by hours worked."),
    (s2, "2", "Sort mines into groups", "Group the mine-quarters by how much of each warning sign they had: "
                                        "<b>None</b>, then four equal-size groups from <b>Low</b> to <b>Highest</b>."),
    (s3, "3", "Check the next quarter", "Compare each group's injury rate in the <b>following quarter</b>. If the bars "
                                        "climb from None to Highest, the sign is a useful early warning."),
]:
    col.markdown(f"<div class='step-card'><span class='step-num'>{num}</span><b>{head}</b><br/>{body}</div>",
                 unsafe_allow_html=True)

# Key -> (label, SQL expression for the quartile, kind, plain-language description).
# kind "candidate" = tested as a leading indicator; "confounded" = shown but known to be driven by MSHA targeting.
INDICATORS = {
    "prior_injury": ("Prior injury rate", "prior_injury_rate_quartile", "candidate",
                     "Injuries per 200K hours worked in the past year"),
    "vent_methane": ("Ventilation/methane citations", "ventilation_methane_quartile", "candidate",
                     "30 CFR 75 Subpart D citations per 200K hours (compliance proxy, not a gas reading)"),
    "uwf_imminent": ("104(d)/107(a) actions", "unwarrantable_imminent_quartile", "candidate",
                     "Unwarrantable-failure and imminent-danger orders per 200K hours, MSHA's most serious tools"),
    "high_negligence": ("High-negligence citations", "high_negligence_quartile", "candidate",
                        "Citations where the inspector found high or reckless negligence, per 200K hours"),
    "ss_per_hours": ("S&S citations", "significant_substantial_quartile", "candidate",
                     "Significant & substantial citations per 200K hours"),
    "ss_share": ("S&S share of violations", "ss_share_quartile", "candidate",
                 "What fraction of a mine's citations were S&S, regardless of how many it had"),
    "inspection": ("Inspection intensity", "inspection_intensity_quartile", "confounded",
                   "Inspector hours on site per 200K hours worked"),
}
GROUP_LABELS = {0: "None", 1: "Low", 2: "Med-low", 3: "Med-high", 4: "Highest"}

f1, f2 = st.columns([1, 2])
category = f1.segmented_control("Mine category", ["Coal", "Metal/Nonmetal"], default="Coal") or "Coal"
outcome = f2.segmented_control("Measure next quarter's injuries as", ["Injury rate", "% of mines with any injury"],
                               default="Injury rate") or "Injury rate"


def quartile_table(cat: str) -> pd.DataFrame:
    # S&S *share* isn't precomputed as a quartile, so derive it the same way: 0 = no violations, 1-4 = quartiles of non-zero.
    unions = "\nUNION ALL\n".join(
        f"SELECT '{k}' indicator, {expr} quartile, next_quarter_operator_injuries inj, "
        f"next_quarter_operator_hours hrs, had_injury_next_quarter any_inj FROM li"
        for k, (_, expr, _, _) in INDICATORS.items())
    sql = f"""
        WITH li AS (
            SELECT *, IFF(prior_4q_violations = 0, 0,
                          NTILE(4) OVER (PARTITION BY (prior_4q_violations > 0)
                                         ORDER BY prior_4q_significant_substantial_rate)) ss_share_quartile
            FROM {DB}.LEADING_INDICATORS
            WHERE is_comparable AND mine_category = ?),
        u AS ({unions})
        SELECT indicator, quartile, COUNT(*) mine_quarters,
               SUM(inj) * 200000 / NULLIF(SUM(hrs), 0) rate,
               100 * AVG(IFF(any_inj, 1, 0)) pct_any
        FROM u WHERE quartile IS NOT NULL
        GROUP BY 1, 2 ORDER BY 1, 2"""
    return run_query(sql, (cat,))


df = quartile_table(category)
ycol = "rate" if outcome == "Injury rate" else "pct_any"
ylab = "Next-quarter injuries per 200K hrs" if ycol == "rate" else "% of mine-quarters with an injury next quarter"
unit = "injuries per 200K hours" if ycol == "rate" else "% had an injury"
fmt = (lambda x: f"{x:.1f}") if ycol == "rate" else (lambda x: f"{x:.0f}%")
base = run_query(f"""
    SELECT SUM(next_quarter_operator_injuries) * 200000 / SUM(next_quarter_operator_hours) rate,
           100 * AVG(IFF(had_injury_next_quarter, 1, 0)) pct_any, COUNT(*) n
    FROM {DB}.LEADING_INDICATORS WHERE is_comparable AND mine_category = ?""", (category,)).iloc[0]


def verdict(g: pd.DataFrame) -> dict:
    """Data-driven test: top quartile at least 2x the zero group, and rising steadily across quartiles 1-4."""
    g = g.set_index("quartile").sort_index()
    q0 = g[ycol].get(0)
    q = g[ycol].reindex([1, 2, 3, 4])
    if q.isna().any() or q0 is None:
        return {"holds": False, "lift": None, "monotonic": False, "q0": q0, "q4": q.get(4), "sparse": True}
    lift = q[4] / q0 if q0 > 0 else float("inf")
    monotonic = bool((q.diff().dropna() > 0).all())
    return {"holds": lift >= 2 and monotonic, "lift": lift, "monotonic": monotonic, "q0": q0, "q4": q[4],
            "sparse": False}


verdicts = {k: verdict(df[df.indicator == k]) for k in INDICATORS}

good = [k for k, v in verdicts.items() if INDICATORS[k][2] == "candidate" and v["holds"]]
bad = [k for k, v in verdicts.items() if INDICATORS[k][2] == "candidate" and not v["holds"]]

# Headline finding, as a worked example
st.markdown("### What the data shows")
if good:
    best = max(good, key=lambda k: verdicts[k]["lift"])
    v = verdicts[best]
    st.markdown(
        f"<div class='headline'>In {category.lower()} mines, the strongest warning sign is the "
        f"<b>{INDICATORS[best][0].lower()}</b>. Mines in the <b>highest</b> group had <b>{fmt(v['q4'])}</b> {unit} "
        f"the next quarter, versus <b>{fmt(v['q0'])}</b> for mines with none: about "
        f"<b>{v['lift']:.1f}× higher</b>. The average across all {int(base.n):,} {category.lower()} mine-quarters "
        f"was {fmt(base[ycol])}.</div>", unsafe_allow_html=True)
else:
    st.markdown(f"<div class='headline'>None of the candidate warning signs clear the bar for "
                f"{category.lower()} mines with this measure.</div>", unsafe_allow_html=True)

h1, h2 = st.columns(2)
with h1:
    lines = "".join(f"<li><b>{INDICATORS[k][0]}</b>: {fmt(verdicts[k]['q0'])} → {fmt(verdicts[k]['q4'])} "
                    f"({verdicts[k]['lift']:.1f}× higher)</li>" for k in good)
    st.markdown(f"<div class='verdict-good'><b style='color:{TEAL}'>✓ Warning signs that hold up</b>"
                f"<div class='verdict-sub'>Next-quarter injuries climb steadily from None to Highest</div>"
                f"<ul>{lines or '<li>None for this selection</li>'}</ul></div>", unsafe_allow_html=True)
with h2:
    items = []
    for k in bad:
        v, lbl = verdicts[k], INDICATORS[k][0]
        if v["sparse"]:
            why = "too few mines have any, so groups can't be formed"
        elif not v["monotonic"]:
            why = f"injuries don't climb steadily across the groups ({fmt(v['q0'])} → {fmt(v['q4'])})"
        else:
            why = f"rises, but the highest group is only {v['lift']:.1f}× the None group"
        if k == "ss_per_hours" and category == "Metal/Nonmetal":
            why += "; small mines inflate per-hour ratios"
        items.append(f"<li><b>{lbl}</b>: {why}</li>")
    items.append("<li><b>Inspection intensity</b>: likely reflects MSHA targeting mines it already sees as risky, "
                 "so it can't be read as an independent warning sign</li>")
    st.markdown(f"<div class='verdict-bad'><b style='color:#475569'>✗ Signals that don't hold up</b>"
                f"<div class='verdict-sub'>Weak, uneven, or explained by something else</div>"
                f"<ul>{''.join(items)}</ul></div>", unsafe_allow_html=True)
st.caption("Test used: a sign 'holds up' when the Highest group is at least 2× the None group and injuries rise at "
           "every step from Low to Highest. These are in-sample associations across many mines, not causal or tested out of sample, "
           "and not a prediction for any one mine. Verdicts can change with the measure selected.")

st.divider()
st.markdown("### The evidence, one warning sign at a time")
st.caption(f"Each bar is a group of {category.lower()} mine-quarters. Height = {ylab.lower()}. "
           "Light grey = None; amber = a sign that holds up; grey = one that doesn't. "
           "Dotted line = average for all mine-quarters.")

cols = st.columns(3)
for i, (k, (label, _, kind, desc)) in enumerate(INDICATORS.items()):
    g = df[df.indicator == k].copy()
    v = verdicts[k]
    with cols[i % 3]:
        with st.container(border=True):
            badge = ("<span class='badge-good'>Holds up</span>" if kind == "candidate" and v["holds"] else
                     "<span class='badge-warn'>Confounded</span>" if kind == "confounded" else
                     "<span class='badge-bad'>Doesn't hold up</span>")
            st.markdown(f"<div class='ind-title'>{label} {badge}</div><div class='ind-desc'>{desc}</div>",
                        unsafe_allow_html=True)
            if v["sparse"]:
                st.caption(f"Too few {category.lower()} mines have any of this to form groups.")
            elif kind == "confounded":
                q1 = g.set_index("quartile")[ycol].get(1)
                st.caption(f"Low {fmt(q1)} → Highest {fmt(v['q4'])}, likely reflecting MSHA targeting of riskier mines.")
            else:
                st.caption(f"None {fmt(v['q0'])} → Highest {fmt(v['q4'])} ({v['lift']:.1f}× higher)")
            g["group"] = g.quartile.map(lambda q: GROUP_LABELS.get(int(q), str(q)))
            color = AMBER if kind == "candidate" and v["holds"] else GREY
            g["c"] = g.quartile.map(lambda q: "#cbd5e1" if q == 0 else color)
            fig = px.bar(g, x="group", y=ycol, custom_data=["mine_quarters"],
                         category_orders={"group": list(GROUP_LABELS.values())})
            fig.update_traces(marker_color=g.c.tolist(),
                              texttemplate="%{y:.1f}" if ycol == "rate" else "%{y:.0f}%", textposition="outside",
                              hovertemplate=f"<b>%{{x}}</b> {label.lower()}<br>{ylab}: "
                                            + ("%{y:.2f}" if ycol == "rate" else "%{y:.1f}%")
                                            + "<br>Mine-quarters in group: %{customdata[0]:,}<extra></extra>")
            fig.add_hline(y=base[ycol], line_dash="dot", line_color=NAVY, opacity=.5)
            fig.update_yaxes(range=[0, max(g[ycol].max(), base[ycol]) * 1.25])
            st.plotly_chart(plotly_layout(fig, height=240, yaxis_title=None), width="stretch",
                            key=f"chart_{k}")
provenance("LEADING_INDICATORS WHERE is_comparable · pooled next-quarter rates; "
           "None = the sign was zero in the prior 4 quarters")

with st.expander("Methodology"):
    st.markdown("""
- **Unit:** one mine-quarter. **Features** use only the **prior four quarters** (no leakage from the outcome quarter).
- **Outcome:** the **next** quarter's operator injuries and hours; pooled rate = `SUM(injuries) × 200,000 / SUM(hours)`.
- **Comparable rows** (`is_comparable`): four prior quarters of history, ≥ 20K prior operator hours, and a known
  next-quarter outcome.
- **Groups (quartiles):** None = the indicator was zero in the prior year; Low → Highest = quartiles 1–4 of the non-zero values, computed
  within mine category. S&S share is quartiled the same way here, in SQL.
- **Associations, not a predictive model.** Mine-level correlations are weak (≈ 0) because quarterly injury counts
  are noisy; the signal appears only when mines are pooled into groups. No risk score is computed on this page.
""")
