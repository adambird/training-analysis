---
name: fit-manipulation
description: >-
  Parse and manipulate FIT files (Garmin/Wahoo cycling data format). Read FIT
  files using lib/fit_parser.rb, or modify timestamps and other fields by
  parsing the binary FIT protocol directly. Use when fixing corrupted FIT files,
  adjusting timestamps, or extracting/modifying FIT data.
---

# FIT file parsing and manipulation

FIT (Flexible and Interoperable Data Transfer) is the binary format used by
Garmin, Wahoo, and other fitness devices. This repo has tools for both reading
and writing FIT files.

## Reading FIT files

**`lib/fit_parser.rb`** is a minimal, in-house FIT decoder that extracts power,
heart rate, and altitude data from record messages. It was written to handle
Zwift-generated files that crash the `fit4ruby` gem.

```ruby
require './lib/fit_parser'

data = File.binread('activity.fit')
result = FitParser.parse(data)

# Returns:
# {
#   samples: [[epoch_seconds, watts, bpm_or_nil, altitude_m_or_nil], ...],
#   cycling: true/false,
#   distance_m: 8451.5,
#   total_ascent_m: 123
# }
```

**Key implementation details:**
- FIT epoch is 1989-12-31 00:00:00 UTC (timestamps are uint32 seconds since then)
- Handles compressed timestamp headers (5-bit second offsets, bit 7 set)
- Supports chained FIT entities in a single file
- Field 253 is the timestamp field in record/event/device_info messages
- Global message 20 = record, 18 = session
- Altitude stored scaled by 5 with offset 500 (both field 2 and enhanced field 78)

## Modifying FIT files

To modify FIT files (e.g., fix corrupted timestamps), parse the binary format
directly:

### FIT file structure

```
[Header: 12 or 14 bytes]
  - byte 0: header size (12 or 14)
  - bytes 4-7: data size (uint32 little-endian)
  - bytes 8-11: ".FIT"
  - bytes 12-13: header CRC (if 14-byte header)

[Data messages]
  Definition messages define the structure
  Data messages contain the actual values

[CRC: 2 bytes at end]
```

### Message header byte format

```
Definition message: 0x40 bit set
  - Local message type: bits 0-3
  - Has developer fields: 0x20 bit set

Data message: 0x40 bit clear, 0x80 bit clear
  - Local message type: bits 0-3

Compressed timestamp: 0x80 bit set
  - Local message type: bits 5-6
  - Time offset: bits 0-4 (0-31 seconds)
```

### Python example: Adjusting all timestamps

```python
import struct

def fix_fit_timestamps(input_file, output_file, offset_seconds):
    with open(input_file, 'rb') as f:
        data = bytearray(f.read())

    header_size = data[0]
    data_size = struct.unpack('<I', data[4:8])[0]
    pos = header_size
    end_pos = header_size + data_size

    definitions = {}

    while pos < end_pos - 1:
        header_byte = data[pos]
        pos += 1

        if header_byte & 0x40:  # Definition message
            local_msg_type = header_byte & 0xF
            pos += 1  # reserved byte
            arch = data[pos]  # 0 = little-endian
            pos += 1
            global_msg = struct.unpack_from('<H' if arch == 0 else '>H', data, pos)[0]
            pos += 2
            num_fields = data[pos]
            pos += 1

            fields = []
            for _ in range(num_fields):
                field_num = data[pos]
                field_size = data[pos + 1]
                fields.append((field_num, field_size))
                pos += 3

            # Handle developer fields if present
            dev_bytes = 0
            if header_byte & 0x20:
                num_dev = data[pos]
                pos += 1
                for _ in range(num_dev):
                    dev_bytes += data[pos + 1]
                    pos += 3

            definitions[local_msg_type] = {
                'fields': fields,
                'arch': arch,
                'dev_bytes': dev_bytes,
                'global_msg': global_msg
            }

        elif header_byte & 0x80 == 0:  # Normal data message
            local_msg_type = header_byte & 0xF
            if local_msg_type in definitions:
                defn = definitions[local_msg_type]

                for field_num, field_size in defn['fields']:
                    # Timestamp fields:
                    # - Field 253: timestamp in record/event/device_info
                    # - Field 4: time_created in file_id (global msg 0)
                    is_timestamp = (field_num == 253) or \
                                   (field_num == 4 and defn['global_msg'] == 0)

                    if is_timestamp and field_size == 4:
                        fmt = '<I' if defn['arch'] == 0 else '>I'
                        old_ts = struct.unpack_from(fmt, data, pos)[0]
                        if old_ts != 0xFFFFFFFF and old_ts > 0:
                            new_ts = old_ts + offset_seconds
                            struct.pack_into(fmt, data, pos, new_ts)

                    pos += field_size
                pos += defn['dev_bytes']

        else:  # Compressed timestamp - skip data
            local_msg_type = (header_byte >> 5) & 0x3
            if local_msg_type in definitions:
                defn = definitions[local_msg_type]
                for _, field_size in defn['fields']:
                    pos += field_size
                pos += defn['dev_bytes']

    # Recalculate CRCs
    def calc_crc(data, start, end):
        crc_table = [
            0x0000, 0xCC01, 0xD801, 0x1400, 0xF001, 0x3C00, 0x2800, 0xE401,
            0xA001, 0x6C00, 0x7800, 0xB401, 0x5000, 0x9C01, 0x8801, 0x4400
        ]
        crc = 0
        for byte in data[start:end]:
            tmp = crc_table[crc & 0xF]
            crc = (crc >> 4) & 0x0FFF
            crc ^= tmp ^ crc_table[byte & 0xF]
            tmp = crc_table[crc & 0xF]
            crc = (crc >> 4) & 0x0FFF
            crc ^= tmp ^ crc_table[(byte >> 4) & 0xF]
        return crc

    # Update header CRC if 14-byte header
    if header_size == 14:
        hcrc = calc_crc(data, 0, 12)
        struct.pack_into('<H', data, 12, hcrc)

    # Update file CRC (last 2 bytes)
    fcrc = calc_crc(data, 0, len(data) - 2)
    struct.pack_into('<H', data, len(data) - 2, fcrc)

    with open(output_file, 'wb') as f:
        f.write(data)
```

## Important FIT protocol constants

- **FIT epoch:** 1989-12-31 00:00:00 UTC
- **Timestamps:** uint32 seconds since FIT epoch
- **Invalid values:** 0xFF for uint8, 0xFFFF for uint16, 0xFFFFFFFF for uint32
- **Endianness:** Stored in architecture byte of definition message (0 = little)

## Common global message numbers

- 0: file_id (field 4 = time_created)
- 18: session (field 5 = sport, field 9 = total_distance, field 22 = total_ascent)
- 20: record (field 253 = timestamp, field 7 = power, field 3 = heart_rate,
            field 2/78 = altitude, field 5 = distance)
- 21: event
- 23: device_info

## Python libraries available

- **fitparse:** Read-only FIT parser, good for inspection
- **garmin-fit-sdk:** Official SDK with encoder/decoder, but complex API requiring
  message number metadata
- Neither library makes timestamp manipulation straightforward — binary parsing
  is more reliable for bulk timestamp adjustments

## When to use which approach

- **Reading data for analysis:** Use `lib/fit_parser.rb` (fast, reliable)
- **Inspecting FIT structure:** Use Python `fitparse` or `garmin-fit-sdk`
- **Modifying timestamps or fields:** Use binary parsing (Python example above)
- **Creating new FIT files:** Use `garmin-fit-sdk.Encoder` with full message
  definitions (complex, see official FIT SDK docs)
