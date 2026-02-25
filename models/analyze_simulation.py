import json, math, os, unicodedata
import numpy as np
import pandas as pd

BASE = os.path.dirname(os.path.abspath(__file__))
TRIPS = os.path.join(BASE, "trips.csv")
EVENTS = os.path.join(BASE, "events.csv")
POP = os.path.join(BASE, "population_stats.csv")
REF = os.path.join(BASE, "reference_stats.csv")
REPORT_JSON = os.path.join(BASE, "report.json")
REPORT_MD = os.path.join(BASE, "report.md")
MODE_PIE_SVG = os.path.join(BASE, "mode_share_pie.svg")
ACTIVE_SVG = os.path.join(BASE, "active_travelers_timeline.svg")
CROSSWALK_THRESHOLD_S = 60.0
COMPANION_DIST_THRESHOLD_M = 5.0


def nk(v):
    if v is None:
        return ""
    t = str(v).strip().lower()
    t = unicodedata.normalize("NFKD", t).encode("ascii", "ignore").decode("ascii")
    return " ".join(t.replace(",", " ").split())


def sf(v, d=0.0):
    try:
        return float(v)
    except (TypeError, ValueError):
        return d


def canon_category(group, name):
    g = nk(group)
    c = nk(name)
    if "gender" in g:
        if ("muj" in c) or ("fem" in c):
            return "female"
        if ("hom" in c) or ("male" in c) or ("varon" in c):
            return "male"
        return c
    if "household_size" in g:
        if "total" in c:
            return ""
        if "1" in c:
            return "1 persona"
        if "2" in c:
            return "2 personas"
        if "3" in c:
            return "3 personas"
        if "4" in c:
            return "4 personas"
        if "5" in c:
            return "5 o mas personas"
        return c
    return c


def load():
    if not (os.path.exists(TRIPS) and os.path.exists(EVENTS)):
        return None, None, pd.DataFrame(), pd.DataFrame()
    t = pd.read_csv(TRIPS, skipinitialspace=True)
    try:
        e = pd.read_csv(EVENTS, skipinitialspace=True)
    except pd.errors.ParserError:
        # Some event details may contain unquoted commas; rebuild rows with fixed schema.
        rows = []
        with open(EVENTS, "r", encoding="utf-8", errors="replace") as fh:
            lines = fh.read().splitlines()
        for line in lines[1:]:
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
        e = pd.DataFrame(
            rows,
            columns=["event_type", "time", "entity_id", "related_id", "details", "extra_1", "extra_2"],
        )
    p = pd.read_csv(POP, skipinitialspace=True) if os.path.exists(POP) else pd.DataFrame()
    r = pd.read_csv(REF, skipinitialspace=True) if os.path.exists(REF) else pd.DataFrame()
    for c in ["start_time", "end_time", "duration", "wait_time"]:
        if c in t.columns:
            t[c] = pd.to_numeric(t[c], errors="coerce")
    for c in ["mode", "purpose", "status", "person_id"]:
        if c in t.columns:
            t[c] = t[c].astype(str).str.strip()
    if "mode" in t.columns:
        t["mode"] = t["mode"].str.lower()
    if "purpose" in t.columns:
        t["purpose"] = t["purpose"].str.lower()
    if "status" in t.columns:
        t["status"] = t["status"].str.upper()
    if "time" in e.columns:
        e["time"] = pd.to_numeric(e["time"], errors="coerce")
    for c in ["event_type", "details", "entity_id", "related_id"]:
        if c in e.columns:
            e[c] = e[c].astype(str).str.strip()
    if "event_type" in e.columns:
        e["event_type"] = e["event_type"].str.upper()
    for x in [p, r]:
        if not x.empty and "metric_value" in x.columns:
            x["metric_value"] = pd.to_numeric(x["metric_value"], errors="coerce")
        for c in ["metric_group", "metric_name"]:
            if not x.empty and c in x.columns:
                x[c] = x[c].astype(str).str.strip()
    return t, e, p, r


def mode_shares(t):
    return {} if t.empty or "mode" not in t.columns else {k: float(v) for k, v in t["mode"].value_counts(normalize=True).to_dict().items()}


