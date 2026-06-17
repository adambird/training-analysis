---
name: training-analysis
description: >-
  Analyse cycling power data (FIT/TCX/GPX workout files) with this repo's Ruby
  tool — a fitness-progression report covering power curve, critical power,
  durability under fatigue, early-race punch, race-day analysis, and aerobic
  efficiency. Use when the user asks to analyse their training, power, fitness
  progression, or races, or to (re)generate the report.
---

# Training analysis

A Ruby CLI tool (`bin/fitness`) that turns a directory of cycling workout files
into a self-contained HTML fitness-progression report. Run with `bundle exec`
from the repo root.

## First: check setup

The tool reads `config.yml` (gitignored) for `workout_dir`. If it is missing,
copy the template and ask the user for the value:

```sh
cp config.example.yml config.yml   # then set workout_dir
cp races.example.yml races.yml      # optional: their race calendar
```

`workout_dir` can also come from the `WORKOUT_DIR` env var. The tool aborts with
a setup hint if the workout directory is missing.

## The tool

**`bin/fitness`** — the progression report answering "am I getting faster?":
power curve (trailing 12mo vs prior), critical power & W′ trend, durability
(power after 1,500/2,500 kJ), early-race punch, race-day percentiles, and
aerobic efficiency.

```sh
bundle exec bin/fitness --months 24 --csv data/fitness.csv
```

Flags: `--months N` (span of monthly trends), `--compare N` (power-curve
comparison window, latest N months vs prior N), `--exclude YYYY-MM` (drop a
partial month, repeatable), `--csv FILE` (per-ride metrics), `--snapshot [DATE]`
(archive a dated copy under `reports/`), `--dir`, `--races`, `--no-open`.

Add `--snapshot` to bank a dated baseline for later comparison. The report opens
in the browser automatically (macOS); pass `--no-open` in non-interactive
contexts. Generated CSVs live in `data/`, HTML in `reports/` (both gitignored).

## Conventions to respect when interpreting results

- **Power curve** is the threshold-free progression signal — best average power
  at each duration; comparing periods answers "faster or not" without choosing
  any threshold.
- **Moving time** for average and normalised power (matches Strava/Garmin);
  recording gaps count as 0W only for effort detection, so an effort never
  spans a pause.
- **Normalised power** (Coggan) is whole-ride only — not meaningful over short
  windows.
- **Critical power** is fitted from the best 3–20min efforts in a trailing
  90-day window; it reads low if no maximal effort was ridden, so treat it as a
  floor.
- **Durability** lines are monthly *medians* over the long rides that reached
  each kJ mark (a max would track one good day); smaller fresh-vs-fatigued gaps
  mean better fatigue resistance.
- **Early punch** is observational — it only registers when something demanded
  the effort, so read the best lines (races, hard group rides), not the medians.
- **Seasonality**: prefer year-over-year (the faint dotted ghost lines) over
  straight trendlines — the data has a strong annual cycle.

## Races

`races.yml` lists race days (longest ride that day = the race; `role: key|prep`,
optional `name`). `bin/fitness` ranks each race metric against training rides
≥90 min in the preceding 12 months, as percentiles (race days excluded from the
training set).

## Tests

`bundle exec ruby test/fitness_test.rb` and `test/power_series_test.rb`. Run
them after changing any `lib/` logic.

## Notes

- Power parsing: `lib/fit_parser.rb` is an in-house FIT decoder (the `fit4ruby`
  gem crashes on Zwift files). Non-cycling activities are skipped via the FIT
  sport field (running power would otherwise pollute the data).
- This repo contains no personal data; the user's paths, races, and
  generated reports stay in the gitignored `config.yml`/`races.yml`/`data/`/
  `reports/`.
