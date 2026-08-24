SuperStrict

Framework BRL.StandardIO
Import Bcc2ManifestTest.ClosureOwner

If ReadOwned() <> "module-owned" Then RuntimeError "module-owned Closure specialization"
Local importedReader:Closure<String()> = OwnedReader
If importedReader() <> "module-owned" Then RuntimeError "imported Closure Global"

Local addTwo:Closure<Int(value:Int)> = MakeAdder(2)
If addTwo(40) <> 42 Then RuntimeError "ordinary cross-module Closure result"

Local reader:Closure<String()> = Remember<String>("application-reader")
If reader() <> "application-reader" Then RuntimeError "source-free capturing Closure specialization"

Local lengthOf:Closure<Int(value:String)> = Function(value:String)
	Return value.length
End Function
If Apply<String, Int>("closure", lengthOf) <> 7 Then RuntimeError "source-free Closure parameter specialization"

Local doubleValue:Closure<Int(value:Int)> = Function(value:Int)
	Return value * 2
End Function
If Invoke(21, doubleValue) <> 42 Then RuntimeError "ordinary cross-module Closure parameter"

Print "module-closure-owner-ok"
