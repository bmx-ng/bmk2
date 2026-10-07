# SDL Android Java baseline

The Java classes under
`android-project/app/src/main/java/org/libsdl/app` are imported from SDL's
`android-project/app/src/main/java/org/libsdl/app` directory. The current
baseline is SDL 3.4.16.

Keep these classes synchronized with the SDL version bundled by BlitzMax. Do
not put BlitzMax application policy in this directory: package settings,
manifest defaults, Gradle configuration, icons and `BlitzMaxApp.java` belong
to the surrounding BlitzMax project template.

To compare or refresh the baseline from an SDL source tree:

```sh
./resources/android/sync-sdl-java.sh check /path/to/SDL3
./resources/android/sync-sdl-java.sh update /path/to/SDL3
```

The check is intentionally local and deterministic; it does not download SDL.
