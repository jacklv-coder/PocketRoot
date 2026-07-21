#ifndef CPOCKETROOT_ARCHIVE_SUPPORT_H
#define CPOCKETROOT_ARCHIVE_SUPPORT_H

#include <stddef.h>
#include <stdint.h>

/// Decompresses a gzip stream to a new file while enforcing an output limit.
/// Returns zero on success and writes a human-readable error otherwise.
int pocketroot_gzip_decompress(
    const char *source_path,
    const char *destination_path,
    uint64_t maximum_output_size,
    char *error_buffer,
    size_t error_buffer_size
);

#endif
