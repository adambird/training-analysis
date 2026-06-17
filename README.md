# Training Analysis

Analyses power data from cycling workout files (FIT, TCX, GPX — gzipped or not)
to track how peak efforts over fixed time windows progress over time.

Answers questions like: *in rides over 120 minutes, how many times did I hold
300W+ for a minute — and is that count, and the power of those efforts,
trending up or down?*

## Setup

```sh
bundle install
cp config.example.yml config.yml   # then set workout_dir and ftp
cp races.example.yml races.yml      # optional: list your races
```

`config.yml` and `races.yml` are gitignored — they hold your personal paths,
FTP, and race calendar. `workout_dir` / `ftp` can also be set via the
`WORKOUT_DIR` / `FTP` environment variables.

## Usage

```sh
# Uses workout_dir from config.yml; rides >= 120 min;
# windows 1min@300W, 3min@280W, 5min@260W
bundle exec bin/analyze

# Custom windows/thresholds and per-ride CSV output
bundle exec bin/analyze --min-duration 90 \
  --window 60:320 --window 300:250 \
  --csv data/rides.csv
```

The terminal report shows, per window, a monthly summary (rides, qualifying
efforts, efforts per ride/hour, mean effort power, best effort) plus
least-squares trend slopes scaled to per-30-days. The CSV holds the per-ride
detail.

## Shareable report

```sh
bundle exec bin/analyze --min-duration 90 --csv data/rides.csv
bundle exec bin/chart --months 12 --title "Training Power Trends"
```

`bin/chart` renders the CSV into `report.html` — a single self-contained file
(Chart.js inlined from `vendor/`, works offline) with interactive monthly
trend charts (toggleable trendlines via the legend), collapsible monthly
summary tables, per-ride detail, and methodology notes. Email or AirDrop it
as-is. `--months N` limits to the trailing N months; `--exclude YYYY-MM`
drops partial months that would skew trendlines.

## Fitness progression

```sh
bundle exec bin/fitness --months 24 --csv data/fitness.csv
```

Add `--snapshot` to also save a dated copy under `reports/` (default today, or
`--snapshot 2026-09-12`) for comparison over time; commit it to keep the
baseline. Renders a self-contained fitness report answering "improving or not":
power curve (best power at 5s–90min, trailing 12 months vs prior 12),
durability (best 5-min power fresh vs after 1,500/2,500 kJ), critical power
trend (work–time model over the best 3–20 min efforts in a trailing 90-day
window), and aerobic efficiency (NP/avg HR on steady rides, plus
half-by-half power:HR drift). Non-cycling activities are excluded via the
FIT sport field — Garmin watches record running power in the same field.

## Interval sessions

```sh
bundle exec bin/intervals --csv data/intervals.csv
```

Discovers interval sessions by power signature and classifies each by rep
length — 40/20, ~1min, ~2min hill reps, ~5min, etc. The exported files carry no
workout name (and the Zwift target-power field is unpopulated), so detection is
purely by shape: efforts above ~95% of CP, grouped into a set when they are
close in time and consistent in duration. This separates a deliberate set from
incidental hard efforts in a long ride, and finds outdoor sets (e.g. 2-min hill
reps with long descent recoveries) as well as indoor ERG work. Race days
(`races.yml`) are excluded.

`intervals.html` shows a rep-power trend chart per type (mean/best, with rolling
median) plus a full session table. The `bin/fitness` report carries a focused
40/20 chart and lists every interval type found.

## Methodology

- Each file is resolved to two 1Hz power series: elapsed time (seconds with
  no sample count as 0W) and moving time (recorded seconds only).
- **Effort detection** uses elapsed time, so an effort can never span a
  pause.
- **Average and normalised power** use moving time, matching what
  Strava/Garmin/TrainingPeaks report.
- **Rolling averages** for each window are computed over every second-aligned
  position via prefix sums.
- **Normalised power** follows Coggan's definition: 30s rolling average,
  fourth power, mean, fourth root — reported for whole rides only, since NP
  is not meaningful over short windows.
- **Effort counting** scans rolling means left to right; when a window meets
  the threshold it slides forward to the local peak alignment, records that
  effort, then skips a full window length. Efforts never overlap, and a
  sustained block above threshold counts once per window length (5 continuous
  minutes over 300W = five 1-minute efforts).
- Duplicate exports of the same ride (same start time and duration) are
  de-duplicated.

## Structure

- `lib/fit_parser.rb` — minimal in-house FIT decoder (timestamp + power from
  record messages). Written because `fit4ruby` crashes on Zwift-generated
  files; validated against `fit4ruby` output on Garmin files.
- `lib/xml_parsers.rb` — TCX (`Watts`) and GPX (`power`/`PowerInWatts`
  extensions) parsers.
- `lib/activity.rb` — file loading (gzip-aware) and 1Hz series construction.
- `lib/power_series.rb` — rolling means, normalised power, effort detection.
- `lib/analyzer.rb` — directory scan, per-ride results, monthly summary, trends.
- `bin/analyze` — CLI.

```sh
bundle exec ruby test/power_series_test.rb
```
