SuperStrict

Framework BRL.StandardIO

Import "application_quoted_generic_provider.bmx"

Global AppendQuoted:Closure<String(value:String)> = Function(value:String)
	Return value + "!"
End Function

Print QuotedTransform("seed", AppendQuoted)
