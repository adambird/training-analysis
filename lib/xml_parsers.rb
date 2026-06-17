require 'nokogiri'
require 'time'

# TCX and GPX both store power as an extension on per-point elements.
# Both parsers return {samples:, cycling:} where samples is an array of
# [epoch_seconds, watts, bpm_or_nil] triples and cycling is true/false, or
# nil when the file doesn't declare a sport.
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
      [Time.parse(time).to_i, watts.to_i, bpm&.positive? ? bpm : nil]
    end
    { samples: samples, cycling: sport && sport.casecmp('biking').zero? }
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
      [Time.parse(time).to_i, watts.to_i, bpm&.positive? ? bpm : nil]
    end
    # Strava writes the numeric type 1 for rides; others write words
    cycling = type && (type == '1' || type.downcase.match?(/cycl|bik|ride/)) ? true : type && false
    { samples: samples, cycling: cycling }
  end
end
