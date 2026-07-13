require 'minitest/autorun'
require_relative '../lib/altitude'

class AltitudeTest < Minitest::Test
  def test_sea_level_is_full_power
    assert_in_delta 1.0, Altitude.power_factor(0), 0.001
    assert_in_delta 1.0, Altitude.power_factor(-50), 0.001
    assert_in_delta 1.0, Altitude.power_factor(nil), 0.001
  end

  # Table values are keyed in feet; check a couple land on the published points.
  def test_table_points_match_chart
    ft5000 = 5_000 * Altitude::M_PER_FT
    assert_in_delta 0.911, Altitude.power_factor(ft5000, model: :non_acclimatized), 0.001
    assert_in_delta 0.944, Altitude.power_factor(ft5000, model: :acclimatized), 0.001
    ft10000 = 10_000 * Altitude::M_PER_FT
    assert_in_delta 0.860, Altitude.power_factor(ft10000, model: :peronnet), 0.001
  end

  def test_interpolates_between_rows
    # halfway (in feet) between 4000 (93.2) and 5000 (91.1) non-acclimatized
    ft4500 = 4_500 * Altitude::M_PER_FT
    assert_in_delta (0.932 + 0.911) / 2, Altitude.power_factor(ft4500, model: :non_acclimatized), 0.001
  end

  def test_clamps_above_top_row
    assert_in_delta 0.704, Altitude.power_factor(20_000 * Altitude::M_PER_FT, model: :non_acclimatized), 0.001
  end

  def test_default_model_is_conservative
    m = 2_000 # ~6,562 ft
    default = Altitude.power_factor(m)
    accl = Altitude.power_factor(m, model: :acclimatized)
    assert default < accl, 'default (non-acclimatized) should read lower than acclimatized'
  end

  def test_sea_level_equivalent_scales_up
    m = 3_000 # thin air → observed power scales up to a larger sea-level number
    obs = 250.0
    eq = Altitude.sea_level_equivalent(obs, m)
    assert eq > obs
    assert_in_delta obs, eq * Altitude.power_factor(m), 0.001
    assert_nil Altitude.sea_level_equivalent(nil, m)
  end

  def test_median
    assert_equal 2, Altitude.median([1, 2, 3])
    assert_in_delta 2.5, Altitude.median([1, 2, 3, 4]), 0.001
    assert_nil Altitude.median([])
    assert_nil Altitude.median(nil)
    assert_equal 2, Altitude.median([nil, 1, 2, 3, nil]) # nils dropped
  end
end
