SuperStrict

Import BRL.ThreadPool
Import BRL.Threads
Import "bmk_config.bmx"
Import "bmk_ng_utils.bmx"

Type TProcessManager

	Field pool:TThreadPoolExecutor
	
	Field cpuCount:Int
	Field taskLock:TMutex
	Field outstandingTasks:Int
	Field submittedTasks:Int
	Field maximumOutstandingTasks:Int
	
	Method New()
		cpuCount = GetCoreCount()
		taskLock = TMutex.Create()
		pool = TThreadPoolExecutor.newFixedThreadPool(Max(1, cpuCount - 1))
		
	End Method

	Method CheckTasks()
		' BRL.ThreadPool uses an unbounded queue. Reserve one of bmk's bounded
		' outstanding slots before submitting so a fast producer cannot enqueue an
		' entire build batch ahead of later, dependency-relevant work.
		Local waiting:Int
		Local nextTrace:Int
		Repeat
			Local reserved:Int
			taskLock.Lock()
			If outstandingTasks < pool.maxThreads Then
				outstandingTasks :+ 1
				submittedTasks :+ 1
				maximumOutstandingTasks = Max(maximumOutstandingTasks, outstandingTasks)
				reserved = True
			End If
			taskLock.Unlock()
			If reserved Then
				If waiting Then TraceBuild("worker capacity wait end")
				Return
			End If
			If Not waiting Then
				waiting = True
				nextTrace = MilliSecs() + 5000
				TraceBuild("worker capacity wait begin; outstanding=" + OutstandingTaskCount())
			Else If MilliSecs() >= nextTrace Then
				TraceBuild("worker capacity wait; outstanding=" + OutstandingTaskCount())
				nextTrace = MilliSecs() + 5000
			End If
			Delay 5
		Forever
	End Method

	Method TaskFinished()
		taskLock.Lock()
		outstandingTasks :- 1
		taskLock.Unlock()
	End Method

	Method OutstandingTaskCount:Int()
		taskLock.Lock()
		Local result:Int = outstandingTasks
		taskLock.Unlock()
		Return result
	End Method

	Method ResetStatistics()
		taskLock.Lock()
		submittedTasks = 0
		maximumOutstandingTasks = outstandingTasks
		taskLock.Unlock()
	End Method

	Method Statistics:String()
		taskLock.Lock()
		Local result:String = pool.maxThreads + " workers, " + submittedTasks + " tasks, maximum " + maximumOutstandingTasks + " outstanding"
		taskLock.Unlock()
		Return result
	End Method
	
	Method WaitForTasks()
		Local started:Int = MilliSecs()
		Local nextTrace:Int = started + 5000
		If OutstandingTaskCount() Then TraceBuild("worker drain begin; outstanding=" + OutstandingTaskCount())
		While OutstandingTaskCount()
			If MilliSecs() >= nextTrace Then
				TraceBuild("worker drain; outstanding=" + OutstandingTaskCount() + ", elapsed=" + (MilliSecs() - started) + " ms")
				nextTrace = MilliSecs() + 5000
			End If
			Delay 5
		Wend
		If MilliSecs() > started Then TraceBuild("worker drain end; elapsed=" + (MilliSecs() - started) + " ms")
	End Method
	
	Method DoSystem(cmd:String, src:String, obj:String, supp:String, publish:String = "")
		CheckTasks()

		pool.execute(New TThreadPoolTask.Create(Self, TProcessTask._DoTasks, CreateProcessTask(cmd, src, obj, supp, publish)))

	End Method

	Method AddTask:Int(func:Object(data:Object), data:Object)
		CheckTasks()

		pool.execute(New TThreadPoolTask.Create(Self, func, data))
	End Method
	
End Type

Type TThreadPoolTask Extends TRunnable

	Field manager:TProcessManager
	Field func:Object(data:Object)
	Field data:Object

	Method Create:TThreadPoolTask(manager:TProcessManager, func:Object(data:Object), data:Object)
		Self.manager = manager
		Self.func = func
		Self.data = data
		Return self
	End Method

	Method run()
		Try
			func(data)
		Finally
			manager.TaskFinished()
		End Try
	End Method

End Type
