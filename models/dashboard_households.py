from __future__ import annotations

import argparse
import csv
import math
import unicodedata
from pathlib import Path

import pandas as pd
import plotly.express as px
import plotly.graph_objects as go
from dash import Dash, Input, Output, dash_table, dcc, html

BASE_DIR = Path(__file__).resolve().parent
HOUSEHOLDS_CSV = BASE_DIR / "households.csv"
HOUSEHOLD_MEMBERS_CSV = BASE_DIR / "household_members.csv"
DATA_CACHE = {"key": None, "bundle": None}
CALLBACK_CACHE = {}
DETAIL_CARD_LIMIT = 120

KEY_TO_LABEL = {
    "single_female_under_65": "Hogar con una mujer sola menor de 65 a?os",
    "single_male_under_65": "Hogar con un hombre solo menor de 65 a?os",
    "single_female_65_plus": "Hogar con una mujer sola de 65 a?os o m?s",
    "single_male_65_plus": "Hogar con un hombre solo de 65 a?os o m?s",
    "single_parent_minor_25": "Hogar con un solo progenitor que convive con alg?n hijo menor de 25 a?os",
    "single_parent_all_children_25_plus": "Hogar con un solo progenitor que convive con todos sus hijos de 25 a?os o m?s",
    "couple_without_children": "Hogar formado por pareja sin hijos",
    "couple_with_minor_25": "Hogar formado por pareja con hijos en donde alg?n hijo es menor de 25 a?os",
    "couple_all_children_25_plus": "Hogar formado por pareja con hijos en donde todos los hijos de 25 a?os o m?s",
    "family_with_minor_25_and_other_persons": "Hogar formado por pareja o un solo progenitor que convive con alg?n hijo menor de 25 a?os y otra(s) persona(s)",
    "other": "Otro tipo de hogar",
    "hard_constraint_fallback": "Hard constraint fallback",
    "unlinked_other": "Otra estructura o sin v?nculos detectados",
}

LABEL_TO_KEY = {
    "hogar con una mujer sola menor de 65 anos": "single_female_under_65",
    "hogar con un hombre solo menor de 65 anos": "single_male_under_65",
    "hogar con una mujer sola de 65 anos o mas": "single_female_65_plus",
    "hogar con un hombre solo de 65 anos o mas": "single_male_65_plus",
    "hogar con un solo progenitor que convive con algun hijo menor de 25 anos": "single_parent_minor_25",
    "hogar con un solo progenitor que convive con todos sus hijos de 25 anos o mas": "single_parent_all_children_25_plus",
    "hogar formado por pareja sin hijos": "couple_without_children",
    "hogar formado por pareja con hijos en donde algun hijo es menor de 25 anos": "couple_with_minor_25",
    "hogar formado por pareja con hijos en donde todos los hijos de 25 anos o mas": "couple_all_children_25_plus",
    "hogar formado por pareja o un solo progenitor que convive con algun hijo menor de 25 anos y otra(s) persona(s)": "family_with_minor_25_and_other_persons",
    "otro tipo de hogar": "other",
    "hard_constraint_fallback": "hard_constraint_fallback",
}

EXPECTED_PARTNER = {"couple_without_children", "couple_with_minor_25", "couple_all_children_25_plus"}
EXPECTED_CHILDREN = {"single_parent_minor_25", "single_parent_all_children_25_plus", "couple_with_minor_25", "couple_all_children_25_plus", "family_with_minor_25_and_other_persons"}
EXPECTED_MINOR = {"single_parent_minor_25", "couple_with_minor_25", "family_with_minor_25_and_other_persons"}


def norm(value: object) -> str:
    if value is None or (isinstance(value, float) and math.isnan(value)):
        return ""
    text = str(value).strip().lower()
    return "".join(ch for ch in unicodedata.normalize("NFKD", text) if not unicodedata.combining(ch))


def size_label(label: object, actual: int | None = None) -> str:
    s = norm(label)
    if s in {"1 persona", "1 personas"}:
        return "1 persona"
    if s == "2 personas":
        return "2 personas"
    if s == "3 personas":
        return "3 personas"
    if s == "4 personas":
        return "4 personas"
    if s in {"5 o mas personas", "5 o m?s personas"}:
        return "5 o m?s personas"
    if actual is None:
        return "Unknown"
    return "1 persona" if actual <= 1 else "2 personas" if actual == 2 else "3 personas" if actual == 3 else "4 personas" if actual == 4 else "5 o m?s personas"


def gen_key(label: object) -> str:
    return LABEL_TO_KEY.get(norm(label), "other")


def reciprocal_pairs(group: pd.DataFrame) -> tuple[int, int]:
    names = set(group["person_name"].dropna())
    links = {}
    invalid = 0
    for row in group.itertuples(index=False):
        if pd.notna(row.partner_name) and row.partner_name in names:
            links[row.person_name] = row.partner_name
        elif pd.notna(row.partner_name):
            invalid += 1
    pairs = {tuple(sorted((a, b))) for a, b in links.items() if links.get(b) == a and a != b}
    return len(pairs), invalid


