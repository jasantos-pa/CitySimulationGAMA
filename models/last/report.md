# Simulation Analysis Report

## Mode Shares
- **car**: 74.98%
- **train**: 18.93%
- **walking**: 5.84%
- **taxi**: 0.25%

### Expected vs Observed by Mode
- **car**: observed=74.98%, expected(mixed)=69.58%, delta=5.40 pp
- **taxi**: observed=0.25%, expected(mixed)=2.90%, delta=-2.65 pp
- **train**: observed=18.93%, expected(mixed)=19.35%, delta=-0.42 pp
- **walking**: observed=5.84%, expected(mixed)=8.16%, delta=-2.33 pp

![Mode share pie chart](mode_share_pie.svg)

## Travel Demand Over Time
- **Peak travelers in transit**: 747 at 0.01h
- **Average travelers in transit**: 309.88
- **P95 travelers in transit**: 651.10
- **Peak/Mean ratio**: 2.41
- **Hours above P90 demand**: 0.26

![Active travelers timeline](active_travelers_timeline.svg)

## Trip Consistency
- **Total trips**: 3597
- **Closure rate**: 100.00%
- **Non-positive durations**: 83

## Worker Return Consistency
- **Workers with outbound trips**: 3557
- **Workers with resting return**: 0
- **Return rate (resting)**: 0.00%

## Schedule Trigger Flow
- **Work departures (events)**: 4997
- **Home returns (events)**: 0
- **Home return / work departure ratio**: 0.00%
- **Gap (work - home)**: 4997

## Assigned Work Schedule (Population)
- **Unique start hours**: 7
- **Unique end hours**: 7

## Train Consistency
- **Train trips**: 681
- **Train zero-duration trips**: 39
- **Persons with both train+walking trips**: 0
- **Train queue entries**: 236
- **Train alight+continue events**: 5
- **Alight-after-queue ratio**: 2.12%

## Trip Event Lifecycle
- **Trip start events**: 5301
- **Trip end events**: 3597
- **Event closure rate**: 67.86%
- **Unclosed trip ids**: 1704
- **Orphan end trip ids**: 0

## Real vs Simulated Comparison
- **household_size**: MAE=0.1591, RMSE=0.1671, JS=0.1161
- **gender**: MAE=0.1285, RMSE=0.1285, JS=0.0085
- **age_range**: MAE=0.0170, RMSE=0.0228, JS=0.0504
- **district**: MAE=0.0023, RMSE=0.0033, JS=0.0001
- **work_start_hour**: MAE=0.0024, RMSE=0.0032, JS=0.0001
- **transport_vs_short_target**: MAE=0.1838, RMSE=0.2168, JS=0.1494
- **transport_vs_long_target**: MAE=0.0405, RMSE=0.0433, JS=0.0289
