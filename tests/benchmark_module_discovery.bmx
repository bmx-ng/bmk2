SuperStrict

Framework BRL.StandardIO

Import BRL.MaxUtil
Import BRL.FileSystem

If AppArgs.length < 2 Then Throw "usage: benchmark_module_discovery <module-root> [iterations]"

Local moduleRoot:String = RealPath(AppArgs[1])
Local iterations:Int = 20
If AppArgs.length > 2 Then iterations = Max(1, Int(AppArgs[2]))

Local directoryCount:Int
Local concreteCount:Int
Local started:Int = MilliSecs()
For Local iteration:Int = 0 Until iterations
	Local directories:TList = EnumModuleDirectories(moduleRoot)
	directoryCount = directories.Count()
	concreteCount = 0
	For Local item:TModuleDirectory = EachIn directories
		If FileType(item.SourcePath()) = FILETYPE_FILE Then concreteCount :+ 1
	Next
Next
Local elapsed:Int = MilliSecs() - started

Print "directories=" + directoryCount + " concrete=" + concreteCount + " iterations=" + iterations + " elapsed_ms=" + elapsed
