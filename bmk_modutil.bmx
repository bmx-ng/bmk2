
Strict

Import BRL.MaxUtil
Import BRL.Map
Import BRL.TextStream

Import "bmk_util.bmx"
Import "options_parser.bmx"
Import "bmk_bcc2_manifest.bmx"

Global installedModulePaths:TMap

Function InitializeInstalledModuleCatalogue()
	If installedModulePaths Then Return
	installedModulePaths = New TMap
	Local moduleRoot:String = ModulePath("")
	For Local item:TModuleDirectory = EachIn EnumModuleDirectories(moduleRoot)
		If FileType(item.SourcePath()) <> FILETYPE_FILE Then Continue
		Local key:String = item.name.ToLower()
		Local existing:String = String(installedModulePaths.ValueForKey(key))
		If existing.length Then
			Throw "Ambiguous module '" + item.name + "' maps to both '" + existing + "' and '" + item.path + "'"
		End If
		installedModulePaths.Insert(key, item.path)
	Next
End Function

Function InstalledModulePath:String(moduleName:String)
	InitializeInstalledModuleCatalogue()
	Local path:String = String(installedModulePaths.ValueForKey(moduleName.ToLower()))
	If path.length Then Return path
	Return ModulePath(moduleName)
End Function

Const SOURCE_UNKNOWN:Int = 0
Const SOURCE_BMX:Int = $01
Const SOURCE_IFACE:Int = $02
Const SOURCE_C:Int = $04
Const SOURCE_HEADER:Int = $08
Const SOURCE_ASM:Int = $10
Const SOURCE_RES:Int = $20
'Const SOURCE_PYTHON:Int = $20
'Const SOURCE_PERL:Int = $40
'Const SOURCE_RUBY:Int = $80
' etc ?

Const STAGE_GENERATE:Int = 0
Const STAGE_FASM2AS:Int = 1
Const STAGE_OBJECT:Int = 2
Const STAGE_LINK:Int = 3
Const STAGE_MERGE:Int = 4
Const STAGE_APP_LINK:Int = 5

Function FindBlitzMaxLineCommentStart:Int(line:String)
	Local index:Int
	Local inString:Int
	Local inMultiline:Int
	While index < line.length
		If Not inString And index + 2 < line.length And line[index] = 34 And line[index + 1] = 34 And line[index + 2] = 34 Then
			inMultiline = Not inMultiline
			index :+ 3
			Continue
		End If
		If inMultiline Then
			index :+ 1
			Continue
		End If
		If inString And line[index] = 126 And index + 1 < line.length Then
			index :+ 2
			Continue
		End If
		If line[index] = 34 Then
			inString = Not inString
			index :+ 1
			Continue
		End If
		If Not inString And line[index] = 39 Then Return index
		index :+ 1
	Wend
	Return -1
End Function

