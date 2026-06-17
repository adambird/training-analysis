# Rolling-window power maths over a 1Hz power array.
module PowerSeries
  NP_SMOOTHING = 30 # seconds, per Coggan's normalised power definition

  module_function

  # Rolling mean for every window of +window+ seconds.
  # Returns an array where element i is the mean of powers[i, window],
  # computed in O(n) via prefix sums.
  def rolling_means(powers, window)
    return [] if powers.size < window

    prefix = [0]
    powers.each { |w| prefix << prefix.last + w }
    (0..powers.size - window).map do |i|
      (prefix[i + window] - prefix[i]).to_f / window
    end
  end

  # Normalised power of the whole array: 30s rolling average, raised to the
  # 4th power, averaged, 4th root.
  def normalised_power(powers)
    smoothed = powers.size >= NP_SMOOTHING ? rolling_means(powers, NP_SMOOTHING) : [powers.sum.to_f / powers.size]
    (smoothed.sum { |w| w**4 } / smoothed.size)**0.25
  end

  # Rolling NP for every window of +window+ seconds: the NP you held over
  # each window-length stretch. Uses prefix sums over the 4th powers of the
  # 30s-smoothed series.
  def rolling_normalised_powers(powers, window)
    return [] if powers.size < window || window < NP_SMOOTHING

    smoothed = rolling_means(powers, NP_SMOOTHING)
    span = window - NP_SMOOTHING + 1 # smoothed values fully inside the window
    prefix = [0.0]
    smoothed.each { |w| prefix << prefix.last + w**4 }
    (0..smoothed.size - span).map do |i|
      ((prefix[i + span] - prefix[i]) / span)**0.25
    end
  end

  Effort = Struct.new(:start_offset, :average_power, keyword_init: true)

  # Non-overlapping windows whose mean power meets +threshold+, scanned
  # greedily left to right. Answers "how many times in this ride did I hold
  # >= threshold W for window seconds?"
  def efforts_over(powers, window, threshold)
    means = rolling_means(powers, window)
    efforts = []
    i = 0
    while i < means.size
      if means[i] >= threshold
        # Slide forward to the local peak so the recorded effort reflects the
        # strongest alignment of the window, not the first qualifying one.
        i += 1 while i + 1 < means.size && means[i + 1] > means[i]
        efforts << Effort.new(start_offset: i, average_power: means[i])
        i += window # a sustained block above threshold counts once per window length
      else
        i += 1
      end
    end
    efforts
  end

  def best_mean(powers, window)
    rolling_means(powers, window).max
  end

  # Centered moving average of +window+ seconds (window/2 either side), same
  # length as the input. Smooths 1Hz power noise without shifting features.
  def centered_means(powers, window)
    prefix = [0]
    powers.each { |w| prefix << prefix.last + w }
    half = window / 2
    (0...powers.size).map do |i|
      a = [0, i - half].max
      b = [powers.size, i + half + 1].min
      (prefix[b] - prefix[a]).to_f / (b - a)
    end
  end

  # Best rolling mean for several window lengths at once, sharing one prefix
  # sum. Returns {window => best_watts_or_nil}.
  def best_means(powers, windows)
    prefix = [0]
    powers.each { |w| prefix << prefix.last + w }
    windows.to_h do |window|
      best = nil
      (0..powers.size - window).each do |i|
        mean = (prefix[i + window] - prefix[i]).to_f / window
        best = mean if best.nil? || mean > best
      end
      [window, best]
    end
  end

  # Index of the second at which cumulative work first reaches +kj+, or nil.
  def index_at_kj(powers, kj)
    target = kj * 1000
    total = 0
    powers.each_with_index do |w, i|
      total += w
      return i if total >= target
    end
    nil
  end

  def best_normalised(powers, window)
    rolling_normalised_powers(powers, window).max
  end
end
