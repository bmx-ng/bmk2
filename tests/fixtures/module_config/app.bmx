SuperStrict
Framework BRL.StandardIO
Import ConfigAudit.Choice
Import ConfigAudit.Sibling
Import ConfigAudit.Choice.Nested
?config_one Or config_two
Import "configuration-leaked.bmx"
?
Print ConfigValue() + SiblingValue()