Type TSourceFile
	Field ext$		'one of: "bmx", "i", "c", "cpp", "m", "s", "h"
	Field exti:Int
	Field path$
	Field modid$
	Field framewk$
	Field info:TList=New TList

	Field modimports:TList=New TList
	
	Field imports:TList=New TList
	' Lexical native-option state at each quoted Import. This is parallel to
	' imports so duplicate imports at different push/pop scopes remain distinct.
	Field importOptions:TList=New TList
	Field includes:TList=New TList
	Field incbins:TList=New TList
	Field hashes:TMap=New TMap
	
	Field pragmas:TList = New TList
	
	Field stage:Int
	Field deps:TMap = New TMap
	Field moddeps:TMap
	Field processed:Int
	Field arc_path:String
	Field iface_path:String
	Field iface_path2:String
	Field obj_path:String
	Field time:Int
	Field obj_time:Int
	Field arc_time:Int
	Field asm_time:Int
	Field iface_time:Int
	Field gen_time:Int
	Field requiresBuild:Int
	Field dontBuild:Int
	Field depsList:TList
	Field ext_files:TList
	
	Field merge_path:String
	Field merge_time:Int
	
	Field cc_opts:String
	Field bcc_opts:String
	Field cpp_opts:String
	Field c_opts:String
	Field asm_opts:String
	
	Field mod_opts:TModOpt
	Field includePaths:TOrderedMap = New TOrderedMap
	Field includePathString:String
	
	Field pct:Int
	
	Field linksCache:TList
	Field optsCache:TList
	Field lastCache:Int = -1
	Field doneLinks:Int
	'cache calculated MaxLinkTime()-value for faster lookups
	Field maxLinkTimeCache:Int = -1
	Field maxIfaceTimeCache:Int = -1
	Field maxGeneratedHeaderTimeCache:Int = -1
	
	Field isInclude:Int
	Field owner_path:String
	Field bcc2BuildRoot:String
	Field bcc2ManifestPath:String
	Field bcc2Manifest:TBcc2BuildManifest
	Field bcc2ManifestChecked:Int
	Field bcc2FreshnessChecked:Int
	Field bcc2OwnedSource:Int
	Field bcc2ApplicationSource:Int
	Field bcc2SourceModuleName:String
	Field bcc2SourceUnitPath:String
	
	' add cc_opts or ld_opts
	Method AddModOpt(opt:String)
		If Not mod_opts Then
			mod_opts = New TModOpt
		End If
		mod_opts.AddOption(opt, path)
	End Method
	
	Method MaxObjTime:Int()
		' Dependency graphs converge heavily. Keep visitation local to this query so
		' object timestamps can still change safely between build phases.
		Return MaxObjTimeVisited(New TMap)
	End Method

	Method MaxObjTimeVisited:Int(visited:TMap)
		If visited.Contains(Self) Then Return 0
		visited.Insert(Self, Self)

		Local t:Int = obj_time
		If bcc2Manifest Then
			For Local link:TBcc2BuildLink = EachIn bcc2Manifest.links
				t = Max(t, FileTime(TBcc2BuildManifestCodec.Resolve(bcc2BuildRoot, link.objectPath)))
			Next
		End If
		If depsList Then
			For Local s:TSourceFile = EachIn depsList
				Local st:Int = s.MaxObjTimeVisited(visited)
				If st > t Then
					t = st
				End If
			Next
		End If
		Return t
	End Method

	Method GetObjs(list:TList)
		' Avoid recursively expanding every distinct path to a shared dependency.
		If list Then GetObjsVisited(list, New TMap)
	End Method

	Method GetObjsVisited(list:TList, visited:TMap)
		If visited.Contains(Self) Then Return
		visited.Insert(Self, Self)

		If Not stage Then
			If Not list.Contains(obj_path) Then
				list.AddLast(obj_path)
			End If
			AddBcc2Objects(list)
		End If

		If depsList Then
			For Local s:TSourceFile = EachIn depsList
				s.GetObjsVisited(list, visited)
			Next
		End If
	End Method

	Method AddBcc2Objects(list:TList)
		If Not list Or Not bcc2Manifest Then Return
		For Local link:TBcc2BuildLink = EachIn bcc2Manifest.links
			Local path:String = TBcc2BuildManifestCodec.Resolve(bcc2BuildRoot, link.objectPath)
			If Not list.Contains(path) Then list.AddLast(path)
		Next
	End Method

	Method SetRequiresBuild(enable:Int)
		If requiresBuild <> enable Then
			requiresBuild = enable
			'seems our information is outdated now
			If requiresBuild Then
				maxLinkTimeCache = -1
				maxIfaceTimeCache = -1
			End If
		End If
	End Method

	Method MaxLinkTime:Int(modsOnly:Int = False)
		If maxLinkTimeCache = -1 Then
			Local t:Int
			If modid Then
				t = arc_time
			Else
				t = obj_time
			End If
			If bcc2Manifest Then
				For Local link:TBcc2BuildLink = EachIn bcc2Manifest.links
					t = Max(t, FileTime(TBcc2BuildManifestCodec.Resolve(bcc2BuildRoot, link.objectPath)))
				Next
			End If
			If depsList Then
				For Local s:TSourceFile = EachIn depsList
					Local st:Int = s.MaxLinkTime(modsOnly)
					If st > t Then
						t = st
					End If
				Next
			End If
			If moddeps Then
				For Local s:TSourceFile = EachIn moddeps.Values()
					Local st:Int = s.MaxLinkTime(True)
					If st > t Then
						t = st
					End If
				Next
			End If

			maxLinkTimeCache = t
		End If

		Return maxLinkTimeCache
	End Method
	
	Method MakeFatter(list:TList, o_path:String)
		Local ext:String = ExtractExt(o_path)
		If ext = "o" Then
			Local file:String = StripExt(o_path)
			Local fp:String = StripExt(file)
			Select ExtractExt(file)
				Case "arm64"
					fp :+ ".armv7.o"
				Case "armv7"
					fp :+ ".arm64.o"
				Case "x86"
					fp :+ ".x64.o"
				Case "x64"
					fp :+ ".x86.o"
			End Select
			If Not list.Contains(fp) Then
				list.AddLast(fp)
				
				linksCache.AddLast(fp)
			End If
		End If
	End Method

	Method GetLinks(list:TList, opts:TList, modsOnly:Int = False, cList:TList = Null, cOpts:TList = Null)

		If linksCache Then
		
			If lastCache <> modsOnly Then
				linksCache = Null
				optsCache = Null
				doneLinks = False
			End If
		
		End If
		
		If doneLinks Then
			Return
		End If
		
		doneLinks = True

		If Not linksCache Then
			linksCache = New TList
			optsCache = New TList
			lastCache = modsOnly
		

			If list And (stage = STAGE_LINK Or stage = STAGE_APP_LINK) Then
				If Not modid Then
					If Not list.Contains(obj_path) Then
						list.AddLast(obj_path)
						
						linksCache.AddLast(obj_path)
					
						If opt_universal And processor.Platform() = "ios" Then
							MakeFatter(list, obj_path)
						End If
					End If
				End If
			End If

			If list And Not stage And bcc2Manifest Then
				For Local link:TBcc2BuildLink = EachIn bcc2Manifest.links
					Local path:String = TBcc2BuildManifestCodec.Resolve(bcc2BuildRoot, link.objectPath)
					If Not list.Contains(path) Then
						list.AddLast(path)
						linksCache.AddLast(path)
					End If
				Next
			End If

			If depsList And list Then
				For Local s:TSourceFile = EachIn depsList
					If Not modsOnly Or (modsOnly And s.modid) Then
						If Not stage Then
							If Not s.modid Then
								If s.obj_path And Not list.Contains(s.obj_path) Then
									list.AddLast(s.obj_path)
									
									linksCache.AddLast(s.obj_path)
									
									If opt_universal And processor.Platform() = "ios" Then
										MakeFatter(list, s.obj_path)
									End If
								End If
							End If
						End If
					End If

					If s.exti = SOURCE_BMX Or s.exti = SOURCE_IFACE Or s.modid Or s.exti = SOURCE_RES Then
						s.GetLinks(list, opts, modsOnly, linksCache, optsCache)
					End If
	
				Next
			End If
	
			If moddeps Then
				For Local s:TSourceFile = EachIn moddeps.Values()
					s.GetLinks(list, opts, True, linksCache, optsCache)
				Next
			End If
	
			If mod_opts Then
				For Local f:String = EachIn mod_opts.ld_opts
					Local p:String = TModOpt.SetPath(f, ExtractDir(path))
					If Not list.Contains(p) Then
						list.AddLast(p)
						
						linksCache.AddLast(p)
					End If
				Next
			End If
		
			If ext_files Then
				For Local f:String = EachIn ext_files
					' remove previous link, add latest to the end...
					If opts.Contains(f) Then
						opts.Remove(f)
						
						optsCache.Remove(f)
					End If
					opts.AddLast(f)
					
					optsCache.AddLast(f)
				Next
			End If
			
			If cList Then
				For Local s:String = EachIn linksCache
					cList.AddLast(s)
				Next
				For Local f:String = EachIn optsCache
					If cOpts.Contains(f) Then
						cOpts.Remove(f)
					End If
					cOpts.AddLast(f)
				Next
			End If

		Else

			For Local s:String = EachIn linksCache
				list.AddLast(s)
			Next
		
			For Local f:String = EachIn optsCache
				If opts.Contains(f) Then
					opts.Remove(f)
				End If
				opts.AddLast(f)
			Next

			If cList Then
				For Local s:String = EachIn linksCache
					cList.AddLast(s)
				Next
				For Local f:String = EachIn optsCache
					If cOpts.Contains(f) Then
						cOpts.Remove(f)
					End If
					cOpts.AddLast(f)
				Next
			End If

		End If

	End Method

	Method MaxIfaceTime:Int()
		If maxIfaceTimeCache = -1 Then
			Local t:Int = iface_time
			If depsList Then
				For Local s:TSourceFile = EachIn depsList
					Local st:Int = s.MaxIFaceTime()
					If st > t Then
						t = st
					End If
				Next
			End If
			If moddeps Then
				For Local s:TSourceFile = EachIn moddeps.Values()
					Local st:Int = s.MaxIFaceTime()
					If st > t Then
						t = st
					End If
				Next
			End If
			
			maxIfaceTimeCache = t
			
		End If

		Return maxIfaceTimeCache
	End Method

	Method MaxGeneratedHeaderTime:Int()
		If maxGeneratedHeaderTimeCache = -1 Then
			Local t:Int
			If ext.ToLower() = "bmx" And obj_path Then
				t = FileTime(StripExt(obj_path) + ".h")
			End If
			If depsList Then
				For Local source:TSourceFile = EachIn depsList
					t = Max(t, source.MaxGeneratedHeaderTime())
				Next
			End If
			If moddeps Then
				For Local source:TSourceFile = EachIn moddeps.Values()
					t = Max(t, source.MaxGeneratedHeaderTime())
				Next
			End If
			maxGeneratedHeaderTimeCache = t
		End If
		Return maxGeneratedHeaderTimeCache
	End Method

	Method CopyInfo(source:TSourceFile)
		source.ext = ext
		source.exti = exti
		source.path = path
		source.modid = modid
		source.framewk = framewk
		source.info = info
		source.processed = processed
		source.arc_path = arc_path
		source.iface_path = iface_path
		source.iface_path2 = iface_path2
		source.obj_path = obj_path
		source.time = time
		source.obj_time = obj_time
		source.arc_time = arc_time
		source.iface_time = iface_time
		source.gen_time = gen_time
		source.requiresBuild = requiresBuild
		source.dontBuild = dontBuild
		source.cc_opts = cc_opts
		source.bcc_opts = bcc_opts
		source.merge_path = merge_path
		source.merge_time = merge_time
		source.cpp_opts = cpp_opts
		source.c_opts = c_opts
		source.asm_opts = asm_opts
		source.bcc2BuildRoot = bcc2BuildRoot
		source.bcc2ManifestPath = bcc2ManifestPath
		source.bcc2Manifest = bcc2Manifest
		source.bcc2OwnedSource = bcc2OwnedSource
		source.bcc2ApplicationSource = bcc2ApplicationSource
		source.bcc2SourceModuleName = bcc2SourceModuleName
		source.bcc2SourceUnitPath = bcc2SourceUnitPath
		source.CopyIncludePaths(includePaths)
		source.maxLinkTimeCache = maxLinkTimeCache
		source.maxIfaceTimeCache = maxIfaceTimeCache
		source.maxGeneratedHeaderTimeCache = maxGeneratedHeaderTimeCache
	End Method
	
	Method GetSourcePath:String()
		Local p:String
		Select stage
			Case STAGE_GENERATE
				p = path
			Case STAGE_FASM2AS
				p = StripExt(obj_path) + ".s"
			Case STAGE_OBJECT
				p = StripExt(obj_path) + ".c"
			Case STAGE_LINK, STAGE_APP_LINK
				p = obj_path
			Case STAGE_MERGE
				p = arc_path
		End Select
		Return p
	End Method
	
	Method GetIncludePaths:String()
		If Not includePathString Then
			For Local path:String = EachIn includePaths.OrderedKeys()
				includePathString :+ path
			Next
		End If
		Return includePathString
	End Method
	
	Method AddIncludePath(path:String)
		includePaths.Insert(path, path)
		includePathString = ""
	End Method
	
	Method CopyIncludePaths(paths:TOrderedMap)
		For Local path:String = EachIn paths.OrderedKeys()
			includePaths.Insert(path, path)
		Next
		includePathString = ""
	End Method
	