def compute_purpose_mode_matrix(t):
    if t.empty or not {"purpose", "mode"}.issubset(t.columns):
        return {"counts": {}, "shares_by_purpose": {}}
    base = t.dropna(subset=["purpose", "mode"]).copy()
    if base.empty:
        return {"counts": {}, "shares_by_purpose": {}}
    counts = base.groupby(["purpose", "mode"]).size().unstack(fill_value=0)
    shares = counts.div(counts.sum(axis=1).replace(0, np.nan), axis=0).fillna(0.0)
    return {
        "counts": {str(p): {str(m): int(v) for m, v in row.items()} for p, row in counts.to_dict(orient="index").items()},
        "shares_by_purpose": {str(p): {str(m): float(v) for m, v in row.items()} for p, row in shares.to_dict(orient="index").items()},
    }


def trip_consistency(t):
    if t.empty:
        return {}
    out = {"total_trips": int(len(t))}
    out["status_counts"] = {k: int(v) for k, v in t["status"].value_counts(dropna=False).to_dict().items()} if "status" in t.columns else {}
    out["missing_start"] = int(t["start_time"].isna().sum()) if "start_time" in t.columns else 0
    out["missing_end"] = int(t["end_time"].isna().sum()) if "end_time" in t.columns else 0
    out["non_positive_duration"] = int((t["duration"] <= 0).sum()) if "duration" in t.columns else 0
    out["closure_rate"] = float((t["start_time"].notna() & t["end_time"].notna() & (t["duration"] >= 0)).mean()) if {"start_time", "end_time", "duration"}.issubset(t.columns) else 0.0
    if {"mode", "duration"}.issubset(t.columns):
        out["duration_by_mode"] = {m: {"count": int(len(g)), "p50": float(g["duration"].quantile(0.5)), "p95": float(g["duration"].quantile(0.95)), "non_positive": int((g["duration"] <= 0).sum())} for m, g in t.groupby("mode")}
    return out


def check_taxi_kpis(t):
    if t.empty or "mode" not in t.columns:
        return {"count": 0}
    tx = t[t["mode"] == "taxi"].copy()
    if tx.empty:
        return {"count": 0}
    out = {
        "count": int(len(tx)),
        "avg_duration": float(pd.to_numeric(tx["duration"], errors="coerce").mean()) if "duration" in tx.columns else 0.0,
        "min_duration": float(pd.to_numeric(tx["duration"], errors="coerce").min()) if "duration" in tx.columns else 0.0,
        "max_duration": float(pd.to_numeric(tx["duration"], errors="coerce").max()) if "duration" in tx.columns else 0.0,
    }
    if "wait_time" in tx.columns:
        w = pd.to_numeric(tx["wait_time"], errors="coerce").dropna()
        out["avg_wait"] = float(w.mean()) if not w.empty else 0.0
        out["p95_wait"] = float(w.quantile(0.95)) if not w.empty else 0.0
    return out


def worker_return(t):
    if t.empty or not {"purpose", "person_id"}.issubset(t.columns):
        return {}
    w = set(t.loc[t["purpose"] == "working", "person_id"])
    if not w:
        return {}
    r = set(t.loc[t["purpose"] == "resting", "person_id"])
    nw = set(t.loc[t["purpose"] != "working", "person_id"])
    out = {"workers_total": len(w), "workers_with_return_resting": len(w & r), "return_rate_resting": len(w & r) / len(w), "workers_only_working": len(w - nw)}
    if {"mode", "start_time"}.issubset(t.columns):
        first = t[t["purpose"] == "working"].sort_values("start_time").drop_duplicates("person_id")[["person_id", "mode"]]
        out["return_by_work_mode"] = {m: {"workers": len(set(g["person_id"])), "with_return_resting": len(set(g["person_id"]) & r)} for m, g in first.groupby("mode")}
    return out


def train_consistency(t):
    if t.empty or "mode" not in t.columns:
        return {}
    tr = t[t["mode"] == "train"].copy()
    if tr.empty:
        return {"train_trips": 0}
    out = {"train_trips": len(tr), "zero_duration_count": int((tr["duration"] == 0).sum()) if "duration" in tr.columns else 0}
    out["aborted_count"] = int(tr["status"].fillna("").str.contains("ABORTED").sum()) if "status" in tr.columns else 0
    out["persons_with_train_and_walking_modes"] = int(sum(1 for s in t.groupby("person_id")["mode"].apply(set) if {"train", "walking"}.issubset(s))) if {"person_id", "mode"}.issubset(t.columns) else 0
    return out


