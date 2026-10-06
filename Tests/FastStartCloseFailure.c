// Inject a final buffered-output failure without filling the user's disk.
#include <stdio.h>
#include <fcntl.h>
#include <errno.h>
int test_fclose(FILE *stream) {
    int flags = fcntl(fileno(stream), F_GETFL);
    int writable = flags >= 0 && (flags & O_ACCMODE) != O_RDONLY;
    int result = fclose(stream);
    if (writable) { errno = ENOSPC; return EOF; }
    return result;
}
