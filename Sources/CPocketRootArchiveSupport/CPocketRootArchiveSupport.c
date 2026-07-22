#include "CPocketRootArchiveSupport.h"

#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>
#include <zlib.h>

static void pocketroot_set_error(
    char *buffer,
    size_t buffer_size,
    const char *message
) {
    if (buffer == NULL || buffer_size == 0) {
        return;
    }
    snprintf(buffer, buffer_size, "%s", message == NULL ? "Unknown archive error." : message);
}

int pocketroot_gzip_decompress(
    const char *source_path,
    const char *destination_path,
    uint64_t maximum_output_size,
    char *error_buffer,
    size_t error_buffer_size
) {
    if (source_path == NULL || destination_path == NULL || maximum_output_size == 0) {
        pocketroot_set_error(error_buffer, error_buffer_size, "Invalid gzip arguments.");
        return 1;
    }

    gzFile source = gzopen(source_path, "rb");
    if (source == NULL) {
        pocketroot_set_error(error_buffer, error_buffer_size, "Unable to open the gzip archive.");
        return 2;
    }

    int destination_fd = open(
        destination_path,
        O_WRONLY | O_CREAT | O_EXCL,
        S_IRUSR | S_IWUSR
    );
    if (destination_fd < 0) {
        pocketroot_set_error(error_buffer, error_buffer_size, strerror(errno));
        gzclose(source);
        return 3;
    }
    FILE *destination = fdopen(destination_fd, "wb");
    if (destination == NULL) {
        pocketroot_set_error(error_buffer, error_buffer_size, strerror(errno));
        close(destination_fd);
        unlink(destination_path);
        gzclose(source);
        return 3;
    }

    unsigned char buffer[64 * 1024];
    uint64_t output_size = 0;
    int result = 0;

    while (1) {
        int bytes_read = gzread(source, buffer, (unsigned int) sizeof(buffer));
        if (bytes_read < 0) {
            int zlib_error = Z_OK;
            const char *message = gzerror(source, &zlib_error);
            pocketroot_set_error(error_buffer, error_buffer_size, message);
            result = 4;
            break;
        }
        if (bytes_read == 0) {
            if (!gzeof(source)) {
                int zlib_error = Z_OK;
                const char *message = gzerror(source, &zlib_error);
                pocketroot_set_error(error_buffer, error_buffer_size, message);
                result = 4;
            }
            break;
        }

        if ((uint64_t) bytes_read > maximum_output_size ||
            output_size > maximum_output_size - (uint64_t) bytes_read) {
            pocketroot_set_error(
                error_buffer,
                error_buffer_size,
                "The expanded gzip stream exceeds the configured size limit."
            );
            result = 5;
            break;
        }

        if (fwrite(buffer, 1, (size_t) bytes_read, destination) != (size_t) bytes_read) {
            pocketroot_set_error(error_buffer, error_buffer_size, strerror(errno));
            result = 6;
            break;
        }
        output_size += (uint64_t) bytes_read;
    }

    if (fclose(destination) != 0 && result == 0) {
        pocketroot_set_error(error_buffer, error_buffer_size, strerror(errno));
        result = 7;
    }

    int gzip_close_result = gzclose(source);
    if (gzip_close_result != Z_OK && result == 0) {
        pocketroot_set_error(error_buffer, error_buffer_size, "The gzip stream did not close cleanly.");
        result = 8;
    }

    if (result != 0) {
        unlink(destination_path);
    }
    return result;
}
