// File/Path Helpers.
#include "file.h"

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <pwd.h>
#include <sys/stat.h>

#define NP_READ_CEILING (16u * 1024u * 1024u)

uint8_t *np_read_whole_file(const char *path, size_t *out_len) {
    int fd = open(path, O_RDONLY);
    if (fd < 0)
        return NULL;

    struct stat meta;
    if (fstat(fd, &meta) != 0 || !S_ISREG(meta.st_mode) ||
        meta.st_size <= 0 || (uintmax_t)meta.st_size > NP_READ_CEILING) {
        close(fd);
        return NULL;
    }

    size_t total = (size_t)meta.st_size;
    uint8_t *data = (uint8_t *)malloc(total);
    if (!data) {
        close(fd);
        return NULL;
    }

    size_t got = 0;
    while (got < total) {
        ssize_t n = read(fd, data + got, total - got);
        if (n <= 0) {
            free(data);
            close(fd);
            return NULL;
        }
        got += (size_t)n;
    }

    close(fd);
    *out_len = total;
    return data;
}

const char *np_home_dir(void) {
    const char *env = getenv("HOME");
    if (env && env[0])
        return env;

    struct passwd *pw = getpwuid(getuid());
    if (pw && pw->pw_dir && pw->pw_dir[0])
        return pw->pw_dir;
    return NULL;
}

// Ambaplay 3.0 moved the support folder from .../notproton. Until the app has moved it, a
// home that has only the old folder keeps using it, and nothing creates the new one beside it.
static int is_dir(const char *home, const char *rel) {
    char path[1024];
    struct stat st;
    snprintf(path, sizeof(path), "%s%s", home, rel);
    return stat(path, &st) == 0 && S_ISDIR(st.st_mode);
}

void np_support_path(char *buf, size_t bufsz, const char *home, const char *rel) {
    static const char current[] = "/Library/Application Support/ambaplay";
    static const char legacy[]  = "/Library/Application Support/notproton";
    const char *base = !is_dir(home, current) && is_dir(home, legacy) ? legacy : current;
    if (rel && rel[0])
        snprintf(buf, bufsz, "%s%s/%s", home, base, rel);
    else
        snprintf(buf, bufsz, "%s%s", home, base);
}
