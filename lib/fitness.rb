require_relative 'activity'
require_relative 'power_series'

# Fitness-progression metrics for a single ride, plus the aggregations and
# model fits used by bin/fitness: mean-maximal power, durability (power
# after kJ of work), critical power, and aerobic efficiency.
module Fitness
  # Power-curve durations (seconds): sprint through to long climbs
  MMP_DURATIONS = [5, 15, 30, 60, 120, 180, 300, 480, 600, 900, 1200, 1800, 2700, 3600, 5400].freeze
  # Durations used for the CP fit: 3-20 min, where the CP model holds
  CP_DURATIONS = [180, 300, 480, 600, 900, 1200].freeze
  DURABILITY_WINDOWS = [60, 120, 180, 300].freeze # 1/2/3/5 min, fresh vs fatigued
  # 1000 kJ matches the load used in published amateur durability studies, so
  # the decline figures are comparable to those benchmarks; 1500/2500 probe
  # deeper fatigue. The first mark is the primary "long ride" threshold.
  DURABILITY_KJS = [1000, 1500, 2500].freeze
  # Early punch: the efforts that make the front group at a race start
  EARLY_SECONDS = 1800 # first 30 minutes
  EARLY_WINDOWS = [60, 180, 300].freeze

  RideMetrics = Struct.new(
    :start_time, :duration_seconds, :work_kj, :distance_m, :mmp,
    :avg_w, :np_w,                    # moving-time average and normalised power
    :durability,                      # {window => {fresh:, after: {kj => watts_or_nil}}}
    :early,                           # {window => best_watts} in first 30 min, nil for short rides
    :total_ascent_m,                  # elevation gain, nil without altitude
    :ascent_early_mph, :ascent_late_mph, # climbing rate before/after the first kJ mark
    :ef, :decoupling_pct, :steady,    # aerobic efficiency fields (nil without HR)
    keyword_init: true
  )

  module_function

  def analyse_ride(activity)
    powers = activity.powers
    mmp = PowerSeries.best_means(powers, MMP_DURATIONS)

    starts = DURABILITY_KJS.to_h { |kj| [kj, PowerSeries.index_at_kj(powers, kj)] }
    durability = DURABILITY_WINDOWS.to_h do |window|
      after = DURABILITY_KJS.to_h do |kj|
        start = starts[kj]
        best = start && powers.size - start >= window ? PowerSeries.rolling_means(powers[start..], window).max : nil
        [kj, best]
      end
      [window, { fresh: mmp[window], after: after }]
    end

    early = powers.size >= EARLY_SECONDS ? PowerSeries.best_means(powers[0, EARLY_SECONDS], EARLY_WINDOWS) : nil

    ef, drift, steady = aerobic_efficiency(activity)

    # Climbing rate (m/h) before vs after the first kJ mark — does late-ride
    # terrain still offer sustained climbs, or does the riding flatten out once
    # fatigued? Needs altitude and a ride that reaches the mark with time to spare.
    mark = starts[DURABILITY_KJS.first]
    ascent_early_mph = ascent_late_mph = nil
    if activity.altitudes && mark&.positive? && powers.size - mark > 60
      ascent_early_mph = ascent_rate(activity.ascent_between(0, mark), mark)
      ascent_late_mph = ascent_rate(activity.ascent_between(mark, powers.size), powers.size - mark)
    end

    RideMetrics.new(
      start_time: activity.start_time,
      duration_seconds: activity.duration_seconds,
      work_kj: powers.sum / 1000,
      distance_m: activity.distance_m,
      mmp: mmp,
      avg_w: activity.average_power.round(1),
      np_w: activity.normalised_power.round(1),
      durability: durability,
      early: early,
      total_ascent_m: activity.total_ascent_m,
      ascent_early_mph: ascent_early_mph,
      ascent_late_mph: ascent_late_mph,
      ef: ef, decoupling_pct: drift, steady: steady
    )
  end

  # Metres climbed per hour over +seconds+ of elapsed time, nil if undefined.
  def ascent_rate(metres, seconds)
    return nil if metres.nil? || seconds.nil? || seconds <= 0

    (metres / (seconds / 3600.0)).round
  end

  def median(values)
    return nil if values.empty?

    sorted = values.sort
    mid = sorted.size / 2
    sorted.size.odd? ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2.0
  end

  # Percentage of +values+ at or below +value+ (0-100), nil when either side
  # is missing.
  def percentile_rank(values, value)
    return nil if value.nil? || values.empty?

    (values.count { |v| v <= value } * 100.0 / values.size).round
  end

  # EF = NP / average HR over moving time. Only meaningful on steady rides:
  # >= 60 min moving, variability index <= 1.15, >= 80% HR coverage.
  # Decoupling compares power:HR between ride halves (positive = HR drifted).
  def aerobic_efficiency(activity)
    powers = activity.moving_powers
    hrs = activity.moving_hrs
    paired = powers.zip(hrs).select { |_, h| h }
    return [nil, nil, false] if powers.size < 3600 || paired.size < powers.size * 0.8

    avg = powers.sum.to_f / powers.size
    np = PowerSeries.normalised_power(powers)
    return [nil, nil, false] if avg <= 0 || np / avg > 1.15

    avg_hr = paired.sum { |_, h| h }.to_f / paired.size
    ef = np / avg_hr

    half = paired.size / 2
    r1 = half_power_hr_ratio(paired[0...half])
    r2 = half_power_hr_ratio(paired[half..])
    drift = r1&.positive? && r2 ? ((r1 - r2) / r1 * 100).round(1) : nil

    [ef.round(3), drift, true]
  end

  def half_power_hr_ratio(pairs)
    return nil if pairs.empty?

    hr = pairs.sum { |_, h| h }.to_f / pairs.size
    return nil unless hr.positive?

    pairs.sum { |p, _| p }.to_f / pairs.size / hr
  end

  # Critical power via the linear work-time model: W(t) = W' + CP * t,
  # least-squares over [duration, best_watts] points. Requires points
  # spanning at least a 3x duration range to be meaningful.
  # Returns {cp:, w_prime_kj:} or nil.
  def cp_fit(points)
    points = points.select { |_, w| w }
    return nil if points.size < 3
    return nil if points.map(&:first).max < points.map(&:first).min * 3

    xs = points.map(&:first)
    ys = points.map { |t, w| t * w } # work in joules
    n = points.size.to_f
    sx = xs.sum
    sy = ys.sum
    sxx = xs.sum { |x| x * x }
    sxy = xs.zip(ys).sum { |x, y| x * y }
    cp = (n * sxy - sx * sy) / (n * sxx - sx * sx)
    w_prime = (sy - cp * sx) / n
    return nil if cp <= 0 || w_prime <= 0

    { cp: cp.round(1), w_prime_kj: (w_prime / 1000).round(1) }
  end

  # Best power per duration across a set of ride metrics.
  def aggregate_mmp(rides, durations = MMP_DURATIONS)
    durations.to_h do |d|
      [d, rides.filter_map { |r| r.mmp[d] }.max]
    end
  end

  # CP fit from the best CP_DURATIONS efforts across +rides+.
  def cp_for(rides)
    cp_fit(CP_DURATIONS.map { |d| [d, rides.filter_map { |r| r.mmp[d] }.max] })
  end

  def duration_label(seconds)
    seconds < 60 ? "#{seconds}s" : "#{seconds / 60}m"
  end
end
