// Host unit test of the boot guard state machine (BPGuard.c). Build and run (any POSIX host with a C compiler, also the CI runner):
//   clang -Wall -Wextra -Werror -DBPGUARD_TEST -o /tmp/bpguard_test tools/bpguard_test.c && BPGUARD_TEST_ROOT=/tmp/bpguard_hostroot /tmp/bpguard_test
// (BPGUARD_TEST_ROOT: scratch directory that the test deletes and recreates; do not point it at anything you want to keep)
// BPGuard.c is included with BPGUARD_TEST: dlopen and the main queue are recorders here, the "boot finished" event is a call to bpg_clear_marker().
#define BPGUARD_TEST 1
#include "../BPGuard.c"

#include <assert.h>
#include <dirent.h>

static int gDlopenCalls, gArmCalls, gFailDlopen;
static char gLastPath[700];
void *bpg_test_dlopen(const char *path) { gDlopenCalls++; snprintf(gLastPath, sizeof gLastPath, "%s", path); return gFailDlopen ? NULL : (void *)0x1; }
const char *bpg_test_dlerror(void) { return "dlopen error: image not found\nsecond line"; }
void bpg_test_arm_clear(void) { gArmCalls++; }

static char gRoot[600];
static int gFails;
#define CHECK(c) do { if (!(c)) { printf("  FAIL line %d: %s\n", __LINE__, #c); gFails++; } } while (0)

static void touch(const char *name) {
    char p[800]; snprintf(p, sizeof p, "%s/tmp/%s", gRoot, name);
    int fd = open(p, O_WRONLY | O_CREAT, 0644); if (fd >= 0) close(fd);
}
static void rmf(const char *name) { char p[800]; snprintf(p, sizeof p, "%s/tmp/%s", gRoot, name); unlink(p); }
static int has(const char *name) { char p[800]; snprintf(p, sizeof p, "%s/tmp/%s", gRoot, name); return bpg_exists(p); }
static int logLines(const char *needle) {
    char p[800]; snprintf(p, sizeof p, "%s/tmp/Backport162.log", gRoot);
    FILE *f = fopen(p, "r"); if (!f) return 0;
    char l[2000]; int n = 0;
    while (fgets(l, sizeof l, f)) if (!needle || strstr(l, needle)) n++;
    fclose(f);
    return n;
}
static void fresh(const char *label) {
    char cmd[900];
    snprintf(cmd, sizeof cmd, "rm -rf '%s' && mkdir -p '%s/tmp'", gRoot, gRoot);
    if (system(cmd) != 0) { printf("cannot prepare %s\n", gRoot); exit(2); }
    gDlopenCalls = gArmCalls = gFailDlopen = 0;
    printf("%s\n", label);
}
static int launch(int sb) { gDlopenCalls = gArmCalls = 0; return bpg_launch(gRoot, sb); }