def derive_observed(group: pd.DataFrame, generated_key: str, declared_size: str) -> dict:
    names = set(group["person_name"].dropna())
    pair_count, invalid_partner = reciprocal_pairs(group)
    linked_children, linked_parents, invalid_parent = set(), set(), 0
    for row in group.itertuples(index=False):
        if pd.notna(row.father_name):
            if row.father_name in names:
                linked_children.add(row.person_name)
                linked_parents.add(row.father_name)
            else:
                invalid_parent += 1
        if pd.notna(row.mother_name):
            if row.mother_name in names:
                linked_children.add(row.person_name)
                linked_parents.add(row.mother_name)
            else:
                invalid_parent += 1
    children_df = group[group["person_name"].isin(linked_children)]
    minor_children = int((children_df["age"] < 25).sum())
    observed_key = "unlinked_other"
    if len(group) == 1:
        row = group.iloc[0]
        gender, age = norm(row["gender"]), int(row["age"])
        if gender == "female" and age < 65:
            observed_key = "single_female_under_65"
        elif gender == "male" and age < 65:
            observed_key = "single_male_under_65"
        elif gender == "female":
            observed_key = "single_female_65_plus"
        elif gender == "male":
            observed_key = "single_male_65_plus"
    elif pair_count == 1 and not linked_children and len(group) == 2:
        observed_key = "couple_without_children"
    elif linked_children:
        extra = max(0, len(group) - len(linked_children | linked_parents))
        if pair_count == 1:
            observed_key = "family_with_minor_25_and_other_persons" if minor_children > 0 and extra > 0 else "couple_with_minor_25" if minor_children > 0 else "couple_all_children_25_plus"
        elif len(linked_parents) == 1:
            observed_key = "family_with_minor_25_and_other_persons" if minor_children > 0 and extra > 0 else "single_parent_minor_25" if minor_children > 0 else "single_parent_all_children_25_plus"
    elif generated_key == "other":
        observed_key = "other"
    issues = []
    if size_label(declared_size, len(group)) != size_label(declared_size):
        issues.append("size_label_mismatch")
    if generated_key in EXPECTED_PARTNER and pair_count == 0:
        issues.append("missing_partner_links")
    if generated_key in EXPECTED_CHILDREN and not linked_children:
        issues.append("missing_child_links")
    if generated_key in EXPECTED_MINOR and minor_children == 0:
        issues.append("missing_minor_child")
    if generated_key == "hard_constraint_fallback":
        issues.append("hard_constraint_fallback")
    if invalid_partner:
        issues.append("invalid_partner_refs")
    if invalid_parent:
        issues.append("invalid_parent_refs")
    if observed_key != generated_key:
        issues.append("generated_observed_mismatch")
    return {
        "observed_key": observed_key,
        "observed_label": KEY_TO_LABEL.get(observed_key, KEY_TO_LABEL["unlinked_other"]),
        "partner_pairs": pair_count,
        "linked_children": len(linked_children),
        "linked_parents": len(linked_parents),
        "linked_minor_children": minor_children,
        "issue_flags": "|".join(issues),
        "has_any_issue": bool(issues),
        "member_names": "|".join(sorted(names)),
    }


def read_household_csv(path: Path) -> pd.DataFrame:
    with path.open("r", encoding="utf-8", newline="") as handle:
        reader = csv.reader(handle)
        try:
            header = next(reader)
        except StopIteration:
            return pd.DataFrame()
        expected_len = len(header)
        rows = []
        for row in reader:
            if len(row) < expected_len:
                row = row + [""] * (expected_len - len(row))
            elif len(row) > expected_len:
                row = row[: expected_len - 1] + [",".join(row[expected_len - 1 :]).strip()]
            rows.append(row)
    return pd.DataFrame(rows, columns=header)


def file_signature(path: Path) -> tuple[int, int]:
    stat = path.stat()
    return stat.st_mtime_ns, stat.st_size


def build_enriched_households(households: pd.DataFrame, members: pd.DataFrame, grouped: dict[str, pd.DataFrame]) -> pd.DataFrame:
    if households.empty:
        return households
    hh = households.copy()
    hh["generated_key"] = hh["household_type_generated"].map(gen_key)
    hh["generated_label"] = hh["generated_key"].map(KEY_TO_LABEL)
    hh["is_hard_fallback"] = hh["generated_key"] == "hard_constraint_fallback"
    hh["declared_size_label"] = hh["number_persons"].map(size_label)
    hh["actual_member_count"] = hh["household_id"].map(members.groupby("household_id").size()).fillna(0).astype(int)
    hh["actual_size_label"] = hh["actual_member_count"].map(lambda x: size_label(None, x))
    hh["declared_member_count_matches_actual"] = hh["member_count"].fillna(-1).astype(int) == hh["actual_member_count"]
    hh["declared_size_matches_actual"] = hh["declared_size_label"] == hh["actual_size_label"]
    observed = []
    for row in hh.itertuples(index=False):
        group = grouped.get(row.household_id, pd.DataFrame(columns=members.columns))
        item = derive_observed(group, row.generated_key, row.declared_size_label)
        item["household_id"] = row.household_id
        observed.append(item)
    hh = hh.merge(pd.DataFrame(observed), on="household_id", how="left")
    hh["generated_observed_match"] = hh["generated_key"] == hh["observed_key"]
    return hh


