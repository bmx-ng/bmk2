SuperStrict

Framework BRL.StandardIO

Import "forced_conflict/shared.bmx"
Import "forced_conflict/left/use.bmx"
Import "forced_conflict/right/use.bmx"

If ForcedConflictLeftValue() <> 41 Or ForcedConflictRightValue() <> 42 Then
	RuntimeError "forced specialization conflict recovery failed"
End If

Print "forced-specialization-conflict-ok"
