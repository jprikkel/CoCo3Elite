#include "decb_bin_format.h"

// $FE00-$FEFF is reserved only while the temporary ROM-Pak loader runs.  It
// supplies a private stack and the final unmap/jump trampoline.  Rejecting
// overlap makes launch deterministic without adding a third CoCo RAM port.
static int range_overlaps(uint16_t address, uint16_t length,
                          uint16_t first, uint16_t last)
{
    uint32_t end;
    if (!length)
        return 0;
    end = (uint32_t)address + length - 1u;
    return address <= last && end >= first;
}

static int next_byte(decb_bin_read_byte_fn read_byte, void *context,
                     uint32_t file_size, uint32_t *offset, uint8_t *value)
{
    if (*offset >= file_size || read_byte(context, value))
        return DECB_BIN_TRUNCATED;
    ++*offset;
    return DECB_BIN_OK;
}

int decb_bin_validate(decb_bin_read_byte_fn read_byte, void *context,
                      uint32_t file_size, struct decb_bin_info *info)
{
    uint32_t offset = 0;
    uint8_t type, high, low, value;

    info->execution_address = 0;
    info->data_bytes = 0;
    info->stream_bytes = 0;
    info->data_records = 0;

    for (;;) {
        uint16_t length, address;
        int result;

        if ((result = next_byte(read_byte, context, file_size, &offset, &type)) ||
            (result = next_byte(read_byte, context, file_size, &offset, &high)) ||
            (result = next_byte(read_byte, context, file_size, &offset, &low)))
            return result;
        length = ((uint16_t)high << 8) | low;
        if ((result = next_byte(read_byte, context, file_size, &offset, &high)) ||
            (result = next_byte(read_byte, context, file_size, &offset, &low)))
            return result;
        address = ((uint16_t)high << 8) | low;

        if (type == 0x00u) {
            uint32_t end = (uint32_t)address + length;
            if (end > 0x10000u)
                return DECB_BIN_ADDRESS_WRAP;
            // LOADM files may intentionally initialize CoCo hardware (for
            // example MEMT2023 writes GIME register $FFA2).  Protect only the
            // temporary loader mailbox rather than rejecting the full I/O
            // page as the first implementation did.
            if (range_overlaps(address, length, 0xff62u, 0xff64u))
                return DECB_BIN_IO_OVERLAP;
            if (range_overlaps(address, length, 0xfe00u, 0xfeffu))
                return DECB_BIN_LOADER_OVERLAP;
            if ((uint32_t)length > file_size - offset)
                return DECB_BIN_BAD_LENGTH;
            for (uint16_t n = 0; n < length; ++n)
                if ((result = next_byte(read_byte, context, file_size,
                                        &offset, &value)))
                    return result;
            ++info->data_records;
            info->data_bytes += length;
            continue;
        }

        // Disk BASIC treats any nonzero record marker as the postamble and
        // ignores its two length/dummy bytes.  SAVEM writes $ff,0,0, but some
        // commercial loaders (including Zenix) deliberately leave a nonzero
        // dummy value there.  Require the conventional $ff marker while
        // matching LOADM's handling of the following two bytes.
        if (type != 0xffu)
            return DECB_BIN_BAD_RECORD;
        if (!info->data_records)
            return DECB_BIN_MISSING_DATA;
        if (address >= 0xff62u && address <= 0xff64u)
            return DECB_BIN_IO_OVERLAP;
        if (address >= 0xfe00u && address <= 0xfeffu)
            return DECB_BIN_LOADER_OVERLAP;
        info->execution_address = address;
        // Disk BASIC stops at the execution postamble.  Many archived BINs
        // retain zero, $1A, or stale granule padding after it, so stream only
        // this validated prefix and ignore the physical-file tail.
        info->stream_bytes = offset;
        return DECB_BIN_OK;
    }
}