End Type

Type TSourceImportOptions
	Field ccOpts:String
	Field asmOpts:String
End Type

Function SourcePragmaWord:String(line:String, cursor:Int Var)
	While cursor < line.length And (line[cursor] = 32 Or line[cursor] = 9)
		cursor :+ 1
	Wend
	Local start:Int = cursor
	While cursor < line.length And line[cursor] <> 32 And line[cursor] <> 9
		cursor :+ 1
	Wend
	Return line[start..cursor]
End Function

Function PopSourceOptionState:TOptionVariable(stack:TList, current:TOptionVariable)
	If stack And Not stack.IsEmpty() Then Return TOptionVariable(stack.RemoveLast())
	Return current
End Function

' Model only the built-in native option pragmas needed while discovering the
' import graph. Arbitrary bmk commands still execute once, at the source's
' normal generation stage, and are deliberately not run during a read-only
' dependency scan.
Function ApplySourceImportPragma(line:String, ccState:TOptionVariable Var, asmState:TOptionVariable Var, ccStack:TList, asmStack:TList)
	Local cursor:Int
	Local command:String = SourcePragmaWord(line, cursor).ToLower()
	Local key:String = SourcePragmaWord(line, cursor)
	Local value:String = line[cursor..].Trim()
	Select command
		Case "push"
			Select key.ToLower()
				Case "cc_opts"
					ccStack.AddLast(ccState.Clone())
				Case "asm_opts"
					asmStack.AddLast(asmState.Clone())
			End Select
		Case "pop"
			Select key.ToLower()
				Case "cc_opts"
					ccState = PopSourceOptionState(ccStack, ccState)
				Case "asm_opts"
					asmState = PopSourceOptionState(asmStack, asmState)
			End Select
		Case "pushall"
			ccStack.AddLast(ccState.Clone())
			asmStack.AddLast(asmState.Clone())
		Case "popall"
			ccState = PopSourceOptionState(ccStack, ccState)
			asmState = PopSourceOptionState(asmStack, asmState)
		Case "addccopt"
			ccState.AddVar(key, value)
		Case "setccopt"
			ccState.SetVar(key, value)
		Case "rmccopt"
			ccState.RemoveVar(key)
		Case "addwin32ccopt"
			If processor.Platform() = "win32" Then ccState.AddVar(key, value)
		Case "setwin32ccopt"
			If processor.Platform() = "win32" Then ccState.SetVar(key, value)
		Case "setwin32x86ccopt"
			If processor.Platform() = "win32" And processor.CPU() = "x86" Then ccState.SetVar(key, value)
		Case "setwin32x64ccopt"
			If processor.Platform() = "win32" And processor.CPU() = "x64" Then ccState.SetVar(key, value)
		Case "addmacccopt"
			If processor.Platform() = "macos" Then ccState.AddVar(key, value)
		Case "setmacccopt"
			If processor.Platform() = "macos" Then ccState.SetVar(key, value)
		Case "addmacppcccopt"
			If processor.Platform() = "macos" And processor.CPU() = "ppc" Then ccState.AddVar(key, value)
		Case "setmacppcccopt"
			If processor.Platform() = "macos" And processor.CPU() = "ppc" Then ccState.SetVar(key, value)
		Case "addmacx86ccopt"
			If processor.Platform() = "macos" And processor.CPU() = "x86" Then ccState.AddVar(key, value)
		Case "setmacx86ccopt"
			If processor.Platform() = "macos" And processor.CPU() = "x86" Then ccState.SetVar(key, value)
		Case "addlinuxccopt"
			If processor.Platform() = "linux" Or processor.Platform() = "android" Or processor.Platform() = "raspberrypi" Then ccState.AddVar(key, value)
		Case "setlinuxccopt"
			If processor.Platform() = "linux" Or processor.Platform() = "android" Or processor.Platform() = "raspberrypi" Then ccState.SetVar(key, value)
		Case "addasmopt"
			asmState.AddVar(key, value)
		Case "rmasmopt"
			asmState.RemoveVar(key)
	End Select
