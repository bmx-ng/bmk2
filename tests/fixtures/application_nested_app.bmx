SuperStrict

Framework BRL.StandardIO

Import "nested/left/common.bmx"
Import "nested/right/common.bmx"

If LeftNestedValue() <> 20 Or RightNestedValue() <> 22 Then RuntimeError "nested quoted source linkage failed"
Print "bcc2 nested quoted application ok"
