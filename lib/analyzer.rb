require 'csv'
require_relative 'activity'
require_relative 'power_series'

# Runs the per-ride analysis across a directory of workout files and
# aggregates the results into a monthly trend.
class Analyzer
  RideResult = Struct.new(
    :activity, :window_results,
    keyword_init: true
  )

  WindowResult = Struct.new(
    :window, :threshold, :best_mean, :efforts,
    keyword_init: true
  ) do
    def effort_count = efforts.size

    def mean_effort_power
      return nil if efforts.empty?

      efforts.sum(&:average_power) / efforts.size
    end
  end

  # windows: hash of {seconds => threshold_watts}
  def initialize(dir:, min_duration_minutes:, windows:)
    @dir = dir
    @min_duration = min_duration_minutes * 60
    @windows = windows
  end

  def results
    @results ||= workout_files.filter_map do |path|
      activity = Activity.load(path)
      next unless activity && activity.duration_seconds >= @min_duration

      RideResult.new(activity: activity, window_results: analyse(activity))
    end.uniq { |r| [r.activity.start_time, r.activity.duration_seconds] } # same ride exported twice
      .sort_by { |r| r.activity.start_time }
  end

  def write_csv(io)
    # Generation parameters, so consumers (bin/chart) don't have to infer them
    io.puts "# min_duration_min=#{@min_duration / 60}"
    csv = CSV.new(io)
    csv << ['date', 'file', 'duration_min', 'moving_min', 'avg_w', 'np_w'] +
           @windows.keys.flat_map { |w|
             m = w / 60
             ["best_#{m}min_avg_w",
              "efforts_#{m}min_over_#{@windows[w].round}w", "mean_effort_#{m}min_w"]
           }
    results.each do |r|
      a = r.activity
      csv << [a.start_time.strftime('%Y-%m-%d %H:%M'), File.basename(a.path),
              (a.duration_seconds / 60.0).round(1), (a.moving_seconds / 60.0).round(1),
              a.average_power.round(1), a.normalised_power.round(1)] +
             r.window_results.flat_map { |wr|
               [wr.best_mean&.round(1), wr.effort_count, wr.mean_effort_power&.round(1)]
             }
    end
  end

  # Whole-ride normalised power by month:
  # { 'YYYY-MM' => {rides:, mean_np_w:, best_np_w:} }
  def monthly_np_summary
    results.group_by { |r| r.activity.start_time.strftime('%Y-%m') }
           .transform_values do |rides|
      nps = rides.map { |r| r.activity.normalised_power }
      { rides: rides.size, mean_np_w: nps.sum / nps.size, best_np_w: nps.max }
    end.sort.to_h
  end

  # {window_seconds => { 'YYYY-MM' => {rides:, efforts:, ...} }}
  def monthly_summary
    @windows.keys.to_h do |window|
      months = results.group_by { |r| r.activity.start_time.strftime('%Y-%m') }
      [window, months.transform_values do |rides|
        wrs = rides.map { |r| r.window_results.find { |wr| wr.window == window } }
        efforts = wrs.flat_map(&:efforts)
        hours = rides.sum { |r| r.activity.duration_seconds } / 3600.0
        {
          rides: rides.size,
          efforts: efforts.size,
          efforts_per_ride: efforts.size.to_f / rides.size,
          efforts_per_hour: efforts.size / hours,
          mean_effort_w: efforts.empty? ? nil : efforts.sum(&:average_power) / efforts.size,
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

  def analyse(activity)
    @windows.map do |window, threshold|
      WindowResult.new(
        window: window,
        threshold: threshold,
        best_mean: PowerSeries.best_mean(activity.powers, window),
        efforts: PowerSeries.efforts_over(activity.powers, window, threshold)
      )
    end
  end
end