End Function

Function ValidSourceExt( ext:Int )
	If ext & $FFFF Then
		Return True
	End If
	Return False
End Function

Function ParseSourceFile:TSourceFile( path$ )

	Local info:SFileStat
	If Not FileStat(path, info) Or info.fileType <> FILETYPE_FILE Then Return

	Local ext$=ExtractExt( path ).ToLower()
	Local exti:Int = String(processor.RunCommand("source_type", [ext])).ToInt()
	
	' don't want headers?
	If exti = SOURCE_HEADER Return

	If Not ValidSourceExt( exti ) Return

	Local file:TSourceFile=New TSourceFile
	file.ext=ext
	file.exti=exti
	file.path=path
	file.time = info.modifiedTime
	
	Local str$=LoadText( path )

	Local pos,in_rem,cc=True
	Local in_multiline:Int = False

	SetCompilerValues()
	
	Local lineCount:Int
	Local importCcState:TOptionVariable = New TOptionVariable
	Local importAsmState:TOptionVariable = New TOptionVariable
	Local importCcStack:TList = New TList
	Local importAsmStack:TList = New TList
	
	While pos<Len(str)

		Local eol=str.Find( "~n",pos )
		If eol=-1 eol=Len(str)

		lineCount :+ 1

		Local line$=str[pos..eol].Trim()
		pos=eol+1

		Local pragmaLine:String
		Local n:Int = -1
		If Not in_rem And Not in_multiline Then n = FindBlitzMaxLineCommentStart(line)
		If n <> -1 Then
			Local commentBody:String = line[n + 1..].Trim()
			If commentBody.ToLower().StartsWith("@bmk") Then pragmaLine = commentBody[4..]
		End If
		
		Select exti
		Case SOURCE_BMX, SOURCE_IFACE

			n = FindBlitzMaxLineCommentStart(line)
			If n<>-1 line=line[..n]
			
			If Not line And Not pragmaLine Continue

			Local lline$=line.Tolower()

			If in_rem
				If lline[..6]="endrem" Or lline[..7]="end rem" 
					in_rem=False
				EndIf
				Continue
			End If

			' First, check if we are inside a multiline string.
			If in_multiline Then
				' Look for the closing triple quotes.
				If line.Find("~q~q~q") <> -1 Then
					in_multiline = False
				End If
				Continue  ' Skip processing any directives while in a multiline string.
			End If

			If Not in_rem And lline[..3]="rem"
				in_rem=True
				Continue
			EndIf

			' Now, check for the start of a multiline string.
			Local tripleStart:Int = line.Find("~q~q~q")
			If tripleStart <> -1 Then
				Local tripleEnd:Int = line.Find("~q~q~q", tripleStart + 3)
				If tripleEnd = -1 Then
					in_multiline = True
					' Optionally remove the part after the opening triple quotes:
					line = line[..tripleStart - 1].Trim()
					If line = "" Then Continue
				Else
					' If both start and end markers are on this line,
					' remove the content between them.
					line = (line[..tripleStart - 1] + " " + line[tripleEnd + 3..]).Trim()
				End If
			End If

			Local cmopt:String = lline.Trim()
			If cmopt[..1]="?"
				Local t$=cmopt[1..]
				Try
					cc = EvalOption(t)
				Catch e:String
					WriteStderr "Compile Error: " + e + "~n[" + path + ";" + lineCount + ";1]~n"
					Throw e
				End Try
			EndIf

			If Not cc Continue
			
			Local i:Int
			' new pragma stuff
			If pragmaLine Then
				Local lpragma:String = pragmaLine.ToLower()
				i = 0
				While i<lpragma.length And Not (CharIsAlpha(lpragma[i]) Or CharIsDigit(lpragma[i]) Or lpragma[i] = Asc("@"))
					i:+1
				Wend
				file.pragmas.AddLast pragmaLine[i..]
				ApplySourceImportPragma(pragmaLine[i..], importCcState, importAsmState, importCcStack, importAsmStack)
			End If

			If lline.length And Not CharIsAlpha( lline[0] ) Continue

			i=1
			While i<lline.length And (CharIsAlpha(lline[i]) Or CharIsDigit(lline[i]))
				i:+1
			Wend
			If i=lline.length Continue
			
			Local key$=lline[..i]
			
			Local val$=line[i..].Trim(),qval$,qext$
			If val.length>1 And val[0]=34 And val[val.length-1]=34
				qval=val[1..val.length-1]
			EndIf

			Select key
			Case "module"
				file.modid=val.ToLower()
			Case "framework"
				file.framewk=val.ToLower()
			Case "import"
				If qval
					file.imports.AddLast ReQuote(qval)
					Local importOptions:TSourceImportOptions = New TSourceImportOptions
					importOptions.ccOpts = importCcState.ToString()
					importOptions.asmOpts = importAsmState.ToString()
					file.importOptions.AddLast(importOptions)
				Else
					file.modimports.AddLast val.ToLower()
				EndIf
			Case "incbin"
				If qval
					file.incbins.AddLast qval
				EndIf
			Case "include"
				If qval
					file.includes.AddLast qval
				EndIf
			Case "moduleinfo"
				If qval
					file.info.AddLast qval
					file.AddModOpt(qval) ' bmk2
					'If mod_opts mod_opts.addOption(qval) ' BaH
				EndIf
			End Select
		Case SOURCE_C, SOURCE_HEADER '"c","m","h","cpp","cxx","hpp","hxx"
		'	If line[..8]="#include"
		''		Local val$=line[8..].Trim(),qval$,qext$
			'	If val.length>1 And val[0]=34 And val[val.length-1]=34
			'		qval=val[1..val.length-1]
			'	EndIf
			'	If qval
			'		file.includes.AddLast qval
			'	EndIf
			'EndIf
		End Select

	Wend
	
	Return file

