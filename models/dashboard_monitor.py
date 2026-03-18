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
TRANSPORT_TARGET_MUNICIPALITY_CODE = os.getenv("CITY_MUNICIPALITY_CODE", "28074")
TRANSPORT_MODE_ORDER = ["car", "train", "walking", "taxi"]
TRIP_CLASS_FILTER_OPTIONS = [
    {"label": "All Trips (Mixed)", "value": "all"},
    {"label": "Short Trips", "value": "short"},
    {"label": "Long Trips", "value": "long"},
]
# DB uses Spanish category keys for household statistics; keep raw keys for SQL and canonical matching.
HOUSEHOLD_SIZE_ORDER = ["1 persona", "2 personas", "3 personas", "4 personas", "5 o mas personas"]
HOUSEHOLD_STRUCTURE_FOCUS = [
    "Hogar con un hombre solo de 65 años o más",
    "Hogar con un hombre solo menor de 65 años",
    "Hogar con un solo progenitor que convive con algún hijo menor de 25 años",
    "Hogar con un solo progenitor que convive con todos sus hijos de 25 años o más",
    "Hogar con una mujer sola de 65 años o más",
    "Hogar con una mujer sola menor de 65 años",
]
HOUSEHOLD_SIZE_DISPLAY = {
    "1 persona": "1 person",
    "2 personas": "2 persons",
    "3 personas": "3 persons",
    "4 personas": "4 persons",
    "5 o mas personas": "5+ persons",
}
HOUSEHOLD_STRUCTURE_DISPLAY = {
    "hogar con un hombre solo de 65 anos o mas": "Man living alone (65+)",
    "hogar con un hombre solo menor de 65 anos": "Man living alone (<65)",
    "hogar con un solo progenitor que convive con algun hijo menor de 25 anos": "Single parent with at least one child under 25",
    "hogar con un solo progenitor que convive con todos sus hijos de 25 anos o mas": "Single parent with all children 25+",
    "hogar con una mujer sola de 65 anos o mas": "Woman living alone (65+)",
    "hogar con una mujer sola menor de 65 anos": "Woman living alone (<65)",
    "hogar formado por pareja sin hijos": "Couple without children",
    "hogar formado por pareja con hijos en donde algun hijo es menor de 25 anos": "Couple with children (at least one under 25)",
    "hogar formado por pareja con hijos en donde todos los hijos de 25 anos o mas": "Couple with children (all 25+)",
    "hogar formado por pareja o un solo progenitor que convive con algun hijo menor de 25 anos y otra(s) persona(s)": "Couple/single parent + child under 25 + others",
    "otro tipo de hogar": "Other household type",
    "total (estructura del hogar)": "Total (household structure)",
}
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


def finite_float(value, default=0.0):
    try:
        v = float(value)
    except (TypeError, ValueError):
        return default
    if pd.isna(v):
        return default
    if v == float("inf") or v == float("-inf"):
        return default
    return v


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


def household_size_display_label(raw):
    size_key = canonical_household_size_label(raw) if raw is not None else None
    if size_key is None and raw is not None:
        size_key = canonical_household_size_label(str(raw))
    return HOUSEHOLD_SIZE_DISPLAY.get(size_key, str(raw) if raw is not None else "")


def household_structure_display_label(raw):
    label = "" if raw is None else str(raw).strip()
    if not label:
        return ""
    return HOUSEHOLD_STRUCTURE_DISPLAY.get(nk(label), label)


