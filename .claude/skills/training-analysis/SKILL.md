---
name: training-analysis
description: >-
  Analyse cycling power data (FIT/TCX/GPX workout files) with this repo's Ruby
  tools — effort-trend reports, fitness-progression reports (power curve,
  critical power, durability, aerobic efficiency, race-day analysis), and
  interval-session detection. Use when the user asks to analyse their training,
  power, fitness progression, races, or interval sessions, or to (re)generate
  any of the reports.
---

# Training analysis

Ruby CLI tools that turn a directory of cycling workout files into reports.
Run everything with `bundle exec` from the repo root.

## First: check setup

The tools read `config.yml` (gitignored) for `workout_dir` and `ftp`. If it is
missing, copy the template and ask the user for values:

```sh
cp config.example.yml config.yml   # then set workout_dir + ftp
cp races.example.yml races.yml      # optional: their race calendar
```

`workout_dir`/`ftp` can also come from the `WORKOUT_DIR`/`FTP` env vars. The
tools abort with a setup hint if the workout directory is missing.

## The four tools

- **`bin/analyze`** — counts efforts over fixed time windows (default
  1min@300W, 3min@280W, 5min@260W) in rides above a duration, with monthly
  trends. Write the per-ride CSV that `bin/chart` consumes:
  `bundle exec bin/analyze --min-duration 90 --csv data/rides.csv`
  Flags: `--min-duration N` (0 = all rides), `--window SEC:WATTS` (repeatable),
  `--dir`, `--csv`.

- **`bin/chart`** — renders `data/rides.csv` into a self-contained HTML report
  under `reports/` (interactive charts, year-ago ghost lines, toggleable
  rolling medians, tables). `bundle exec bin/chart --months 12`
  Flags: `--input`, `--months N`, `--exclude YYYY-MM` (drop partial months),
  `--title`, `--no-open`.

- **`bin/fitness`** — the main progression report: power curve (trailing 12mo
  vs prior), critical power trend, durability (power after 1500/2500 kJ),
  early-race punch, aerobic efficiency, race-day percentiles, and an interval
  summary. `bundle exec bin/fitness --months 24 --csv data/fitness.csv`
  Flags: `--months N`, `--compare N` (power-curve comparison window),
  `--exclude`, `--snapshot [DATE]` (archive a dated copy under `reports/`).

- **`bin/intervals`** — discovers interval sessions by power signature and
  classifies them by rep length (40/20, ~1/2/5-min, hill reps), with a
  per-type rep-power trend. `bundle exec bin/intervals --csv data/intervals.csv`

## Typical workflow

1. `bin/analyze --min-duration 90 --csv data/rides.csv` then `bin/chart` — for
   "how are my efforts trending".
2. `bin/fitness --months 24` — for "am I improving as a cyclist" / race prep.
   Add `--snapshot` to bank a dated baseline for later comparison.
3. `bin/intervals` — for "how are my interval sessions going".

Reports open in the browser automatically (macOS); pass `--no-open` in
non-interactive contexts. Generated CSVs live in `data/`, HTML in `reports/`
(both gitignored).

## Conventions to respect when interpreting results

- **Efforts/hour, not per ride** — effort counts are normalised by ride
  duration so long and short rides compare fairly.
- **Moving time** for average and normalised power (matches Strava/Garmin);
  recording gaps count as 0W only for effort detection, so an effort never
  spans a pause.
- **Normalised power** (Coggan) is whole-ride only — not meaningful over short
  windows.
- **Critical power** is fitted from the best 3–20min efforts in a trailing
  90-day window; it reads low if no maximal effort was ridden, so treat it as a
  floor.
- **Seasonality**: prefer year-over-year (the ghost lines) over straight
  trendlines — the data has a strong annual cycle.
- **Interval detection is by shape, not label** (files carry no workout name).
  Single-set outdoor detections may be incidental; multi-set and structured
  (Zwift) sessions are high-confidence. **Race days (`races.yml`) are excluded**
  from interval detection.
- **Fade** = mean of the last third of reps minus the first third (end vs start
  of a session); negative = faded / started too hot.

## Races

`races.yml` lists race days (longest ride that day = the race; `role: key|prep`,
optional `name`). `bin/fitness` ranks each race against training rides as
percentiles; both tools exclude race days from interval detection.

## Tests

`bundle exec ruby test/power_series_test.rb` (and `fitness_test.rb`,
`intervals_test.rb`). Run them after changing any `lib/` logic.

## Notes

- Power parsing: `lib/fit_parser.rb` is an in-house FIT decoder (the `fit4ruby`
  gem crashes on Zwift files). Non-cycling activities are skipped via the FIT
  sport field (running power would otherwise pollute the data).
- This repo contains no personal data; the user's paths, FTP, races, and
  generated reports stay in the gitignored `config.yml`/`races.yml`/`data/`/
  `reports/`.
