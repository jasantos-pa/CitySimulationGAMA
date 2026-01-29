import pandas as pd
import json
import os

# Configuration
TRIPS_FILE = 'trips.csv'
EVENTS_FILE = 'events.csv'
REPORT_JSON = 'report.json'
REPORT_MD = 'report.md'
CROSSWALK_THRESHOLD_S = 60.0
COMPANION_DIST_THRESHOLD_M = 5.0

def load_data():
    if not os.path.exists(TRIPS_FILE) or not os.path.exists(EVENTS_FILE):
        return None, None
    
    trips = pd.read_csv(TRIPS_FILE, skipinitialspace=True)
    events = pd.read_csv(EVENTS_FILE, skipinitialspace=True)
    return trips, events

def check_crosswalk_blocking(events):
    print("Checking crosswalk blocking...")
    cw_events = events[events['event_type'].isin(['CROSSWALK_ENTER', 'CROSSWALK_EXIT', 'CROSSWALK_BLOCK_FORCE_RELEASE'])].copy()
    cw_events = cw_events.sort_values(by=['entity_id', 'related_id', 'time'])
    
    blocking_issues = []
    
    # Group by person and crosswalk (related_id)
    grouped = cw_events.groupby(['entity_id', 'related_id'])
    
    for (person, crosswalk), group in grouped:
        enters = group[group['event_type'] == 'CROSSWALK_ENTER']
        exits = group[group['event_type'].isin(['CROSSWALK_EXIT', 'CROSSWALK_BLOCK_FORCE_RELEASE'])]
        
        # Simple Logic: For each enter, look for NEXT exit
        for _, enter in enters.iterrows():
            t_start = enter['time']
            # Find next exit
            future_exits = exits[exits['time'] > t_start]
            if not future_exits.empty:
                exit_evt = future_exits.iloc[0]
                t_end = exit_evt['time']
                dur = t_end - t_start
                if dur > CROSSWALK_THRESHOLD_S:
                    blocking_issues.append({
                        'person': person,
                        'crosswalk': crosswalk,
                        'duration': dur,
                        'start': t_start,
                        'end': t_end,
                        'type': 'LONG_BLOCKING'
                    })
                if exit_evt['event_type'] == 'CROSSWALK_BLOCK_FORCE_RELEASE':
                     blocking_issues.append({
                        'person': person,
                        'crosswalk': crosswalk,
                        'duration': dur,
                        'start': t_start,
                        'end': t_end,
                        'type': 'FORCED_RELEASE'
                    })
            else:
                # No exit found!
                blocking_issues.append({
                    'person': person,
                    'crosswalk': crosswalk,
                    'duration': -1,
                    'start': t_start,
                    'end': None,
                    'type': 'STUCK_NO_EXIT'
                })
                
    return blocking_issues

def check_companion_logic(events):
    print("Checking companion logic...")
    comp_events = events[events['event_type'] == 'COMPANION_DISTANCE_SAMPLE'].copy()
    
    issues = []
    
    for _, row in comp_events.iterrows():
        # Details format: "relation_dist:VALUE"
        details = str(row['details'])
        if ':' in details:
            try:
                val_str = details.split(':')[1]
                dist = float(val_str)
                if dist > COMPANION_DIST_THRESHOLD_M:
                    issues.append({
                        'person': row['entity_id'],
                        'companion': row['related_id'],
                        'time': row['time'],
                        'distance': dist
                    })
            except:
                pass
                
    return issues

def check_mode_shares(trips):
    if len(trips) == 0:
        return {}
    counts = trips['mode'].value_counts(normalize=True).to_dict()
    return counts

def check_trip_timings(trips):
    if len(trips) == 0 or 'start_time' not in trips.columns:
        return {}
    return trips['start_time'].describe().to_dict()

def check_taxi_kpis(trips):
    taxis = trips[trips['mode'] == 'taxi']
    if taxis.empty:
        return {'count': 0}
    
    kpis = {
        'count': len(taxis),
        'avg_duration': taxis['duration'].mean(),
        'min_duration': taxis['duration'].min(),
        'max_duration': taxis['duration'].max(),
    }
    if 'wait_time' in taxis.columns:
        kpis['avg_wait'] = taxis['wait_time'].mean()
    return kpis

def generate_report(blocking, companion_issues, mode_shares, timings, taxi_kpis):
    report_data = {
        'crosswalk_issues': blocking,
        'companion_issues': companion_issues,
        'mode_shares': mode_shares,
        'timings': timings,
        'taxi_kpis': taxi_kpis
    }
    
    with open(REPORT_JSON, 'w') as f:
        json.dump(report_data, f, indent=2)
        
    with open(REPORT_MD, 'w') as f:
        f.write("# Simulation Analysis Report\n\n")
        
        f.write("## Mode Shares\n")
        for mode, share in mode_shares.items():
            f.write(f"- **{mode}**: {share*100:.2f}%\n")

        f.write("\n## Taxi KPIs\n")
        f.write(f"- **Total Trips**: {taxi_kpis.get('count', 0)}\n")
        if taxi_kpis.get('count', 0) > 0:
            f.write(f"- **Avg Duration**: {taxi_kpis.get('avg_duration', 0):.2f}s\n")
            if 'avg_wait' in taxi_kpis:
                f.write(f"- **Avg Wait Time**: {taxi_kpis.get('avg_wait', 0):.2f}s\n")

        f.write("\n## Trip Timings\n")
        if timings:
            f.write(f"- **Min Start**: {timings.get('min', 0):.2f}\n")
            f.write(f"- **Max Start**: {timings.get('max', 0):.2f}\n")
        
        f.write("\n## Crosswalk Blocking Issues\n")
        f.write(f"Found {len(blocking)} issues (Threshold: {CROSSWALK_THRESHOLD_S}s)\n")
        if len(blocking) > 0:
            df = pd.DataFrame(blocking)
            f.write(df[['person', 'crosswalk', 'type', 'duration']].head(10).to_markdown())
            if len(blocking) > 10:
                f.write(f"\n... and {len(blocking)-10} more.\n")
                
        f.write("\n## Companion Distance Issues\n")
        f.write(f"Found {len(companion_issues)} issues (Threshold: {COMPANION_DIST_THRESHOLD_M}m)\n")
        if len(companion_issues) > 0:
            df = pd.DataFrame(companion_issues)
            f.write(df.head(10).to_markdown())

if __name__ == "__main__":
    trips, events = load_data()
    if trips is not None:
        blocking = check_crosswalk_blocking(events)
        companions = check_companion_logic(events)
        shares = check_mode_shares(trips)
        timings = check_trip_timings(trips)
        taxi_kpis = check_taxi_kpis(trips)
        generate_report(blocking, companions, shares, timings, taxi_kpis)
        print(f"Report generated: {REPORT_MD}")
    else:
        print("Logs not found. Run simulation first.")
