# Altitude correction for aerobic power.
#
# Above roughly 1,500 m the reduced partial pressure of oxygen lowers the
# aerobic power a rider can sustain, so power recorded on rides at altitude
# reads low for reasons that have nothing to do with fitness. This module maps
# elevation to the fraction of sea-level aerobic power still available, from two
# published models, so altitude rides can be flagged (and their power expressed
# as a sea-level equivalent) rather than silently dragging the trends down.
#
# Data points (percentage of sea-level aerobic power by elevation in feet):
#   Bassett et al.  — acclimatized and non-acclimatized athletes
#   Péronnet et al. — modelled VO2max decline
# A multi-day trip starts non-acclimatized and only partly acclimatizes, so
# NON_ACCLIMATIZED is the default: it is the conservative choice (largest
# reduction), so it never overstates fitness.
module Altitude
  M_PER_FT = 0.3048

  # elevation_ft => { acclimatized:, non_acclimatized:, peronnet: } percentages
  TABLE = {
    0      => [99.9, 100.0, 99.9],
    1_000  => [99.2, 98.6, 98.9],
    2_000  => [98.3, 97.0, 97.8],
    3_000  => [97.2, 95.2, 96.8],
    4_000  => [95.9, 93.2, 95.6],
    5_000  => [94.4, 91.1, 94.4],
    6_000  => [92.7, 88.9, 93.1],
    7_000  => [90.7, 86.5, 91.6],
    8_000  => [88.6, 84.2, 89.9],
    9_000  => [86.3, 81.7, 88.1],
    10_000 => [83.7, 79.3, 86.0],
    11_000 => [80.9, 77.0, 83.7],
    12_000 => [78.0, 74.7, 81.1],
    13_000 => [74.8, 72.5, 78.2],
    14_000 => [71.4, 70.4, 75.0]
  }.freeze

  MODELS = { acclimatized: 0, non_acclimatized: 1, peronnet: 2 }.freeze
  DEFAULT_MODEL = :non_acclimatized

  # Rides whose median elevation is at or above this are treated as altitude
  # rides. 1,000 m (~3,300 ft) cleanly separates a genuine altitude block from
  # normal riding and sits where the reduction first exceeds a few percent.
  THRESHOLD_M = 1_000

  module_function

  # Fraction (0–1) of sea-level aerobic power available at +metres+, linearly
  # interpolated between the table rows. Below sea level → 1.0; above the top
  # row → clamped to the top row.
  def power_factor(metres, model: DEFAULT_MODEL)
    return 1.0 if metres.nil? || metres <= 0

    col = MODELS.fetch(model)
    feet = metres / M_PER_FT
    rows = TABLE.keys
    return TABLE[rows.last][col] / 100.0 if feet >= rows.last

    hi = rows.find { |ft| ft >= feet }
    lo = rows[rows.index(hi) - 1]
    frac = (feet - lo) / (hi - lo).to_f
    pct = TABLE[lo][col] + (TABLE[hi][col] - TABLE[lo][col]) * frac
    pct / 100.0
  end

  # Observed watts scaled up to their sea-level equivalent, so an altitude ride
  # can be read against sea-level rides. nil-safe.
  def sea_level_equivalent(watts, metres, model: DEFAULT_MODEL)
    return watts if watts.nil?

    watts / power_factor(metres, model: model)
  end

  # Median of an elevation series (metres), nil if empty.
  def median(altitudes)
    clean = altitudes&.compact
    return nil if clean.nil? || clean.empty?

    sorted = clean.sort
    mid = sorted.size / 2
    sorted.size.odd? ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2.0
  end
end
