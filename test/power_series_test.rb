require 'minitest/autorun'
require_relative '../lib/power_series'

class PowerSeriesTest < Minitest::Test
  def surge_ride # 10 min at 200W with a single 60s surge at 350W
    powers = Array.new(600, 200)
    (120...180).each { |i| powers[i] = 350 }
    powers
  end

  def test_best_mean_finds_the_surge
    assert_equal 350.0, PowerSeries.best_mean(surge_ride, 60)
  end

  def test_single_surge_counts_once_at_peak_alignment
    efforts = PowerSeries.efforts_over(surge_ride, 60, 300)
    assert_equal 1, efforts.size
    assert_equal 120, efforts.first.start_offset
    assert_equal 350.0, efforts.first.average_power
  end

  def test_sustained_block_counts_once_per_window_length
    powers = Array.new(600, 200)
    (60...360).each { |i| powers[i] = 320 } # 5 min above threshold
    efforts = PowerSeries.efforts_over(powers, 60, 300)
    assert_equal 5, efforts.size
    assert(efforts.each_cons(2).all? { |a, b| b.start_offset - a.start_offset >= 60 })
  end

  def test_np_of_constant_power_is_that_power
    assert_in_delta 250.0, PowerSeries.normalised_power(Array.new(600, 250)), 0.001
  end

  def test_np_exceeds_average_for_variable_power
    powers = Array.new(600) { |i| (i / 30).even? ? 100 : 400 }
    assert_operator PowerSeries.normalised_power(powers), :>, 250.0
  end

  def test_rolling_np_at_least_best_mean_for_surge
    assert_operator PowerSeries.best_normalised(surge_ride, 60), :>=, 350.0
  end

  def test_short_ride_returns_no_windows
    assert_empty PowerSeries.rolling_means(Array.new(30, 200), 60)
    assert_empty PowerSeries.efforts_over(Array.new(30, 400), 60, 300)
  end
end
