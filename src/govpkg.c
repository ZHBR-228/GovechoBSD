/* govpkg — пакетный менеджер govechoOS: FreeBSD pkg + Linux flatpak/snap (Debian-шлюз) */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>

static int run(const char *fmt, ...) {
    char cmd[1024]; va_list ap; va_start(ap, fmt); vsnprintf(cmd, sizeof cmd, fmt, ap); va_end(ap);
    fprintf(stderr, "\033[2mgovpkg: %s\033[0m\n", cmd);
    return system(cmd);
}
static void usage(void) {
    printf("govpkg — единый интерфейс пакетов GovechoBSD\n"
           "Использование: govpkg <команда> [пакет]\n\n"
           "  install <pkg>     pkg install (FreeBSD base)\n"
           "  remove <pkg>      pkg delete\n"
           "  search <слово>    pkg search\n"
           "  list              pkg info\n"
           "  update            pkg update && pkg upgrade\n"
           "  flatpak install <app-id>   через Linuxulator/flatpak\n"
           "  govos             информация о системе и репозиториях\n");
}
int main(int argc, char **argv) {
    if (argc < 2) { usage(); return 1; }
    const char *c = argv[1];
    if (!strcmp(c,"install") && argc>=3) return run("pkg install -y %s", argv[2]);
    if (!strcmp(c,"remove")  && argc>=3) return run("pkg delete -y %s", argv[2]);
    if (!strcmp(c,"search")  && argc>=3) return run("pkg search %s", argv[2]);
    if (!strcmp(c,"list"))   return run("pkg info");
    if (!strcmp(c,"update")) return run("pkg update && pkg upgrade -y");
    if (!strcmp(c,"flatpak") && argc>=4) return run("flatpak %s %s", argv[2], argv[3]);
    if (!strcmp(c,"govos")) {
        printf("govechoOS BSD Edition v1.0 | автор ZHBR-228 | MIT\n");
        return run("uname -sr; pkg -v 2>/dev/null; echo '--- датасеты:'; zfs list -r govechoOS 2>/dev/null | head -15");
    }
    fprintf(stderr,"govpkg: неизвестная команда '%s'\n", c); return 2;
}