def load_bundle() -> tuple[pd.DataFrame, pd.DataFrame, dict[str, pd.DataFrame], tuple[tuple[int, int], tuple[int, int]]]:
    cache_key = (file_signature(HOUSEHOLDS_CSV), file_signature(HOUSEHOLD_MEMBERS_CSV))
    if DATA_CACHE["key"] == cache_key and DATA_CACHE["bundle"] is not None:
        return DATA_CACHE["bundle"]
    households = read_household_csv(HOUSEHOLDS_CSV)
    members = read_household_csv(HOUSEHOLD_MEMBERS_CSV)
    if households.empty:
        bundle = (households, members, {}, cache_key)
        DATA_CACHE["key"] = cache_key
        DATA_CACHE["bundle"] = bundle
        CALLBACK_CACHE.clear()
        return bundle
    if not members.empty and "age" in members.columns:
        members["age"] = pd.to_numeric(members["age"], errors="coerce")
    if not members.empty and "children_count" in members.columns:
        members["children_count"] = pd.to_numeric(members["children_count"], errors="coerce").fillna(0).astype(int)
    grouped = {hid: grp.copy() for hid, grp in members.groupby("household_id", sort=False)}
    enriched = build_enriched_households(households, members, grouped)
    bundle = (enriched, members, grouped, cache_key)
    DATA_CACHE["key"] = cache_key
    DATA_CACHE["bundle"] = bundle
    CALLBACK_CACHE.clear()
    return bundle


def load_and_enrich() -> pd.DataFrame:
    households, _, _, _ = load_bundle()
    return households


def pct(part: int | float, whole: int | float) -> float:
    return 0.0 if not whole else round(100.0 * float(part) / float(whole), 2)


def bar_chart(df: pd.DataFrame, col: str, title: str, color: str) -> go.Figure:
    data = df.groupby(col, dropna=False).size().reset_index(name="households").sort_values("households", ascending=False)
    fig = px.bar(data, x="households", y=col, orientation="h", text="households", title=title)
    fig.update_traces(marker_color=color)
    fig.update_layout(template="plotly_white", margin=dict(l=30, r=20, t=60, b=30), yaxis={"categoryorder": "total ascending"})
    return fig


def size_chart(df: pd.DataFrame) -> go.Figure:
    data = df.groupby("actual_size_label", dropna=False).size().reset_index(name="households")
    data["order"] = data["actual_size_label"].map({"1 persona": 1, "2 personas": 2, "3 personas": 3, "4 personas": 4, "5 o m?s personas": 5}).fillna(99)
    data = data.sort_values(["order", "actual_size_label"])
    fig = px.bar(data, x="actual_size_label", y="households", text="households", title="Actual Household Size Distribution")
    fig.update_traces(marker_color="#4c78a8")
    fig.update_layout(template="plotly_white", margin=dict(l=30, r=20, t=60, b=30))
    return fig


def confusion_heatmap(df: pd.DataFrame) -> go.Figure:
    cross = df.groupby(["generated_label", "observed_label"], dropna=False).size().reset_index(name="households")
    pivot = cross.pivot(index="generated_label", columns="observed_label", values="households").fillna(0)
    fig = go.Figure(data=go.Heatmap(z=pivot.values, x=list(pivot.columns), y=list(pivot.index), colorscale="Blues"))
    fig.update_layout(title="Generated vs Observed Household Structure", template="plotly_white", margin=dict(l=30, r=20, t=60, b=30))
    return fig


def empty_figure(title: str) -> go.Figure:
    fig = go.Figure()
    fig.update_layout(title=title, template="plotly_white", margin=dict(l=30, r=20, t=60, b=30))
    fig.add_annotation(text="No data available", x=0.5, y=0.5, xref="paper", yref="paper", showarrow=False, font={"size": 14, "color": "#666"})
    return fig


def make_card(title: str, value: str, subtitle: str) -> html.Div:
    return html.Div([html.Div(title, className="card-title"), html.Div(value, className="card-value"), html.Div(subtitle, className="card-subtitle")], className="metric-card")


