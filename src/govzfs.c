/* govzfs — утилита управления ZFS-пулом govechoOS (BSD Edition)
 * Автор: ZHBR-228, лицензия MIT */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>

static int run(const char *fmt, ...) {
    char cmd[1024];
    va_list ap; va_start(ap, fmt); vsnprintf(cmd, sizeof cmd, fmt, ap); va_end(ap);
    fprintf(stderr, "\033[2mgovzfs: %s\033[0m\n", cmd);
    return system(cmd);
}

static void usage(void) {
    printf("govzfs — управление файловой системой ZFS в GovechoBSD\n"
           "Использование: govzfs <команда> [аргументы]\n\n"
           "Команды:\n"
           "  status              состояние пула govechoOS/zroot\n"
           "  list                все датасеты с использованием\n"
           "  snap create <имя>   снапшот govechoOS/zroot/ROOT@<имя>\n"
           "  snap list           список снапшотов\n"
           "  rollback <снап>     откат к снапшоту (как Time Machine)\n"
           "  boot set <снап>     выбрать снапшот для загрузки\n"
           "  boot list           варианты загрузки\n"
           "  du                  свободное место в пуле\n");
}

int main(int argc, char **argv) {
    if (argc < 2) { usage(); return argc == 2 && !strcmp(argv[1], "--help") ? 0 : 1; }
    const char *c = argv[1];
    if (!strcmp(c, "status"))      return run("zpool status govechoOS");
    if (!strcmp(c, "list"))        return run("zfs list -r govechoOS -o name,used,avail,mountpoint");
    if (!strcmp(c, "du"))          return run("zpool list govechoOS");
    if (!strcmp(c, "snap") && argc >= 4 && !strcmp(argv[2], "create"))
        return run("zfs snapshot govechoOS/zroot/ROOT@%s", argv[3]);
    if (!strcmp(c, "snap") && argc >= 3 && !strcmp(argv[2], "list"))
        return run("zfs list -t snapshot -o name,created -r govechoOS/zroot/ROOT");
    if (!strcmp(c, "rollback") && argc >= 3)
        return run("zfs rollback -r govechoOS/zroot/ROOT@%s", argv[2]);
    if (!strcmp(c, "boot") && argc >= 4 && !strcmp(argv[2], "set"))
        return run("goverlay set-bootprog zroot govechoOS/zroot/ROOT@%s", argv[3]) != 0
             ? run("zpool set bootfs=govechoOS/zroot/ROOT@%s govechoOS", argv[3]) : 0;
    if (!strcmp(c, "boot") && argc >= 3 && !strcmp(argv[2], "list"))
        return run("zfs list -H -o name -t snapshot -r govechoOS/zroot/ROOT | tail -20");
    fprintf(stderr, "govzfs: неизвестная команда '%s' (см. govzfs --help)\n", c);
    return 2;
}