End Function

Function ParseISourceFile:TSourceFile( path$ )

	Local info:SFileStat
	If Not FileStat(path, info) Or info.fileType <> FILETYPE_FILE Then Return

	Local file:TSourceFile=New TSourceFile
	file.ext="i"
	file.exti=SOURCE_IFACE
	file.path=path
	file.time = info.modifiedTime
	
	Local str$=LoadText( path )

	Local pos,in_rem,cc=True

	While pos<Len(str)

		Local eol=str.Find( "~n",pos )
		If eol=-1 eol=Len(str)

		Local line$=str[pos..eol].Trim()
		pos=eol+1

		Local lline$=line.Tolower()

		Local i:Int

		If lline.length And Not CharIsAlpha( lline[0] ) Continue

		i=1
		While i<lline.length And (CharIsAlpha(lline[i]) Or CharIsDigit(lline[i]))
			i:+1
		Wend
		If i=lline.length Continue
		
		Local key$=lline[..i]
		
		Local val$=line[i..].Trim(),qval$,qext$
		If val.length>1 And val[0]=34 And val[val.length-1]=34
			qval=val[1..val.length-1]
		EndIf

		Select key
		Case "module"
			file.modid=val.ToLower()
		Case "import"
			If qval
				Local q:String = ReQuote(qval)
				If q.StartsWith("-") Then
					file.imports.AddLast q
				End If
			Else
				file.modimports.AddLast val.ToLower()
			EndIf
		Case "moduleinfo"
			If qval
				file.info.AddLast qval
				file.AddModOpt(qval) ' bmk2
				'If mod_opts mod_opts.addOption(qval) ' BaH
			EndIf
		case "#pragma"
			file.pragmas.AddLast val
		End Select

	Wend
	
	Return file

