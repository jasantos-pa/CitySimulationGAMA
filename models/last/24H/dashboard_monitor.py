import argparse
import json
import os
import sqlite3
import unicodedata
from datetime import datetime
from pathlib import Path

import pandas as pd

try:
    import plotly.graph_objects as go
    from dash import Dash, Input, Output, dash_table, dcc, html
except ImportError as exc:
    raise SystemExit(
        "Missing dependencies: install with `python -m pip install -r models/requirements-dashboard.txt` "
        "using Python 3.12 or lower."
    ) from exc

from analyze_simulation import compute_active_travelers_profile


BASE_DIR = Path(__file__).resolve().parent
REPORT_JSON = BASE_DIR / "report.json"
TRIPS_CSV = BASE_DIR / "trips.csv"
EVENTS_CSV = BASE_DIR / "events.csv"
HOUSEHOLDS_CSV = BASE_DIR / "households.csv"
DB_PATH = BASE_DIR.parent / "includes" / "SimuCityDB.db"
HOUSEHOLD_TARGET_MUNICIPALITY_CODE = os.getenv("CITY_MUNICIPALITY_CODE", "28074")
HOUSEHOLD_SIZE_ORDER = ["1 persona", "2 personas", "3 personas", "4 personas", "5 o mas personas"]
HOUSEHOLD_STRUCTURE_FOCUS = [
    "Hogar con un hombre solo de 65 años o más",
    "Hogar con un hombre solo menor de 65 años",
    "Hogar con un solo progenitor que convive con algún hijo menor de 25 años",
    "Hogar con un solo progenitor que convive con todos sus hijos de 25 años o más",
    "Hogar con una mujer sola de 65 años o más",
    "Hogar con una mujer sola menor de 65 años",
]
DASHBOARD_EXPORT_LATEST = BASE_DIR / "dashboard_export_latest.csv"
DASHBOARD_EXPORTS_DIR = BASE_DIR / "dashboard_exports"

REFRESH_INTERVAL_MS = 15_000


