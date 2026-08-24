SuperStrict

Framework BRL.StandardIO

Include "../bmk_bcc2_options.bmx"
Include "../bmk_bcc2_protocol.bmx"

Function Check(condition:Int, message:String)
	If Not condition Then Throw message
End Function

Check(NormalizeBcc2EngineProtocolLine("bcc2-engine 2~r") = "bcc2-engine 2", "Windows CRLF protocol lines discard their retained carriage return")
Check(NormalizeBcc2EngineProtocolLine("bcc2-engine 2") = "bcc2-engine 2", "Unix protocol lines remain unchanged")
Check(NormalizeBcc2EngineProtocolLine("data 1 value ") = "data 1 value ", "protocol-significant whitespace is not trimmed")

Local application:String = Bcc2CompilerConfigurationArgs("win32", "x64", True, False, True, True, True, True, "console", "~qbrl.standardio~q", "~qfeature=1~q")
Check(application = " --platform win32 --arch x64 --release --single-threaded --coverage --gdb-debug --musl --verbose --user-defs ~qfeature=1~q --app-type console --framework ~qbrl.standardio~q", "application configuration is forwarded to bcc2 deterministically")

Local moduleBuild:String = Bcc2CompilerConfigurationArgs("macos", "arm64", False, True, False, False, False, False)
Check(moduleBuild = " --platform macos --arch arm64 --debug --threaded", "module configuration omits application-only framework and type options")

Local values:String[] = Bcc2CompilerConfigurationValues("win32", "x64", True, False, True, True, True, True, "console", "brl.standardio", "feature=1")
Local expectedValues:String[] = ["--platform", "win32", "--arch", "x64", "--release", "--single-threaded", "--coverage", "--gdb-debug", "--musl", "--verbose", "--user-defs", "feature=1", "--app-type", "console", "--framework", "brl.standardio"]
Check(values.length = expectedValues.length, "engine configuration has the expected argument count")
For Local index:Int = 0 Until expectedValues.length
	Check(values[index] = expectedValues[index], "engine configuration preserves argument " + index)
Next

Local noisyFingerprint:String = Bcc2GenerationFingerprintOptions(" -g x64 -m brl.test -q -v -r -h -ud feature=1")
Local plainFingerprint:String = Bcc2GenerationFingerprintOptions(" -g x64 -m brl.test -r -h -ud feature=1")
Check(noisyFingerprint = plainFingerprint, "quiet and verbose reporting flags do not invalidate compiler generation freshness")

Check(Bcc2ApplicationIdentity("/work/tools/bmk.bmx") = "application.bmk", "application linkage identity uses the main source basename")
Check(Bcc2ApplicationIdentity("/work/tools/My-App.bmx") = "application.my_app", "application linkage identity is path-independent and C-identifier safe")
Check(Bcc2SourceUnitPath("drivers/posix/driver.bmx", "../common.bmx") = "drivers/common.bmx", "quoted source-unit paths normalize relative to their importer")
Check(Not Bcc2SourceUnitPath("root.bmx", "../outside.bmx").length, "quoted source-unit paths cannot escape their ownership root")
Local leftUnit:String = Bcc2SourceUnitAbiIdentity("nested/left/common.bmx")
Local rightUnit:String = Bcc2SourceUnitAbiIdentity("nested/right/common.bmx")
Check(leftUnit <> rightUnit And leftUnit.StartsWith("nested_left_common_") And rightUnit.StartsWith("nested_right_common_"), "same-basename nested source units receive readable collision-resistant ABI identities")

Print "bmk bcc2 compiler-option tests passed"
