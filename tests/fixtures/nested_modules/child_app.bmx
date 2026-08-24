SuperStrict

Framework BRL.StandardIO
Import NestedAudit.Parent.Child

Local box:TBox<String> = New TBox<String>
box.value = "nested"
Local output:String
Local wordIterator:ICloseableIterator<String> = Words<String>(box.Read())
For Local word:String = EachIn wordIterator
	output :+ word
Next
Local excitedIterator:ICloseableIterator<String> = ExcitedWords(box.Read())
For Local word:String = EachIn excitedIterator
	output :+ word
Next
Print Reader()() + ":" + output