def taxi_sla(t, e):
    out = {"taxi_trips": 0, "wait_time_stats": {}, "queue_snapshot_stats": {}}
    if not t.empty and "mode" in t.columns:
        tx = t[t["mode"] == "taxi"].copy()
        out["taxi_trips"] = int(len(tx))
        if not tx.empty and "wait_time" in tx.columns:
            w = pd.to_numeric(tx["wait_time"], errors="coerce").dropna()
            if not w.empty:
                out["wait_time_stats"] = {"mean": float(w.mean()), "p50": float(w.quantile(0.50)), "p95": float(w.quantile(0.95)), "p99": float(w.quantile(0.99)), "non_zero_rate": float((w > 0).mean())}
    if not e.empty and {"event_type", "details", "extra_1", "extra_2"}.issubset(e.columns):
        q = e[e["event_type"] == "TAXI_QUEUE_SNAPSHOT"].copy()
        if not q.empty:
            q["pending"] = pd.to_numeric(q["details"], errors="coerce")
            out["queue_snapshot_stats"] = {"samples": int(len(q)), "pending_mean": float(q["pending"].mean()), "pending_p95": float(q["pending"].quantile(0.95)), "pending_max": float(q["pending"].max())}
    return out


def crosswalk_blocking(e):
    if e.empty or not {"event_type", "entity_id", "related_id", "time"}.issubset(e.columns):
        return []
    x = e[e["event_type"].isin(["CROSSWALK_ENTER", "CROSSWALK_EXIT", "CROSSWALK_BLOCK_FORCE_RELEASE"])].sort_values(["entity_id", "time"])
    out = []
    for pid, g in x.groupby("entity_id"):
        q = []
        for _, r in g.iterrows():
            if r["event_type"] == "CROSSWALK_ENTER":
                q.append((str(r["related_id"]), float(r["time"])))
                continue
            if not q:
                continue
            cw, st = q.pop(0)
            dur = float(r["time"]) - st
            if dur > CROSSWALK_THRESHOLD_S:
                out.append({"person": pid, "crosswalk": cw, "duration": dur, "type": "LONG_BLOCKING"})
            if r["event_type"] == "CROSSWALK_BLOCK_FORCE_RELEASE":
                out.append({"person": pid, "crosswalk": cw, "duration": dur, "type": "FORCED_RELEASE"})
        for cw, st in q:
            out.append({"person": pid, "crosswalk": cw, "duration": -1, "type": "STUCK_NO_EXIT"})
    return out


def companion(e):
    if e.empty or not {"event_type", "details", "entity_id", "related_id", "time"}.issubset(e.columns):
        return [], {}
    c = e[e["event_type"] == "COMPANION_DISTANCE_SAMPLE"].copy()
    vals, issues = [], []
    for _, r in c.iterrows():
        s = str(r["details"])
        if ":" not in s:
            continue
        try:
            d = float(s.split(":", 1)[1]); vals.append(d)
            if d > COMPANION_DIST_THRESHOLD_M:
                issues.append({"person": r["entity_id"], "companion": r["related_id"], "time": r["time"], "distance": d})
        except (TypeError, ValueError):
            pass
    if not vals:
        return issues, {"samples": 0, "issues": len(issues), "issue_rate": 0.0}
    v = pd.Series(vals, dtype=float)
    return issues, {"samples": int(len(v)), "issues": int(len(issues)), "issue_rate": float(len(issues) / len(v)), "distance_stats": {"p50": float(v.quantile(0.50)), "p95": float(v.quantile(0.95)), "p99": float(v.quantile(0.99))}}


def parse_details_map(s):
    out = {}
    txt = "" if s is None else str(s)
    for tok in txt.split("|"):
        tok = tok.strip()
        if ":" not in tok:
            continue
        k, v = tok.split(":", 1)
        out[nk(k)] = v.strip()
    return out


def trip_event_lifecycle(e):
    if e.empty or not {"event_type", "related_id", "details"}.issubset(e.columns):
        return {}
    starts = e[e["event_type"] == "TRIP_LOG_START"].copy()
    ends = e[e["event_type"] == "TRIP_LOG_END"].copy()
    sids = set(starts["related_id"].dropna().astype(str))
    eids = set(ends["related_id"].dropna().astype(str))
    st = {}
    for d in ends["details"].dropna():
        m = parse_details_map(d)
        if "status" in m:
            k = m["status"].upper()
            st[k] = st.get(k, 0) + 1
    unclosed = sorted(list(sids - eids))
    orphan_end = sorted(list(eids - sids))
    return {
        "start_events": int(len(starts)),
        "end_events": int(len(ends)),
        "event_closure_rate": float(len(eids & sids) / max(len(sids), 1)),
        "status_counts_from_end_events": st,
        "unclosed_trip_ids_count": int(len(unclosed)),
        "orphan_end_trip_ids_count": int(len(orphan_end)),
        "unclosed_trip_ids_sample": unclosed[:20],
        "orphan_end_trip_ids_sample": orphan_end[:20],
    }