End Function

Function ValidatePlatformArchitecture()
	Local valid:Int = False
	
	Local platform:String = processor.Platform()
	Local arch:String = processor.CPU()

	Select platform
		Case "win32"
			If arch = "x86" Or arch = "x64" or arch = "armv7" or arch = "arm64" Then
				valid = True
			End If
		Case "linux"
			If arch = "x86" Or arch = "x64" Or arch = "arm" Or arch="arm64" Or arch = "riscv32" Or arch = "riscv64" Then
				valid = True
			End If
		Case "macos", "osx"
			If arch = "x86" Or arch = "x64" Or arch = "ppc" Or arch = "arm64" Then
				valid = True
			End If
		Case "ios"
			If arch = "x86" Or arch = "x64" Or arch = "armv7" Or arch = "arm64" Then
				valid = True
			End If
		Case "android"
			If arch = "x86" Or arch = "x64" Or arch = "arm" Or arch = "armeabi"  Or arch = "armeabiv7a"  Or arch = "arm64v8a" Then
				valid = True
			End If
		Case "raspberrypi"
			If arch = "arm" Or arch="arm64" Then
				valid = True
			End If
		Case "pico"
			If arch = "arm" Then
				valid = True
			End If
		Case "emscripten"
			If arch = "js" Then
				valid = True
			End If
		Case "nx"
			If arch = "arm64" Then
				valid = True
			End If
		Case "haiku"
			If arch = "x86" Or arch = "x64" Or arch = "arm64" Then
				valid = True
			End If
	End Select
	
	If Not valid Then
		CmdError "Invalid Platform/Architecture configuration : " + platform + "/" + arch
	End If