def member_role_map(group: pd.DataFrame) -> dict[str, str]:
    names = set(group["person_name"].dropna())
    fathers = set(x for x in group["father_name"].dropna() if x in names)
    mothers = set(x for x in group["mother_name"].dropna() if x in names)
    roles = {}
    for row in group.itertuples(index=False):
        name = row.person_name
        gender = norm(row.gender)
        if name in fathers and name in mothers:
            roles[name] = "Father" if gender == "male" else "Mother" if gender == "female" else "Parent"
        elif name in fathers:
            roles[name] = "Father"
        elif name in mothers:
            roles[name] = "Mother"
        elif (pd.notna(row.father_name) and str(row.father_name).strip()) or (pd.notna(row.mother_name) and str(row.mother_name).strip()):
            roles[name] = "Child"
        elif int(getattr(row, "children_count", 0) or 0) > 0:
            roles[name] = "Parent"
        elif pd.notna(row.partner_name) and str(row.partner_name).strip():
            roles[name] = "Partner"
        else:
            roles[name] = "Other"
    return roles


def household_relationship_metrics(group: pd.DataFrame, roles: dict[str, str]) -> dict[str, int | None]:
    if group.empty:
        return {"mother_first_birth_age": None, "father_first_birth_age": None, "max_sibling_gap": None, "couple_gap": None}
    rows = group.copy()
    rows["age_num"] = pd.to_numeric(rows["age"], errors="coerce")
    name_to_row = {row.person_name: row for row in rows.itertuples(index=False)}
    children = rows[rows["person_name"].map(lambda n: roles.get(n) == "Child" and pd.notna(rows.loc[rows["person_name"] == n, "age_num"]).any())]
    child_ages = [int(a) for a in children["age_num"].dropna().tolist()]

    mother_candidates = rows[rows["person_name"].map(lambda n: roles.get(n) == "Mother")]
    if mother_candidates.empty:
        mother_candidates = rows[rows["person_name"].map(lambda n: roles.get(n) == "Parent" and norm(rows.loc[rows["person_name"] == n, "gender"].iloc[0]) == "female")]
    mother_first_birth_age = None
    if child_ages and not mother_candidates.empty:
        mother_age = mother_candidates["age_num"].dropna()
        if not mother_age.empty:
            mother_first_birth_age = int(mother_age.max() - max(child_ages))
    father_candidates = rows[rows["person_name"].map(lambda n: roles.get(n) == "Father")]
    if father_candidates.empty:
        father_candidates = rows[rows["person_name"].map(lambda n: roles.get(n) == "Parent" and norm(rows.loc[rows["person_name"] == n, "gender"].iloc[0]) == "male")]
    father_first_birth_age = None
    if child_ages and not father_candidates.empty:
        father_age = father_candidates["age_num"].dropna()
        if not father_age.empty:
            father_first_birth_age = int(father_age.max() - max(child_ages))

    max_sibling_gap = None
    if len(child_ages) >= 2:
        max_sibling_gap = int(max(child_ages) - min(child_ages))

    couple_gap = None
    internal_names = set(rows["person_name"].dropna())
    seen_pairs: set[tuple[str, str]] = set()
    chosen_pair: tuple[str, str] | None = None
    preferred_pairs: list[tuple[str, str]] = []
    fallback_pairs: list[tuple[str, str]] = []
    for row in rows.itertuples(index=False):
        if pd.isna(row.partner_name) or not str(row.partner_name).strip():
            continue
        partner_name = str(row.partner_name).strip()
        if partner_name not in internal_names:
            continue
        pair = tuple(sorted((row.person_name, partner_name)))
        if pair in seen_pairs:
            continue
        partner_row = name_to_row.get(partner_name)
        if partner_row is None or str(getattr(partner_row, "partner_name", "")).strip() != row.person_name:
            continue
        seen_pairs.add(pair)
        roles_pair = {roles.get(pair[0], "Other"), roles.get(pair[1], "Other")}
        if roles_pair & {"Father", "Mother", "Parent"}:
            preferred_pairs.append(pair)
        else:
            fallback_pairs.append(pair)
    if preferred_pairs:
        chosen_pair = preferred_pairs[0]
    elif fallback_pairs:
        chosen_pair = fallback_pairs[0]
    else:
        father_candidates = rows[rows["person_name"].map(lambda n: roles.get(n) == "Father")]
        mother_candidates_for_gap = rows[rows["person_name"].map(lambda n: roles.get(n) == "Mother")]
        if not father_candidates.empty and not mother_candidates_for_gap.empty:
            chosen_pair = (
                str(father_candidates.iloc[0]["person_name"]),
                str(mother_candidates_for_gap.iloc[0]["person_name"]),
            )
    if chosen_pair is not None:
        p1 = rows.loc[rows["person_name"] == chosen_pair[0], "age_num"].dropna()
        p2 = rows.loc[rows["person_name"] == chosen_pair[1], "age_num"].dropna()
        if not p1.empty and not p2.empty:
            couple_gap = int(abs(p1.iloc[0] - p2.iloc[0]))

    return {
        "mother_first_birth_age": mother_first_birth_age,
        "father_first_birth_age": father_first_birth_age,
        "max_sibling_gap": max_sibling_gap,
        "couple_gap": couple_gap,
    }


