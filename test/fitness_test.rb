require 'minitest/autorun'
require_relative '../lib/fitness'
require_relative '../lib/power_series'

class FitnessTest < Minitest::Test
  FakeActivity = Struct.new(:powers, :moving_powers, :moving_hrs, :start_time, :duration_seconds) do
    def average_power = moving_powers.sum.to_f / moving_powers.size
    def normalised_power = PowerSeries.normalised_power(moving_powers)
  end

  def test_cp_fit_recovers_known_model
    # Perfect P(t) = CP + W'/t data: CP=250W, W'=20kJ
    points = [180, 300, 600, 1200].map { |t| [t, 250.0 + 20_000.0 / t] }
    fit = Fitness.cp_fit(points)
    assert_in_delta 250.0, fit[:cp], 0.1
    assert_in_delta 20.0, fit[:w_prime_kj], 0.1
  end

  def test_cp_fit_rejects_sparse_or_narrow_points
    assert_nil Fitness.cp_fit([[180, 350], [300, 320]]) # too few
    assert_nil Fitness.cp_fit([[180, 350], [200, 345], [240, 338]]) # < 3x span
    assert_nil Fitness.cp_fit([[180, nil], [300, nil], [1200, nil]])
  end

  def test_best_means_matches_single_window_calc
    powers = Array.new(900) { |i| 150 + (i % 100) }
    multi = PowerSeries.best_means(powers, [60, 300])
    assert_equal PowerSeries.best_mean(powers, 60), multi[60]
    assert_equal PowerSeries.best_mean(powers, 300), multi[300]
    assert_nil PowerSeries.best_means(powers, [1200])[1200] # longer than ride
  end

  def test_early_punch_only_sees_first_30_minutes
    # 350W surge at minute 10 (inside window), 400W surge at minute 50 (outside)
    powers = Array.new(3600, 150)
    (600...660).each { |i| powers[i] = 350 }
    (3000...3060).each { |i| powers[i] = 400 }
    activity = FakeActivity.new(powers, powers, Array.new(powers.size), Time.now, powers.size)
    m = Fitness.analyse_ride(activity)
    assert_equal 350.0, m.early[60]
    assert_equal 400.0, m.mmp[60] # whole-ride best still sees the later surge

    short = FakeActivity.new(Array.new(900, 200), Array.new(900, 200), Array.new(900), Time.now, 900)
    assert_nil Fitness.analyse_ride(short).early # under 30 min: no early metric
  end

  def test_median
    assert_nil Fitness.median([])
    assert_equal 3, Fitness.median([5, 1, 3])
    assert_equal 2.5, Fitness.median([4, 1, 2, 3])
  end

  def test_index_at_kj
    powers = Array.new(1000, 200) # 200 J/s -> 100 kJ at second 499 (0-indexed)
    assert_equal 499, PowerSeries.index_at_kj(powers, 100)
    assert_nil PowerSeries.index_at_kj(powers, 500)
  end

  def test_durability_detects_fade
    # 250W until 1500 kJ (~6000s), then 200W with one 220W 5-min surge
    powers = Array.new(6000, 250) + Array.new(3000, 200)
    (7000...7300).each { |i| powers[i] = 220 }
    activity = FakeActivity.new(powers, powers, Array.new(powers.size), Time.now, powers.size)
    m = Fitness.analyse_ride(activity)
    assert_in_delta 250.0, m.durability[300][:fresh], 0.5
    assert_in_delta 220.0, m.durability[300][:after][1500], 0.5
    assert_in_delta 220.0, m.durability[180][:after][1500], 0.5 # surge is 5 min long
    assert_nil m.durability[300][:after][2500] # ride ends before 2500 kJ
    assert_equal 2106, m.work_kj # 6000s*250 + 3000s*200 + 300s*20 extra
  end

  def test_aerobic_efficiency_steady_ride
    # 2h at steady 200W, HR 130 first half, 140 second half -> EF ~ 200/135, drift ~7%
    powers = Array.new(7200, 200)
    hrs = Array.new(3600, 130) + Array.new(3600, 140)
    activity = FakeActivity.new(powers, powers, hrs, Time.now, powers.size)
    ef, drift, steady = Fitness.aerobic_efficiency(activity)
    assert steady
    assert_in_delta 200.0 / 135, ef, 0.01
    assert_in_delta 7.1, drift, 0.2
  end

  def test_aerobic_efficiency_rejects_spiky_or_hr_less_rides
    spiky = Array.new(7200) { |i| (i / 60).even? ? 100 : 400 }
    activity = FakeActivity.new(spiky, spiky, Array.new(7200, 140), Time.now, 7200)
    assert_equal false, Fitness.aerobic_efficiency(activity)[2]

    no_hr = FakeActivity.new(Array.new(7200, 200), Array.new(7200, 200), Array.new(7200), Time.now, 7200)
    assert_equal false, Fitness.aerobic_efficiency(no_hr)[2]
  end
end
