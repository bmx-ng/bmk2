SuperStrict

Framework BRL.StandardIO
Import BRL.FileSystem

Include "../bmk_esp32_paths.bmx"

Function Check(condition:Int, message:String)
	If Not condition Then Throw message
End Function

Local temporary:String = getenv_("TMPDIR").Trim()
If Not temporary.length Then temporary = getenv_("TEMP").Trim()
If Not temporary.length Then temporary = "."
Local root:String = temporary + "/bmk_esp32_path_tests"
If FileType(root) = FILETYPE_DIR Then DeleteDir(root, True)

Local home:String = root + "/home"
Local manualIdf:String = home + "/checkouts/esp-idf-v6.1"
Local toolsRoot:String = home + "/.espressif"
CreateDir(manualIdf + "/tools/cmake", True)
CreateDir(toolsRoot + "/tools/xtensa-esp-elf/version/xtensa-esp-elf/bin", True)
CreateDir(toolsRoot + "/python_env/idf6.1_py3.12_env/bin", True)
CreateDir(toolsRoot + "/python_env/idf6.1_py3.13_env/bin", True)
SaveText "set(IDF_VERSION_MAJOR 6)~nset(IDF_VERSION_MINOR 1)~nset(IDF_VERSION_PATCH 0)~n", manualIdf + "/tools/cmake/version.cmake"
SaveText "", toolsRoot + "/python_env/idf6.1_py3.12_env/bin/python"
SaveText "6.1~n", toolsRoot + "/python_env/idf6.1_py3.12_env/idf_version.txt"
SaveText "", toolsRoot + "/python_env/idf6.1_py3.13_env/bin/python"
SaveText "5.4~n", toolsRoot + "/python_env/idf6.1_py3.13_env/idf_version.txt"

Check(Esp32IdfVersion(manualIdf) = "6.1.0", "ESP-IDF version is read from version.cmake")
Check(Esp32ResolveToolsRoot("", home, manualIdf) = RealPath(toolsRoot), "manual installs use the independent user tools root")
Check(Esp32ResolvePython("", toolsRoot, manualIdf, "linux") = toolsRoot + "/python_env/idf6.1_py3.12_env/bin/python", "manual Linux Python environments are discovered")
Check(Esp32ToolDirectory(toolsRoot, "xtensa-esp-elf") = toolsRoot + "/tools/xtensa-esp-elf", "manual toolchains are found below the standard tools directory")

Local explicitRoot:String = root + "/custom-tools"
Local explicitPython:String = root + "/custom-python"
CreateDir(explicitRoot + "/python_env", True)
CreateDir(explicitPython + "/bin", True)
SaveText "", explicitPython + "/bin/python3"
Check(Esp32ResolveToolsRoot(explicitRoot, home, manualIdf) = RealPath(explicitRoot), "IDF_TOOLS_PATH takes precedence")
Check(Esp32ResolvePython(explicitPython, toolsRoot, manualIdf, "linux") = explicitPython + "/bin/python3", "IDF_PYTHON_ENV_PATH takes precedence")

Local managedRoot:String = root + "/managed/.espressif"
Local managedIdf:String = managedRoot + "/v6.1/esp-idf"
CreateDir(managedIdf + "/tools/cmake", True)
CreateDir(managedRoot + "/tools/python/v6.1/venv/bin", True)
CreateDir(managedRoot + "/tools/xtensa-esp-elf/version/xtensa-esp-elf/bin", True)
SaveText "set(IDF_VERSION_MAJOR 6)~nset(IDF_VERSION_MINOR 1)~nset(IDF_VERSION_PATCH 0)~n", managedIdf + "/tools/cmake/version.cmake"
SaveText "", managedRoot + "/tools/python/v6.1/venv/bin/python"
Check(Esp32ResolveToolsRoot("", root + "/missing-home", managedIdf) = RealPath(managedRoot + "/tools"), "installer-managed tools are inferred from the ESP-IDF checkout")
Check(Esp32ResolvePython("", managedRoot + "/tools", managedIdf, "macos") = managedRoot + "/tools/python/v6.1/venv/bin/python", "installer-managed Python remains supported")
Check(Esp32ToolDirectory(managedRoot + "/tools", "xtensa-esp-elf") = managedRoot + "/tools/xtensa-esp-elf", "installer-managed toolchains remain supported")

DeleteDir root, True
Print "bmk ESP32 path-discovery tests passed"
