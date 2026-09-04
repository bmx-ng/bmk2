Function PicoHostPlatform:String()
?win32
	Return "win32"
?macos
	Return "macos"
?linux
	Return "linux"
?
End Function

Function PicoExecutableName:String(name:String, platform:String)
	If platform = "win32" And Not name.ToLower().EndsWith(".exe") Then Return name + ".exe"
	Return name
End Function

Function PicoPathSeparator:String(platform:String)
	If platform = "win32" Then Return ";"
	Return ":"
End Function

Function PicoUserHome:String(platform:String)
	If platform = "win32" Then
		Local profile:String = getenv_("USERPROFILE").Trim()
		If profile.length Then Return profile
		Local drive:String = getenv_("HOMEDRIVE").Trim()
		Local path:String = getenv_("HOMEPATH").Trim()
		If drive.length And path.length Then Return drive + path
	End If
	Return getenv_("HOME").Trim()
End Function

Function PicoPreferredConfiguredValue:String(optionValue:String, environmentValue:String)
	optionValue = optionValue.Trim()
	If optionValue.length Then Return optionValue
	Return environmentValue.Trim()
End Function

Function PicoExecutableFromValue:String(value:String, name:String, platform:String)
	value = value.Trim()
	If Not value.length Then Return ""
	If FileType(value) = FILETYPE_FILE Then Return value
	If FileType(value) = FILETYPE_DIR Then
		Local candidate:String = value + "/" + PicoExecutableName(name, platform)
		If FileType(candidate) = FILETYPE_FILE Then Return candidate
	End If
	Return ""
End Function

Function PicoFindExecutableOnPath:String(name:String, pathValue:String, platform:String)
	Local executable:String = PicoExecutableName(name, platform)
	For Local directory:String = EachIn pathValue.Split(PicoPathSeparator(platform))
		directory = directory.Trim()
		If Not directory.length Then Continue
		Local candidate:String = directory + "/" + executable
		If FileType(candidate) = FILETYPE_FILE Then Return candidate
	Next
	Return ""
End Function

Function PicoAsciiDigit:Int(character:Int)
	Return character >= Asc("0") And character <= Asc("9")
End Function

Function PicoNaturalVersionCompare:Int(left:String, right:String)
	left = left.ToLower()
	right = right.ToLower()
	Local leftIndex:Int
	Local rightIndex:Int
	While leftIndex < left.length And rightIndex < right.length
		If PicoAsciiDigit(left[leftIndex]) And PicoAsciiDigit(right[rightIndex]) Then
			While leftIndex < left.length And left[leftIndex] = Asc("0")
				leftIndex :+ 1
			Wend
			While rightIndex < right.length And right[rightIndex] = Asc("0")
				rightIndex :+ 1
			Wend
			Local leftEnd:Int = leftIndex
			Local rightEnd:Int = rightIndex
			While leftEnd < left.length And PicoAsciiDigit(left[leftEnd])
				leftEnd :+ 1
			Wend
			While rightEnd < right.length And PicoAsciiDigit(right[rightEnd])
				rightEnd :+ 1
			Wend
			If leftEnd - leftIndex <> rightEnd - rightIndex Then Return (leftEnd - leftIndex) - (rightEnd - rightIndex)
			Local leftNumber:String = left[leftIndex..leftEnd]
			Local rightNumber:String = right[rightIndex..rightEnd]
			If leftNumber < rightNumber Then Return -1
			If leftNumber > rightNumber Then Return 1
			leftIndex = leftEnd
			rightIndex = rightEnd
			Continue
		End If
		If left[leftIndex] < right[rightIndex] Then Return -1
		If left[leftIndex] > right[rightIndex] Then Return 1
		leftIndex :+ 1
		rightIndex :+ 1
	Wend
	' A stable version is newer than a prerelease with the same numeric prefix.
	If leftIndex = left.length And rightIndex < right.length And right[rightIndex] = Asc("-") Then Return 1
	If rightIndex = right.length And leftIndex < left.length And left[leftIndex] = Asc("-") Then Return -1
	Return (left.length - leftIndex) - (right.length - rightIndex)
End Function

Function PicoManagedVersionPath:String(home:String, category:String, version:String, suffixes:String[])
	home = home.Trim()
	version = version.Trim()
	If Not home.length Or Not version.length Then Return ""
	Local root:String = home + "/.pico-sdk/" + category + "/" + version
	For Local suffix:String = EachIn suffixes
		Local candidate:String = root + suffix
		If FileType(candidate) Then Return candidate
	Next
	Return ""
End Function

Function PicoLatestManagedPath:String(home:String, category:String, suffixes:String[])
	home = home.Trim()
	If Not home.length Then Return ""
	Local root:String = home + "/.pico-sdk/" + category
	If FileType(root) <> FILETYPE_DIR Then Return ""
	Local bestVersion:String
	Local bestCandidate:String
	For Local entry:String = EachIn LoadDir(root)
		For Local suffix:String = EachIn suffixes
			Local candidate:String = root + "/" + entry + suffix
			If FileType(candidate) Then
				If Not bestCandidate.length Or PicoNaturalVersionCompare(entry, bestVersion) > 0 Then
					bestVersion = entry
					bestCandidate = candidate
				End If
				Exit
			End If
		Next
	Next
	Return bestCandidate
End Function

Function PicoManagedOrPathExecutable:String(name:String, pathValue:String, platform:String, home:String, category:String, suffixes:String[], preferredManagedVersion:String = "")
	Local executable:String = PicoManagedVersionPath(home, category, preferredManagedVersion, suffixes)
	If Not executable.length Then executable = PicoLatestManagedPath(home, category, suffixes)
	If executable.length And FileType(executable) = FILETYPE_FILE Then Return executable
	Return PicoFindExecutableOnPath(name, pathValue, platform)
End Function

Function PicoCMakeManagedSuffixes:String[](platform:String)
	If platform = "macos" Then Return ["/CMake.app/Contents/bin/cmake", "/bin/cmake", "/cmake"]
	If platform = "win32" Then Return ["/bin/cmake.exe", "/cmake.exe", "/CMake/bin/cmake.exe"]
	Return ["/bin/cmake", "/cmake"]
End Function

Function PicoNinjaManagedSuffixes:String[](platform:String)
	Local executable:String = PicoExecutableName("ninja", platform)
	Return ["/" + executable, "/bin/" + executable]
End Function

Function PicoToolManagedSuffixes:String[](name:String, platform:String)
	Local executable:String = PicoExecutableName(name, platform)
	Return ["/" + name + "/" + executable, "/" + executable, "/bin/" + executable]
End Function

Function PicoPackageDirectory:String(value:String, packageName:String)
	value = value.Trim()
	If Not value.length Then Return ""
	Local directory:String = value
	If FileType(directory) = FILETYPE_FILE Then directory = ExtractDir(directory)
	If FileType(directory + "/" + packageName + "Config.cmake") = FILETYPE_FILE Then Return directory
	Return ""
End Function
