require 'nokogiri'
require 'time'

# TCX and GPX both store power as an extension on per-point elements.
# Both parsers return {samples:, cycling:, distance_m:} where samples is an
# array of [epoch_seconds, watts, bpm_or_nil, altitude_m_or_nil] tuples and
# cycling is true/false, or nil when the file doesn't declare a sport.
module TcxParser
  module_function

  def parse(data)
    doc = Nokogiri::XML(data)
    doc.remove_namespaces!
    sport = doc.at_xpath('//Activity/@Sport')&.text
    samples = doc.xpath('//Trackpoint').filter_map do |tp|
      time = tp.at_xpath('Time')&.text
      watts = tp.at_xpath('.//Watts')&.text
      next unless time && watts

      bpm = tp.at_xpath('HeartRateBpm/Value')&.text&.to_i
      alt = tp.at_xpath('AltitudeMeters')&.text
      [Time.parse(time).to_i, watts.to_i, bpm&.positive? ? bpm : nil, alt&.to_f]
    end
    # DistanceMeters is cumulative, so the largest value is the ride total.
    dists = doc.xpath('//Trackpoint/DistanceMeters').map { |n| n.text.to_f }
    { samples: samples, cycling: sport && sport.casecmp('biking').zero?, distance_m: dists.max }
  end
end

module GpxParser
  module_function

  def parse(data)
    doc = Nokogiri::XML(data)
    doc.remove_namespaces!
    type = doc.at_xpath('//trk/type')&.text
    samples = doc.xpath('//trkpt').filter_map do |pt|
      time = pt.at_xpath('time')&.text
      # Strava uses <power>, Garmin's extension uses <PowerInWatts>
      watts = pt.at_xpath('.//power | .//PowerInWatts')&.text
      next unless time && watts

      bpm = pt.at_xpath('.//hr')&.text&.to_i
      ele = pt.at_xpath('ele')&.text
      [Time.parse(time).to_i, watts.to_i, bpm&.positive? ? bpm : nil, ele&.to_f]
    end
    # Strava writes the numeric type 1 for rides; others write words
    cycling = type && (type == '1' || type.downcase.match?(/cycl|bik|ride/)) ? true : type && false
    coords = doc.xpath('//trkpt').filter_map do |pt|
      lat = pt['lat']&.to_f
      lon = pt['lon']&.to_f
      [lat, lon] if lat && lon
    end
    { samples: samples, cycling: cycling, distance_m: haversine_total(coords) }
  end

  # Cumulative great-circle distance (metres) along a list of [lat, lon] points.
  def haversine_total(coords)
    return nil if coords.size < 2

    r = 6_371_000.0 # mean Earth radius, metres
    rad = ->(d) { d * Math::PI / 180 }
    coords.each_cons(2).sum do |(lat1, lon1), (lat2, lon2)|
      dlat = rad.(lat2 - lat1)
      dlon = rad.(lon2 - lon1)
      a = Math.sin(dlat / 2)**2 + Math.cos(rad.(lat1)) * Math.cos(rad.(lat2)) * Math.sin(dlon / 2)**2
      2 * r * Math.asin(Math.sqrt(a))
    end
  end
end
