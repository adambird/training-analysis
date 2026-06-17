require_relative 'power_series'

# Discovers interval sessions from a power trace and classifies them by rep
# length (40/20, ~1min, ~2min hill reps, ~5min, …). There is no workout label
# in the exported files (the name lives in Zwift/TrainingPeaks), and the
# Zwift target_power field is present but unpopulated, so detection is purely
# by shape: clusters of efforts that are consistent in duration and power and
# close together in time. This finds outdoor sets (e.g. 2-min hill reps with
# variable descent recoveries) as readily as indoor ERG work.
module Intervals
  DEFAULT_FTP = 250        # ~critical power; threshold anchor for "an effort"
  EFFORT_FRACTION = 0.95   # an effort sustains >= this * ftp
  REP_RANGE = (28..360)    # seconds; a single rep, 40s through ~6min
  SMOOTH = 5               # seconds, rides out 1Hz noise
  MIN_REPS = 4             # reps in a set
  MAX_RECOVERY = 240       # seconds; longer gap ends the set
  DUR_RATIO = (0.6..1.7)   # adjacent reps must be similar length
  DUR_CV_MAX = 0.35        # a set's rep durations must be this consistent
  RAMP_FRACTION = 0.85     # leading reps below this * set-median are warm-up

  Set = Struct.new(:rep_watts, :rep_seconds, :recovery_seconds, keyword_init: true) do
    def avg = (rep_watts.sum.to_f / rep_watts.size).round
    def size = rep_watts.size
  end

  Session = Struct.new(:start_time, :sets, :structured, keyword_init: true) do
    def reps = sets.flat_map(&:rep_watts)
    def rep_count = reps.size
    def set_count = sets.size
    def mean_w = (reps.sum.to_f / reps.size).round
    def best_w = reps.max
    def set_avgs = sets.map(&:avg)

    # Power change from start to end of the session: mean of the last third of
    # reps minus the first third. Positive = finished stronger, negative =
    # faded. Defined for single- and multi-set sessions alike; for evenly-split
    # multi-set sessions the thirds line up with first/last set.
    def fade_w
      r = reps
      return nil if r.size < 4

      n = [r.size / 3, 1].max
      ((r.last(n).sum.to_f / n) - (r.first(n).sum.to_f / n)).round
    end

    def rep_seconds = Intervals.median(sets.flat_map(&:rep_seconds)).round
    def recovery_seconds = Intervals.median(sets.map(&:recovery_seconds).compact)&.round

    # Classification by rep length, with 40/20 as the short-rep/short-recovery
    # special case.
    def type
      r = rep_seconds
      return '40/20' if (35..50).cover?(r) && recovery_seconds && (12..30).cover?(recovery_seconds)
      return "#{(r / 10.0).round * 10}s reps" if r < 75

      "#{(r / 60.0).round}min reps"
    end
  end

  module_function

  # Returns a Session (one ride's interval work, sets classified to a single
  # dominant type), or nil if nothing qualifies.
  def detect(activity, ftp: DEFAULT_FTP)
    sets = find_sets(activity.powers, ftp)
    return nil if sets.empty?

    # Keep only the sets of the most-repped type, so a session has one type.
    by_type = sets.group_by { |s| set_type(s) }
    sets = by_type.max_by { |_, ss| ss.sum(&:size) }.last
    return nil if sets.sum(&:size) < MIN_REPS

    Session.new(
      start_time: activity.start_time,
      sets: sets,
      structured: File.basename(activity.path).start_with?('zwift-activity')
    )
  end

  def find_sets(powers, ftp)
    return [] if powers.size < 480

    smoothed = PowerSeries.centered_means(powers, SMOOTH)
    threshold = ftp * EFFORT_FRACTION

    efforts = segment_efforts(powers, smoothed, threshold)
    cluster(efforts).filter_map { |group| build_set(group) }
  end

  # Runs above threshold lasting a rep's worth of seconds, with trimmed-centre
  # mean power and the recovery gap that follows each.
  def segment_efforts(powers, smoothed, threshold)
    efforts = []
    start = nil
    smoothed.each_index do |i|
      above = smoothed[i] >= threshold
      if above && start.nil?
        start = i
      elsif !above && start
        len = i - start
        efforts << { start: start, dur: len, w: rep_power(powers, start, len) } if REP_RANGE.cover?(len)
        start = nil
      end
    end
    efforts
  end

  # Group consecutive efforts into candidate sets by proximity and similar
  # duration; the consistency/cleanup happens in build_set.
  def cluster(efforts)
    groups = []
    current = []
    efforts.each do |e|
      if current.empty?
        current << e
      else
        prev = current.last
        gap = e[:start] - (prev[:start] + prev[:dur])
        similar = DUR_RATIO.cover?(e[:dur].to_f / prev[:dur])
        close = gap <= [prev[:dur] * 3, MAX_RECOVERY].max
        if similar && close
          current << e
        else
          groups << current
          current = [e]
        end
      end
    end
    groups << current
    groups
  end

  # Clean a candidate group into a Set, or nil if it doesn't qualify: drop
  # leading warm-up ramp reps, require enough consistent reps.
  def build_set(group)
    return nil if group.size < MIN_REPS

    median_w = median(group.map { |e| e[:w] })
    group = group.drop_while { |e| e[:w] < median_w * RAMP_FRACTION }
    return nil if group.size < MIN_REPS

    durations = group.map { |e| e[:dur] }
    return nil if cv(durations) > DUR_CV_MAX

    recoveries = group.each_cons(2).map { |a, b| b[:start] - (a[:start] + a[:dur]) }
    Set.new(
      rep_watts: group.map { |e| e[:w] },
      rep_seconds: durations,
      recovery_seconds: recoveries.empty? ? nil : median(recoveries)
    )
  end

  # Mean power over the effort, trimming a few seconds each end so ramp in/out
  # and the smoothing boundary don't dilute the figure.
  def rep_power(powers, start, len)
    trim = [5, len / 4].min
    core = powers[start + trim, len - 2 * trim]
    (core.sum.to_f / core.size).round
  end

  def set_type(set)
    Session.new(start_time: nil, sets: [set], structured: false).type
  end

  def median(values)
    return nil if values.empty?

    sorted = values.sort
    mid = sorted.size / 2
    sorted.size.odd? ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2.0
  end

  def cv(values)
    mean = values.sum.to_f / values.size
    return 0.0 if mean.zero?

    Math.sqrt(values.sum { |x| (x - mean)**2 } / values.size) / mean
  end
end
