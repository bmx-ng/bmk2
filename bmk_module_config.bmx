' Module-local build configuration. Included by bmk_modutil.bmx.
Global moduleBuildConfigs:TMap = New TMap
Global moduleConfigStamps:TMap = New TMap

Type TModuleBuildConfig
	Field active:Int
	Field definitions:String
	Field ccOptions:String
	Field cOptions:String
	Field cppOptions:String
	Field asmOptions:String
	Field ldOptions:String
	Field fingerprint:String
End Type

Function ModuleConfigCloneMap:TMap(source:TMap)
	Local result:TMap = New TMap
	For Local key:String = EachIn source.Keys()
		Local value:Object = source.ValueForKey(key)
		If TOptionVariable(value) Then value = TOptionVariable(value).Clone()
		result.Insert(key, value)
	Next
	Return result
End Function

Function ModuleBuildConfigForPath:TModuleBuildConfig(path:String)
	Local directory:String = ExtractDir(RealPath(path))
	While directory
		Local leaf:String = StripDir(directory)
		If leaf.EndsWith(".mod") And FileType(directory + "/" + leaf[..leaf.length - 4] + ".bmx") = FILETYPE_FILE Then Exit
		Local parent:String = ExtractDir(directory)
		If parent = directory Then Return Null
		directory = parent
	Wend
	If Not directory Then Return Null
	Local key:String = directory + opt_configmung + processor.CPU()
	Local config:TModuleBuildConfig = TModuleBuildConfig(moduleBuildConfigs.ValueForKey(key))
	If config Then Return config
	config = New TModuleBuildConfig
	Local content:String
	For Local name:String = EachIn ["module.bmk"]
		Local file:String = directory + "/" + name
		content :+ name + "~n"
		If FileType(file) = FILETYPE_FILE Then
			config.active = True
			content :+ LoadText(file)
		End If
		content :+ "~n"
	Next
	If config.active Then
		Local savedVars:TMap = globals.vars
		Local savedStack:TMap = globals.stack
		Local savedCommands:TMap = processor.commands
		Local savedDirectory:String = CurrentDir()
		globals.vars = ModuleConfigCloneMap(savedVars)
		globals.stack = New TMap
		processor.commands = ModuleConfigCloneMap(savedCommands)
		For Local option:String = EachIn ["cc_opts", "c_opts", "cpp_opts", "asm_opts", "ld_opts"]
			globals.SetVar(option, New TOptionVariable)
		Next
		globals.SetVar("user_defs", "")
		globals.SetVar("MODPATH", directory)
		Local savedLoading:Int = processor.loadingModuleConfig
		processor.loadingModuleConfig = True
		globals.SetVar("_MODULE_CONFIG_ERROR", "")
		Local failure:Object
		Try
			ChangeDir(directory)
			For Local name:String = EachIn ["module.bmk"]
				If FileType(directory + "/" + name) = FILETYPE_FILE Then processor.LoadBMK(directory + "/" + name, True)
			Next
			config.definitions = globals.Get("user_defs")
			config.ccOptions = globals.Get("cc_opts")
			config.cOptions = globals.Get("c_opts")
			config.cppOptions = globals.Get("cpp_opts")
			config.asmOptions = globals.Get("asm_opts")
			config.ldOptions = globals.Get("ld_opts")
		Catch error:Object
			failure = error
		End Try
		processor.loadingModuleConfig = savedLoading
		globals.vars = savedVars
		globals.stack = savedStack
		processor.commands = savedCommands
		ChangeDir(savedDirectory)
		If failure Then Throw failure
	End If
	content :+ config.definitions + "~n" + config.ccOptions + "~n" + config.cOptions + "~n"
	content :+ config.cppOptions + "~n" + config.asmOptions + "~n" + config.ldOptions
	config.fingerprint = TBcc2BuildManifestCodec.Digest(content)
	moduleBuildConfigs.Insert(key, config)
	Return config
End Function

Function PublishModuleConfigStamps()
	If Not (opt_standalone And opt_boot) Then
		For Local path:String = EachIn moduleConfigStamps.Keys()
			Local value:String = String(moduleConfigStamps.ValueForKey(path))
			If FileType(path) <> FILETYPE_FILE Or LoadText(path) <> value Then
				If Not processor.PublishText(value, path) Then Throw "Cannot publish module configuration stamp: " + path
			End If
		Next
	End If
	moduleConfigStamps.Clear()
End Function

Function ModuleConfigApplicationChanged:Int(path:String)
	If moduleConfigStamps.IsEmpty() And FileType(path) <> FILETYPE_FILE Then Return False
	Local content:String
	For Local key:String = EachIn moduleConfigStamps.Keys()
		content :+ key + "~n" + String(moduleConfigStamps.ValueForKey(key)) + "~n"
	Next
	Local fingerprint:String = TBcc2BuildManifestCodec.Digest(content)
	Local changed:Int = FileType(path) <> FILETYPE_FILE Or LoadText(path) <> fingerprint
	moduleConfigStamps.Insert(path, fingerprint)
	Return changed
End Function
