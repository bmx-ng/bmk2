#include <stdlib.h>

typedef int (*BMXSDLMainFunction)(int argc, char *argv[]);

extern int SDL_main(int argc, char *argv[]);
extern int SDL_RunApp(int argc, char *argv[], BMXSDLMainFunction mainFunction, void *reserved);

int main(int argc, char *argv[])
{
    return SDL_RunApp(argc, argv, SDL_main, NULL);
}
