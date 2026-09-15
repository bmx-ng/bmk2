SuperStrict

Import "bmk_pico.bmx"
Import "bmk_esp32.bmx"

Function ConfiguredPicoBoardRoot:String()
	Local sdk:String = PicoConfiguredPath("pico.sdk", "PICO_SDK_PATH")
	If sdk.length And FileType(sdk) = FILETYPE_DIR Then Return sdk
	Return PicoLatestManagedPath(PicoUserHome(PicoHostPlatform()), "sdk", [""])
End Function

Function PicoBoardDefinitionExists:Int(board:String)
	Local name:String = ValidatePicoBoardName(board)
	Local sdk:String = ConfiguredPicoBoardRoot()
	If sdk.length And FileType(sdk + "/src/boards/include/boards/" + name + ".h") = FILETYPE_FILE Then Return True

	Local configured:String = PicoConfiguredPath("pico.board.header.dirs", "PICO_BOARD_HEADER_DIRS")
	If Not configured.length Then Return False
	Local separator:String = ":"
	If PicoHostPlatform() = "win32" Then separator = ";"
	If separator = ":" Then configured = configured.Replace(";", ":")
	For Local root:String = EachIn configured.Split(separator)
		root = root.Trim()
		If root.length And FileType(root + "/" + name + ".h") = FILETYPE_FILE Then Return True
	Next
	Return False
End Function

Function OptionalEsp32BoardProfile:TEsp32BoardProfile(board:String)
	If FileType(BlitzMaxPath() + "/mod/esp32.mod/boards") <> FILETYPE_DIR Then Return Null
	Return Esp32BoardProfiles().Find(board.Trim().ToLower())
End Function

Function ApplyInferredEmbeddedTarget(platform:String, architecture:String, board:String)
	If opt_target_platform_set And opt_target_platform <> platform Then
		Throw "Board '" + board + "' selects the " + platform + " platform, but -l " + opt_target_platform + " was supplied."
	End If
	If opt_arch_set And opt_arch <> architecture Then
		Throw "Board '" + board + "' selects the " + architecture + " architecture, but -g " + opt_arch + " was supplied."
	End If
	opt_target_platform = platform
	opt_target_platform_set = True
	opt_arch = architecture
	opt_arch_set = True
End Function

Function ResolveExplicitBoardTarget:Int()
	If Not opt_target_board_set Then Return False
	Local originalPlatform:String = processor.Platform()
	Local originalArchitecture:String = processor.CPU()
	Local board:String = opt_target_board.Trim()
	Local esp32Profile:TEsp32BoardProfile = OptionalEsp32BoardProfile(board)

	If opt_target_platform_set
		Select opt_target_platform
			Case "esp32"
				If Not esp32Profile Then Throw "Unsupported ESP32 board profile: " + board + ". Available profiles: " + Esp32BoardProfiles().Names() + "."
				ApplyInferredEmbeddedTarget("esp32", Esp32TargetArchitecture(esp32Profile.idfTarget), board)
			Case "pico"
				ApplyInferredEmbeddedTarget("pico", "arm", board)
			Default
				Throw "The -board option selects embedded hardware and cannot be used with the " + opt_target_platform + " platform."
		End Select
	Else
		Local picoMatch:Int = PicoBoardDefinitionExists(board)
		If esp32Profile And picoMatch Then
			Throw "Board '" + board + "' matches both an ESP32 profile and a Pico SDK board definition. Specify -l esp32 or -l pico."
		Else If esp32Profile
			ApplyInferredEmbeddedTarget("esp32", Esp32TargetArchitecture(esp32Profile.idfTarget), board)
		Else If picoMatch
			ApplyInferredEmbeddedTarget("pico", "arm", board)
		Else
			Throw "Unable to infer an embedded target from board '" + board + "': no matching ESP32 profile or Pico SDK board definition was found. Specify -l pico or -l esp32, and -g if the target architecture cannot otherwise be determined."
		End If
	End If

	Return processor.Platform() <> originalPlatform Or processor.CPU() <> originalArchitecture
End Function
