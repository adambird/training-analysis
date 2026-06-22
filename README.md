# Training Analysis

Analyses power data from cycling workout files (FIT, TCX, GPX — gzipped or not)
to track cycling fitness over time and answer one question: *am I getting
faster?*

The **power-duration curve** (best mean-maximal power at each duration) is the
primary progression signal — it answers *"is my power improving?"* directly,
without arbitrary thresholds. Around it the report layers the qualities that a
single curve hides: critical power, durability under fatigue, early-ride punch,
race-day demands, and aerobic efficiency.

## Setup

```sh
bundle install
cp config.example.yml config.yml   # then set workout_dir
cp races.example.yml races.yml      # optional: list your races
```

`config.yml` and `races.yml` are gitignored — they hold your personal workout
path and race calendar. `workout_dir` can also be set via the `WORKOUT_DIR`
environment variable.

## Usage

```sh
# Uses workout_dir from config.yml; 24 months of trends; power-curve
# comparison of the latest 12 months vs the prior 12.
bundle exec bin/fitness

# Custom span, comparison window, per-ride CSV, and a dated snapshot.
bundle exec bin/fitness --months 24 --compare 12 \
  --csv data/fitness.csv --snapshot
```

Renders a self-contained HTML report under `reports/` (Chart.js inlined from
`vendor/`, so it works offline) and opens it in the browser. Email or AirDrop
it as-is. Key flags:

- `--months N` — span of the monthly trend charts (default 24).
- `--compare N` — power-curve comparison period, latest N months vs the prior N
  (default 12).
- `--exclude YYYY-MM` — drop a partial month that would skew trendlines
  (repeatable).
- `--csv FILE` — also write per-ride metrics to CSV.
- `--snapshot [DATE]` — save a dated copy under `reports/` (default today, or
  `--snapshot 2026-09-12`) for comparison over time; commit it to keep a
  baseline.
- `--no-open` — don't open the report in the browser.

## What the report shows

- **Power curve** — best average power at each duration (5s–90min) over the
  period, latest window vs the prior one. The threshold-free "faster or not"
  signal.
- **Critical power & W′** — linear work–time model fitted to the best 3–20 min
  efforts in a trailing 90-day window. CP approximates FTP; W′ is anaerobic
  capacity.
- **Durability** — best 1/2/3/5-min power when fresh vs after 1,000/2,000 kJ in
  the same ride, as monthly medians over the long rides that reached each mark,
  plus the fade as a % drop. The 1,000 kJ mark matches published amateur
  durability studies so the decline is comparable, and 2,000 kJ probes deeper
  race-distance fatigue; smaller gaps mean better fatigue resistance; the
  1m→2m→3m decay gradient shows whether longer efforts fade more.
- **Climbing** — total ascent per ride, and the climbing rate before vs after
  the 1,500 kJ mark on long rides, to see whether late-ride terrain still
  offers sustained climbs. Year-by-year tables sit alongside the durability
  decay so fatigue resistance can be weighed against intensity and climbing.
- **Race days** — each race metric (from `races.yml`) as a percentile of the
  training rides ≥90 min in the preceding 12 months (includes early-effort and
  fatigued-power metrics).
- **Aerobic efficiency** — normalised power ÷ average heart rate on steady
  rides, plus half-by-half power:HR drift.

Faint dotted lines show the same month a year earlier (seasonality-free
comparison); dashed 3-month rolling medians and most tables are hidden by
default — toggle via the legend or expand the collapsible tables. The report
carries full methodology notes at the foot.

Non-cycling activities are excluded via the FIT sport field (Garmin watches
record running power in the same field).

## Methodology

- Each file is resolved to two 1Hz power series: elapsed time (seconds with
  no sample count as 0W) and moving time (recorded seconds only).
- **Average and normalised power** use moving time, matching what
  Strava/Garmin/TrainingPeaks report.
- **Rolling averages** for each window are computed over every second-aligned
  position via prefix sums.
- **Normalised power** follows Coggan's definition: 30s rolling average,
  fourth power, mean, fourth root — reported for whole rides only, since NP
  is not meaningful over short windows.
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
- `lib/fitness.rb` — per-ride fitness metrics (power curve, durability, CP,
  aerobic efficiency).
- `lib/config.rb` — workout-directory and race-calendar loading.
- `bin/fitness` — CLI and HTML report.

```sh
bundle exec ruby test/fitness_test.rb
bundle exec ruby test/power_series_test.rb
```

## License

MIT — see [LICENSE](LICENSE).

Bundles [Chart.js](https://www.chartjs.org) (`vendor/chart.umd.min.js`, MIT
licensed) so generated reports render offline.
