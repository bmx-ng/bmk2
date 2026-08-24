SuperStrict

Framework BRL.Blitz

Import "application_quoted_mid.bmx"

If ApplicationQuotedValue() <> 42 Then RuntimeError "application-owned quoted source linkage failed"
