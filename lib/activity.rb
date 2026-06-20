require 'zlib'
require_relative 'fit_parser'
require_relative 'xml_parsers'
require_relative 'power_series'

# A single workout file resolved to 1Hz power (and heart rate) series.
#
# Two views of the ride:
# - +powers+: elapsed time, seconds with no sample filled as 0W. Used for
#   effort detection so an effort can never span a pause.
# - +moving_powers+ / +moving_hrs+: recorded seconds only (pauses removed),
#   index-aligned with each other. Used for average power, normalised power
#   and power:HR, matching what Strava/Garmin report. moving_hrs entries are
#   nil where the file has no heart rate sample.
class Activity
  ASCENT_THRESHOLD_M = 2.0 # ignore sub-2m wiggles so GPS noise doesn't inflate ascent

  attr_reader :path, :start_time, :powers, :moving_powers, :moving_hrs, :distance_m, :altitudes

  def self.load(path)
    data = read_raw(path)
    parsed =
      case path.sub(/\.gz\z/i, '')
      when /\.fit\z/i then FitParser.parse(data)
      when /\.tcx\z/i then TcxParser.parse(data)
      when /\.gpx\z/i then GpxParser.parse(data)
      else return nil
      end
    # Skip declared non-cycling activities: Garmin watches record running
    # power in the same field, which would poison the power analysis.
    # Files without a sport declaration are kept.
    return nil if parsed[:cycling] == false
    return nil if parsed[:samples].empty?

    new(path, parsed[:samples], parsed[:distance_m], parsed[:total_ascent_m])
  end

  def self.read_raw(path)
    if path.end_with?('.gz')
      Zlib::GzipReader.open(path, &:read).force_encoding(Encoding::BINARY)
    else
      File.binread(path)
    end
  end

  def initialize(path, samples, distance_m = nil, total_ascent_m = nil)
    @path = path
    @distance_m = distance_m
    @device_ascent_m = total_ascent_m
    by_second = {} # last sample wins per second
    samples.sort_by(&:first).each { |ts, watts, bpm, alt| by_second[ts] = [watts, bpm, alt] }
    t0 = by_second.keys.first
    @start_time = Time.at(t0).utc

    @powers = Array.new(by_second.keys.last - t0 + 1, 0)
    by_second.each { |ts, (watts, _, _)| @powers[ts - t0] = watts }
    @moving_powers = by_second.values.map { |v| v[0] }
    @moving_hrs = by_second.values.map { |v| v[1] }
    @altitudes = build_altitude_series(by_second, t0)
  end

  # Total elevation gain in metres. Prefers the device-reported total (FIT
  # session); falls back to summing the altitude series. nil without altitude.
  def total_ascent_m
    @device_ascent_m || (@altitudes && Activity.cumulative_ascent(@altitudes))
  end

  # Elevation gained over an elapsed-second index range [from, to) — used to
  # compare climbing before vs after a fatigue mark. nil without altitude.
  def ascent_between(from, to)
    return nil unless @altitudes

    Activity.cumulative_ascent(@altitudes[from...to])
  end

  # Cumulative ascent with hysteresis: only bank a climb once it clears the
  # noise threshold above the running low point, so GPS jitter isn't counted.
  def self.cumulative_ascent(alts, threshold = ASCENT_THRESHOLD_M)
    clean = alts&.compact
    return nil if clean.nil? || clean.size < 2

    ascent = 0.0
    ref = clean.first
    clean.each do |a|
      if a - ref >= threshold
        ascent += a - ref
        ref = a
      elsif a < ref
        ref = a
      end
    end
    ascent.round
  end

  def duration_seconds
    @powers.size
  end

  def moving_seconds
    @moving_powers.size
  end

  def average_power
    @moving_powers.sum.to_f / @moving_powers.size
  end

  def normalised_power
    PowerSeries.normalised_power(@moving_powers)
  end

  private

  # 1Hz altitude aligned to elapsed seconds, gaps carried forward (and the
  # leading gap back-filled) so it lines up index-for-index with +powers+.
  # nil when the file carries no altitude at all.
  def build_altitude_series(by_second, t0)
    return nil if by_second.values.none? { |v| v[2] }

    span = by_second.keys.last - t0 + 1
    arr = Array.new(span)
    by_second.each { |ts, (_, _, alt)| arr[ts - t0] = alt if alt }
    last = arr.compact.first
    arr.map! { |v| v ? (last = v) : last }
  end
end