End Function

Function SetCompilerValues()

	compilerOptions = New TValues

	compilerOptions.Add("debug", opt_debug)
	compilerOptions.Add("threaded", opt_threaded)

	compilerOptions.Add("x86", processor.CPU()="x86")

	compilerOptions.Add("ppc", processor.CPU()="ppc")
	compilerOptions.Add("x64", processor.CPU()="x64")
	compilerOptions.Add("arm", processor.CPU()="arm")
	compilerOptions.Add("armeabi", processor.CPU()="armeabi")
	compilerOptions.Add("armeabiv7a", processor.CPU()="armeabiv7a")
	compilerOptions.Add("arm64v8a", processor.CPU()="arm64v8a")
	compilerOptions.Add("armv7", processor.CPU()="armv7")
	compilerOptions.Add("arm64", processor.CPU()="arm64")
	compilerOptions.Add("riscv32", processor.CPU()="riscv32")
	compilerOptions.Add("riscv64", processor.CPU()="riscv64")
	compilerOptions.Add("js", processor.CPU()="js")

	compilerOptions.Add("ptr32", processor.CPU()="x86" Or processor.CPU()="ppc" Or processor.CPU()="arm" Or processor.CPU()="armeabi" Or processor.CPU()="armeabiv7a" Or processor.CPU()="armv7" Or processor.CPU()="js" Or processor.CPU()="riscv32")
	compilerOptions.Add("ptr64", processor.CPU()="x64" Or processor.CPU()="arm64v8a" Or processor.CPU()="arm64" Or processor.CPU()="riscv64")

	Local longInt8:Int = True
	' on windows and 32-bit platforms longint is 4 bytes
	If processor.Platform()="win32" Or processor.Platform()="win64" Or processor.Platform()="pico" Or processor.CPU()="x86" Or processor.CPU()="ppc" Then
		longInt8 = False
	End If
	compilerOptions.Add("longint8", longInt8)
	compilerOptions.Add("longint4", Not longInt8)
	compilerOptions.Add("ulongint8", longInt8)
	compilerOptions.Add("ulongint4", Not longInt8)
	
	compilerOptions.Add("win32", processor.Platform() = "win32")
	compilerOptions.Add("win32x86", processor.Platform() = "win32" And processor.CPU()="x86")
	compilerOptions.Add("win32ppc", processor.Platform() = "win32" And processor.CPU()="ppc")
	compilerOptions.Add("win32x64", processor.Platform() = "win32" And processor.CPU()="x64")
	compilerOptions.Add("win32armv7", processor.Platform() = "win32" And processor.CPU()="armv7")
	compilerOptions.Add("win32arm64", processor.Platform() = "win32" And processor.CPU()="arm64")

	compilerOptions.Add("linux", processor.Platform() = "linux" Or processor.Platform() = "android" Or processor.Platform() = "raspberrypi")
	compilerOptions.Add("linuxx86", (processor.Platform() = "linux" Or processor.Platform() = "android") And processor.CPU()="x86")
	compilerOptions.Add("linuxppc", processor.Platform() = "linux" And processor.CPU()="ppc")
	compilerOptions.Add("linuxx64", (processor.Platform() = "linux" Or processor.Platform() = "android") And processor.CPU()="x64")
	compilerOptions.Add("linuxarm", (processor.Platform() = "linux" Or processor.Platform() = "android" Or processor.Platform() = "raspberrypi") And processor.CPU()="arm")
	compilerOptions.Add("linuxarm64", ((processor.Platform() = "linux" Or processor.Platform() = "raspberrypi") And processor.CPU()="arm64") Or (processor.Platform() = "android" And processor.CPU()="arm64v8a"))
	compilerOptions.Add("linuxriscv32", (processor.Platform() = "linux" And processor.CPU()="riscv32"))
	compilerOptions.Add("linuxriscv64", ((processor.Platform() = "linux" And processor.CPU()="riscv64")))

	compilerOptions.Add("macos", processor.Platform() = "macos" Or processor.Platform() = "osx" Or processor.Platform() = "ios")
	compilerOptions.Add("macosx86", (processor.Platform() = "macos"Or processor.Platform() = "osx" Or processor.Platform() = "ios") And processor.CPU()="x86")
	compilerOptions.Add("macosppc", (processor.Platform() = "macos" Or processor.Platform() = "osx") And processor.CPU()="ppc")
	compilerOptions.Add("macosx64", (processor.Platform() = "macos" Or processor.Platform() = "osx" Or processor.Platform() = "ios") And processor.CPU()="x64")
	compilerOptions.Add("macosarm64", (processor.Platform() = "macos" Or processor.Platform() = "osx" Or processor.Platform() = "ios") And processor.CPU()="arm64")
	compilerOptions.Add("osx", processor.Platform() = "macos" Or processor.Platform() = "osx")
	compilerOptions.Add("osxx86", (processor.Platform() = "macos"Or processor.Platform() = "osx") And processor.CPU()="x86")
	compilerOptions.Add("osxx64", (processor.Platform() = "macos" Or processor.Platform() = "osx") And processor.CPU()="x64")
	compilerOptions.Add("osxarm64", (processor.Platform() = "macos" Or processor.Platform() = "osx") And processor.CPU()="arm64")
	compilerOptions.Add("ios", processor.Platform() = "ios")
	compilerOptions.Add("iosx86", processor.Platform() = "ios" And processor.CPU()="x86")
	compilerOptions.Add("iosx64", processor.Platform() = "ios" And processor.CPU()="x64")
	compilerOptions.Add("iosarmv7", processor.Platform() = "ios" And processor.CPU()="armv7")
	compilerOptions.Add("iosarm64", processor.Platform() = "ios" And processor.CPU()="arm64")

	compilerOptions.Add("android", processor.Platform() = "android")
	compilerOptions.Add("androidarm", processor.Platform() = "android" And processor.CPU()="arm")
	compilerOptions.Add("androidarmeabi", processor.Platform() = "android" And processor.CPU()="armeabi")
	compilerOptions.Add("androidarmeabiv7a", processor.Platform() = "android" And processor.CPU()="armeabiv7a")
	compilerOptions.Add("androidarm64v8a", processor.Platform() = "android" And processor.CPU()="arm64v8a")

	compilerOptions.Add("raspberrypi", processor.Platform() = "raspberrypi")
	compilerOptions.Add("raspberrypiarm", processor.Platform() = "raspberrypi" And processor.CPU()="arm")
	compilerOptions.Add("raspberrypiarm64", processor.Platform() = "raspberrypi" And processor.CPU()="arm64")
	compilerOptions.Add("pico", processor.Platform() = "pico")
	compilerOptions.Add("picoarm", processor.Platform() = "pico" And processor.CPU()="arm")

	compilerOptions.Add("haiku", processor.Platform() = "haiku")
	compilerOptions.Add("haikux86", processor.Platform() = "haiku" And processor.CPU()="x86")
	compilerOptions.Add("haikux64", processor.Platform() = "haiku" And processor.CPU()="x64")
	compilerOptions.Add("haikuarm64", processor.Platform() = "haiku" And processor.CPU()="arm64")
	
	compilerOptions.Add("emscripten", processor.Platform() = "emscripten")
	compilerOptions.Add("emscriptenjs", processor.Platform() = "emscripten" And processor.CPU()="js")

	compilerOptions.Add("opengles", processor.Platform() = "android" Or processor.Platform() ="raspberrypi" Or processor.Platform() = "emscripten" Or processor.Platform() = "ios")

	compilerOptions.Add("bmxng", processor.BCCVersion() <> "BlitzMax")
	compilerOptions.Add("bmxng2", processor.BCCVersion() = "bcc2")
	compilerOptions.Add("coverage", opt_coverage)

	compilerOptions.Add("musl", processor.Platform() = "linux" Or processor.Platform() ="raspberrypi")

	compilerOptions.Add("nx", processor.Platform() = "nx")
	compilerOptions.Add("nxarm64", processor.Platform() = "nx" And processor.CPU()="arm64")

	Local userdefs:TUserDef[] = GetUserDefs()
	If userdefs Then
		For Local def:TUserDef = EachIn userdefs
			compilerOptions.Add(def.name, def.value)
		Next
	End If
End Function

Function GetUserDefs:TUserDef[]()
	Local defs:String = opt_userdefs
	If globals.Get("user_defs") Then
		If defs Then
			defs :+ ","
		End If
		defs :+ globals.Get("user_defs")
	End If
	
	Local parts:String[] = defs.ToLower().Split(",")
	Local userdefs:TUserDef[parts.length]
	Local count:Int
	For Local def:String = EachIn parts
		def = def.Trim()
		If Not def Then
			Continue
		End If

		Local name:String = def
		Local value:Int = 1
		
		Local dp:String[] = def.Split("=")
		If dp.length = 2 Then
			name = dp[0]
			value = Int(dp[1])
		End If
		Local ud:TUserDef = New TUserDef
		ud.name = name
		ud.value = value
		
		userdefs[count] = ud
		count :+ 1
	Next
	If count < parts.length Then
		userdefs = userdefs[..count]
	End If
	Return userdefs
End Function

Type TUserDef
	Field name:String
	Field value:Int = 1
End Type