def schedule_flow(e):
    if e.empty or not {"event_type", "time"}.issubset(e.columns):
        return {}
    w = e[e["event_type"] == "SCHEDULE_WORK_DEPARTURE"].copy()
    h = e[e["event_type"] == "SCHEDULE_HOME_RETURN"].copy()
    a = e[e["event_type"] == "SCHEDULE_ACTIVITY_RETURN"].copy()
    out = {
        "work_departures": int(len(w)),
        "home_returns": int(len(h)),
        "activity_returns": int(len(a)),
        "home_return_vs_work_gap": int(len(w) - len(h)),
        "home_return_to_work_ratio": float(len(h) / max(len(w), 1)),
    }
    if not w.empty:
        w["hour_bin"] = np.floor(pd.to_numeric(w["time"], errors="coerce") / 3600.0).astype("Int64")
        out["work_departures_by_hour"] = {str(int(k)): int(v) for k, v in w.dropna(subset=["hour_bin"]).groupby("hour_bin").size().to_dict().items()}
    if not h.empty:
        h["hour_bin"] = np.floor(pd.to_numeric(h["time"], errors="coerce") / 3600.0).astype("Int64")
        out["home_returns_by_hour"] = {str(int(k)): int(v) for k, v in h.dropna(subset=["hour_bin"]).groupby("hour_bin").size().to_dict().items()}
    return out


def train_transfer_flow(e):
    if e.empty or not {"event_type", "entity_id"}.issubset(e.columns):
        return {}
    q = e[e["event_type"] == "TRAIN_QUEUE_ENTER"].copy()
    al = e[e["event_type"] == "TRAIN_ALIGHT_CONTINUE"].copy()
    qp = set(q["entity_id"].dropna().astype(str))
    ap = set(al["entity_id"].dropna().astype(str))
    return {
        "queue_entries": int(len(q)),
        "alight_continue_events": int(len(al)),
        "persons_queued": int(len(qp)),
        "persons_alight_continue": int(len(ap)),
        "persons_alight_after_queue": int(len(qp & ap)),
        "alight_after_queue_ratio": float(len(qp & ap) / max(len(qp), 1)),
    }


def active_profile(t):
    if t.empty or not {"start_time", "end_time"}.issubset(t.columns):
        return {}
    v = t[["start_time", "end_time"]].dropna(); v = v[v["end_time"] >= v["start_time"]]
    if v.empty:
        return {}
    c = pd.concat([pd.DataFrame({"time": v["start_time"], "delta": 1}), pd.DataFrame({"time": v["end_time"], "delta": -1})], ignore_index=True).groupby("time", as_index=False)["delta"].sum().sort_values("time")
    tm = c["time"].to_numpy(dtype=float); cm = c["delta"].to_numpy(dtype=float).cumsum()
    t0, t1 = float(v["start_time"].min()), float(v["end_time"].max())
    s = np.linspace(t0, t1, int(min(max(120, len(tm)), 600))) if t1 > t0 else np.array([t0], dtype=float)
    idx = np.searchsorted(tm, s, side="right") - 1
    a = np.maximum(np.where(idx >= 0, cm[idx], 0.0), 0.0)
    p, m = int(np.argmax(a)), max(float(np.mean(a)), 1e-9)
    top_ix = list(np.argsort(-a)[:20])
    top_peaks = []
    seen = set()
    for ix in top_ix:
        ts = float(s[ix])
        if ts in seen:
            continue
        seen.add(ts)
        top_peaks.append({"time_seconds": ts, "active": int(a[ix])})
        if len(top_peaks) >= 5:
            break
    return {
        "times": s.tolist(),
        "active": a.tolist(),
        "summary": {
            "peak_active": int(a[p]),
            "peak_time_seconds": float(s[p]),
            "avg_active": float(np.mean(a)),
            "active_p95": float(np.percentile(a, 95)),
            "active_non_zero_min": int(np.min(a[a > 0])) if np.any(a > 0) else 0,
            "top_peaks": top_peaks,
        },
        "quality": {
            "peak_to_mean_ratio": float(a[p] / m),
            "time_above_p90_hours": float(np.sum(a >= np.percentile(a, 90)) * (s[1] - s[0]) / 3600.0) if len(s) > 1 else 0.0,
        },
    }


def compute_active_travelers_profile(trips):
    return active_profile(trips)