def relationship_badges(metrics: dict[str, int | None]) -> html.Div | None:
    chips = []
    if metrics.get("father_first_birth_age") is not None:
        chips.append(
            html.Span(
                f"Father at first birth: {metrics['father_first_birth_age']}",
                style={"padding": "3px 8px", "borderRadius": "999px", "background": "#eef4ff", "color": "#294c9b", "fontSize": "11px", "fontWeight": "600"},
            )
        )
    if metrics.get("mother_first_birth_age") is not None:
        chips.append(
            html.Span(
                f"Mother at first birth: {metrics['mother_first_birth_age']}",
                style={"padding": "3px 8px", "borderRadius": "999px", "background": "#eef4ff", "color": "#294c9b", "fontSize": "11px", "fontWeight": "600"},
            )
        )
    if metrics.get("max_sibling_gap") is not None:
        chips.append(
            html.Span(
                f"Max sibling gap: {metrics['max_sibling_gap']}",
                style={"padding": "3px 8px", "borderRadius": "999px", "background": "#eefbf2", "color": "#1d6b42", "fontSize": "11px", "fontWeight": "600"},
            )
        )
    if metrics.get("couple_gap") is not None:
        chips.append(
            html.Span(
                f"Couple gap: {metrics['couple_gap']}",
                style={"padding": "3px 8px", "borderRadius": "999px", "background": "#fff4ea", "color": "#9a4a10", "fontSize": "11px", "fontWeight": "600"},
            )
        )
    if not chips:
        return None
    return html.Div(chips, style={"display": "flex", "gap": "6px", "flexWrap": "wrap", "marginTop": "6px"})


def member_card(name: str, age: object, gender: object, role: str) -> html.Div:
    age_text = "?" if pd.isna(age) else str(int(age))
    gender_text = "" if gender is None else str(gender)
    gender_norm = norm(gender_text)
    gender_color = "#555"
    if gender_norm == "male":
        gender_color = "#2f6df6"
    elif gender_norm == "female":
        gender_color = "#e85aa6"
    return html.Div(
        [
            html.Div(name, style={"fontWeight": "700", "fontSize": "14px"}),
            html.Div(role, style={"fontSize": "12px", "color": "#1f4b99"}),
            html.Div(
                [
                    html.Span(f"{age_text} years | ", style={"color": "#555"}),
                    html.Span(gender_text, style={"color": gender_color, "fontWeight": "700"}),
                ],
                style={"fontSize": "12px"},
            ),
        ],
        style={
            "border": "1px solid #d7deea",
            "borderRadius": "10px",
            "padding": "10px 12px",
            "background": "#f8fbff",
            "minWidth": "140px",
        },
    )


def build_household_cards(
    filtered: pd.DataFrame,
    grouped_members: dict[str, pd.DataFrame],
    selected_type: str | None,
    max_cards: int = DETAIL_CARD_LIMIT,
) -> tuple[str, list[html.Div]]:
    if not selected_type or selected_type == "ALL":
        return "Select a generated household structure to list matching households.", []
    subset = filtered[filtered["generated_label"] == selected_type].sort_values(["district", "household_id"])
    if subset.empty:
        return "No households match the selected generated structure under the current filters.", []
    total_matches = len(subset)
    subset = subset.head(max_cards)
    cards = []
    for row in subset.itertuples(index=False):
        group = grouped_members.get(row.household_id, pd.DataFrame())
        if group.empty:
            continue
        roles = member_role_map(group)
        metrics = household_relationship_metrics(group, roles)
        top_cards = []
        bottom_cards = []
        for member in group.sort_values(["age", "person_name"], ascending=[False, True]).itertuples(index=False):
            role = roles.get(member.person_name, "Other")
            card = member_card(member.person_name, member.age, member.gender, role)
            if role in {"Father", "Mother", "Parent", "Partner"}:
                top_cards.append(card)
            else:
                bottom_cards.append(card)
        cards.append(
            html.Div(
                [
                    html.Div(
                        [
                            html.Div(f"{row.household_id} | {row.district}", style={"fontWeight": "700", "fontSize": "15px"}),
                            html.Div(f"{row.generated_label} | {row.actual_size_label} | {row.actual_member_count} members", style={"fontSize": "12px", "color": "#56627a"}),
                            relationship_badges(metrics),
                        ],
                        style={"marginBottom": "10px"},
                    ),
                    html.Div(top_cards if top_cards else [html.Div("No father/mother/parent/partner roles detected.", style={"fontSize": "12px", "color": "#777"})], style={"display": "flex", "gap": "8px", "flexWrap": "wrap", "marginBottom": "8px"}),
                    html.Div(bottom_cards if bottom_cards else [html.Div("No child/other members detected.", style={"fontSize": "12px", "color": "#777"})], style={"display": "flex", "gap": "8px", "flexWrap": "wrap"}),
                ],
                style={"border": "1px solid #cfd7e6", "borderRadius": "12px", "padding": "12px", "background": "white", "marginBottom": "12px"},
            )
        )
    if total_matches > max_cards:
        return (
            f"{total_matches} households match the selected generated structure. "
            f"Showing first {max_cards} for performance.",
            cards,
        )
    return f"{len(subset)} households listed for the selected generated structure.", cards


