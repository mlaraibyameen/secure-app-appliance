#define _GNU_SOURCE

#include <ctype.h>
#include <errno.h>
#include <fcntl.h>
#include <linux/memfd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

#define MASTER_BYTES 64
#define MASTER_HEX_BYTES 128

static int hex_value(char c)
{
    if (c >= '0' && c <= '9') {
        return c - '0';
    }

    c = (char) tolower((unsigned char) c);

    if (c >= 'a' && c <= 'f') {
        return c - 'a' + 10;
    }

    return -1;
}

int main(int argc, char **argv)
{
    char hex[MASTER_HEX_BYTES + 2];
    unsigned char master[MASTER_BYTES];
    size_t len;
    size_t i;
    int fd;

    if (argc < 2) {
        fprintf(
            stderr,
            "sws-keyhold: command is required\n"
        );

        return 1;
    }

    if (!fgets(hex, sizeof(hex), stdin)) {
        fprintf(
            stderr,
            "sws-keyhold: unlock key was not received\n"
        );

        return 1;
    }

    len = strcspn(hex, "\r\n");
    hex[len] = '\0';

    if (len != MASTER_HEX_BYTES) {
        fprintf(
            stderr,
            "sws-keyhold: invalid unlock key length\n"
        );

        return 1;
    }

    for (i = 0; i < MASTER_BYTES; i++) {
        int hi = hex_value(hex[i * 2]);
        int lo = hex_value(hex[i * 2 + 1]);

        if (hi < 0 || lo < 0) {
            fprintf(
                stderr,
                "sws-keyhold: unlock key is not hexadecimal\n"
            );

            explicit_bzero(
                hex,
                sizeof(hex)
            );

            return 1;
        }

        master[i] =
            (unsigned char) (
                (hi << 4) |
                lo
            );
    }

    fd = memfd_create(
        "sws-key",
        MFD_ALLOW_SEALING
    );

    if (fd < 0) {
        perror("sws-keyhold: memfd_create");
        return 1;
    }

    if (
        write(
            fd,
            master,
            sizeof(master)
        ) != sizeof(master)
    ) {
        perror("sws-keyhold: write");
        close(fd);
        return 1;
    }

    if (lseek(fd, 0, SEEK_SET) < 0) {
        perror("sws-keyhold: lseek");
        close(fd);
        return 1;
    }

    if (
        fcntl(
            fd,
            F_ADD_SEALS,
            F_SEAL_WRITE |
            F_SEAL_GROW |
            F_SEAL_SHRINK |
            F_SEAL_SEAL
        ) < 0
    ) {
        perror("sws-keyhold: seal");
        close(fd);
        return 1;
    }

    if (fd != 3) {
        if (dup2(fd, 3) < 0) {
            perror("sws-keyhold: dup2");
            close(fd);
            return 1;
        }

        close(fd);
    }

    if (
        fcntl(
            3,
            F_SETFD,
            0
        ) < 0
    ) {
        perror("sws-keyhold: fcntl");
        return 1;
    }

    explicit_bzero(
        hex,
        sizeof(hex)
    );

    explicit_bzero(
        master,
        sizeof(master)
    );

    setenv(
        "SWS_KEY_FD",
        "3",
        1
    );

    execvp(
        argv[1],
        &argv[1]
    );

    perror("sws-keyhold: exec");

    return 1;
}