def dist(tbl, grp):
    if tbl.empty or "metric_group" not in tbl.columns:
        return {}
    s = tbl[tbl["metric_group"].str.lower() == grp.lower()]
    out = {}
    for _, r in s.iterrows():
        k = canon_category(grp, r["metric_name"])
        if not k:
            continue
        out[k] = out.get(k, 0.0) + sf(r["metric_value"], 0.0)
    return out


def counts(tbl, grp):
    if tbl.empty or "metric_group" not in tbl.columns:
        return {}
    s = tbl[tbl["metric_group"].str.lower() == grp.lower()]
    out = {}
    for _, r in s.iterrows():
        k = canon_category(grp, r["metric_name"])
        if not k:
            continue
        out[k] = out.get(k, 0.0) + sf(r["metric_value"], 0.0)
    return {k: int(v) for k, v in out.items()}


def mode_expectation(e, r, observed_mode_shares):
    short_target = normdist(dist(r, "transport_short_target"))
    long_target = normdist(dist(r, "transport_long_target"))
    samples = 0
    long_count = 0
    if not e.empty and {"event_type", "details"}.issubset(e.columns):
        choices = e[e["event_type"] == "MODE_CHOICE"].copy()
        for _, row in choices.iterrows():
            d = parse_details_map(row["details"])
            klass = nk(d.get("distance_class", ""))
            if klass not in {"short", "long"}:
                continue
            samples += 1
            if klass == "long":
                long_count += 1
    long_share = (long_count / samples) if samples > 0 else None
    all_modes = sorted(set(observed_mode_shares.keys()) | set(short_target.keys()) | set(long_target.keys()))
    per_mode = {}
    for m in all_modes:
        exp_short = float(short_target.get(nk(m), 0.0))
        exp_long = float(long_target.get(nk(m), 0.0))
        if long_share is None:
            exp_mix = None
            delta_mix = None
        else:
            exp_mix = (1.0 - long_share) * exp_short + long_share * exp_long
            delta_mix = float(observed_mode_shares.get(m, 0.0) - exp_mix)
        per_mode[m] = {
            "observed_share": float(observed_mode_shares.get(m, 0.0)),
            "expected_short_share": exp_short,
            "expected_long_share": exp_long,
            "expected_mixed_share": exp_mix,
            "delta_vs_mixed": delta_mix,
        }
    mixed_target = {}
    if long_share is not None:
        for m in all_modes:
            mixed_target[m] = per_mode[m]["expected_mixed_share"]
    return {
        "samples": int(samples),
        "class_counts": {"short": int(samples - long_count), "long": int(long_count)},
        "observed_long_share": long_share,
        "targets": {
            "short": short_target,
            "long": long_target,
            "mixed_by_observed_class_share": mixed_target,
        },
        "per_mode": per_mode,
    }


def work_schedule_assignment(p, r):
    start_counts = counts(p, "work_start_hour_count")
    end_counts = counts(p, "work_end_hour_count")
    start_shares = normdist(dist(p, "work_start_hour_share"))
    end_shares = normdist(dist(p, "work_end_hour_share"))
    target_start = normdist(dist(r, "work_start_target"))
    target_end = normdist(dist(r, "work_end_target"))
    return {
        "start_counts": start_counts,
        "end_counts": end_counts,
        "start_shares": start_shares,
        "end_shares": end_shares,
        "start_target_shares": target_start,
        "end_target_shares": target_end,
    }


def normdist(d):
    x = {k: sf(v) for k, v in d.items() if sf(v) > 0}; s = sum(x.values())
    return {} if s <= 0 else {k: v / s for k, v in x.items()}


def cmp_dist(a, b):
    sa, sb = normdist(a), normdist(b); keys = sorted(set(sa) | set(sb))
    if not keys:
        return {"available": False}
    x = np.array([sa.get(k, 0.0) for k in keys], dtype=float); y = np.array([sb.get(k, 0.0) for k in keys], dtype=float)
    if x.sum() <= 0 or y.sum() <= 0:
        return {"available": False}
    ad = np.abs(x-y); eps = 1e-12
    px, py = np.maximum(x, eps), np.maximum(y, eps); px, py = px/px.sum(), py/py.sum(); m = 0.5*(px+py); js = float(0.5*(np.sum(px*np.log(px/m))+np.sum(py*np.log(py/m))))
    rows = [
        {
            "category": keys[i],
            "sim_share": float(x[i]),
            "target_share": float(y[i]),
            "abs_delta": float(ad[i]),
            "delta": float(x[i] - y[i]),
        }
        for i in range(len(keys))
    ]
    rows.sort(key=lambda z: z["abs_delta"], reverse=True)
    return {
        "available": True,
        "mae": float(ad.mean()),
        "rmse": float(np.sqrt(np.mean((x-y)**2))),
        "js_divergence": js,
        "rows": rows,
        "top_abs_deltas": rows[:10],
    }


