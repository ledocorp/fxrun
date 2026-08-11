/* fxrun_host.c — argv + orchestrate fxrun_lib.
 *
 * Flags: --list --dry-run --force
 * Usage: fxrun [--list] [--dry-run] [--force] [recipe]
 */
#include <stdio.h>
#include <string.h>
#include "fx_cli_host.h"
#include "fxrun_lib.h"

extern int fxrun_host_run_cmd(const char *cmd);

int main(int argc, char **argv) {
    int list = 0;
    int dry = 0;
    int force = 0;
    const char *recipe = "";
    int i;
    fx_fxrun_lib_Result_i32 r;

    for (i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--list") == 0) {
            list = 1;
        } else if (strcmp(argv[i], "--dry-run") == 0) {
            dry = 1;
        } else if (strcmp(argv[i], "--force") == 0) {
            force = 1;
        } else if (strcmp(argv[i], "--help") == 0 || strcmp(argv[i], "-h") == 0) {
            return fx_cli_usage(
                "usage: fxrun [--list] [--dry-run] [--force] [recipe]\n"
                "  Reads Fxrun.toml / fxrun.toml in cwd or a parent directory.");
        } else if (argv[i][0] == '-') {
            return fx_cli_fail("fxrun", "unknown flag", 2);
        } else if (recipe[0] == '\0') {
            recipe = argv[i];
        } else {
            return fx_cli_fail("fxrun", "extra arguments", 2);
        }
    }

    r = fx_fxrun_lib_run(list, dry, force, recipe);
    FX_CLI_RETURN_RESULT_I32(r, "fxrun");
}
