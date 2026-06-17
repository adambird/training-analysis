require 'minitest/autorun'
require_relative '../lib/intervals'

class IntervalsTest < Minitest::Test
  FakeActivity = Struct.new(:powers, :path, :start_time)

  # Builds a power trace: warmup, then `sets` blocks of `reps` efforts of
  # `on` seconds at `effort` W with `off`-second recoveries at 100W, separated
  # by `rest` seconds. Defaults describe a classic 40/20.
  def build(effort:, sets:, reps:, on: 40, off: 20, rest: 300, warmup: 600)
    p = Array.new(warmup, 150)
    sets.times do
      reps.times { p.concat(Array.new(on, effort)).concat(Array.new(off, 100)) }
      p.concat(Array.new(rest, 120))
    end
    p
  end

  def session(powers, path: 'zwift-activity-1.fit.gz', ftp: 250)
    Intervals.detect(FakeActivity.new(powers, path, Time.now), ftp: ftp)
  end

  def test_detects_classic_3x5
    s = session(build(effort: 350, sets: 3, reps: 5))
    refute_nil s
    assert_equal 3, s.set_count
    assert_equal 15, s.rep_count
    assert_in_delta 350, s.mean_w, 3
    assert_equal '40/20', s.type
  end

  def test_classifies_2min_hill_reps
    # 6 x 2-min efforts at 320W, 90s recoveries (outdoor hill-rep shape)
    s = session(build(effort: 320, sets: 1, reps: 6, on: 120, off: 90),
                path: 'garmin-gravel.fit.gz')
    refute_nil s
    assert_equal 6, s.rep_count
    assert_equal '2min reps', s.type
    refute s.structured
  end

  def test_classifies_5min_reps
    s = session(build(effort: 300, sets: 1, reps: 4, on: 300, off: 120))
    assert_equal '5min reps', s.type
  end

  def test_set_averages_and_fade
    # ascending: 300, 320, 340 -> positive fade (finished stronger)
    p = Array.new(600, 150)
    [300, 320, 340].each do |w|
      5.times { p.concat(Array.new(40, w)).concat(Array.new(20, 100)) }
      p.concat(Array.new(300, 120))
    end
    s = session(p)
    assert_equal [300, 320, 340], s.set_avgs
    assert_equal 40, s.fade_w
  end

  def test_single_set_session_still_has_fade
    # one set of 6 reps that fades 380 -> 320; thirds: last(380? no) ...
    p = Array.new(600, 150)
    [380, 378, 360, 350, 330, 320].each { |w| p.concat(Array.new(40, w)).concat(Array.new(20, 100)) }
    s = session(p)
    assert_equal 1, s.set_count
    refute_nil s.fade_w                 # defined despite single set
    assert_operator s.fade_w, :<, 0     # faded
  end

  def test_negative_fade_when_blowing_up
    p = Array.new(600, 150)
    [400, 360, 320].each do |w|
      4.times { p.concat(Array.new(40, w)).concat(Array.new(20, 100)) }
      p.concat(Array.new(300, 120))
    end
    assert_equal(-80, session(p).fade_w)
  end

  def test_ignores_steady_ride
    assert_nil session(Array.new(3600, 200))
  end

  def test_trims_leading_warmup_ramp
    # two ramp reps (260, 280) before the real 380W efforts — should be dropped
    p = Array.new(600, 150)
    [260, 280, 380, 382, 379, 381].each { |w| p.concat(Array.new(40, w)).concat(Array.new(20, 100)) }
    s = session(p)
    assert_equal 4, s.rep_count          # ramp reps trimmed
    assert_operator s.mean_w, :>, 375
  end

  def test_structured_flag_from_filename
    assert session(build(effort: 350, sets: 3, reps: 5), path: 'zwift-activity-9.fit.gz').structured
    refute session(build(effort: 350, sets: 3, reps: 5), path: 'garmin-outdoor.fit.gz').structured
  end

  def test_three_reps_is_not_a_session
    assert_nil session(build(effort: 350, sets: 1, reps: 3)) # 3 reps < MIN_REPS
    refute_nil session(build(effort: 350, sets: 1, reps: 4)) # 4 reps qualifies
  end
end