def real_vs_sim(p, r, ms):
    mo = {nk(k): sf(v) for k, v in ms.items()}
    comps = {
        "household_size": cmp_dist(dist(p, "household_size"), dist(r, "household_size_target")),
        "gender": cmp_dist(dist(p, "gender"), dist(r, "gender_target")),
        "age_range": cmp_dist(dist(p, "age_range"), dist(r, "age_range_target")),
        "district": cmp_dist(dist(p, "district"), dist(r, "district_target")),
        "work_start_hour": cmp_dist(dist(p, "work_start_hour_share"), dist(r, "work_start_target")),
        "transport_vs_short_target": cmp_dist(mo, dist(r, "transport_short_target")),
        "transport_vs_long_target": cmp_dist(mo, dist(r, "transport_long_target")),
    }
    td = []
    for d, c in comps.items():
        if c.get("available", False):
            td += [
                {
                    "dimension": d,
                    "category": x["category"],
                    "sim_share": x["sim_share"],
                    "target_share": x["target_share"],
                    "abs_delta": x["abs_delta"],
                    "delta": x["delta"],
                }
                for x in c.get("rows", [])[:3]
            ]
    td.sort(key=lambda z: z["abs_delta"], reverse=True)
    return {"population_stats_available": not p.empty, "reference_stats_available": not r.empty, "comparisons": comps, "top_discrepancies": td[:20]}