int main(void) {
    const char *envRoot = getenv("BPGUARD_TEST_ROOT");   // scratch directory (removed and recreated by the test); default below
    snprintf(gRoot, sizeof gRoot, "%s", envRoot && envRoot[0] ? envRoot : "/tmp/bpguard_test_hostroot");
    char corePath[700];
    if (!strstr(gRoot, "bpguard")) { printf("refusing to delete %s: BPGUARD_TEST_ROOT must contain \"bpguard\"\n", gRoot); return 2; }

    fresh("1. normal sequence: first launch, crash before clear, tripped launch, retry, clean boot, crash after clear");
    char cmd[900];
    snprintf(cmd, sizeof cmd, "mkdir -p '%s/usr/lib/Backport162' && touch '%s/usr/lib/Backport162/Backport162Core.dylib'", gRoot, gRoot);
    CHECK(system(cmd) == 0);
    snprintf(corePath, sizeof corePath, "%s/usr/lib/Backport162/Backport162Core.dylib", gRoot);
    CHECK(launch(1) == BPG_LOADED);                      // first launch
    CHECK(gDlopenCalls == 1 && gArmCalls == 1);
    CHECK(strcmp(gLastPath, corePath) == 0);
    CHECK(has("Backport162.booting"));
    CHECK(!has("Backport162.tripped"));
    char mk[200]; { char p[800]; snprintf(p, sizeof p, "%s/tmp/Backport162.booting", gRoot); FILE *f = fopen(p, "r"); mk[0] = 0; if (f) { if (!fgets(mk, sizeof mk, f)) mk[0] = 0; fclose(f); } }
    CHECK(strncmp(mk, "pid=", 4) == 0 && strstr(mk, " t=") != NULL);
    CHECK(logLines(NULL) == 0);                          // nothing is logged on a normal launch without Backport162.debug
    // crash before the clear: nothing calls bpg_clear_marker; second launch
    CHECK(launch(1) == BPG_TRIPPED);
    CHECK(gDlopenCalls == 0 && gArmCalls == 0);          // core NOT loaded, nothing scheduled
    CHECK(!has("Backport162.booting"));
    CHECK(has("Backport162.tripped"));
    CHECK(logLines("BOOT GUARD TRIPPED") == 1);          // visible without Backport162.debug
    CHECK(logLines(NULL) == 1);
    // third launch: retries
    CHECK(launch(1) == BPG_LOADED);
    CHECK(gDlopenCalls == 1 && gArmCalls == 1);
    CHECK(has("Backport162.booting"));
    // SpringBoard finished booting: the clear runs
    bpg_clear_marker();
    CHECK(!has("Backport162.booting"));
    // a crash after the clear leaves nothing behind: the next launch is clean, not tripped
    CHECK(launch(1) == BPG_LOADED);
    CHECK(gDlopenCalls == 1);
    CHECK(logLines("BOOT GUARD TRIPPED") == 1);          // still only the one trip line
    bpg_clear_marker();
    bpg_clear_marker();                                  // clearing twice is harmless (ENOENT is silent)
    CHECK(logLines(NULL) == 1);

    fresh("2. noguard: a stale marker is removed and ignored, the core is always loaded, no marker is created");
    snprintf(cmd, sizeof cmd, "mkdir -p '%s/usr/lib/Backport162' && touch '%s/usr/lib/Backport162/Backport162Core.dylib'", gRoot, gRoot);
    CHECK(system(cmd) == 0);
    touch("Backport162.booting"); touch("Backport162.noguard");
    CHECK(launch(1) == BPG_LOADED_NOGUARD);
    CHECK(gDlopenCalls == 1 && gArmCalls == 0 && !has("Backport162.booting") && !has("Backport162.tripped"));
    CHECK(launch(1) == BPG_LOADED_NOGUARD);              // "crashing" launches never trip it
    CHECK(gDlopenCalls == 1 && !has("Backport162.booting"));
    rmf("Backport162.noguard");
    CHECK(launch(1) == BPG_LOADED);                      // guard back on, nothing stale
    CHECK(has("Backport162.booting"));

    fresh("3. off.all: the core is never loaded, a stale marker is removed, noguard does not override it");
    snprintf(cmd, sizeof cmd, "mkdir -p '%s/usr/lib/Backport162' && touch '%s/usr/lib/Backport162/Backport162Core.dylib'", gRoot, gRoot);
    CHECK(system(cmd) == 0);
    touch("Backport162.booting"); touch("Backport162.off.all");
    CHECK(launch(1) == BPG_OFF_ALL);
    CHECK(gDlopenCalls == 0 && gArmCalls == 0 && !has("Backport162.booting") && !has("Backport162.tripped"));
    touch("Backport162.noguard");
    CHECK(launch(1) == BPG_OFF_ALL);
    CHECK(gDlopenCalls == 0);
    CHECK(logLines(NULL) == 0);                          // user's own switch: silent without Backport162.debug
    rmf("Backport162.off.all"); rmf("Backport162.noguard");
    CHECK(launch(1) == BPG_LOADED);                      // off.all removed: loads (marker was cleaned, so no trip)
    CHECK(gDlopenCalls == 1);

    fresh("4. debug file: the loader also logs its decisions");
    snprintf(cmd, sizeof cmd, "mkdir -p '%s/usr/lib/Backport162' && touch '%s/usr/lib/Backport162/Backport162Core.dylib'", gRoot, gRoot);
    CHECK(system(cmd) == 0);
    touch("Backport162.debug");
    CHECK(launch(1) == BPG_LOADED);
    CHECK(logLines("core loaded") == 1);
    bpg_clear_marker();
    CHECK(logLines("marker removed") == 1);
    touch("Backport162.off.all");
    CHECK(launch(1) == BPG_OFF_ALL);
    CHECK(logLines("off.all") == 1);

    fresh("5. dlopen failure: dlerror line is logged (always), no crash, marker stays armed for the normal clear");
    snprintf(cmd, sizeof cmd, "mkdir -p '%s/usr/lib/Backport162' && touch '%s/usr/lib/Backport162/Backport162Core.dylib'", gRoot, gRoot);
    CHECK(system(cmd) == 0);
    gFailDlopen = 1;
    CHECK(launch(1) == BPG_LOADED);
    CHECK(gDlopenCalls == 1 && gArmCalls == 1);
    CHECK(logLines("dlopen(") == 1 && logLines("image not found") == 1);
    CHECK(logLines("second line") == 1);                 // the newline of the message was flattened into one log line
    CHECK(logLines(NULL) == 1);

    fresh("6. core file missing: logged, no dlopen, no crash");
    CHECK(launch(1) == BPG_LOADED);
    CHECK(gDlopenCalls == 0 && logLines("is missing") == 1);

    fresh("7. not SpringBoard: core loaded, no marker, never tripped");
    snprintf(cmd, sizeof cmd, "mkdir -p '%s/usr/lib/Backport162' && touch '%s/usr/lib/Backport162/Backport162Core.dylib'", gRoot, gRoot);
    CHECK(system(cmd) == 0);
    touch("Backport162.booting");
    CHECK(launch(0) == BPG_LOADED_NO_SB);
    CHECK(gDlopenCalls == 1 && gArmCalls == 0 && has("Backport162.booting") && !has("Backport162.tripped"));

    fresh("8. tmp directory missing / not writable: fail open (core loaded, no marker, no crash)");
    snprintf(cmd, sizeof cmd, "mkdir -p '%s/usr/lib/Backport162' && touch '%s/usr/lib/Backport162/Backport162Core.dylib' && rm -rf '%s/tmp'", gRoot, gRoot, gRoot);
    CHECK(system(cmd) == 0);
    CHECK(launch(1) == BPG_LOADED_UNGUARDED);
    CHECK(gDlopenCalls == 1 && gArmCalls == 0);

    fresh("9. marker that cannot be removed (directory): trip is reported, no crash");
    snprintf(cmd, sizeof cmd, "mkdir -p '%s/usr/lib/Backport162' && touch '%s/usr/lib/Backport162/Backport162Core.dylib' && mkdir -p '%s/tmp/Backport162.booting/x'", gRoot, gRoot, gRoot);
    CHECK(system(cmd) == 0);
    CHECK(launch(1) == BPG_TRIPPED);
    CHECK(gDlopenCalls == 0);
    CHECK(logLines("could NOT be removed") == 1);

    fresh("10. log is appended, never truncated");
    snprintf(cmd, sizeof cmd, "mkdir -p '%s/usr/lib/Backport162' && touch '%s/usr/lib/Backport162/Backport162Core.dylib' && echo 'earlier line' > '%s/tmp/Backport162.log'", gRoot, gRoot, gRoot);
    CHECK(system(cmd) == 0);
    touch("Backport162.booting");
    CHECK(launch(1) == BPG_TRIPPED);
    CHECK(logLines("earlier line") == 1 && logLines("BOOT GUARD TRIPPED") == 1);

    snprintf(cmd, sizeof cmd, "rm -rf '%s'", gRoot);
    if (system(cmd) != 0) { /* temp dir cleanup only */ }
    printf(gFails ? "FAILED: %d check(s)\n" : "all bpguard checks passed\n", gFails);
    return gFails ? 1 : 0;
}
