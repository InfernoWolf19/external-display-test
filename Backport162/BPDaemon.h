// BPDaemon.h : file output of the daemon halves (BBD.x in backboardd, PTR.x in pointeruid), shared by both translation units.
//
// Why this exists: Dopamine gives every injected process a sandbox extension that makes <jbroot> READABLE and only <jbroot>/var/mobile (= /var/mobile) WRITABLE
// (BaseBin/launchdhook/src/jbserver/jbdomain_systemwide.c, systemwide_process_checkin).  backboardd and pointeruid are sandboxed daemons, so open(O_CREAT) in
// <jbroot>/tmp (where SpringBoard writes Backport162.log) fails for them: the log lines, the .ctor markers and the crash guard strikes of earlier builds were never written.
// Reading is fine (the Backport162.debug / Backport162.off.* switch files are found).
//
// The daemons therefore append to <writable dir>/Backport162.daemon.log, the first directory of kBPDWDirs in which that file can be opened.  SpringBoard's tweak (G2D.x,
// G2D_IngestDaemonLog) looks in the same directories and copies the new lines into Backport162.log with the prefix "daemon:".
#ifndef BPDAEMON_H
#define BPDAEMON_H

#import <fcntl.h>
#import <stdio.h>
#import <string.h>
#import <sys/stat.h>
#import <time.h>
#import <unistd.h>

#define BPDW_DIR_COUNT 4
static const char *const kBPDWDirs[BPDW_DIR_COUNT] = { "/var/jb/tmp", "/var/mobile/Library/Caches", "/var/mobile", "/tmp" };
#define BPDW_FILE "Backport162.daemon.log"
#define BPDW_MAX_BYTES (256 * 1024)

// Directory the daemon can write to (probed once, then cached; -1 = none of them).
static inline int BPDW_DirIndex(void) {
    static int idx = -2;
    if (idx != -2) return idx;
    idx = -1;
    for (int i = 0; i < BPDW_DIR_COUNT; i++) {
        char p[300]; snprintf(p, sizeof p, "%s/%s", kBPDWDirs[i], BPDW_FILE);
        int fd = open(p, O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, 0644);
        if (fd < 0) continue;
        close(fd);
        idx = i;
        break;
    }
    return idx;
}

// <dir>/<name> in the writable directory; NULL when there is none.
static inline const char *BPDW_Path(const char *name, char *buf, size_t size) {
    int i = BPDW_DirIndex();
    if (i < 0) return NULL;
    snprintf(buf, size, "%s/%s", kBPDWDirs[i], name);
    return buf;
}

// One line, always written (callers decide whether the line is worth writing).
static inline void BPDW_Line(const char *tag, const char *text) {
    char p[300];
    if (!BPDW_Path(BPDW_FILE, p, sizeof p)) return;
    int fd = open(p, O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, 0644);
    if (fd < 0) return;
    struct stat st;
    if (fstat(fd, &st) == 0 && st.st_size > BPDW_MAX_BYTES) (void)!ftruncate(fd, 0);
    struct timespec ts; clock_gettime(CLOCK_REALTIME, &ts);
    struct tm tmv; localtime_r(&ts.tv_sec, &tmv);
    char line[1400];
    int n = snprintf(line, sizeof line, "%02d:%02d:%02d.%03ld %s[%d] %s\n", tmv.tm_hour, tmv.tm_min, tmv.tm_sec, ts.tv_nsec / 1000000, tag, (int)getpid(), text);
    if (n > 0) (void)!write(fd, line, (size_t)(n < (int)sizeof line ? n : (int)sizeof line - 1));
    close(fd);
}

#endif
