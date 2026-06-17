require 'csv'
require_relative 'activity'
require_relative 'power_series'

# Runs the per-ride effort analysis across a directory of workout files.
#
# An "effort" at a duration is power held at or above a threshold that is a
# percentage of the rider's *own best* mean-maximal power at that duration over
# a trailing window — not an arbitrary fixed wattage. This keeps "a hard 5-min
# effort" meaning the same thing as fitness changes, and makes the count a
# signal of how often near-best efforts are produced rather than a proxy for
# fitness (the power curve in bin/fitness is the threshold-free progression
# metric).
class Analyzer
  RideResult = Struct.new(:activity, :window_results, keyword_init: true)

  WindowResult = Struct.new(:window, :threshold, :best_mean, :efforts, keyword_init: true) do
    def effort_count = efforts.size

    def mean_effort_power
      return nil if efforts.empty?

      efforts.sum(&:average_power) / efforts.size
    end
  end

  # windows: array of durations in seconds
  # effort_pct: fraction of rolling-best that counts as an effort (e.g. 0.85)
  # ref_window_days: trailing window over which "best" is taken
  def initialize(dir:, min_duration_minutes:, windows:, effort_pct: 0.85, ref_window_days: 90)
    @dir = dir
    @min_duration = min_duration_minutes * 60
    @windows = windows
    @effort_pct = effort_pct
    @ref_window_days = ref_window_days
  end

  attr_reader :effort_pct, :ref_window_days

  # Every ride with power, with its best mean-maximal power per window. The
  # reference for rolling-best is drawn from all rides (a short VO2 session can
  # set the best 1-min even if it's below the duration cutoff for counting).
  def all_rides
    @all_rides ||= workout_files.filter_map do |path|
      activity = Activity.load(path)
      next unless activity

      { activity: activity, date: activity.start_time,
        mmp: PowerSeries.best_means(activity.powers, @windows) }
    end.uniq { |r| [r[:date], r[:activity].duration_seconds] }
       .sort_by { |r| r[:date] }
  end

  def results
    @results ||= all_rides
                 .select { |r| r[:activity].duration_seconds >= @min_duration }
                 .map { |r| RideResult.new(activity: r[:activity], window_results: analyse(r)) }
  end

  def write_csv(io)
    io.puts "# min_duration_min=#{@min_duration / 60} effort_pct=#{(@effort_pct * 100).round} " \
            "ref_window_days=#{@ref_window_days}"
    csv = CSV.new(io)
    csv << ['date', 'file', 'duration_min', 'moving_min', 'avg_w', 'np_w'] +
           @windows.flat_map { |w|
             m = w / 60
             ["best_#{m}min_avg_w", "threshold_#{m}min_w", "efforts_#{m}min", "mean_effort_#{m}min_w"]
           }
    results.each do |r|
      a = r.activity
      csv << [a.start_time.strftime('%Y-%m-%d %H:%M'), File.basename(a.path),
              (a.duration_seconds / 60.0).round(1), (a.moving_seconds / 60.0).round(1),
              a.average_power.round(1), a.normalised_power.round(1)] +
             r.window_results.flat_map { |wr|
               [wr.best_mean&.round(1), wr.threshold&.round, wr.effort_count, wr.mean_effort_power&.round(1)]
             }
    end
  end

  # Whole-ride normalised power by month.
  def monthly_np_summary
    results.group_by { |r| r.activity.start_time.strftime('%Y-%m') }
           .transform_values do |rides|
      nps = rides.map { |r| r.activity.normalised_power }
      { rides: rides.size, mean_np_w: nps.sum / nps.size, best_np_w: nps.max }
    end.sort.to_h
  end

  # {window_seconds => { 'YYYY-MM' => {rides:, efforts:, ...} }}
  def monthly_summary
    @windows.to_h do |window|
      months = results.group_by { |r| r.activity.start_time.strftime('%Y-%m') }
      [window, months.transform_values do |rides|
        wrs = rides.map { |r| r.window_results.find { |wr| wr.window == window } }
        efforts = wrs.flat_map(&:efforts)
        hours = rides.sum { |r| r.activity.duration_seconds } / 3600.0
        thresholds = wrs.filter_map(&:threshold)
        {
          rides: rides.size,
          efforts: efforts.size,
          efforts_per_hour: efforts.size / hours,
          mean_effort_w: efforts.empty? ? nil : efforts.sum(&:average_power) / efforts.size,
          mean_threshold_w: thresholds.empty? ? nil : thresholds.sum / thresholds.size,
          best_w: wrs.filter_map(&:best_mean).max
        }
      end.sort.to_h]
    end
  end

  # Least-squares slope of [x, y] points; sign answers "up or down over time?".
  def self.trend_slope(points)
    return nil if points.size < 2

    n = points.size
    sx = points.sum { |x, _| x }
    sy = points.sum { |_, y| y }
    sxx = points.sum { |x, _| x * x }
    sxy = points.sum { |x, y| x * y }
    denom = n * sxx - sx * sx
    return nil if denom.zero?

    (n * sxy - sx * sy).to_f / denom
  end

  private

  def workout_files
    Dir.children(@dir)
       .select { |f| f =~ /\.(fit|tcx|gpx)(\.gz)?\z/i }
       .map { |f| File.join(@dir, f) }
       .sort
  end

  def analyse(ride)
    @windows.map do |window|
      ref = rolling_best(ride[:date], window)
      threshold = ref && (@effort_pct * ref)
      efforts = threshold ? PowerSeries.efforts_over(ride[:activity].powers, window, threshold) : []
      WindowResult.new(window: window, threshold: threshold,
                       best_mean: ride[:mmp][window], efforts: efforts)
    end
  end

  # Best mean-maximal power at +window+ over the trailing ref window up to and
  # including +date+ (so a breakthrough ride is measured against itself).
  def rolling_best(date, window)
    earliest = date - @ref_window_days * 86_400
    all_rides.filter_map { |r| r[:mmp][window] if r[:date] <= date && r[:date] >= earliest }.max
  end
end
