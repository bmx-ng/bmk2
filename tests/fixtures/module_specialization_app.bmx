SuperStrict

Framework BRL.StandardIO
Import Bcc2ManifestTest.Owner

SetOwned("module")

Local applicationOwned:TArchiveBox<String> = New TArchiveBox<String>
applicationOwned.Set("application")

If GetOwned() <> "module" Then RuntimeError "module specialization ownership"
If applicationOwned.Get() <> "application" Then RuntimeError "application specialization ownership"

Print "module-specialization-owner-ok"
