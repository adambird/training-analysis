# Minimal FIT decoder that extracts (timestamp, power) samples from
# record messages (global message 20). Written in-house because fit4ruby
# crashes on Zwift-generated files (blank developer field names, missing
# developer_data_id messages).
#
# FIT reference: https://developer.garmin.com/fit/protocol/
module FitParser
  FIT_EPOCH = Time.utc(1989, 12, 31).to_i
  RECORD_MSG = 20
  SESSION_MSG = 18
  FIELD_TIMESTAMP = 253
  FIELD_POWER = 7
  FIELD_HEART_RATE = 3
  FIELD_SPORT = 5             # session message; also distance in record messages
  FIELD_TOTAL_DISTANCE = 9    # session message
  FIELD_ALTITUDE = 2          # record message (uint16, scale 5, offset 500)
  FIELD_ENHANCED_ALTITUDE = 78 # record message (uint32, scale 5, offset 500)
  FIELD_TOTAL_ASCENT = 22     # session message (uint16, metres)
  ALT_SCALE = 5.0
  ALT_OFFSET = 500.0
  SPORT_CYCLING = 2

  module_function

  # Returns {samples:, cycling:, distance_m:, total_ascent_m:} where samples is
  # an array of [epoch_seconds, watts, bpm_or_nil, altitude_m_or_nil] tuples and
  # cycling is true/false, or nil when the file carries no sport (Garmin watches
  # record running power in the same power field, so sport matters).
  def parse(data)
    data = data.dup.force_encoding(Encoding::BINARY)
    samples = []
    state = { sport: nil }
    pos = 0
    # A .fit file may contain several chained FIT entities.
    while pos < data.bytesize - 2
      header_size = data.getbyte(pos)
      break if header_size.nil? || header_size < 12
      data_size = data[pos + 4, 4].unpack1('V')
      break unless data[pos + 8, 4] == '.FIT'

      body_start = pos + header_size
      parse_entity(data, body_start, data_size, samples, state)
      pos = body_start + data_size + 2 # trailing CRC
    end
    # Distance is stored scaled by 100 (so raw / 100 = metres). Prefer the
    # session total; fall back to the running record distance for files (e.g.
    # some Zwift exports) that omit the session message.
    raw_distance = state[:session_dist] || state[:record_dist]
    {
      samples: samples,
      cycling: state[:sport] && state[:sport] == SPORT_CYCLING,
      distance_m: raw_distance && raw_distance / 100.0,
      total_ascent_m: state[:total_ascent]
    }
  end

  def parse_entity(data, start, size, samples, state)
    pos = start
    fin = start + size
    definitions = {}
    last_ts = nil

    while pos < fin
      header = data.getbyte(pos)
      pos += 1

      if header & 0x80 != 0 # compressed timestamp data message
        definition = definitions[(header >> 5) & 0x3] or break
        offset = header & 0x1F
        if last_ts
          last5 = last_ts & 0x1F
          last_ts = last_ts - last5 + offset + (offset >= last5 ? 0 : 0x20)
        end
        pos = read_data_message(data, pos, definition, samples, last_ts, state) { |ts| last_ts = ts if ts }
      elsif header & 0x40 != 0 # definition message
        definitions[header & 0xF] = read_definition(data, pos, dev_fields: header & 0x20 != 0) do |new_pos|
          pos = new_pos
        end
      else # data message
        definition = definitions[header & 0xF] or break
        pos = read_data_message(data, pos, definition, samples, last_ts, state) { |ts| last_ts = ts if ts }
      end
    end
  end

  def read_definition(data, pos, dev_fields:)
    pos += 1 # reserved byte
    big_endian = data.getbyte(pos) == 1
    pos += 1
    global_msg = data[pos, 2].unpack1(big_endian ? 'n' : 'v')
    pos += 2
    field_count = data.getbyte(pos)
    pos += 1
    fields = field_count.times.map do
      field = [data.getbyte(pos), data.getbyte(pos + 1)] # [field_num, size]
      pos += 3 # third byte is base type, not needed
      field
    end
    dev_bytes = 0
    if dev_fields
      dev_count = data.getbyte(pos)
      pos += 1
      dev_count.times do
        dev_bytes += data.getbyte(pos + 1)
        pos += 3
      end
    end
    yield pos
    { global_msg: global_msg, fields: fields, big_endian: big_endian, dev_bytes: dev_bytes }
  end

  # Reads one data message. Yields the timestamp (if present) so the caller
  # can track it for compressed timestamp headers; appends a sample when the
  # message is a record with power. Returns the new position.
  def read_data_message(data, pos, definition, samples, last_ts, state)
    is_record = definition[:global_msg] == RECORD_MSG
    is_session = definition[:global_msg] == SESSION_MSG
    big_endian = definition[:big_endian]
    ts = nil
    power = nil
    heart_rate = nil
    altitude = nil
    enhanced_altitude = nil

    definition[:fields].each do |field_num, size|
      case field_num
      when FIELD_SPORT # field 5: sport on the session, distance on a record
        if is_session && size == 1
          state[:sport] = data.getbyte(pos)
        elsif is_record && size == 4
          value = data[pos, 4].unpack1(big_endian ? 'N' : 'V')
          state[:record_dist] = value if value != 0xFFFFFFFF
        end
      when FIELD_TOTAL_DISTANCE
        if is_session && size == 4
          value = data[pos, 4].unpack1(big_endian ? 'N' : 'V')
          state[:session_dist] = value if value != 0xFFFFFFFF
        end
      when FIELD_TOTAL_ASCENT
        if is_session && size == 2
          value = data[pos, 2].unpack1(big_endian ? 'n' : 'v')
          state[:total_ascent] = value if value != 0xFFFF
        end
      when FIELD_ALTITUDE
        if is_record && size == 2
          value = data[pos, 2].unpack1(big_endian ? 'n' : 'v')
          altitude = value / ALT_SCALE - ALT_OFFSET if value != 0xFFFF
        end
      when FIELD_ENHANCED_ALTITUDE
        if is_record && size == 4
          value = data[pos, 4].unpack1(big_endian ? 'N' : 'V')
          enhanced_altitude = value / ALT_SCALE - ALT_OFFSET if value != 0xFFFFFFFF
        end
      when FIELD_TIMESTAMP
        if size == 4
          value = data[pos, 4].unpack1(big_endian ? 'N' : 'V')
          ts = value if value != 0xFFFFFFFF
        end
      when FIELD_POWER
        if is_record && size == 2
          value = data[pos, 2].unpack1(big_endian ? 'n' : 'v')
          power = value if value != 0xFFFF
        end
      when FIELD_HEART_RATE
        if is_record && size == 1
          value = data.getbyte(pos)
          heart_rate = value if value != 0xFF && value.positive?
        end
      end
      pos += size
    end

    yield ts
    effective_ts = ts || last_ts
    if is_record && effective_ts && power
      samples << [FIT_EPOCH + effective_ts, power, heart_rate, enhanced_altitude || altitude]
    end
    pos + definition[:dev_bytes]
  end
end