app = Dash(__name__)
app.title = "Household Structure Monitor"
app.layout = html.Div(
    [
        dcc.Interval(id="refresh", interval=5000, n_intervals=0),
        html.Div([html.H1("Household Structure Monitor", className="page-title"), html.Div(id="last-refresh", className="last-refresh")], className="header-row"),
        html.Div([
            html.Div([html.Label("District"), dcc.Dropdown(id="district-filter", clearable=False)], className="filter-card"),
            html.Div([html.Label("Actual size"), dcc.Dropdown(id="size-filter", clearable=False)], className="filter-card"),
            html.Div([html.Label("View"), dcc.Checklist(id="mismatch-filter", options=[{"label": "Mismatch households only", "value": "mismatch"}], value=[], inline=True)], className="filter-card"),
        ], className="filters-row"),
        html.Div([
            html.Div([html.Label("Generated structure detail"), dcc.Dropdown(id="detail-type-filter", clearable=False)], className="filter-card")
        ], className="filters-row"),
        html.Div(id="metric-cards", className="metrics-grid"),
        html.Div([dcc.Graph(id="size-chart", className="graph-card"), dcc.Graph(id="generated-chart", className="graph-card")], className="graph-grid"),
        html.Div([dcc.Graph(id="observed-chart", className="graph-card"), dcc.Graph(id="heatmap", className="graph-card")], className="graph-grid"),
        html.Div([
            html.Div([html.H3("Observed Structures By Size"), dash_table.DataTable(id="structure-table", page_size=20, sort_action="native", style_table={"overflowX": "auto"}, style_cell={"textAlign": "left", "padding": "8px", "fontSize": "13px"})], className="table-card"),
            html.Div([html.H3("Integrity Metrics"), dash_table.DataTable(id="integrity-table", page_size=12, sort_action="native", style_table={"overflowX": "auto"}, style_cell={"textAlign": "left", "padding": "8px", "fontSize": "13px"})], className="table-card"),
        ], className="table-grid"),
        html.Div([html.H3("Households With Relation Or Structure Issues"), dash_table.DataTable(id="issues-table", page_size=15, sort_action="native", filter_action="native", style_table={"overflowX": "auto"}, style_cell={"textAlign": "left", "padding": "8px", "fontSize": "12px", "maxWidth": "320px", "whiteSpace": "normal"})], className="table-card full-width"),
        html.Div(
            [
                html.H3("Household Listing By Generated Structure"),
                html.Div(id="detail-summary", style={"fontSize": "13px", "color": "#56627a", "marginBottom": "10px"}),
                html.Div(id="detail-households", style={"maxHeight": "900px", "overflowY": "auto", "paddingRight": "6px"}),
            ],
            className="table-card full-width",
        ),
    ], style={"padding": "20px"}
)