def household_category_display_label(raw):
    text = "" if raw is None else str(raw).strip()
    if not text:
        return ""
    if " | " in text:
        size_label, structure_label = text.split(" | ", 1)
        return f"{household_size_display_label(size_label)} | {household_structure_display_label(structure_label)}"
    size_only = household_size_display_label(text)
    if size_only:
        return size_only
    return household_structure_display_label(text)


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

    for size_bucket_db, structure_db, total in rows:
        size_raw = "" if size_bucket_db is None else str(size_bucket_db).strip()
        struct_raw = "" if structure_db is None else str(structure_db).strip()
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

    for size_bucket_db, total_households, percentage in rows:
        size_label = canonical_household_size_label(size_bucket_db)
        if size_label is None:
            continue
        count_value = float(total_households or 0.0)
        pct_value = float(percentage or 0.0) / 100.0
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
                "category": household_size_display_label(size),
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

    for size_bucket_db, structure_db, households_count, percentage in rows:
        size_label = canonical_household_size_label(size_bucket_db)
        if size_label is None:
            continue
        struct_label = str(structure_db or "").strip()
        if not struct_label:
            continue
        struct_key = nk(struct_label)
        out["display_labels"][struct_key] = struct_label
        out["by_size_count"][size_label][struct_key] = float(households_count or 0.0)
        out["by_size_pct"][size_label][struct_key] = float(percentage or 0.0) / 100.0

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
            display = household_structure_display_label(targets.get("display_labels", {}).get(sk, label))
            rows.append(
                {
                    "dimension": "household_structure_focus_by_size",
                    "category": f"{household_size_display_label(size)} | {display}",
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
                "category": household_structure_display_label(labels.get(sk, sk)),
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
                    "category": f"{household_size_display_label(size)} | {household_structure_display_label(labels.get(sk, sk))}",
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


def parse_details_map(details):
    out = {}
    txt = "" if details is None else str(details)
    for token in txt.split("|"):
        token = token.strip()
        if ":" not in token:
            continue
        k, v = token.split(":", 1)
        out[nk(k)] = v.strip()
    return out


def canonical_route_agent(raw):
    key = nk(raw)
    if key in {"person", "walker", "walking", "person_walking"}:
        return "person_walking"
    if key in {"car", "car_private", "normal_car", "normalcars", "vehicle_car"}:
        return "car"
    return None


def canonical_route_result(raw):
    key = nk(raw)
    if "started_without_route" in key or "without_helper" in key:
        return "started_without_route"
    if "first" in key:
        return "first_try_success"
    if "recover" in key or ("retry" in key and "fail" not in key):
        return "recovered_after_retries"
    if "fail" in key or "abort" in key:
        return "failed_after_retries"
    return None


def canonical_stuck_agent(raw):
    key = nk(raw)
    if key in {"car", "normal_car", "normalcars", "vehicle_car", "car_private"}:
        return "car"
    if key in {"taxi", "electric_car", "electriccars", "electriccar"}:
        return "taxi"
    return "unknown"


def compute_stuck_removal_summary(events):
    summary = {"total": 0, "car": 0, "taxi": 0, "unknown": 0}
    if events is None or events.empty or "event_type" not in events.columns:
        return summary

    ev = events.copy()
    ev["event_type"] = ev["event_type"].astype(str).str.strip().str.upper()
    ev = ev[ev["event_type"] == "ROUTE_STUCK_REMOVAL"]
    if ev.empty:
        return summary

    seen = set()
    for _, row in ev.iterrows():
        entity = nk(row.get("entity_id", ""))
        if not entity or entity in seen:
            continue
        seen.add(entity)
        details = parse_details_map(row.get("details", ""))
        agent_raw = details.get("agent", row.get("related_id", ""))
        agent = canonical_stuck_agent(agent_raw)
        summary[agent] = int(summary.get(agent, 0)) + 1
        summary["total"] += 1
    return summary


def looks_like_car_vehicle_id(raw):
    key = nk(raw)
    return key.startswith("normalcars")


def looks_like_taxi_vehicle_id(raw):
    key = nk(raw)
    return key.startswith("electriccars")


def compute_runtime_vehicle_pool(events):
    summary = {"total": 0, "car": 0, "taxi": 0}
    if events is None or events.empty or "entity_id" not in events.columns:
        return summary

    entity_raw = events["entity_id"].astype(str).str.strip()
    entity_lower = entity_raw.str.lower()
    valid_mask = (entity_raw != "") & (~entity_lower.isin({"global", "switchboard", "queue"}))
    if not valid_mask.any():
        return summary

    valid_entities = entity_lower[valid_mask]
    car_prefix = valid_entities[valid_entities.str.startswith("normalcars")]
    taxi_prefix = valid_entities[valid_entities.str.startswith("electriccars")]

    # Fast path: current logs use stable vehicle id prefixes.
    car_ids = set(car_prefix.unique().tolist())
    taxi_ids = set(taxi_prefix.unique().tolist())
    if car_ids or taxi_ids:
        summary["car"] = len(car_ids)
        summary["taxi"] = len(taxi_ids)
        summary["total"] = summary["car"] + summary["taxi"]
        return summary

    # Compatibility fallback for legacy logs without standard prefixes.
    cols = [c for c in ["event_type", "entity_id", "related_id", "details"] if c in events.columns]
    fallback = events.loc[valid_mask, cols].copy()
    if fallback.empty:
        return summary

    if "event_type" in fallback.columns:
        evt = fallback["event_type"].astype(str).str.strip().str.upper()
    else:
        evt = pd.Series([""] * len(fallback), index=fallback.index)
    if "related_id" in fallback.columns:
        rel = fallback["related_id"].astype(str).str.strip().str.lower()
    else:
        rel = pd.Series([""] * len(fallback), index=fallback.index)

    candidate_mask = rel.isin({"car", "taxi"}) | evt.str.startswith("ROUTE_") | evt.str.startswith("TAXI_")
    if not candidate_mask.any():
        return summary

    for _, row in fallback.loc[candidate_mask].iterrows():
        entity = nk(row.get("entity_id", ""))
        if not entity:
            continue
        details = parse_details_map(row.get("details", ""))
        agent = canonical_stuck_agent(details.get("agent", row.get("related_id", "")))
        related = nk(row.get("related_id", ""))

        if agent == "car" or looks_like_car_vehicle_id(entity):
            car_ids.add(entity)
            continue
        if agent == "taxi" or related == "taxi" or looks_like_taxi_vehicle_id(entity):
            taxi_ids.add(entity)
            continue

    summary["car"] = len(car_ids)
    summary["taxi"] = len(taxi_ids)
    summary["total"] = summary["car"] + summary["taxi"]
    return summary


def compute_stuck_removal_rows(events):
    if events is None or events.empty or "event_type" not in events.columns:
        return []

    ev = events.copy()
    ev["event_type"] = ev["event_type"].astype(str).str.strip().str.upper()
    ev = ev[ev["event_type"] == "ROUTE_STUCK_REMOVAL"]
    if ev.empty:
        return []

    rows = []
    for _, row in ev.iterrows():
        details = parse_details_map(row.get("details", ""))
        agent = canonical_stuck_agent(details.get("agent", row.get("related_id", "")))
        phase = details.get("phase", "")
        t_s = finite_float(row.get("time", 0.0), 0.0)
        stuck_min = finite_float(details.get("stuck_minutes", None), None)
        threshold_min = finite_float(details.get("threshold_minutes", None), None)
        stuck_start_time = finite_float(details.get("stuck_start_time", None), None)
        rows.append(
            {
                "time_s": round(t_s, 2),
                "time_h": round(t_s / 3600.0, 2),
                "vehicle_id": str(row.get("entity_id", "")),
                "agent": agent,
                "phase": str(phase) if str(phase).strip() else "-",
                "stuck_min": round(stuck_min, 2) if stuck_min is not None else None,
                "threshold_min": round(threshold_min, 2) if threshold_min is not None else None,
                "stuck_start_s": round(stuck_start_time, 2) if stuck_start_time is not None else None,
            }
        )

    rows.sort(key=lambda r: finite_float(r.get("time_s", 0.0), 0.0), reverse=True)
    return rows


def compute_route_planning_rows(events):
    base_counts = {
        "person_walking": {
            "first_try_success": 0,
            "recovered_after_retries": 0,
            "started_without_route": 0,
            "failed_after_retries": 0,
            "attempts_sum": 0.0,
            "attempts_n": 0,
        },
        "car": {
            "first_try_success": 0,
            "recovered_after_retries": 0,
            "started_without_route": 0,
            "failed_after_retries": 0,
            "attempts_sum": 0.0,
            "attempts_n": 0,
        },
    }
    if events is None or events.empty or "event_type" not in events.columns:
        return [], {}

    ev_all = events.copy()
    ev_all["event_type"] = ev_all["event_type"].astype(str).str.strip().str.upper()

    # Backward-compatible tag: old runs reported this case in ROUTE_EXEC/LEGACY_FALLBACK only.
    started_without_route_entities = set()
    legacy_exec = ev_all[ev_all["event_type"] == "ROUTE_EXEC"]
    for _, row in legacy_exec.iterrows():
        d = parse_details_map(row.get("details", ""))
        if canonical_route_agent(d.get("agent", "")) != "person_walking":
            continue
        rk = nk(d.get("result", ""))
        if "started_without_helper_path" in rk or "started_without_route" in rk:
            entity = nk(row.get("entity_id", ""))
            if entity:
                started_without_route_entities.add(entity)

    legacy_fallback = ev_all[ev_all["event_type"] == "ROUTE_PLAN_LEGACY_FALLBACK"]
    for _, row in legacy_fallback.iterrows():
        entity = nk(row.get("entity_id", ""))
        if entity:
            started_without_route_entities.add(entity)

    ev = ev_all[ev_all["event_type"] == "ROUTE_PLAN"]
    if ev.empty:
        return [], {}

    seen = set()
    for _, row in ev.iterrows():
        details = parse_details_map(row.get("details", ""))
        agent = canonical_route_agent(details.get("agent", ""))
        result = canonical_route_result(details.get("result", ""))
        if agent is None or result is None:
            continue
        entity = nk(row.get("entity_id", ""))
        if agent == "person_walking" and result == "failed_after_retries" and entity in started_without_route_entities:
            result = "started_without_route"
        attempts = int(finite_float(details.get("attempts", 0.0), 0.0))
        time_bin = round(finite_float(row.get("time", 0.0), 0.0), 2)
        dedup_key = (agent, entity, result, attempts, time_bin)
        if dedup_key in seen:
            continue
        seen.add(dedup_key)
        base_counts[agent][result] += 1
        attempts_f = finite_float(details.get("attempts", None), None)
        if attempts_f is not None:
            base_counts[agent]["attempts_sum"] += attempts_f
            base_counts[agent]["attempts_n"] += 1

    rows = []
    summary = {}
    labels = {"person_walking": "Person (walking)", "car": "Car trips"}
    for agent in ["person_walking", "car"]:
        c = base_counts[agent]
        failed_hard = int(c["failed_after_retries"])
        started_without_route = int(c["started_without_route"])
        failed_total = failed_hard + started_without_route
        total = int(c["first_try_success"] + c["recovered_after_retries"] + failed_total)
        if total <= 0:
            continue
        first_pct = 100.0 * c["first_try_success"] / total
        recovered_pct = 100.0 * c["recovered_after_retries"] / total
        failed_pct = 100.0 * failed_total / total
        avg_attempts = (c["attempts_sum"] / c["attempts_n"]) if c["attempts_n"] > 0 else 0.0
        rows.append(
            {
                "agent": labels.get(agent, agent),
                "samples": total,
                "first_try_count": int(c["first_try_success"]),
                "recovered_count": int(c["recovered_after_retries"]),
                "started_without_route_count": int(started_without_route),
                "failed_no_route_count": int(failed_hard),
                "failed_count": int(failed_total),
                "first_try_pct": round(first_pct, 2),
                "recovered_pct": round(recovered_pct, 2),
                "failed_pct": round(failed_pct, 2),
                "avg_attempts": round(avg_attempts, 2),
            }
        )
        summary[agent] = {
            "samples": total,
            "first_try_count": int(c["first_try_success"]),
            "recovered_count": int(c["recovered_after_retries"]),
            "started_without_route_count": int(started_without_route),
            "failed_no_route_count": int(failed_hard),
            "failed_count": int(failed_total),
            "first_try_pct": first_pct,
            "recovered_pct": recovered_pct,
            "failed_pct": failed_pct,
            "avg_attempts": avg_attempts,
        }
    return rows, summary


def route_planning_figure(route_plan_rows):
    if not route_plan_rows:
        fig = go.Figure()
        fig.add_annotation(text="No ROUTE_PLAN data", showarrow=False, font={"size": 16})
        fig.update_layout(template="plotly_white", margin={"l": 20, "r": 20, "t": 40, "b": 20})
        return fig

    agents = [str(r.get("agent", "")) for r in route_plan_rows]
    first = [finite_float(r.get("first_try_pct", 0.0), 0.0) for r in route_plan_rows]
    recovered = [finite_float(r.get("recovered_pct", 0.0), 0.0) for r in route_plan_rows]
    failed = [finite_float(r.get("failed_pct", 0.0), 0.0) for r in route_plan_rows]
    samples = [int(finite_float(r.get("samples", 0), 0.0)) for r in route_plan_rows]

    fig = go.Figure()
    fig.add_trace(go.Bar(name="First try", x=agents, y=first, marker_color="#2ca02c"))
    fig.add_trace(go.Bar(name="Recovered", x=agents, y=recovered, marker_color="#ffbf00"))
    fig.add_trace(go.Bar(name="Failed", x=agents, y=failed, marker_color="#d62728"))
    fig.update_layout(
        title="Route Planning Outcomes by Agent",
        template="plotly_white",
        barmode="stack",
        yaxis_title="Share (%)",
        xaxis_title="Agent",
        margin={"l": 40, "r": 20, "t": 50, "b": 40},
        legend={"orientation": "h", "yanchor": "bottom", "y": 1.02, "xanchor": "left", "x": 0.0},
        hoverlabel={"font": {"size": 14}},
    )
    fig.update_traces(
        customdata=[[s] for s in samples],
        hovertemplate="%{x}<br>%{fullData.name}: %{y:.2f}%<br>Samples: %{customdata[0]}<extra></extra>",
    )
    return fig


def build_route_cancel_rows(trips, route_plan_summary, events, stuck_summary=None, vehicle_pool=None, stuck_rows=None):
    rows = []
    total_trips = int(len(trips)) if trips is not None and not trips.empty else 0

    aborted = 0
    aborted_no_route = 0
    car_trips = 0
    taxi_trips = 0
    if total_trips > 0 and "status" in trips.columns:
        st = trips["status"].astype(str).str.strip().str.upper()
        aborted = int(st.str.startswith("ABORTED").sum())
        aborted_no_route = int(st.str.contains("NO_ROUTE", regex=False).sum())
    if total_trips > 0 and "mode" in trips.columns:
        md = trips["mode"].astype(str).str.strip().str.lower()
        car_trips = int((md == "car").sum())
        taxi_trips = int((md == "taxi").sum())

    rows.append(
        {
            "scope": "Trips (executed)",
            "metric": "Cancelled (ABORTED_*)",
            "count": aborted,
            "pct": round((100.0 * aborted / total_trips), 2) if total_trips > 0 else 0.0,
            "denominator": total_trips,
        }
    )
    rows.append(
        {
            "scope": "Trips (executed)",
            "metric": "Cancelled: no route",
            "count": aborted_no_route,
            "pct": round((100.0 * aborted_no_route / total_trips), 2) if total_trips > 0 else 0.0,
            "denominator": total_trips,
        }
    )

    if stuck_summary is None:
        stuck_summary = compute_stuck_removal_summary(events)
    if vehicle_pool is None:
        vehicle_pool = compute_runtime_vehicle_pool(events)
    vehicle_den = int(vehicle_pool.get("total", 0))
    car_vehicle_den = int(vehicle_pool.get("car", 0))
    taxi_vehicle_den = int(vehicle_pool.get("taxi", 0))

    # Fallback for old logs with weak vehicle-id coverage
    if vehicle_den <= 0:
        vehicle_den = car_trips + taxi_trips
    if car_vehicle_den <= 0:
        car_vehicle_den = car_trips
    if taxi_vehicle_den <= 0:
        taxi_vehicle_den = taxi_trips

    rows.append(
        {
            "scope": "Vehicles (runtime unique IDs)",
            "metric": "Removed after stuck > 5 min",
            "count": int(stuck_summary.get("total", 0)),
            "pct": round((100.0 * int(stuck_summary.get("total", 0)) / vehicle_den), 2) if vehicle_den > 0 else 0.0,
            "denominator": vehicle_den,
        }
    )
    rows.append(
        {
            "scope": "Car vehicles (runtime unique IDs)",
            "metric": "Removed after stuck > 5 min",
            "count": int(stuck_summary.get("car", 0)),
            "pct": round((100.0 * int(stuck_summary.get("car", 0)) / car_vehicle_den), 2) if car_vehicle_den > 0 else 0.0,
            "denominator": car_vehicle_den,
        }
    )
    rows.append(
        {
            "scope": "Taxi vehicles (runtime unique IDs)",
            "metric": "Removed after stuck > 5 min",
            "count": int(stuck_summary.get("taxi", 0)),
            "pct": round((100.0 * int(stuck_summary.get("taxi", 0)) / taxi_vehicle_den), 2) if taxi_vehicle_den > 0 else 0.0,
            "denominator": taxi_vehicle_den,
        }
    )

    if stuck_rows is None:
        stuck_rows = compute_stuck_removal_rows(events)
    valid_stuck_rows = [r for r in stuck_rows if r.get("stuck_min") is not None and r.get("threshold_min") is not None]
    below_threshold = int(sum(1 for r in valid_stuck_rows if float(r["stuck_min"]) + 1e-9 < float(r["threshold_min"])))
    rows.append(
        {
            "scope": "Stuck removal data quality",
            "metric": "Removed below threshold (should be 0)",
            "count": below_threshold,
            "pct": round((100.0 * below_threshold / len(valid_stuck_rows)), 2) if len(valid_stuck_rows) > 0 else 0.0,
            "denominator": len(valid_stuck_rows),
        }
    )

    for agent_key, label in [("person_walking", "Walking route planning"), ("car", "Car route planning")]:
        s = (route_plan_summary or {}).get(agent_key, {}) or {}
        samples = int(s.get("samples", 0))
        rec_count = int(s.get("recovered_count", 0))
        fail_count = int(s.get("failed_count", 0))
        started_without_route = int(s.get("started_without_route_count", 0))
        hard_fail_count = max(0, int(s.get("failed_no_route_count", fail_count - started_without_route)))
        rec_pct = round((100.0 * rec_count / samples), 2) if samples > 0 else 0.0
        fail_pct = round((100.0 * fail_count / samples), 2) if samples > 0 else 0.0
        rows.append(
            {
                "scope": label,
                "metric": "Recomputed after retries",
                "count": rec_count,
                "pct": rec_pct,
                "denominator": samples,
            }
        )
        if agent_key == "person_walking":
            rows.append(
                {
                    "scope": label,
                    "metric": "Started without route (red)",
                    "count": started_without_route,
                    "pct": round((100.0 * started_without_route / samples), 2) if samples > 0 else 0.0,
                    "denominator": samples,
                }
            )
            rows.append(
                {
                    "scope": label,
                    "metric": "Hard fail after retries",
                    "count": hard_fail_count,
                    "pct": round((100.0 * hard_fail_count / samples), 2) if samples > 0 else 0.0,
                    "denominator": samples,
                }
            )
        rows.append(
            {
                "scope": label,
                "metric": "Red (no valid route to destination)",
                "count": fail_count,
                "pct": fail_pct,
                "denominator": samples,
            }
        )
    return rows


def normdist(values):
    clean = {}
    for k, v in (values or {}).items():
        fv = finite_float(v, None)
        if fv is None or fv <= 0.0:
            continue
        clean[nk(k)] = fv
    total = float(sum(clean.values()))
    if total <= 0.0:
        return {}
    return {k: v / total for k, v in clean.items()}


def extract_mode_choice_events(events):
    if events is None or events.empty or "event_type" not in events.columns:
        return pd.DataFrame(columns=["distance_class", "mode"])
    base = events.copy()
    base["event_type"] = base["event_type"].astype(str).str.strip().str.upper()
    base = base[base["event_type"] == "MODE_CHOICE"]
    if base.empty:
        return pd.DataFrame(columns=["distance_class", "mode"])

    rows = []
    for _, row in base.iterrows():
        d = parse_details_map(row.get("details", ""))
        klass = nk(d.get("distance_class", ""))
        mode = nk(d.get("chosen", ""))
        if klass not in {"short", "long"} or mode == "":
            continue
        rows.append({"distance_class": klass, "mode": mode})
    return pd.DataFrame(rows, columns=["distance_class", "mode"])


def load_transport_targets_from_db(municipality_code=TRANSPORT_TARGET_MUNICIPALITY_CODE):
    out = {"short": {}, "long": {}}
    if not DB_PATH.exists():
        return out
    code = str(municipality_code or "").strip().split()[0]

    try:
        conn = sqlite3.connect(DB_PATH)
        rows = conn.execute(
            """
            SELECT distance_class, transport_mode, target_share
            FROM transport_mode_targets
            WHERE municipality_code = ?
            """,
            (code,),
        ).fetchall()
        if not rows:
            rows = conn.execute(
                """
                SELECT distance_class, transport_mode, target_share
                FROM transport_mode_targets
                WHERE municipality_code = ''
                """,
            ).fetchall()
        conn.close()
    except sqlite3.Error:
        return out

    for distance_class, mode, share in rows:
        klass = nk(distance_class)
        m = nk(mode)
        if klass in {"short", "long"} and m:
            out.setdefault(klass, {})
            out[klass][m] = finite_float(share, 0.0)
    out["short"] = normdist(out.get("short", {}))
    out["long"] = normdist(out.get("long", {}))
    return out


def compute_observed_mode_shares(trips, mode_choices, distance_filter="all"):
    df = mode_choices if mode_choices is not None else pd.DataFrame()
    if distance_filter in {"short", "long"} and not df.empty:
        cut = df[df["distance_class"] == distance_filter]
        if not cut.empty:
            return {k: float(v) for k, v in cut["mode"].value_counts(normalize=True).to_dict().items()}
    if distance_filter == "all" and not df.empty:
        return {k: float(v) for k, v in df["mode"].value_counts(normalize=True).to_dict().items()}
    if distance_filter == "all" and trips is not None and not trips.empty and "mode" in trips.columns:
        return {nk(k): float(v) for k, v in trips["mode"].value_counts(normalize=True).to_dict().items()}
    return {}


def build_mode_expectation(mode_shares, mode_choices, transport_targets, distance_filter="all", fallback_long_share=None):
    short_target = transport_targets.get("short", {}) or {}
    long_target = transport_targets.get("long", {}) or {}

    class_counts = {"short": 0, "long": 0}
    if mode_choices is not None and not mode_choices.empty:
        class_counts = {
            "short": int((mode_choices["distance_class"] == "short").sum()),
            "long": int((mode_choices["distance_class"] == "long").sum()),
        }
    samples = int(class_counts["short"] + class_counts["long"])

    if distance_filter == "short":
        long_share = 0.0
    elif distance_filter == "long":
        long_share = 1.0
    else:
        if samples > 0:
            long_share = float(class_counts["long"] / samples)
        elif fallback_long_share is not None:
            long_share = finite_float(fallback_long_share, 0.5)
        else:
            long_share = 0.5

    all_modes = sorted(set(TRANSPORT_MODE_ORDER) | set(mode_shares.keys()) | set(short_target.keys()) | set(long_target.keys()))
    per_mode = {}
    mixed_target = {}
    for mode in all_modes:
        exp_short = finite_float(short_target.get(nk(mode), 0.0), 0.0)
        exp_long = finite_float(long_target.get(nk(mode), 0.0), 0.0)
        if distance_filter == "short":
            exp_mix = exp_short
        elif distance_filter == "long":
            exp_mix = exp_long
        else:
            exp_mix = (1.0 - long_share) * exp_short + long_share * exp_long
        obs = finite_float(mode_shares.get(mode, 0.0), 0.0)
        delta = obs - exp_mix
        mixed_target[mode] = exp_mix
        per_mode[mode] = {
            "observed_share": obs,
            "expected_short_share": exp_short,
            "expected_long_share": exp_long,
            "expected_mixed_share": exp_mix,
            "delta_vs_mixed": delta,
        }

    return {
        "samples": samples,
        "class_counts": class_counts,
        "observed_long_share": long_share,
        "distance_filter": distance_filter,
        "targets": {
            "short": short_target,
            "long": long_target,
            "mixed_by_observed_class_share": mixed_target,
        },
        "per_mode": per_mode,
    }


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
    targets = (mode_expectation or {}).get("targets", {})
    short_targets = targets.get("short", {}) if isinstance(targets, dict) else {}
    long_targets = targets.get("long", {}) if isinstance(targets, dict) else {}
    long_share = finite_float((mode_expectation or {}).get("observed_long_share"), 0.5)
    has_expected = bool(per_mode or short_targets or long_targets)
    custom = []
    hover_text = []
    for mode in labels:
        row = per_mode.get(mode, {})
        target_short = finite_float(short_targets.get(nk(mode), 0.0), 0.0)
        target_long = finite_float(long_targets.get(nk(mode), 0.0), 0.0)
        exp_short = finite_float(row.get("expected_short_share"), target_short)
        exp_long = finite_float(row.get("expected_long_share"), target_long)
        default_mix = (1.0 - long_share) * exp_short + long_share * exp_long
        exp_mix = finite_float(row.get("expected_mixed_share"), default_mix)
        obs_share = finite_float(mode_shares.get(mode, 0.0), 0.0)
        delta_mix = finite_float(row.get("delta_vs_mixed"), obs_share - exp_mix)
        custom.append(
            [
                exp_mix * 100.0,
                exp_short * 100.0,
                exp_long * 100.0,
                delta_mix * 100.0,
            ]
        )
        observed = finite_float(mode_shares.get(mode, 0.0), 0.0) * 100.0
        hover_text.append(
            f"{mode}"
            f"<br>Observed: {observed:.2f}%"
            f"<br>Expected mixed: {exp_mix*100.0:.2f}%"
            f"<br>Expected short: {exp_short*100.0:.2f}%"
            f"<br>Expected long: {exp_long*100.0:.2f}%"
            f"<br>Delta vs mixed: {delta_mix*100.0:.2f} pp"
        )

    fig = go.Figure(
        data=[
            go.Pie(
                labels=labels,
                values=values,
                hole=0.35,
                textinfo="label+percent",
                customdata=custom,
                hovertext=hover_text,
                hovertemplate=("%{hovertext}<extra></extra>" if has_expected else "%{label}: %{value:.2f}%<extra></extra>"),
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


def build_mode_expectation_rows(mode_shares, mode_expectation):
    per_mode = (mode_expectation or {}).get("per_mode", {}) or {}
    targets = (mode_expectation or {}).get("targets", {}) or {}
    short_targets = (targets.get("short", {}) if isinstance(targets, dict) else {}) or {}
    long_targets = (targets.get("long", {}) if isinstance(targets, dict) else {}) or {}
    long_share = finite_float((mode_expectation or {}).get("observed_long_share"), 0.5)

    modes = set(TRANSPORT_MODE_ORDER) | set(mode_shares.keys()) | set(per_mode.keys()) | set(short_targets.keys()) | set(long_targets.keys())
    ordered_modes = sorted(
        modes,
        key=lambda m: ((TRANSPORT_MODE_ORDER.index(m) if m in TRANSPORT_MODE_ORDER else 999), str(m)),
    )

    rows = []
    for mode in ordered_modes:
        row = per_mode.get(mode, {}) if isinstance(per_mode, dict) else {}
        obs = finite_float(mode_shares.get(mode, row.get("observed_share", 0.0)), 0.0)
        target_short = finite_float(short_targets.get(nk(mode), 0.0), 0.0)
        target_long = finite_float(long_targets.get(nk(mode), 0.0), 0.0)
        exp_short = finite_float(row.get("expected_short_share"), target_short)
        exp_long = finite_float(row.get("expected_long_share"), target_long)
        exp_total_default = (1.0 - long_share) * exp_short + long_share * exp_long
        exp_total = finite_float(row.get("expected_mixed_share"), exp_total_default)
        delta = finite_float(row.get("delta_vs_mixed"), obs - exp_total)

        rows.append(
            {
                "mode": str(mode),
                "observed_pct": round(obs * 100.0, 2),
                "expected_total_pct": round(exp_total * 100.0, 2),
                "expected_short_pct": round(exp_short * 100.0, 2),
                "expected_long_pct": round(exp_long * 100.0, 2),
                "delta_pp": round(delta * 100.0, 2),
            }
        )
    return rows


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
        dim = str(d.get("dimension", ""))
        raw_category = str(d.get("category", ""))
        display_category = household_category_display_label(raw_category) if dim.startswith("household") else raw_category
        rows.append(
            {
                "rank": idx,
                "dimension": dim,
                "category": display_category,
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
        "orientation": "orientation",
        "couple_age_gap": "couple_age_gap",
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
            raw_category = str(x.get("category", ""))
            display_category = household_category_display_label(raw_category) if dim.startswith("household") else raw_category
            rows.append(
                {
                    "dimension": dim,
                    "category": display_category,
                    "count": int(counts.get(raw_category, 0)),
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


def compute_kpis(report, trips, events, profile, stuck_summary=None, vehicle_pool=None):
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
    if stuck_summary is None:
        stuck_summary = compute_stuck_removal_summary(events)
    if vehicle_pool is None:
        vehicle_pool = compute_runtime_vehicle_pool(events)
    vehicle_den = int(vehicle_pool.get("total", 0))
    if vehicle_den <= 0 and not trips.empty and "mode" in trips.columns:
        md = trips["mode"].astype(str).str.strip().str.lower()
        vehicle_den = int((md == "car").sum() + (md == "taxi").sum())
    stuck_total = int(stuck_summary.get("total", 0))
    stuck_pct = (100.0 * stuck_total / vehicle_den) if vehicle_den > 0 else 0.0
    kpis["stuck_vehicle_removals"] = stuck_total
    kpis["stuck_vehicle_removals_pct"] = fmt_num(stuck_pct, digits=2)
    kpis["runtime_vehicle_pool"] = vehicle_den
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
    route_plan_rows,
    route_cancel_rows,
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
            fv = finite_float(v, None)
            if fv is not None:
                rows.append(
                    {
                        "export_time": export_time,
                        "section": "mode_share",
                        "item": col,
                        "category": str(mode),
                        "value": round(fv * 100.0, 4),
                        "value_text": "",
                        "unit": "pct",
                        "notes": "",
                    }
                )

    for r in route_plan_rows:
        agent = str(r.get("agent", ""))
        samples = int(r.get("samples", 0))
        rows.append(
            {
                "export_time": export_time,
                "section": "route_planning",
                "item": "samples",
                "category": agent,
                "value": samples,
                "value_text": "",
                "unit": "count",
                "notes": "",
            }
        )
        for key in [
            "first_try_count",
            "recovered_count",
            "started_without_route_count",
            "failed_no_route_count",
            "failed_count",
            "first_try_pct",
            "recovered_pct",
            "failed_pct",
            "avg_attempts",
        ]:
            rows.append(
                {
                    "export_time": export_time,
                    "section": "route_planning",
                    "item": key,
                    "category": agent,
                    "value": finite_float(r.get(key, 0.0), 0.0),
                    "value_text": "",
                    "unit": "pct" if key.endswith("_pct") else "count",
                    "notes": "",
                }
            )

    for r in route_cancel_rows:
        rows.append(
            {
                "export_time": export_time,
                "section": "route_cancel_impact",
                "item": str(r.get("metric", "")),
                "category": str(r.get("scope", "")),
                "value": finite_float(r.get("count", 0.0), 0.0),
                "value_text": "",
                "unit": "count",
                "notes": f'pct={finite_float(r.get("pct", 0.0), 0.0)};denominator={int(finite_float(r.get("denominator", 0.0), 0.0))}',
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
    route_plan_rows,
    route_cancel_rows,
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
        route_plan_rows=route_plan_rows,
        route_cancel_rows=route_cancel_rows,
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
            style={"display": "flex", "gap": "10px", "alignItems": "center", "marginBottom": "12px"},
            children=[
                html.Div("Trip class for transport stats:", style={"color": "#d6dfed", "fontSize": "13px"}),
                dcc.Dropdown(
                    id="trip-class-filter",
                    options=TRIP_CLASS_FILTER_OPTIONS,
                    value="all",
                    clearable=False,
                    style={"minWidth": "260px", "maxWidth": "320px", "fontSize": "13px"},
                ),
            ],
        ),
        html.Div(
            style={"display": "grid", "gridTemplateColumns": "1fr 1fr", "gap": "12px", "marginBottom": "12px"},
            children=[
                dcc.Graph(id="mode-pie", config={"displaylogo": False}),
                dcc.Graph(id="active-timeline", config={"displaylogo": False}),
            ],
        ),
        html.Div(
            style={"marginTop": "4px", "background": "#16202f", "border": "1px solid #223147", "borderRadius": "10px", "padding": "8px"},
            children=[
                html.H4("Transport Mode: Observed vs Expected (Total / Short / Long)", style={"margin": "8px 10px", "color": "#f3f6fb"}),
                dash_table.DataTable(
                    id="mode-expected-table",
                    columns=[
                        {"name": "Mode", "id": "mode"},
                        {"name": "Observed (%)", "id": "observed_pct"},
                        {"name": "Expected Total (%)", "id": "expected_total_pct"},
                        {"name": "Expected Short (%)", "id": "expected_short_pct"},
                        {"name": "Expected Long (%)", "id": "expected_long_pct"},
                        {"name": "Delta (pp)", "id": "delta_pp"},
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
                html.H4("Route Planning Diagnostics (Differentiated Section)", style={"margin": "8px 10px", "color": "#f3f6fb"}),
                html.Div(
                    style={"display": "grid", "gridTemplateColumns": "1fr", "gap": "10px"},
                    children=[
                        dcc.Graph(id="route-plan-chart", config={"displaylogo": False}, style={"height": "380px"}),
                        dash_table.DataTable(
                            id="route-plan-table",
                            columns=[
                                {"name": "Agent", "id": "agent"},
                                {"name": "Samples", "id": "samples"},
                                {"name": "First Count", "id": "first_try_count"},
                                {"name": "Recovered Count", "id": "recovered_count"},
                                {"name": "Started w/o Route", "id": "started_without_route_count"},
                                {"name": "Failed Count", "id": "failed_count"},
                                {"name": "First Try (%)", "id": "first_try_pct"},
                                {"name": "Recovered (%)", "id": "recovered_pct"},
                                {"name": "Failed (%)", "id": "failed_pct"},
                                {"name": "Avg Attempts", "id": "avg_attempts"},
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
            ],
        ),
        html.Div(
            style={"marginTop": "12px", "background": "#16202f", "border": "1px solid #223147", "borderRadius": "10px", "padding": "8px"},
            children=[
                html.H4("Cancelled / Recomputed Trips (Impact)", style={"margin": "8px 10px", "color": "#f3f6fb"}),
                dash_table.DataTable(
                    id="route-cancel-table",
                    columns=[
                        {"name": "Scope", "id": "scope"},
                        {"name": "Metric", "id": "metric"},
                        {"name": "Count", "id": "count"},
                        {"name": "%", "id": "pct"},
                        {"name": "Denominator", "id": "denominator"},
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
                html.H4("Stuck Vehicle Removals (Event Log)", style={"margin": "8px 10px", "color": "#f3f6fb"}),
                dash_table.DataTable(
                    id="stuck-removal-table",
                    columns=[
                        {"name": "Time (s)", "id": "time_s"},
                        {"name": "Time (h)", "id": "time_h"},
                        {"name": "Vehicle", "id": "vehicle_id"},
                        {"name": "Agent", "id": "agent"},
                        {"name": "Phase", "id": "phase"},
                        {"name": "Stuck (min)", "id": "stuck_min"},
                        {"name": "Threshold (min)", "id": "threshold_min"},
                        {"name": "Stuck Start (s)", "id": "stuck_start_s"},
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
    Output("mode-expected-table", "data"),
    Output("route-plan-chart", "figure"),
    Output("route-plan-table", "data"),
    Output("route-cancel-table", "data"),
    Output("stuck-removal-table", "data"),
    Output("active-timeline", "figure"),
    Output("starts-per-hour", "figure"),
    Output("work-schedule-hist", "figure"),
    Output("peaks-table", "data"),
    Output("discrepancies-table", "data"),
    Output("population-monitor-table", "data"),
    Output("household-size-breakdown-table", "data"),
    Output("household-structure-focus-table", "data"),
    Input("refresh", "n_intervals"),
    Input("trip-class-filter", "value"),
)
def refresh_dashboard(_, trip_class_filter):
    report = load_report()
    trips = load_trips()
    events = load_events()
    households = load_households_registry()

    trip_class_filter = nk(trip_class_filter) if trip_class_filter is not None else "all"
    if trip_class_filter not in {"all", "short", "long"}:
        trip_class_filter = "all"
    mode_choices = extract_mode_choice_events(events)
    transport_targets = load_transport_targets_from_db(TRANSPORT_TARGET_MUNICIPALITY_CODE)
    if not transport_targets.get("short") and not transport_targets.get("long"):
        fallback_targets = (report.get("mode_expectation", {}) or {}).get("targets", {})
        transport_targets = {
            "short": (fallback_targets.get("short", {}) if isinstance(fallback_targets, dict) else {}) or {},
            "long": (fallback_targets.get("long", {}) if isinstance(fallback_targets, dict) else {}) or {},
        }
    fallback_long_share = (report.get("mode_expectation", {}) or {}).get("observed_long_share")
    mode_shares = compute_observed_mode_shares(trips, mode_choices, trip_class_filter)
    mode_exp = build_mode_expectation(
        mode_shares=mode_shares,
        mode_choices=mode_choices,
        transport_targets=transport_targets,
        distance_filter=trip_class_filter,
        fallback_long_share=fallback_long_share,
    )
    route_plan_rows, route_plan_summary = compute_route_planning_rows(events)
    stuck_summary = compute_stuck_removal_summary(events)
    vehicle_pool = compute_runtime_vehicle_pool(events)
    stuck_removal_rows = compute_stuck_removal_rows(events)
    route_cancel_rows = build_route_cancel_rows(
        trips,
        route_plan_summary,
        events,
        stuck_summary=stuck_summary,
        vehicle_pool=vehicle_pool,
        stuck_rows=stuck_removal_rows,
    )
    profile = compute_active_travelers_profile(trips) if not trips.empty else {}
    summary = profile.get("summary", {})
    kpis = compute_kpis(
        report,
        trips,
        events,
        profile,
        stuck_summary=stuck_summary,
        vehicle_pool=vehicle_pool,
    )
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
        route_plan_rows,
        route_cancel_rows,
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
        card(
            "Stuck Removals",
            kpis["stuck_vehicle_removals"],
            f'{kpis["stuck_vehicle_removals_pct"]}% of runtime vehicles',
        ),
        card(
            "Route Fail (After Retries)",
            "walk " + fmt_num(route_plan_summary.get("person_walking", {}).get("failed_pct", 0.0), digits=1)
            + "% | car " + fmt_num(route_plan_summary.get("car", {}).get("failed_pct", 0.0), digits=1) + "%",
            "from ROUTE_PLAN events",
        ),
        card(
            "Mode Samples",
            mode_exp.get("samples", 0),
            f'short={mode_exp.get("class_counts", {}).get("short", 0)}, long={mode_exp.get("class_counts", {}).get("long", 0)}',
        ),
    ]

    refreshed_at = f"Last refresh: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}"
    refreshed_at += f" | trip_class={trip_class_filter}"
    if export_latest is not None:
        refreshed_at += f" | CSV: {export_latest.name} ({export_rows} rows)"
    if export_snapshot is not None:
        refreshed_at += f" | Snapshot: {export_snapshot.name}"

    return (
        refreshed_at,
        kpi_cards,
        mode_share_figure(mode_shares, mode_exp),
        build_mode_expectation_rows(mode_shares, mode_exp),
        route_planning_figure(route_plan_rows),
        route_plan_rows,
        route_cancel_rows,
        stuck_removal_rows,
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
