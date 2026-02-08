local f = {
	getactors = getactors,
	run_on_actor = run_on_actor or runonactor,
	run_on_actor_async = run_on_actor_async or runonactorasync,

	getactor = getactor,
	getactorid = getactorid,
	getactorbyid = getactorbyid,

	isonactor = isonactor,
	isparallel = isparallel,
	isparallellua = isparallellua,

	getthreadidentity = getthreadidentity,
	setthreadidentity = setthreadidentity,

	checkcaller = checkcaller,
	getcallingscript = getcallingscript,
}

for k, v in pairs(f) do
	print("fn", k, v ~= nil)
end

local a = f.getactors and f.getactors() or {}
print("actors", #a)

for i = 1, #a do
	print(i, a[i])
end

if a[1] and f.run_on_actor then
	f.run_on_actor(a[1], function()
		print("on actor",
			"isonactor", f.isonactor and f.isonactor(),
			"isparallel", f.isparallel and f.isparallel(),
			"isparallellua", f.isparallellua and f.isparallellua(),
			"tid", f.getthreadidentity and f.getthreadidentity(),
			"caller", f.checkcaller and f.checkcaller()
		)
	end)
end

if a[1] and f.run_on_actor_async then
	f.run_on_actor_async(a[1], function()
		print("async actor",
			"isonactor", f.isonactor and f.isonactor(),
			"isparallel", f.isparallel and f.isparallel(),
			"isparallellua", f.isparallellua and f.isparallellua()
		)
	end)
end