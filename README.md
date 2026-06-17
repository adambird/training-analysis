# Training Analysis

Analyses power data from cycling workout files (FIT, TCX, GPX — gzipped or not)
to track cycling fitness and training over time.

The **power-duration curve** (best mean-maximal power at each duration) is the
primary progression signal — it answers *"is my power improving?"* directly,
without arbitrary thresholds. Alongside it, **effort frequency** answers a
separate question — *"how often do I produce near-best efforts?"* — using a
threshold set to a percentage of the rider's *own* rolling-best power at each
duration (e.g. ≥75% of the best 1/3/5-min in the trailing 90 days), so it stays
meaningful as fitness changes rather than drifting with it.

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
# Uses workout_dir from config.yml; rides >= 120 min; durations 1/3/5 min;
# effort threshold = 75% of rolling 90-day best at each duration
bundle exec bin/analyze

# Custom durations, threshold %, reference window, and per-ride CSV
bundle exec bin/analyze --min-duration 90 \
  --window 60 --window 300 --pct 80 --ref-window-days 60 \
  --csv data/rides.csv
```

Per duration, the terminal report shows a monthly summary — **best power**
(the progression signal), the rolling effort **threshold** that month, and
**effort count / per-hour** (the frequency signal) — plus per-30-day trend
slopes for both. `--pct` sets the effort threshold (% of rolling best);
`--ref-window-days` sets how far back "best" looks.

## Shareable report

```sh
bundle exec bin/analyze --min-duration 90 --csv data/rides.csv
bundle exec bin/chart --months 12 --title "Training Power Trends"
```

`bin/chart` renders the CSV into a self-contained HTML report under `reports/`
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

`reports/intervals.html` shows a rep-power trend chart per type (mean/best, with rolling
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
- **Effort thresholds** are per-ride: for each duration, the threshold is a
  percentage (default 75%) of the best mean-maximal power at that duration over
  a trailing window (default 90 days), drawn from all rides — so it tracks
  current fitness instead of being a fixed wattage. The power-duration curve
  (best power per duration) is the threshold-free progression metric.
- **Effort counting** scans rolling means left to right; when a window meets
  the threshold it slides forward to the local peak alignment, records that
  effort, then skips a full window length. Efforts never overlap, and a
  sustained block above threshold counts once per window length.
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

## License

MIT — see [LICENSE](LICENSE).

Bundles [Chart.js](https://www.chartjs.org) (`vendor/chart.umd.min.js`, MIT
licensed) so generated reports render offline.