@app.callback(
    Output("last-refresh", "children"),
    Output("district-filter", "options"),
    Output("district-filter", "value"),
    Output("size-filter", "options"),
    Output("size-filter", "value"),
    Output("detail-type-filter", "options"),
    Output("detail-type-filter", "value"),
    Output("metric-cards", "children"),
    Output("size-chart", "figure"),
    Output("generated-chart", "figure"),
    Output("observed-chart", "figure"),
    Output("heatmap", "figure"),
    Output("structure-table", "data"),
    Output("structure-table", "columns"),
    Output("integrity-table", "data"),
    Output("integrity-table", "columns"),
    Output("issues-table", "data"),
    Output("issues-table", "columns"),
    Output("detail-summary", "children"),
    Output("detail-households", "children"),
    Input("refresh", "n_intervals"),
    Input("district-filter", "value"),
    Input("size-filter", "value"),
    Input("mismatch-filter", "value"),
    Input("detail-type-filter", "value"),
)
def refresh_dashboard(_n, district_value, size_value, mismatch_value, detail_type_value):
    hh = load_and_enrich()
    _, members, grouped_members, bundle_key = load_bundle()
    member_rows = len(members)
    cache_lookup_key = (bundle_key, district_value, size_value, tuple(sorted(mismatch_value or [])), detail_type_value)
    if cache_lookup_key in CALLBACK_CACHE:
        return CALLBACK_CACHE[cache_lookup_key]
    if hh.empty:
        empty_cards = [
            make_card("Households", "0", "Rows in households.csv after filters"),
            make_card("Persons", "0", "Rows counted from household_members.csv"),
            make_card("Average Size", "0.00", "Actual members per household"),
        ]
        result = (
            f"Last refresh | households.csv rows: 0 | household_members.csv rows: {member_rows}",
            [{"label": "All districts", "value": "ALL"}],
            "ALL",
            [{"label": "All sizes", "value": "ALL"}],
            "ALL",
            [{"label": "All generated structures", "value": "ALL"}],
            "ALL",
            empty_cards,
            empty_figure("Actual Household Size Distribution"),
            empty_figure("Generated Household Structures"),
            empty_figure("Observed Household Structures From Member Relations"),
            empty_figure("Generated vs Observed Household Structure"),
            [],
            [{"name": "Actual size", "id": "size"}, {"name": "Observed structure", "id": "structure"}, {"name": "Households", "id": "households"}, {"name": "Share within size (%)", "id": "share_within_size_pct"}],
            [],
            [{"name": "Metric", "id": "metric"}, {"name": "Count", "id": "count"}, {"name": "Share (%)", "id": "share_pct"}, {"name": "Denominator", "id": "denominator"}],
            [],
            [{"name": "Household", "id": "household_id"}, {"name": "District", "id": "district"}, {"name": "Declared size", "id": "declared_size_label"}, {"name": "Actual size", "id": "actual_size_label"}, {"name": "Actual members", "id": "actual_member_count"}, {"name": "Generated structure", "id": "generated_label"}, {"name": "Observed structure", "id": "observed_label"}, {"name": "Partner pairs", "id": "partner_pairs"}, {"name": "Linked children", "id": "linked_children"}, {"name": "Linked parents", "id": "linked_parents"}, {"name": "Linked children < 25", "id": "linked_minor_children"}, {"name": "Issue flags", "id": "issue_flags"}, {"name": "Members", "id": "member_names"}],
            "No household data available in the current CSVs.",
            [],
        )
        CALLBACK_CACHE[cache_lookup_key] = result
        return result
    district_options = [{"label": "All districts", "value": "ALL"}] + [{"label": d, "value": d} for d in sorted(hh["district"].fillna("Unknown").astype(str).unique())]
    district_value = district_value if district_value in {x["value"] for x in district_options} else "ALL"
    size_options = [{"label": "All sizes", "value": "ALL"}] + [{"label": s, "value": s} for s in ["1 persona", "2 personas", "3 personas", "4 personas", "5 o m?s personas"] if s in set(hh["actual_size_label"])]
    size_value = size_value if size_value in {x["value"] for x in size_options} else "ALL"
    filtered = hh.copy()
    if district_value != "ALL":
        filtered = filtered[filtered["district"].fillna("Unknown") == district_value]
    if size_value != "ALL":
        filtered = filtered[filtered["actual_size_label"] == size_value]
    if mismatch_value and "mismatch" in mismatch_value:
        filtered = filtered[~filtered["generated_observed_match"]]
    detail_options = [{"label": "All generated structures", "value": "ALL"}] + [{"label": s, "value": s} for s in sorted(x for x in filtered["generated_label"].dropna().unique())]
    detail_type_value = detail_type_value if detail_type_value in {x["value"] for x in detail_options} else "ALL"

    total_households = len(filtered)
    total_people = int(filtered["actual_member_count"].sum())
    avg_size = round(total_people / total_households, 2) if total_households else 0.0
    cards = [
        make_card("Households", str(total_households), "Rows in households.csv after filters"),
        make_card("Persons", str(total_people), "Rows counted from household_members.csv"),
        make_card("Average Size", f"{avg_size:.2f}", "Actual members per household"),
        make_card("Hard Fallback", f"{(100*filtered['is_hard_fallback'].mean()) if total_households else 0:.1f}%", "Households generated as hard_constraint_fallback"),
        make_card("Generated = Observed", f"{(100*filtered['generated_observed_match'].mean()) if total_households else 0:.1f}%", "Structure match from relations"),
        make_card("With Partner Links", f"{(100*(filtered['partner_pairs']>0).mean()) if total_households else 0:.1f}%", "Households with a reciprocal partner pair"),
        make_card("With Parent-Child Links", f"{(100*(filtered['linked_children']>0).mean()) if total_households else 0:.1f}%", "Households with linked children"),
        make_card("Issue Flagged", f"{(100*filtered['has_any_issue'].mean()) if total_households else 0:.1f}%", "Households with any structural inconsistency"),
    ]

    grouped = filtered.groupby(["actual_size_label", "observed_label"], dropna=False).size().reset_index(name="households")
    totals = grouped.groupby("actual_size_label")["households"].sum().to_dict()
    structure_rows = [{"size": row.actual_size_label, "structure": row.observed_label, "households": int(row.households), "share_within_size_pct": pct(row.households, totals.get(row.actual_size_label, 0))} for row in grouped.itertuples(index=False)]
    structure_rows.sort(key=lambda x: ({"1 persona": 1, "2 personas": 2, "3 personas": 3, "4 personas": 4, "5 o m?s personas": 5}.get(x["size"], 99), -x["households"], x["structure"]))

    partner_expected = int(filtered["generated_key"].isin(EXPECTED_PARTNER).sum())
    child_expected = int(filtered["generated_key"].isin(EXPECTED_CHILDREN).sum())
    minor_expected = int(filtered["generated_key"].isin(EXPECTED_MINOR).sum())
    integrity_rows = [
        {"metric": "Actual persons counted from household_members.csv", "count": total_people, "share_pct": 100.0, "denominator": "All persons"},
        {"metric": "Households with member_count matching actual rows", "count": int(filtered["declared_member_count_matches_actual"].sum()), "share_pct": pct(int(filtered["declared_member_count_matches_actual"].sum()), total_households), "denominator": "All households"},
        {"metric": "Households with number_persons matching actual rows", "count": int(filtered["declared_size_matches_actual"].sum()), "share_pct": pct(int(filtered["declared_size_matches_actual"].sum()), total_households), "denominator": "All households"},
        {"metric": "Generated vs observed structure matches", "count": int(filtered["generated_observed_match"].sum()), "share_pct": pct(int(filtered["generated_observed_match"].sum()), total_households), "denominator": "All households"},
        {"metric": "Expected partner structures with reciprocal partner links", "count": int(((filtered["generated_key"].isin(EXPECTED_PARTNER)) & (filtered["partner_pairs"] > 0)).sum()), "share_pct": pct(int(((filtered["generated_key"].isin(EXPECTED_PARTNER)) & (filtered["partner_pairs"] > 0)).sum()), partner_expected), "denominator": "Households expected to have a partner pair"},
        {"metric": "Expected child structures with linked parent-child relations", "count": int(((filtered["generated_key"].isin(EXPECTED_CHILDREN)) & (filtered["linked_children"] > 0)).sum()), "share_pct": pct(int(((filtered["generated_key"].isin(EXPECTED_CHILDREN)) & (filtered["linked_children"] > 0)).sum()), child_expected), "denominator": "Households expected to have children"},
        {"metric": "Expected minor-child structures with linked child under 25", "count": int(((filtered["generated_key"].isin(EXPECTED_MINOR)) & (filtered["linked_minor_children"] > 0)).sum()), "share_pct": pct(int(((filtered["generated_key"].isin(EXPECTED_MINOR)) & (filtered["linked_minor_children"] > 0)).sum()), minor_expected), "denominator": "Households expected to include a child under 25"},
        {"metric": "Households generated as hard_constraint_fallback", "count": int(filtered["is_hard_fallback"].sum()), "share_pct": pct(int(filtered["is_hard_fallback"].sum()), total_households), "denominator": "All households"},
        {"metric": "Households with any issue flag", "count": int(filtered["has_any_issue"].sum()), "share_pct": pct(int(filtered["has_any_issue"].sum()), total_households), "denominator": "All households"},
    ]

    issue_rows = filtered[filtered["has_any_issue"]][["household_id", "district", "declared_size_label", "actual_size_label", "actual_member_count", "generated_label", "observed_label", "partner_pairs", "linked_children", "linked_parents", "linked_minor_children", "issue_flags", "member_names"]].sort_values(["issue_flags", "household_id"]).head(250).to_dict("records")
    detail_summary, detail_cards = build_household_cards(filtered, grouped_members, detail_type_value, DETAIL_CARD_LIMIT)

    result = (
        f"Last refresh | households.csv rows: {len(hh)} | household_members.csv rows: {member_rows}",
        district_options,
        district_value,
        size_options,
        size_value,
        detail_options,
        detail_type_value,
        cards,
        size_chart(filtered),
        bar_chart(filtered, "generated_label", "Generated Household Structures", "#f58518"),
        bar_chart(filtered, "observed_label", "Observed Household Structures From Member Relations", "#54a24b"),
        confusion_heatmap(filtered),
        structure_rows,
        [{"name": "Actual size", "id": "size"}, {"name": "Observed structure", "id": "structure"}, {"name": "Households", "id": "households"}, {"name": "Share within size (%)", "id": "share_within_size_pct"}],
        integrity_rows,
        [{"name": "Metric", "id": "metric"}, {"name": "Count", "id": "count"}, {"name": "Share (%)", "id": "share_pct"}, {"name": "Denominator", "id": "denominator"}],
        issue_rows,
        [{"name": "Household", "id": "household_id"}, {"name": "District", "id": "district"}, {"name": "Declared size", "id": "declared_size_label"}, {"name": "Actual size", "id": "actual_size_label"}, {"name": "Actual members", "id": "actual_member_count"}, {"name": "Generated structure", "id": "generated_label"}, {"name": "Observed structure", "id": "observed_label"}, {"name": "Partner pairs", "id": "partner_pairs"}, {"name": "Linked children", "id": "linked_children"}, {"name": "Linked parents", "id": "linked_parents"}, {"name": "Linked children < 25", "id": "linked_minor_children"}, {"name": "Issue flags", "id": "issue_flags"}, {"name": "Members", "id": "member_names"}],
        detail_summary,
        detail_cards,
    )
    CALLBACK_CACHE[cache_lookup_key] = result
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description="Household dashboard derived only from households.csv and household_members.csv")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8062)
    args = parser.parse_args()
    print(f"Household dashboard running on http://{args.host}:{args.port}/")
    app.run(host=args.host, port=args.port, debug=False)


if __name__ == "__main__":
    main()
