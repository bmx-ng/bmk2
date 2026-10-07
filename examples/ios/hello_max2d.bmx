SuperStrict

Framework Max2D.SDL3RenderMax2D
Import BRL.PolledInput

Graphics 800, 450
SetClsColor 18, 24, 36

While Not AppTerminate()
	Cls
	SetColor 50, 175, 245
	DrawRect 80, 80, 240, 140
	SetColor 255, 255, 255
	DrawText "BlitzMax + SDL3 + Max2D", 80, 250
	Flip
Wend

EndGraphics
