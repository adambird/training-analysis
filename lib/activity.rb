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
  attr_reader :path, :start_time, :powers, :moving_powers, :moving_hrs

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

    new(path, parsed[:samples])
  end

  def self.read_raw(path)
    if path.end_with?('.gz')
      Zlib::GzipReader.open(path, &:read).force_encoding(Encoding::BINARY)
    else
      File.binread(path)
    end
  end

  def initialize(path, samples)
    @path = path
    by_second = {} # last sample wins per second
    samples.sort_by(&:first).each { |ts, watts, bpm| by_second[ts] = [watts, bpm] }
    t0 = by_second.keys.first
    @start_time = Time.at(t0).utc

    @powers = Array.new(by_second.keys.last - t0 + 1, 0)
    by_second.each { |ts, (watts, _)| @powers[ts - t0] = watts }
    @moving_powers = by_second.values.map(&:first)
    @moving_hrs = by_second.values.map(&:last)
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
end
