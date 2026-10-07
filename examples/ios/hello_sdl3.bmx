SuperStrict

Framework SDL3.SDL3Render
Import BRL.EventQueue

Local window:TSDLWindow = TSDLWindow.Create("BlitzMax SDL3 on iOS", 800, 450, ..
	SDL_WINDOW_RESIZABLE | SDL_WINDOW_HIGH_PIXEL_DENSITY)
If Not window Then Throw SDL_GetError()

Local renderer:TSDLRenderer = TSDLRenderer.Create(window)
If Not renderer Then Throw SDL_GetError()

Local box:SSDLFRect = New SSDLFRect(80, 80, 240, 140)
Local running:Int = True
While running
	While PollEvent()
		Select EventID()
			Case EVENT_APPTERMINATE, EVENT_WINDOWCLOSE
				running = False
		End Select
	Wend
	If Not running Then Exit
	renderer.SetDrawColor(18, 24, 36)
	renderer.Clear()
	renderer.SetDrawColor(50, 175, 245)
	renderer.FillRect(box)
	renderer.Present()
Wend

renderer.Destroy()
window.Destroy()
