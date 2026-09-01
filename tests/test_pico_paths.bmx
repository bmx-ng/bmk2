SuperStrict

Framework BRL.StandardIO
Import BRL.FileSystem

Include "../bmk_pico_paths.bmx"

Function Check(condition:Int, message:String)
	If Not condition Then Throw message
End Function

Local temporary:String = getenv_("TMPDIR").Trim()
If Not temporary.length Then temporary = getenv_("TEMP").Trim()
If Not temporary.length Then temporary = "."
Local root:String = temporary + "/bmk_pico_path_tests"
If FileType(root) = FILETYPE_DIR Then DeleteDir(root, True)
CreateDir(root + "/path-tools", True)
CreateDir(root + "/managed/.pico-sdk/cmake/3.9/bin", True)
CreateDir(root + "/managed/.pico-sdk/cmake/3.31/bin", True)
CreateDir(root + "/package", True)
SaveText "", root + "/path-tools/cmake.exe"
SaveText "", root + "/path-tools/ninja"
SaveText "", root + "/managed/.pico-sdk/cmake/3.9/bin/cmake"
SaveText "", root + "/managed/.pico-sdk/cmake/3.31/bin/cmake"
SaveText "", root + "/package/picotool"
SaveText "", root + "/package/picotoolConfig.cmake"

Check(PicoExecutableName("cmake", "win32") = "cmake.exe", "Windows executable suffix is added")
Check(PicoExecutableName("cmake.exe", "win32") = "cmake.exe", "Windows executable suffix is not duplicated")
Check(PicoPathSeparator("win32") = ";" And PicoPathSeparator("linux") = ":", "host PATH separators are portable")
Check(PicoPreferredConfiguredValue(" /custom/cmake ", "/environment/cmake") = "/custom/cmake", "custom.bmk takes precedence over the environment")
Check(PicoPreferredConfiguredValue("", " /environment/cmake ") = "/environment/cmake", "the environment is used when custom.bmk is unset")
Check(PicoFindExecutableOnPath("cmake", root + "/missing;" + root + "/path-tools", "win32") = root + "/path-tools/cmake.exe", "Windows PATH discovery works")
Check(PicoFindExecutableOnPath("ninja", root + "/missing:" + root + "/path-tools", "linux") = root + "/path-tools/ninja", "Unix PATH discovery works")
Check(PicoExecutableFromValue(root + "/package", "picotool", "linux") = root + "/package/picotool", "a tool directory resolves its executable")
Check(PicoPackageDirectory(root + "/package/picotool", "picotool") = root + "/package", "a tool executable resolves its CMake package directory")
Check(PicoLatestManagedPath(root + "/managed", "cmake", ["/bin/cmake"]) = root + "/managed/.pico-sdk/cmake/3.31/bin/cmake", "the newest managed tool is selected")
Check(PicoNaturalVersionCompare("v1.12.1", "v1.9.0") > 0, "managed versions use natural numeric ordering")

DeleteDir root, True
Print "bmk Pico path-discovery tests passed"