def load_report():
    if not REPORT_JSON.exists():
        return {}
    try:
        return json.loads(REPORT_JSON.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return {}


def load_trips():
    if not TRIPS_CSV.exists():
        return pd.DataFrame()
    trips = pd.read_csv(TRIPS_CSV, skipinitialspace=True)
    for col in ["start_time", "end_time", "duration", "wait_time"]:
        if col in trips.columns:
            trips[col] = pd.to_numeric(trips[col], errors="coerce")
    if "mode" in trips.columns:
        trips["mode"] = trips["mode"].astype(str).str.strip().str.lower()
    return trips


def load_events():
    if not EVENTS_CSV.exists():
        return pd.DataFrame()
    try:
        events = pd.read_csv(EVENTS_CSV, skipinitialspace=True)
    except pd.errors.ParserError:
        # Some event details include commas without CSV quoting; rebuild rows safely.
        raw_lines = EVENTS_CSV.read_text(encoding="utf-8", errors="replace").splitlines()
        rows = []
        for line in raw_lines[1:]:
            if not line.strip():
                continue
            parts = line.split(",")
            if len(parts) < 7:
                continue
            rows.append(
                {
                    "event_type": parts[0].strip(),
                    "time": parts[1].strip(),
                    "entity_id": parts[2].strip(),
                    "related_id": parts[3].strip(),
                    "details": ",".join(parts[4:-2]).strip(),
                    "extra_1": parts[-2].strip(),
                    "extra_2": parts[-1].strip(),
                }
            )
        events = pd.DataFrame(
            rows,
            columns=["event_type", "time", "entity_id", "related_id", "details", "extra_1", "extra_2"],
        )
    if "time" in events.columns:
        events["time"] = pd.to_numeric(events["time"], errors="coerce")
    return events


def nk(value):
    if value is None:
        return ""
    txt = str(value).strip().lower()
    txt = unicodedata.normalize("NFKD", txt).encode("ascii", "ignore").decode("ascii")
    return " ".join(txt.replace(",", " ").split())


def canonical_household_size_label(raw):
    s = nk(raw)
    if not s or "total" in s:
        return None
    if "1" in s:
        return "1 persona"
    if "2" in s:
        return "2 personas"
    if "3" in s:
        return "3 personas"
    if "4" in s:
        return "4 personas"
    if "5" in s:
        return "5 o mas personas"
    return None


def load_households_registry():
    if not HOUSEHOLDS_CSV.exists():
        return pd.DataFrame()
    try:
        return pd.read_csv(HOUSEHOLDS_CSV, skipinitialspace=True)
    except pd.errors.ParserError:
        raw_lines = HOUSEHOLDS_CSV.read_text(encoding="utf-8", errors="replace").splitlines()
        header_parts = raw_lines[0].split(",") if raw_lines else []
        has_nucleus_col = any(nk(h) == "nucleus_member_refs" for h in header_parts)
        rows = []
        for line in raw_lines[1:]:
            if not line.strip():
                continue
            parts = line.split(",")
            if has_nucleus_col and len(parts) < 9:
                continue
            if (not has_nucleus_col) and len(parts) < 8:
                continue
            if has_nucleus_col:
                nucleus_refs = parts[6].strip()
                house_name = ",".join(parts[7:-1]).strip()
                house_type = parts[-1].strip()
            else:
                nucleus_refs = ""
                house_name = ",".join(parts[6:-1]).strip()
                house_type = parts[-1].strip()
            rows.append(
                {
                    "household_id": parts[0].strip(),
                    "number_persons": parts[1].strip(),
                    "district": parts[2].strip(),
                    "household_type_theoretical": parts[3].strip(),
                    "household_type_generated": parts[4].strip(),
                    "member_count": parts[5].strip(),
                    "nucleus_member_refs": nucleus_refs,
                    "house_building_name": house_name,
                    "house_building_type": house_type,
                }
            )
        return pd.DataFrame(
            rows,
            columns=[
                "household_id",
                "number_persons",
                "district",
                "household_type_theoretical",
                "household_type_generated",
                "member_count",
                "nucleus_member_refs",
                "house_building_name",
                "house_building_type",
            ],
        )


def load_household_targets_from_db(municipality_code=HOUSEHOLD_TARGET_MUNICIPALITY_CODE):
    out = {
        "overall_pct": {},
        "by_size_pct": {},
        "display_labels": {},
        "size_order": list(HOUSEHOLD_SIZE_ORDER),
    }
    if not DB_PATH.exists():
        return out

    code = str(municipality_code or "").strip().split()[0]
    like_value = f"{code} %" if code else f"{municipality_code} %"

    try:
        conn = sqlite3.connect(DB_PATH)
        rows = conn.execute(
            "SELECT TamanoHogar, EstructuraHogar, Total FROM Hogares WHERE Municipio LIKE ?",
            (like_value,),
        ).fetchall()
        conn.close()
    except sqlite3.Error:
        return out

    overall_counts = {}
    overall_total = 0.0
    by_size_counts = {s: {} for s in out["size_order"]}
    by_size_totals = {s: 0.0 for s in out["size_order"]}

    for tamano, estructura, total in rows:
        size_raw = "" if tamano is None else str(tamano).strip()
        struct_raw = "" if estructura is None else str(estructura).strip()
        struct_key = nk(struct_raw)
        if not struct_key:
            continue
        out["display_labels"].setdefault(struct_key, struct_raw)
        total_value = float(total or 0.0)
        size_norm = nk(size_raw)
        size_label = canonical_household_size_label(size_raw)

        is_total_structure = "total (estructura del hogar)" in struct_key
        is_total_size_bucket = "total (tamano del hogar)" in size_norm

        if is_total_structure:
            if size_label is not None:
                by_size_totals[size_label] = total_value
            elif is_total_size_bucket:
                overall_total = total_value
            continue

        if size_label is not None:
            by_size_counts[size_label][struct_key] = by_size_counts[size_label].get(struct_key, 0.0) + total_value
        elif is_total_size_bucket:
            overall_counts[struct_key] = overall_counts.get(struct_key, 0.0) + total_value

    if overall_total <= 0.0:
        overall_total = sum(overall_counts.values())
    if overall_total > 0.0:
        out["overall_pct"] = {k: v / overall_total for k, v in overall_counts.items()}

    for size in out["size_order"]:
        den = by_size_totals.get(size, 0.0)
        if den <= 0.0:
            den = sum(by_size_counts.get(size, {}).values())
        if den > 0.0:
            out["by_size_pct"][size] = {k: v / den for k, v in by_size_counts.get(size, {}).items()}
        else:
            out["by_size_pct"][size] = {}

    return out


def load_household_size_targets_from_db_sql(municipality_code=HOUSEHOLD_TARGET_MUNICIPALITY_CODE):
    out = {
        "municipality": "",
        "size_order": list(HOUSEHOLD_SIZE_ORDER),
        "count_by_size": {s: 0.0 for s in HOUSEHOLD_SIZE_ORDER},
        "pct_by_size": {s: 0.0 for s in HOUSEHOLD_SIZE_ORDER},
    }
    if not DB_PATH.exists():
        return out

    code = str(municipality_code or "").strip().split()[0]
    like_value = f"{code} %" if code else f"{municipality_code}"

    try:
        conn = sqlite3.connect(DB_PATH)
        muni_row = conn.execute(
            "SELECT Municipio FROM Hogares WHERE Municipio LIKE ? ORDER BY Municipio LIMIT 1",
            (like_value,),
        ).fetchone()
        municipality_full = muni_row[0] if muni_row else str(municipality_code or "").strip()
        out["municipality"] = municipality_full

        rows = conn.execute(
            """
            WITH Totales AS (
                SELECT
                    TamanoHogar,
                    SUM(total) AS TotalHogares
                FROM Hogares
                WHERE Municipio = ?
                  AND EstructuraHogar = 'Total (estructura del hogar)'
                  AND TamanoHogar IN (
                        '1 persona',
                        '2 personas',
                        '3 personas',
                        '4 personas',
                        '5 o más personas'
                  )
                GROUP BY TamanoHogar
            )
            SELECT
                TamanoHogar,
                TotalHogares,
                ROUND(100.0 * TotalHogares / SUM(TotalHogares) OVER (), 2) AS Porcentaje
            FROM Totales
            ORDER BY
                CASE TamanoHogar
                    WHEN '1 persona' THEN 1
                    WHEN '2 personas' THEN 2
                    WHEN '3 personas' THEN 3
                    WHEN '4 personas' THEN 4
                    WHEN '5 o más personas' THEN 5
                END
            """,
            (municipality_full,),
        ).fetchall()
        conn.close()
    except sqlite3.Error:
        return out

    for tamano, total_hogares, porcentaje in rows:
        size_label = canonical_household_size_label(tamano)
        if size_label is None:
            continue
        count_value = float(total_hogares or 0.0)
        pct_value = float(porcentaje or 0.0) / 100.0
        out["count_by_size"][size_label] = count_value
        out["pct_by_size"][size_label] = pct_value

    return out


def build_household_size_monitor_rows(households, municipality_code=HOUSEHOLD_TARGET_MUNICIPALITY_CODE):
    rows = []
    targets = load_household_size_targets_from_db_sql(municipality_code)

    sim_counts = {s: 0 for s in HOUSEHOLD_SIZE_ORDER}
    size_col = None
    if households is not None and not households.empty:
        for c in ["number_persons", "numberPersons"]:
            if c in households.columns:
                size_col = c
                break
        if size_col is not None:
            for _, row in households.iterrows():
                size_label = canonical_household_size_label(row.get(size_col))
                if size_label is not None:
                    sim_counts[size_label] = sim_counts.get(size_label, 0) + 1

    sim_total = sum(sim_counts.values())

    for size in HOUSEHOLD_SIZE_ORDER:
        sim_count = int(sim_counts.get(size, 0))
        sim_pct = (100.0 * sim_count / sim_total) if sim_total > 0 else 0.0
        target_pct = 100.0 * float(targets.get("pct_by_size", {}).get(size, 0.0))
        rows.append(
            {
                "dimension": "household_size_breakdown",
                "category": size,
                "count": sim_count,
                "sim_pct": round(sim_pct, 2),
                "target_pct": round(target_pct, 2),
                "delta_pct": round(sim_pct - target_pct, 2),
                "abs_delta_pct": round(abs(sim_pct - target_pct), 2),
            }
        )
    return rows


def load_household_structure_focus_targets_from_db_sql(municipality_code=HOUSEHOLD_TARGET_MUNICIPALITY_CODE):
    out = {
        "municipality": "",
        "size_order": list(HOUSEHOLD_SIZE_ORDER),
        "focus_order": list(HOUSEHOLD_STRUCTURE_FOCUS),
        "by_size_pct": {s: {} for s in HOUSEHOLD_SIZE_ORDER},
        "by_size_count": {s: {} for s in HOUSEHOLD_SIZE_ORDER},
        "display_labels": {},
    }
    if not DB_PATH.exists():
        return out

    code = str(municipality_code or "").strip().split()[0]
    like_value = f"{code} %" if code else f"{municipality_code}"

    try:
        conn = sqlite3.connect(DB_PATH)
        muni_row = conn.execute(
            "SELECT Municipio FROM Hogares WHERE Municipio LIKE ? ORDER BY Municipio LIMIT 1",
            (like_value,),
        ).fetchone()
        municipality_full = muni_row[0] if muni_row else str(municipality_code or "").strip()
        out["municipality"] = municipality_full

        rows = conn.execute(
            """
            WITH Desglose AS (
                SELECT
                    TamanoHogar,
                    EstructuraHogar,
                    SUM(total) AS Hogares
                FROM Hogares
                WHERE Municipio = ?
                  AND (TamanoHogar IN ('1 persona', '2 personas', '3 personas', '4 personas', '5 o más personas')
                       OR TamanoHogar LIKE '5 o% personas')
                  AND EstructuraHogar IN (
                      'Hogar con un hombre solo de 65 años o más',
                      'Hogar con un hombre solo menor de 65 años',
                      'Hogar con un solo progenitor que convive con algún hijo menor de 25 años',
                      'Hogar con un solo progenitor que convive con todos sus hijos de 25 años o más',
                      'Hogar con una mujer sola de 65 años o más',
                      'Hogar con una mujer sola menor de 65 años'
                  )
                GROUP BY TamanoHogar, EstructuraHogar
            ),
            ConPorcentajes AS (
                SELECT
                    TamanoHogar,
                    EstructuraHogar,
                    Hogares,
                    ROUND(
                        100.0 * Hogares / SUM(Hogares) OVER (PARTITION BY TamanoHogar),
                        2
                    ) AS PorcentajeDentroTamano
                FROM Desglose
                WHERE Hogares > 0
            )
            SELECT
                TamanoHogar,
                EstructuraHogar,
                Hogares,
                PorcentajeDentroTamano
            FROM ConPorcentajes
            ORDER BY
                CASE TamanoHogar
                    WHEN '1 persona' THEN 1
                    WHEN '2 personas' THEN 2
                    WHEN '3 personas' THEN 3
                    WHEN '4 personas' THEN 4
                    WHEN '5 o más personas' THEN 5
                END,
                Hogares DESC
            """,
            (municipality_full,),
        ).fetchall()
        conn.close()
    except sqlite3.Error:
        return out

    for tamano, estructura, hogares, porcentaje in rows:
        size_label = canonical_household_size_label(tamano)
        if size_label is None:
            continue
        struct_label = str(estructura or "").strip()
        if not struct_label:
            continue
        struct_key = nk(struct_label)
        out["display_labels"][struct_key] = struct_label
        out["by_size_count"][size_label][struct_key] = float(hogares or 0.0)
        out["by_size_pct"][size_label][struct_key] = float(porcentaje or 0.0) / 100.0

    return out


def build_household_structure_focus_rows(households, municipality_code=HOUSEHOLD_TARGET_MUNICIPALITY_CODE):
    rows = []
    targets = load_household_structure_focus_targets_from_db_sql(municipality_code)
    size_order = targets["size_order"]
    focus_order = targets["focus_order"]
    focus_keys = [nk(x) for x in focus_order]

    sim_by_size_counts = {s: {fk: 0 for fk in focus_keys} for s in size_order}
    sim_by_size_totals_focus = {s: 0 for s in size_order}

    type_col = None
    size_col = None
    if households is not None and not households.empty:
        for c in ["household_type_generated", "householdTypeGenerated", "household_type_theoretical", "householdTypeTheoretical", "household_type", "householdType"]:
            if c in households.columns:
                type_col = c
                break
        for c in ["number_persons", "numberPersons"]:
            if c in households.columns:
                size_col = c
                break
        if type_col is not None and size_col is not None:
            for _, row in households.iterrows():
                size_label = canonical_household_size_label(row.get(size_col))
                if size_label is None:
                    continue
                sk = nk(row.get(type_col))
                if sk in sim_by_size_counts[size_label]:
                    sim_by_size_counts[size_label][sk] = sim_by_size_counts[size_label].get(sk, 0) + 1
                    sim_by_size_totals_focus[size_label] = sim_by_size_totals_focus.get(size_label, 0) + 1

    for size in size_order:
        sim_den = int(sim_by_size_totals_focus.get(size, 0))
        for label in focus_order:
            sk = nk(label)
            count = int(sim_by_size_counts.get(size, {}).get(sk, 0))
            sim_pct = (100.0 * count / sim_den) if sim_den > 0 else 0.0
            target_pct = 100.0 * float(targets.get("by_size_pct", {}).get(size, {}).get(sk, 0.0))
            display = targets.get("display_labels", {}).get(sk, label)
            rows.append(
                {
                    "dimension": "household_structure_focus_by_size",
                    "category": f"{size} | {display}",
                    "count": count,
                    "sim_pct": round(sim_pct, 2),
                    "target_pct": round(target_pct, 2),
                    "delta_pct": round(sim_pct - target_pct, 2),
                    "abs_delta_pct": round(abs(sim_pct - target_pct), 2),
                }
            )
    return rows


def build_household_structure_monitor_rows(households, municipality_code=HOUSEHOLD_TARGET_MUNICIPALITY_CODE):
    rows = []
    if households is None or households.empty:
        return rows

    targets = load_household_targets_from_db(municipality_code)
    size_order = targets["size_order"]

    type_col = None
    for c in ["household_type_generated", "householdTypeGenerated", "household_type_theoretical", "householdTypeTheoretical", "household_type", "householdType"]:
        if c in households.columns:
            type_col = c
            break
    size_col = None
    for c in ["number_persons", "numberPersons"]:
        if c in households.columns:
            size_col = c
            break
    if type_col is None or size_col is None:
        return rows

    sim_total = int(len(households))
    sim_overall_counts = {}
    sim_by_size_counts = {s: {} for s in size_order}
    sim_size_totals = {s: 0 for s in size_order}
    sim_display_labels = {}

    for _, row in households.iterrows():
        struct_raw = str(row.get(type_col, "")).strip()
        if not struct_raw:
            continue
        struct_key = nk(struct_raw)
        if not struct_key or "total (estructura del hogar)" in struct_key:
            continue
        sim_display_labels.setdefault(struct_key, struct_raw)
        sim_overall_counts[struct_key] = sim_overall_counts.get(struct_key, 0) + 1

        size_label = canonical_household_size_label(row.get(size_col))
        if size_label is not None:
            sim_size_totals[size_label] = sim_size_totals.get(size_label, 0) + 1
            sim_by_size_counts[size_label][struct_key] = sim_by_size_counts[size_label].get(struct_key, 0) + 1

    all_struct_keys = set(targets.get("display_labels", {}).keys()) | set(sim_overall_counts.keys())
    all_struct_keys = {k for k in all_struct_keys if "total (estructura del hogar)" not in k}
    labels = {**targets.get("display_labels", {}), **sim_display_labels}
    sorted_struct_keys = sorted(all_struct_keys, key=lambda k: labels.get(k, k))

    for sk in sorted_struct_keys:
        count = int(sim_overall_counts.get(sk, 0))
        sim_pct = (100.0 * count / sim_total) if sim_total > 0 else 0.0
        target_pct = 100.0 * float(targets.get("overall_pct", {}).get(sk, 0.0))
        rows.append(
            {
                "dimension": "household_type",
                "category": labels.get(sk, sk),
                "count": count,
                "sim_pct": round(sim_pct, 2),
                "target_pct": round(target_pct, 2),
                "delta_pct": round(sim_pct - target_pct, 2),
                "abs_delta_pct": round(abs(sim_pct - target_pct), 2),
            }
        )

    for size in size_order:
        sim_den = int(sim_size_totals.get(size, 0))
        target_size_map = targets.get("by_size_pct", {}).get(size, {})
        for sk in sorted_struct_keys:
            count = int(sim_by_size_counts.get(size, {}).get(sk, 0))
            sim_pct = (100.0 * count / sim_den) if sim_den > 0 else 0.0
            target_pct = 100.0 * float(target_size_map.get(sk, 0.0))
            rows.append(
                {
                    "dimension": "household_type_by_size",
                    "category": f"{size} | {labels.get(sk, sk)}",
                    "count": count,
                    "sim_pct": round(sim_pct, 2),
                    "target_pct": round(target_pct, 2),
                    "delta_pct": round(sim_pct - target_pct, 2),
                    "abs_delta_pct": round(abs(sim_pct - target_pct), 2),
                }
            )

    return rows


def safe_mode_shares(report, trips):
    shares = report.get("mode_shares", {})
    if shares:
        return shares
    if "mode" not in trips.columns or trips.empty:
        return {}
    counts = trips["mode"].value_counts(normalize=True).to_dict()
    return counts


def mode_share_figure(mode_shares, mode_expectation=None):
    if not mode_shares:
        fig = go.Figure()
        fig.add_annotation(text="No mode data", showarrow=False, font={"size": 18})
        fig.update_layout(template="plotly_white", margin={"l": 20, "r": 20, "t": 40, "b": 20})
        return fig

    items = sorted(mode_shares.items(), key=lambda x: x[1], reverse=True)
    labels = [k for k, _ in items]
    values = [v * 100.0 for _, v in items]
    per_mode = (mode_expectation or {}).get("per_mode", {})
    has_expected = any(
        (per_mode.get(mode, {}).get("expected_mixed_share") is not None) for mode in labels
    )
    custom = []
    for mode in labels:
        row = per_mode.get(mode, {})
        exp_mix = row.get("expected_mixed_share")
        exp_short = row.get("expected_short_share")
        exp_long = row.get("expected_long_share")
        delta_mix = row.get("delta_vs_mixed")
        custom.append(
            [
                (float(exp_mix) * 100.0) if exp_mix is not None else float("nan"),
                (float(exp_short) * 100.0) if exp_short is not None else float("nan"),
                (float(exp_long) * 100.0) if exp_long is not None else float("nan"),
                (float(delta_mix) * 100.0) if delta_mix is not None else float("nan"),
            ]
        )

    fig = go.Figure(
        data=[
            go.Pie(
                labels=labels,
                values=values,
                hole=0.35,
                textinfo="label+percent",
                customdata=custom,
                hovertemplate=(
                    (
                        "%{label}"
                        "<br>Observed: %{value:.2f}%"
                        "<br>Expected mixed: %{customdata[0]:.2f}%"
                        "<br>Expected short: %{customdata[1]:.2f}%"
                        "<br>Expected long: %{customdata[2]:.2f}%"
                        "<br>Delta vs mixed: %{customdata[3]:.2f} pp"
                        "<extra></extra>"
                    )
                    if has_expected
                    else "%{label}: %{value:.2f}%<extra></extra>"
                ),
            )
        ]
    )
    fig.update_layout(
        title="Distribution by Transport Mode",
        template="plotly_white",
        margin={"l": 20, "r": 20, "t": 50, "b": 20},
        legend={"orientation": "h", "yanchor": "bottom", "y": -0.1, "xanchor": "center", "x": 0.5},
        hoverlabel={"font": {"size": 14}},
    )
    return fig


def active_travelers_figure(profile):
    if not profile or "times" not in profile or "active" not in profile:
        fig = go.Figure()
        fig.add_annotation(text="No active-travel profile", showarrow=False, font={"size": 18})
        fig.update_layout(template="plotly_white", margin={"l": 20, "r": 20, "t": 40, "b": 20})
        return fig

    times_h = [t / 3600.0 for t in profile["times"]]
    active = profile["active"]
    summary = profile.get("summary", {})

    fig = go.Figure()
    fig.add_trace(
        go.Scatter(
            x=times_h,
            y=active,
            mode="lines",
            name="Active travelers",
            line={"width": 2.5, "color": "#1f77b4"},
        )
    )

    peak_time = summary.get("peak_time_seconds")
    peak_value = summary.get("peak_active")
    if peak_time is not None and peak_value is not None:
        fig.add_trace(
            go.Scatter(
                x=[peak_time / 3600.0],
                y=[peak_value],
                mode="markers+text",
                text=[f"Peak: {peak_value}"],
                textposition="top center",
                marker={"size": 10, "color": "#d62728"},
                name="Peak",
            )
        )

    fig.update_layout(
        title="Active Travelers Over Time",
        xaxis_title="Simulation time (hours)",
        yaxis_title="Travelers in transit",
        template="plotly_white",
        margin={"l": 20, "r": 20, "t": 50, "b": 30},
        hoverlabel={"font": {"size": 14}},
    )
    return fig


def starts_per_hour_figure(trips):
    if trips.empty or "start_time" not in trips.columns:
        fig = go.Figure()
        fig.add_annotation(text="No trip start data", showarrow=False, font={"size": 18})
        fig.update_layout(template="plotly_white", margin={"l": 20, "r": 20, "t": 40, "b": 20})
        return fig

    base = trips.dropna(subset=["start_time"]).copy()
    if base.empty:
        fig = go.Figure()
        fig.add_annotation(text="No trip start data", showarrow=False, font={"size": 18})
        fig.update_layout(template="plotly_white", margin={"l": 20, "r": 20, "t": 40, "b": 20})
        return fig

    base["hour_bin"] = (base["start_time"] / 3600.0).astype(int)
    if "mode" not in base.columns:
        grouped = base.groupby("hour_bin", as_index=False).size()
        fig = go.Figure(data=[go.Bar(x=grouped["hour_bin"], y=grouped["size"], name="trips")])
    else:
        grouped = base.groupby(["hour_bin", "mode"], as_index=False).size()
        fig = go.Figure()
        for mode in sorted(grouped["mode"].unique()):
            g = grouped[grouped["mode"] == mode]
            fig.add_trace(go.Bar(x=g["hour_bin"], y=g["size"], name=mode))

    fig.update_layout(
        title="Trip Starts per Hour Bin",
        xaxis_title="Hour from simulation start",
        yaxis_title="Number of trips started",
        barmode="stack",
        template="plotly_white",
        margin={"l": 20, "r": 20, "t": 50, "b": 30},
        legend={"orientation": "h", "yanchor": "bottom", "y": -0.2, "xanchor": "center", "x": 0.5},
        hoverlabel={"font": {"size": 14}},
    )
    return fig


def work_schedule_hist_figure(report):
    ws = report.get("work_schedule_assignment", {}) if report else {}
    start_counts = ws.get("start_counts", {}) or {}
    end_counts = ws.get("end_counts", {}) or {}
    target_start = ws.get("start_target_shares", {}) or {}
    target_end = ws.get("end_target_shares", {}) or {}
    hours = sorted({int(h) for h in list(start_counts.keys()) + list(end_counts.keys()) + list(target_start.keys()) + list(target_end.keys())})
    if not hours:
        fig = go.Figure()
        fig.add_annotation(text="No assigned work schedule data", showarrow=False, font={"size": 18})
        fig.update_layout(template="plotly_white", margin={"l": 20, "r": 20, "t": 40, "b": 20})
        return fig

    starts = [int(start_counts.get(str(h), 0)) for h in hours]
    ends = [int(end_counts.get(str(h), 0)) for h in hours]
    target_start_pct = [float(target_start.get(str(h), 0.0)) * 100.0 for h in hours]
    target_end_pct = [float(target_end.get(str(h), 0.0)) * 100.0 for h in hours]

    fig = go.Figure()
    fig.add_trace(go.Bar(x=hours, y=starts, name="Assigned start_work"))
    fig.add_trace(go.Bar(x=hours, y=ends, name="Assigned end_work"))
    fig.add_trace(
        go.Scatter(
            x=hours,
            y=target_start_pct,
            mode="lines+markers",
            name="Target start (%)",
            yaxis="y2",
            line={"width": 2, "color": "#ff7f0e"},
        )
    )
    fig.add_trace(
        go.Scatter(
            x=hours,
            y=target_end_pct,
            mode="lines+markers",
            name="Target end (%)",
            yaxis="y2",
            line={"width": 2, "color": "#f2c14e", "dash": "dash"},
        )
    )

    fig.update_layout(
        title="Assigned Work Schedule Histogram",
        xaxis_title="Hour of day",
        yaxis_title="Persons (count)",
        yaxis2={"title": "Target (%)", "overlaying": "y", "side": "right", "showgrid": False},
        barmode="group",
        template="plotly_white",
        margin={"l": 20, "r": 20, "t": 50, "b": 30},
        legend={"orientation": "h", "yanchor": "bottom", "y": -0.2, "xanchor": "center", "x": 0.5},
        hoverlabel={"font": {"size": 14}},
    )
    return fig


def build_peak_rows(summary):
    peaks = summary.get("top_peaks", [])
    rows = []
    for idx, p in enumerate(peaks, start=1):
        rows.append(
            {
                "rank": idx,
                "time_h": round(float(p["time_seconds"]) / 3600.0, 3),
                "active_travelers": int(p["active"]),
            }
        )
    return rows


def build_discrepancy_rows(report):
    top = report.get("real_vs_sim", {}).get("top_discrepancies", [])
    rows = []
    for idx, d in enumerate(top, start=1):
        rows.append(
            {
                "rank": idx,
                "dimension": str(d.get("dimension", "")),
                "category": str(d.get("category", "")),
                "sim_pct": round(float(d.get("sim_share", 0.0)) * 100.0, 2),
                "target_pct": round(float(d.get("target_share", 0.0)) * 100.0, 2),
                "abs_delta_pct": round(float(d.get("abs_delta", 0.0)) * 100.0, 2),
                "delta_pct": round(float(d.get("delta", 0.0)) * 100.0, 2),
            }
        )
    return rows[:20]


def build_population_monitor_rows(report, households):
    rows = []
    comparisons = report.get("real_vs_sim", {}).get("comparisons", {})
    pop_counts = report.get("population_counts", {})
    work_sched = report.get("work_schedule_assignment", {})
    count_group_for_dim = {
        "household_size": "household_size",
        "gender": "gender",
        "age_range": "age_range",
        "district": "district",
    }
    for dim, comp in comparisons.items():
        if not comp.get("available", False):
            continue
        group_name = count_group_for_dim.get(dim)
        counts = pop_counts.get(group_name, {}) if group_name else {}
        if dim == "work_start_hour":
            counts = {str(k): int(v) for k, v in (work_sched.get("start_counts", {}) or {}).items()}
        for x in comp.get("rows", []):
            cat = str(x.get("category", ""))
            rows.append(
                {
                    "dimension": dim,
                    "category": cat,
                    "count": int(counts.get(cat, 0)),
                    "sim_pct": round(float(x.get("sim_share", 0.0)) * 100.0, 2),
                    "target_pct": round(float(x.get("target_share", 0.0)) * 100.0, 2),
                    "delta_pct": round(float(x.get("delta", 0.0)) * 100.0, 2),
                    "abs_delta_pct": round(float(x.get("abs_delta", 0.0)) * 100.0, 2),
                }
            )
    rows.extend(build_household_size_monitor_rows(households, HOUSEHOLD_TARGET_MUNICIPALITY_CODE))
    rows.extend(build_household_structure_focus_rows(households, HOUSEHOLD_TARGET_MUNICIPALITY_CODE))
    rows.extend(build_household_structure_monitor_rows(households, HOUSEHOLD_TARGET_MUNICIPALITY_CODE))
    return rows


def split_population_monitor_rows(rows):
    household_size_rows = []
    household_structure_focus_rows = []
    general_rows = []

    for row in rows:
        dim = str(row.get("dimension", ""))
        if dim == "household_size_breakdown":
            household_size_rows.append(row)
            continue
        if dim == "household_structure_focus_by_size":
            household_structure_focus_rows.append(row)
            continue
        general_rows.append(row)

    return general_rows, household_size_rows, household_structure_focus_rows


def fmt_num(value, default="-", digits=2):
    if value is None:
        return default
    try:
        return f"{float(value):.{digits}f}"
    except (TypeError, ValueError):
        return default


def compute_kpis(report, trips, events, profile):
    summary = profile.get("summary", {}) if profile else {}
    taxi_kpis = report.get("taxi_kpis", {})
    schedule_flow = report.get("schedule_flow", {})
    trip_lifecycle = report.get("trip_event_lifecycle", {})

    kpis = {
        "total_trips": int(len(trips)) if not trips.empty else 0,
        "peak_active": int(summary.get("peak_active", 0)),
        "peak_time_h": fmt_num((summary.get("peak_time_seconds", 0.0) / 3600.0), digits=2),
        "valley_non_zero": int(summary.get("active_non_zero_min", 0)),
        "avg_active": fmt_num(summary.get("avg_active", 0.0), digits=2),
        "p95_active": fmt_num(summary.get("active_p95", 0.0), digits=2),
        "taxi_trips": int(taxi_kpis.get("count", 0)),
        "taxi_avg_duration_min": fmt_num((taxi_kpis.get("avg_duration", 0.0) / 60.0), digits=2),
        "crosswalk_issues": len(report.get("crosswalk_issues", [])),
        "companion_issues": len(report.get("companion_issues", [])),
        "events_rows": int(len(events)) if not events.empty else 0,
        "home_return_work_ratio_pct": fmt_num(float(schedule_flow.get("home_return_to_work_ratio", 0.0)) * 100.0, digits=1),
        "work_home_gap": int(schedule_flow.get("home_return_vs_work_gap", 0)),
        "trip_event_closure_pct": fmt_num(float(trip_lifecycle.get("event_closure_rate", 0.0)) * 100.0, digits=1),
    }
    return kpis


def starts_per_hour_rows(trips):
    if trips.empty or "start_time" not in trips.columns:
        return []
    base = trips.dropna(subset=["start_time"]).copy()
    if base.empty:
        return []
    base["hour_bin"] = (base["start_time"] / 3600.0).astype(int)
    rows = []
    if "mode" not in base.columns:
        grouped = base.groupby("hour_bin", as_index=False).size()
        for _, r in grouped.iterrows():
            rows.append({"hour_bin": int(r["hour_bin"]), "mode": "all", "trip_count": int(r["size"])})
        return rows
    grouped = base.groupby(["hour_bin", "mode"], as_index=False).size()
    for _, r in grouped.iterrows():
        rows.append({"hour_bin": int(r["hour_bin"]), "mode": str(r["mode"]), "trip_count": int(r["size"])})
    return rows


def work_schedule_rows(report):
    ws = report.get("work_schedule_assignment", {}) if report else {}
    start_counts = ws.get("start_counts", {}) or {}
    end_counts = ws.get("end_counts", {}) or {}
    target_start = ws.get("start_target_shares", {}) or {}
    target_end = ws.get("end_target_shares", {}) or {}
    hours = sorted({int(h) for h in list(start_counts.keys()) + list(end_counts.keys()) + list(target_start.keys()) + list(target_end.keys())})
    rows = []
    for h in hours:
        hs = str(h)
        rows.append(
            {
                "hour": h,
                "start_count": int(start_counts.get(hs, 0)),
                "end_count": int(end_counts.get(hs, 0)),
                "target_start_pct": round(float(target_start.get(hs, 0.0)) * 100.0, 4),
                "target_end_pct": round(float(target_end.get(hs, 0.0)) * 100.0, 4),
            }
        )
    return rows


def build_dashboard_export_rows(
    report,
    trips,
    events,
    mode_shares,
    mode_exp,
    profile,
    kpis,
    peaks_rows,
    discrepancies_rows,
    population_monitor_rows,
):
    export_time = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    rows = []

    rows.append(
        {
            "export_time": export_time,
            "section": "meta",
            "item": "source_rows",
            "category": "trips/events",
            "value": int(len(trips)),
            "value_text": f"{len(trips)}/{len(events)}",
            "unit": "count",
            "notes": "trips_rows/events_rows",
        }
    )

    for key, val in kpis.items():
        rows.append(
            {
                "export_time": export_time,
                "section": "kpi",
                "item": str(key),
                "category": "",
                "value": pd.to_numeric(pd.Series([val]), errors="coerce").iloc[0],
                "value_text": str(val),
                "unit": "",
                "notes": "",
            }
        )

    for mode, share in sorted(mode_shares.items(), key=lambda x: x[1], reverse=True):
        per_mode = (mode_exp or {}).get("per_mode", {}).get(mode, {})
        rows.append(
            {
                "export_time": export_time,
                "section": "mode_share",
                "item": "observed_share_pct",
                "category": str(mode),
                "value": round(float(share) * 100.0, 4),
                "value_text": "",
                "unit": "pct",
                "notes": "",
            }
        )
        for key, col in [
            ("expected_mixed_share", "expected_mixed_share_pct"),
            ("expected_short_share", "expected_short_share_pct"),
            ("expected_long_share", "expected_long_share_pct"),
            ("delta_vs_mixed", "delta_vs_mixed_pct_points"),
        ]:
            v = per_mode.get(key)
            if v is not None:
                rows.append(
                    {
                        "export_time": export_time,
                        "section": "mode_share",
                        "item": col,
                        "category": str(mode),
                        "value": round(float(v) * 100.0, 4),
                        "value_text": "",
                        "unit": "pct",
                        "notes": "",
                    }
                )

    summary = profile.get("summary", {}) if profile else {}
    for k in ["peak_active", "peak_time_seconds", "avg_active", "active_p95", "active_non_zero_min"]:
        if k in summary:
            rows.append(
                {
                    "export_time": export_time,
                    "section": "active_timeline_summary",
                    "item": k,
                    "category": "",
                    "value": float(summary.get(k, 0.0)),
                    "value_text": "",
                    "unit": "count" if "active" in k else "seconds",
                    "notes": "",
                }
            )

    if profile and "times" in profile and "active" in profile:
        for t, a in zip(profile["times"], profile["active"]):
            rows.append(
                {
                    "export_time": export_time,
                    "section": "active_timeline_series",
                    "item": "active_travelers",
                    "category": "",
                    "value": float(a),
                    "value_text": "",
                    "unit": "count",
                    "notes": f"time_seconds={float(t):.3f}",
                }
            )

    for r in starts_per_hour_rows(trips):
        rows.append(
            {
                "export_time": export_time,
                "section": "starts_per_hour",
                "item": "trip_count",
                "category": str(r["mode"]),
                "value": int(r["trip_count"]),
                "value_text": "",
                "unit": "count",
                "notes": f'hour_bin={int(r["hour_bin"])}',
            }
        )

    for r in work_schedule_rows(report):
        rows.append(
            {
                "export_time": export_time,
                "section": "work_schedule_hist",
                "item": "start_count",
                "category": str(r["hour"]),
                "value": int(r["start_count"]),
                "value_text": "",
                "unit": "count",
                "notes": "",
            }
        )
        rows.append(
            {
                "export_time": export_time,
                "section": "work_schedule_hist",
                "item": "end_count",
                "category": str(r["hour"]),
                "value": int(r["end_count"]),
                "value_text": "",
                "unit": "count",
                "notes": "",
            }
        )
        rows.append(
            {
                "export_time": export_time,
                "section": "work_schedule_hist",
                "item": "target_start_pct",
                "category": str(r["hour"]),
                "value": float(r["target_start_pct"]),
                "value_text": "",
                "unit": "pct",
                "notes": "",
            }
        )
        rows.append(
            {
                "export_time": export_time,
                "section": "work_schedule_hist",
                "item": "target_end_pct",
                "category": str(r["hour"]),
                "value": float(r["target_end_pct"]),
                "value_text": "",
                "unit": "pct",
                "notes": "",
            }
        )

    for r in peaks_rows:
        rows.append(
            {
                "export_time": export_time,
                "section": "main_peaks",
                "item": "active_travelers",
                "category": str(r.get("rank", "")),
                "value": int(r.get("active_travelers", 0)),
                "value_text": "",
                "unit": "count",
                "notes": f'time_h={r.get("time_h", "")}',
            }
        )

    for r in discrepancies_rows:
        rows.append(
            {
                "export_time": export_time,
                "section": "top_discrepancies",
                "item": str(r.get("dimension", "")),
                "category": str(r.get("category", "")),
                "value": float(r.get("abs_delta_pct", 0.0)),
                "value_text": "",
                "unit": "pct_points",
                "notes": f'sim_pct={r.get("sim_pct", "")};target_pct={r.get("target_pct", "")};delta_pct={r.get("delta_pct", "")}',
            }
        )

    for r in population_monitor_rows:
        rows.append(
            {
                "export_time": export_time,
                "section": "population_monitor",
                "item": str(r.get("dimension", "")),
                "category": str(r.get("category", "")),
                "value": pd.to_numeric(pd.Series([r.get("count")]), errors="coerce").iloc[0],
                "value_text": "",
                "unit": "count",
                "notes": f'sim_pct={r.get("sim_pct", "")};target_pct={r.get("target_pct", "")};delta_pct={r.get("delta_pct", "")};abs_delta_pct={r.get("abs_delta_pct", "")}',
            }
        )

    return rows


def export_dashboard_csv(
    n_intervals,
    report,
    trips,
    events,
    mode_shares,
    mode_exp,
    profile,
    kpis,
    peaks_rows,
    discrepancies_rows,
    population_monitor_rows,
):
    rows = build_dashboard_export_rows(
        report=report,
        trips=trips,
        events=events,
        mode_shares=mode_shares,
        mode_exp=mode_exp,
        profile=profile,
        kpis=kpis,
        peaks_rows=peaks_rows,
        discrepancies_rows=discrepancies_rows,
        population_monitor_rows=population_monitor_rows,
    )
    if not rows:
        return None, None, 0

    df = pd.DataFrame(rows)
    df.to_csv(DASHBOARD_EXPORT_LATEST, index=False, encoding="utf-8-sig")

    snapshot_path = None
    if int(n_intervals or 0) == 0:
        DASHBOARD_EXPORTS_DIR.mkdir(parents=True, exist_ok=True)
        snapshot_path = DASHBOARD_EXPORTS_DIR / f"dashboard_export_{datetime.now().strftime('%Y%m%d_%H%M%S')}.csv"
        df.to_csv(snapshot_path, index=False, encoding="utf-8-sig")

    return DASHBOARD_EXPORT_LATEST, snapshot_path, len(df)


def card(title, value, subtitle=""):
    return html.Div(
        children=[
            html.Div(title, style={"fontSize": "13px", "opacity": 0.8}),
            html.Div(str(value), style={"fontSize": "30px", "fontWeight": 700, "lineHeight": "36px"}),
            html.Div(subtitle, style={"fontSize": "12px", "opacity": 0.8}),
        ],
        style={
            "background": "#16202f",
            "border": "1px solid #223147",
            "borderRadius": "10px",
            "padding": "12px 14px",
            "color": "#f3f6fb",
            "minWidth": "170px",
        },
    )


app = Dash(__name__)
app.title = "City Simulation Monitor"

app.layout = html.Div(
    style={"backgroundColor": "#0f1724", "minHeight": "100vh", "padding": "16px", "fontFamily": "Segoe UI, Arial, sans-serif"},
    children=[
        dcc.Interval(id="refresh", interval=REFRESH_INTERVAL_MS, n_intervals=0),
        html.Div(
            [
                html.H2("City Simulation Monitor", style={"margin": "0", "color": "#e9edf5"}),
                html.Div(id="last-refresh", style={"color": "#a8b6cc", "fontSize": "13px"}),
            ],
            style={"display": "flex", "justifyContent": "space-between", "alignItems": "center", "marginBottom": "14px"},
        ),
        html.Div(id="kpi-row", style={"display": "grid", "gridTemplateColumns": "repeat(auto-fit, minmax(180px, 1fr))", "gap": "10px", "marginBottom": "14px"}),
        html.Div(
            style={"display": "grid", "gridTemplateColumns": "1fr 1fr", "gap": "12px", "marginBottom": "12px"},
            children=[
                dcc.Graph(id="mode-pie", config={"displaylogo": False}),
                dcc.Graph(id="active-timeline", config={"displaylogo": False}),
            ],
        ),
        html.Div(
            style={"display": "grid", "gridTemplateColumns": "2fr 1fr", "gap": "12px"},
            children=[
                dcc.Graph(id="starts-per-hour", config={"displaylogo": False}),
                html.Div(
                    style={"background": "#16202f", "border": "1px solid #223147", "borderRadius": "10px", "padding": "8px"},
                    children=[
                        html.H4("Main Peak Windows", style={"margin": "8px 10px", "color": "#f3f6fb"}),
                        dash_table.DataTable(
                            id="peaks-table",
                            columns=[
                                {"name": "Rank", "id": "rank"},
                                {"name": "Hour (h)", "id": "time_h"},
                                {"name": "Active", "id": "active_travelers"},
                            ],
                            data=[],
                            style_as_list_view=True,
                            style_cell={"padding": "6px", "fontSize": "13px", "textAlign": "left", "backgroundColor": "#16202f", "color": "#f3f6fb", "border": "1px solid #223147"},
                            style_header={"fontWeight": "bold", "backgroundColor": "#1f2c40", "color": "#f3f6fb", "border": "1px solid #2b3a50"},
                        ),
                    ],
                ),
            ],
        ),
        html.Div(
            style={"marginTop": "12px"},
            children=[dcc.Graph(id="work-schedule-hist", config={"displaylogo": False})],
        ),
        html.Div(
            style={"marginTop": "12px", "background": "#16202f", "border": "1px solid #223147", "borderRadius": "10px", "padding": "8px"},
            children=[
                html.H4("Top Real vs Sim Discrepancies", style={"margin": "8px 10px", "color": "#f3f6fb"}),
                dash_table.DataTable(
                    id="discrepancies-table",
                    columns=[
                        {"name": "Rank", "id": "rank"},
                        {"name": "Dimension", "id": "dimension"},
                        {"name": "Category", "id": "category"},
                        {"name": "Sim (%)", "id": "sim_pct"},
                        {"name": "Target (%)", "id": "target_pct"},
                        {"name": "Abs Delta (%)", "id": "abs_delta_pct"},
                        {"name": "Delta (%)", "id": "delta_pct"},
                    ],
                    data=[],
                    style_as_list_view=True,
                    style_cell={"padding": "6px", "fontSize": "13px", "textAlign": "left", "backgroundColor": "#16202f", "color": "#f3f6fb", "border": "1px solid #223147"},
                    style_header={"fontWeight": "bold", "backgroundColor": "#1f2c40", "color": "#f3f6fb", "border": "1px solid #2b3a50"},
                ),
            ],
        ),
        html.Div(
            style={"marginTop": "12px", "background": "#16202f", "border": "1px solid #223147", "borderRadius": "10px", "padding": "8px"},
            children=[
                html.H4("Population Monitoring (Counts + Shares)", style={"margin": "8px 10px", "color": "#f3f6fb"}),
                dash_table.DataTable(
                    id="population-monitor-table",
                    columns=[
                        {"name": "Dimension", "id": "dimension"},
                        {"name": "Category", "id": "category"},
                        {"name": "Count", "id": "count"},
                        {"name": "Sim (%)", "id": "sim_pct"},
                        {"name": "Target (%)", "id": "target_pct"},
                        {"name": "Delta (%)", "id": "delta_pct"},
                        {"name": "Abs Delta (%)", "id": "abs_delta_pct"},
                    ],
                    data=[],
                    page_size=20,
                    sort_action="native",
                    filter_action="native",
                    style_as_list_view=True,
                    style_cell={"padding": "6px", "fontSize": "13px", "textAlign": "left", "backgroundColor": "#16202f", "color": "#f3f6fb", "border": "1px solid #223147"},
                    style_header={"fontWeight": "bold", "backgroundColor": "#1f2c40", "color": "#f3f6fb", "border": "1px solid #2b3a50"},
                ),
            ],
        ),
        html.Div(
            style={"marginTop": "12px", "background": "#16202f", "border": "1px solid #223147", "borderRadius": "10px", "padding": "8px"},
            children=[
                html.H4("Household Size Breakdown (Sim vs Target)", style={"margin": "8px 10px", "color": "#f3f6fb"}),
                dash_table.DataTable(
                    id="household-size-breakdown-table",
                    columns=[
                        {"name": "Size", "id": "category"},
                        {"name": "Count", "id": "count"},
                        {"name": "Sim (%)", "id": "sim_pct"},
                        {"name": "Target (%)", "id": "target_pct"},
                        {"name": "Delta (%)", "id": "delta_pct"},
                        {"name": "Abs Delta (%)", "id": "abs_delta_pct"},
                    ],
                    data=[],
                    page_size=10,
                    sort_action="native",
                    style_as_list_view=True,
                    style_cell={"padding": "6px", "fontSize": "13px", "textAlign": "left", "backgroundColor": "#16202f", "color": "#f3f6fb", "border": "1px solid #223147"},
                    style_header={"fontWeight": "bold", "backgroundColor": "#1f2c40", "color": "#f3f6fb", "border": "1px solid #2b3a50"},
                ),
            ],
        ),
        html.Div(
            style={"marginTop": "12px", "background": "#16202f", "border": "1px solid #223147", "borderRadius": "10px", "padding": "8px"},
            children=[
                html.H4("Household Structure Focus by Size (Sim vs Target)", style={"margin": "8px 10px", "color": "#f3f6fb"}),
                dash_table.DataTable(
                    id="household-structure-focus-table",
                    columns=[
                        {"name": "Size | Structure", "id": "category"},
                        {"name": "Count", "id": "count"},
                        {"name": "Sim (%)", "id": "sim_pct"},
                        {"name": "Target (%)", "id": "target_pct"},
                        {"name": "Delta (%)", "id": "delta_pct"},
                        {"name": "Abs Delta (%)", "id": "abs_delta_pct"},
                    ],
                    data=[],
                    page_size=20,
                    sort_action="native",
                    filter_action="native",
                    style_as_list_view=True,
                    style_cell={"padding": "6px", "fontSize": "13px", "textAlign": "left", "backgroundColor": "#16202f", "color": "#f3f6fb", "border": "1px solid #223147"},
                    style_header={"fontWeight": "bold", "backgroundColor": "#1f2c40", "color": "#f3f6fb", "border": "1px solid #2b3a50"},
                ),
            ],
        ),
    ],
)


@app.callback(
    Output("last-refresh", "children"),
    Output("kpi-row", "children"),
    Output("mode-pie", "figure"),
    Output("active-timeline", "figure"),
    Output("starts-per-hour", "figure"),
    Output("work-schedule-hist", "figure"),
    Output("peaks-table", "data"),
    Output("discrepancies-table", "data"),
    Output("population-monitor-table", "data"),
    Output("household-size-breakdown-table", "data"),
    Output("household-structure-focus-table", "data"),
    Input("refresh", "n_intervals"),
)
def refresh_dashboard(_):
    report = load_report()
    trips = load_trips()
    events = load_events()
    households = load_households_registry()

    mode_shares = safe_mode_shares(report, trips)
    mode_exp = report.get("mode_expectation", {})
    profile = compute_active_travelers_profile(trips) if not trips.empty else {}
    summary = profile.get("summary", {})
    kpis = compute_kpis(report, trips, events, profile)
    discrepancies = build_discrepancy_rows(report)
    population_monitor_rows = build_population_monitor_rows(report, households)
    population_monitor_general_rows, household_size_rows, household_structure_focus_rows = split_population_monitor_rows(population_monitor_rows)
    peaks_rows = build_peak_rows(summary)

    export_latest, export_snapshot, export_rows = export_dashboard_csv(
        _,
        report,
        trips,
        events,
        mode_shares,
        mode_exp,
        profile,
        kpis,
        peaks_rows,
        discrepancies,
        population_monitor_rows,
    )

    kpi_cards = [
        card("Total Trips", kpis["total_trips"], "rows in trips.csv"),
        card("Peak Active", kpis["peak_active"], f'at {kpis["peak_time_h"]}h'),
        card("Valley (Non-Zero)", kpis["valley_non_zero"], "active travelers"),
        card("Average Active", kpis["avg_active"], f"P95: {kpis['p95_active']}"),
        card("Taxi Trips", kpis["taxi_trips"], f'avg duration: {kpis["taxi_avg_duration_min"]} min'),
        card("Crosswalk Issues", kpis["crosswalk_issues"], "from report.json"),
        card("Companion Issues", kpis["companion_issues"], "from report.json"),
        card("Home Return / Work", f'{kpis["home_return_work_ratio_pct"]}%', f'gap: {kpis["work_home_gap"]}'),
        card("Trip Event Closure", f'{kpis["trip_event_closure_pct"]}%', "starts vs ends"),
        card("Events Rows", kpis["events_rows"], "rows in events.csv"),
    ]

    refreshed_at = f"Last refresh: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}"
    if export_latest is not None:
        refreshed_at += f" | CSV: {export_latest.name} ({export_rows} rows)"
    if export_snapshot is not None:
        refreshed_at += f" | Snapshot: {export_snapshot.name}"

    return (
        refreshed_at,
        kpi_cards,
        mode_share_figure(mode_shares, mode_exp),
        active_travelers_figure(profile),
        starts_per_hour_figure(trips),
        work_schedule_hist_figure(report),
        peaks_rows,
        discrepancies,
        population_monitor_general_rows,
        household_size_rows,
        household_structure_focus_rows,
    )


def parse_args():
    parser = argparse.ArgumentParser(description="City simulation monitoring dashboard")
    parser.add_argument("--host", default="127.0.0.1", help="Host interface")
    parser.add_argument("--port", type=int, default=8050, help="HTTP port")
    parser.add_argument("--debug", action="store_true", help="Enable Dash debug mode")
    return parser.parse_args()


if __name__ == "__main__":
    args = parse_args()
    app.run(host=args.host, port=args.port, debug=args.debug)
