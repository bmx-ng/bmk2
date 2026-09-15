Function Esp32PythonExecutable:String(value:String, platform:String)
	value = value.Trim()
	If Not value.length Then Return ""
	If FileType(value) = FILETYPE_FILE Then Return value
	If FileType(value) <> FILETYPE_DIR Then Return ""
	Local candidates:String[]
	If platform = "win32" Then
		candidates = ["/Scripts/python.exe", "/python.exe"]
	Else
		candidates = ["/bin/python", "/bin/python3"]
	End If
	For Local suffix:String = EachIn candidates
		Local candidate:String = value + suffix
		If FileType(candidate) = FILETYPE_FILE Then Return candidate
	Next
	Return ""
End Function

Function Esp32IdfVersionSetting:String(text:String, name:String)
	Local prefix:String = "set(" + name.ToLower() + " "
	For Local rawLine:String = EachIn text.Replace("~r", "").Split("~n")
		Local line:String = rawLine.Trim()
		If Not line.ToLower().StartsWith(prefix) Then Continue
		Local value:String = line[prefix.length..].Trim()
		If value.EndsWith(")") Then value = value[..value.length - 1].Trim()
		Return value
	Next
	Return ""
End Function

Function Esp32IdfVersion:String(idfPath:String)
	Local versionFile:String = idfPath + "/tools/cmake/version.cmake"
	If FileType(versionFile) <> FILETYPE_FILE Then Return ""
	Local text:String = LoadText(versionFile)
	Local major:String = Esp32IdfVersionSetting(text, "IDF_VERSION_MAJOR")
	Local minor:String = Esp32IdfVersionSetting(text, "IDF_VERSION_MINOR")
	Local patch:String = Esp32IdfVersionSetting(text, "IDF_VERSION_PATCH")
	If Not major.length Or Not minor.length Then Return ""
	If Not patch.length Then patch = "0"
	Return major + "." + minor + "." + patch
End Function

Function Esp32IdfMajorMinor:String(version:String)
	Local parts:String[] = version.Split(".")
	If parts.length < 2 Then Return version
	Return parts[0] + "." + parts[1]
End Function

Function Esp32ToolsRootCandidate:String(value:String)
	value = value.Trim()
	If Not value.length Or FileType(value) <> FILETYPE_DIR Then Return ""
	If FileType(value + "/tools") = FILETYPE_DIR Or ..
		FileType(value + "/python_env") = FILETYPE_DIR Or ..
		FileType(value + "/python") = FILETYPE_DIR Then Return RealPath(value)
	Return ""
End Function

Function Esp32ResolveToolsRoot:String(configured:String, home:String, idfPath:String)
	Local result:String = Esp32ToolsRootCandidate(configured)
	If result.length Then Return result

	' Espressif Installation Manager can place esp-idf under
	' <installation-root>/vX.Y/esp-idf and use <installation-root>/tools as
	' IDF_TOOLS_PATH directly.
	Local installationRoot:String = ExtractDir(ExtractDir(idfPath))
	result = Esp32ToolsRootCandidate(installationRoot + "/tools")
	If result.length Then Return result

	' A manual ESP-IDF checkout normally keeps downloaded tools independently
	' under IDF_TOOLS_PATH, whose default is ~/.espressif.
	result = Esp32ToolsRootCandidate(home + "/.espressif")
	Return result
End Function

Function Esp32PackagedPython:String(toolsRoot:String, version:String, platform:String)
	Local majorMinor:String = Esp32IdfMajorMinor(version)
	Local tags:String[] = ["v" + majorMinor, majorMinor, "v" + version, version]
	For Local tag:String = EachIn tags
		Local executable:String = Esp32PythonExecutable(toolsRoot + "/python/" + tag + "/venv", platform)
		If Not executable.length Then executable = Esp32PythonExecutable(toolsRoot + "/tools/python/" + tag + "/venv", platform)
		If executable.length Then Return executable
	Next
	Return ""
End Function

Function Esp32ToolDirectory:String(toolsRoot:String, toolName:String)
	Local direct:String = toolsRoot + "/" + toolName
	If FileType(direct) = FILETYPE_DIR Then Return direct
	Local nested:String = toolsRoot + "/tools/" + toolName
	If FileType(nested) = FILETYPE_DIR Then Return nested
	Return ""
End Function

Function Esp32StandardPython:String(toolsRoot:String, version:String, platform:String)
	Local root:String = toolsRoot + "/python_env"
	If FileType(root) <> FILETYPE_DIR Then Return ""
	Local majorMinor:String = Esp32IdfMajorMinor(version)
	Local wanted:String = "idf" + majorMinor + "_"
	Local selectedName:String
	Local selected:String
	For Local entry:String = EachIn LoadDir(root)
		Local environment:String = root + "/" + entry
		Local marker:String = environment + "/idf_version.txt"
		If FileType(marker) = FILETYPE_FILE Then
			Local markedVersion:String = LoadText(marker).Trim()
			If markedVersion <> version And markedVersion <> majorMinor Then Continue
		Else If Not entry.ToLower().StartsWith(wanted.ToLower())
			Continue
		End If
		Local executable:String = Esp32PythonExecutable(environment, platform)
		If Not executable.length Then Continue
		If Not selected.length Or entry > selectedName Then
			selectedName = entry
			selected = executable
		End If
	Next
	Return selected
End Function

Function Esp32ResolvePython:String(configured:String, toolsRoot:String, idfPath:String, platform:String)
	Local executable:String = Esp32PythonExecutable(configured, platform)
	If executable.length Then Return executable
	Local version:String = Esp32IdfVersion(idfPath)
	If Not version.length Then Return ""
	executable = Esp32StandardPython(toolsRoot, version, platform)
	If executable.length Then Return executable
	Return Esp32PackagedPython(toolsRoot, version, platform)
End Function