def pie_svg(ms):
    w, h, cx, cy, rr = 980, 520, 250, 260, 180
    colors = ["#1f77b4", "#ff7f0e", "#2ca02c", "#d62728", "#9467bd"]
    if not ms:
        return f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}"><rect width="100%" height="100%" fill="white"/><text x="40" y="70" font-size="28" font-family="Arial">Mode Share</text><text x="40" y="120" font-size="20" font-family="Arial">No trip data available.</text></svg>'
    items = sorted(ms.items(), key=lambda x: x[1], reverse=True); tot = sum(v for _, v in items); a = 0.0; paths = []; leg=[]
    for i, (m, s) in enumerate([(k, (v/tot if tot>0 else 0)) for k, v in items]):
        if s <= 0: continue
        c = colors[i % len(colors)]; b = a + s*360.0
        p = lambda ang: (cx + rr*math.cos(math.radians(ang-90)), cy + rr*math.sin(math.radians(ang-90)))
        x1,y1 = p(a); x2,y2 = p(b); large = 1 if (b-a)>180 else 0
        paths.append(f'<path d="M {cx:.2f},{cy:.2f} L {x1:.2f},{y1:.2f} A {rr:.2f},{rr:.2f} 0 {large} 1 {x2:.2f},{y2:.2f} Z" fill="{c}" stroke="white" stroke-width="2"/>')
        lx,ly=520,120+i*40; leg += [f'<rect x="{lx}" y="{ly-14}" width="20" height="20" fill="{c}"/>', f'<text x="{lx+30}" y="{ly+2}" font-size="18" font-family="Arial">{m}: {s*100:.2f}%</text>']; a=b
    return "".join([f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}">','<rect width="100%" height="100%" fill="white"/>','<text x="40" y="60" font-size="28" font-family="Arial">Mode Share (Pie)</text>',*paths,*leg,"</svg>"])


def active_svg(prof):
    w, h, l, r, t, b = 1100, 560, 80, 30, 70, 80; cw, ch = w-l-r, h-t-b
    if not prof:
        return f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}"><rect width="100%" height="100%" fill="white"/><text x="40" y="70" font-size="28" font-family="Arial">Active Travelers Over Time</text></svg>'
    x = np.array(prof["times"], dtype=float); y = np.array(prof["active"], dtype=float); s = prof["summary"]; t0,t1=float(x.min()),float(max(x.max(),x.min()+1)); ym=max(1.0,float(y.max()))
    sx=lambda v:l+((v-t0)/(t1-t0))*cw; sy=lambda v:t+ch-(v/ym)*ch
    pts=" ".join(f"{sx(a):.2f},{sy(b):.2f}" for a,b in zip(x,y)); px,py=sx(float(s["peak_time_seconds"])),sy(float(s["peak_active"]))
    return "".join([f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}">','<rect width="100%" height="100%" fill="white"/>','<text x="40" y="42" font-size="28" font-family="Arial">Active Travelers Over Time</text>',f'<line x1="{l}" y1="{t+ch}" x2="{l+cw}" y2="{t+ch}" stroke="#222" stroke-width="2"/>',f'<line x1="{l}" y1="{t}" x2="{l}" y2="{t+ch}" stroke="#222" stroke-width="2"/>',f'<polyline fill="none" stroke="#1f77b4" stroke-width="2.5" points="{pts}"/>',f'<circle cx="{px:.2f}" cy="{py:.2f}" r="5" fill="#d62728"/>',f'<text x="{px+10:.2f}" y="{py-10:.2f}" font-size="13" font-family="Arial">Peak: {int(s["peak_active"])} at {s["peak_time_seconds"]/3600.0:.2f}h</text>',"</svg>"])


def run():
    t, e, p, r = load()
    if t is None:
        print("Logs not found. Run simulation first."); return
    ms = mode_shares(t)
    prof = active_profile(t)
    blk = crosswalk_blocking(e)
    comp_issues, comp_sum = companion(e)
    trip_evt = trip_event_lifecycle(e)
    sched = schedule_flow(e)
    train_flow = train_transfer_flow(e)
    pmm = compute_purpose_mode_matrix(t)
    mode_exp = mode_expectation(e, r, ms)
    work_sched = work_schedule_assignment(p, r)
    population_counts = {
        "household_size": counts(p, "household_size_count"),
        "household_type": counts(p, "household_type_count"),
        "gender": counts(p, "gender_count"),
        "age_range": counts(p, "age_range_count"),
        "district": counts(p, "district_count"),
    }
    report = {
        "mode_shares": ms,
        "mode_expectation": mode_exp,
        "timings": {k: float(v) for k, v in t["start_time"].dropna().describe().to_dict().items()} if "start_time" in t.columns and not t["start_time"].dropna().empty else {},
        "taxi_kpis": check_taxi_kpis(t),
        "trip_consistency": trip_consistency(t),
        "purpose_mode_matrix": {"counts": pmm["counts"], "shares_by_purpose": pmm["shares_by_purpose"]},
        "worker_return": worker_return(t),
        "train_consistency": train_consistency(t),
        "taxi_sla": taxi_sla(t, e),
        "travel_demand_profile": prof.get("summary", {}) if prof else {},
        "demand_quality": prof.get("quality", {}) if prof else {},
        "crosswalk_issues": blk,
        "crosswalk_summary": {"total_issues": len(blk), "long_blocking": int(sum(1 for x in blk if x["type"]=="LONG_BLOCKING")), "forced_release": int(sum(1 for x in blk if x["type"]=="FORCED_RELEASE")), "stuck_no_exit": int(sum(1 for x in blk if x["type"]=="STUCK_NO_EXIT"))},
        "companion_issues": comp_issues,
        "companion_summary": comp_sum,
        "trip_event_lifecycle": trip_evt,
        "schedule_flow": sched,
        "train_transfer_flow": train_flow,
        "work_schedule_assignment": work_sched,
        "population_counts": population_counts,
        "real_vs_sim": real_vs_sim(p, r, ms),
        "population_stats_available": not p.empty,
        "reference_stats_available": not r.empty,
        "artifacts": {"mode_share_pie_svg": os.path.basename(MODE_PIE_SVG), "active_travelers_svg": os.path.basename(ACTIVE_SVG)},
    }
    with open(MODE_PIE_SVG, "w", encoding="utf-8") as f: f.write(pie_svg(ms))
    with open(ACTIVE_SVG, "w", encoding="utf-8") as f: f.write(active_svg(prof))
    with open(REPORT_JSON, "w", encoding="utf-8") as f: json.dump(report, f, indent=2)
    with open(REPORT_MD, "w", encoding="utf-8") as f:
        f.write("# Simulation Analysis Report\n\n")
        f.write("## Mode Shares\n"); [f.write(f"- **{m}**: {s*100:.2f}%\n") for m,s in sorted(ms.items(), key=lambda x:x[1], reverse=True)]
        me = report.get("mode_expectation", {})
        if me:
            f.write("\n### Expected vs Observed by Mode\n")
            for mode, data in sorted(me.get("per_mode", {}).items()):
                obs = float(data.get("observed_share", 0.0)) * 100.0
                mix = data.get("expected_mixed_share")
                if mix is None:
                    f.write(f"- **{mode}**: observed={obs:.2f}% (mixed expectation unavailable)\n")
                else:
                    f.write(f"- **{mode}**: observed={obs:.2f}%, expected(mixed)={float(mix)*100.0:.2f}%, delta={float(data.get('delta_vs_mixed',0.0))*100.0:.2f} pp\n")
        f.write(f"\n![Mode share pie chart]({os.path.basename(MODE_PIE_SVG)})\n")
        if prof:
            s = prof["summary"]; q = prof["quality"]
            f.write("\n## Travel Demand Over Time\n")
            f.write(f"- **Peak travelers in transit**: {s['peak_active']} at {s['peak_time_seconds']/3600.0:.2f}h\n")
            f.write(f"- **Average travelers in transit**: {s['avg_active']:.2f}\n")
            f.write(f"- **P95 travelers in transit**: {s['active_p95']:.2f}\n")
            f.write(f"- **Peak/Mean ratio**: {q.get('peak_to_mean_ratio',0):.2f}\n")
            f.write(f"- **Hours above P90 demand**: {q.get('time_above_p90_hours',0):.2f}\n")
            f.write(f"\n![Active travelers timeline]({os.path.basename(ACTIVE_SVG)})\n")
        f.write("\n## Trip Consistency\n")
        tc = report["trip_consistency"]
        f.write(f"- **Total trips**: {tc.get('total_trips',0)}\n- **Closure rate**: {tc.get('closure_rate',0)*100:.2f}%\n- **Non-positive durations**: {tc.get('non_positive_duration',0)}\n")
        wr = report["worker_return"]
        f.write("\n## Worker Return Consistency\n")
        f.write(f"- **Workers with outbound trips**: {wr.get('workers_total',0)}\n- **Workers with resting return**: {wr.get('workers_with_return_resting',0)}\n- **Return rate (resting)**: {wr.get('return_rate_resting',0)*100:.2f}%\n")
        se = report["schedule_flow"]
        if se:
            f.write("\n## Schedule Trigger Flow\n")
            f.write(f"- **Work departures (events)**: {se.get('work_departures',0)}\n")
            f.write(f"- **Home returns (events)**: {se.get('home_returns',0)}\n")
            f.write(f"- **Home return / work departure ratio**: {se.get('home_return_to_work_ratio',0)*100:.2f}%\n")
            f.write(f"- **Gap (work - home)**: {se.get('home_return_vs_work_gap',0)}\n")
        ws = report.get("work_schedule_assignment", {})
        if ws:
            f.write("\n## Assigned Work Schedule (Population)\n")
            f.write(f"- **Unique start hours**: {len(ws.get('start_counts', {}))}\n")
            f.write(f"- **Unique end hours**: {len(ws.get('end_counts', {}))}\n")
        tr = report["train_consistency"]
        f.write("\n## Train Consistency\n")
        f.write(f"- **Train trips**: {tr.get('train_trips',0)}\n- **Train zero-duration trips**: {tr.get('zero_duration_count',0)}\n- **Persons with both train+walking trips**: {tr.get('persons_with_train_and_walking_modes',0)}\n")
        tf = report["train_transfer_flow"]
        if tf:
            f.write(f"- **Train queue entries**: {tf.get('queue_entries',0)}\n")
            f.write(f"- **Train alight+continue events**: {tf.get('alight_continue_events',0)}\n")
            f.write(f"- **Alight-after-queue ratio**: {tf.get('alight_after_queue_ratio',0)*100:.2f}%\n")
        te = report["trip_event_lifecycle"]
        if te:
            f.write("\n## Trip Event Lifecycle\n")
            f.write(f"- **Trip start events**: {te.get('start_events',0)}\n")
            f.write(f"- **Trip end events**: {te.get('end_events',0)}\n")
            f.write(f"- **Event closure rate**: {te.get('event_closure_rate',0)*100:.2f}%\n")
            f.write(f"- **Unclosed trip ids**: {te.get('unclosed_trip_ids_count',0)}\n")
            f.write(f"- **Orphan end trip ids**: {te.get('orphan_end_trip_ids_count',0)}\n")
        f.write("\n## Real vs Simulated Comparison\n")
        for dim, comp in report["real_vs_sim"]["comparisons"].items():
            if comp.get("available", False):
                f.write(f"- **{dim}**: MAE={comp['mae']:.4f}, RMSE={comp['rmse']:.4f}, JS={comp['js_divergence']:.4f}\n")
            else:
                f.write(f"- **{dim}**: not available\n")
    print(f"Report generated: {REPORT_MD}")
    print(f"Pie chart generated: {MODE_PIE_SVG}")
    print(f"Demand chart generated: {ACTIVE_SVG}")


if __name__ == "__main__":
    run()
