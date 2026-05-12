--!strict

local Spec = require("../src")

local results = Spec.run(function()
	require("./Expect.spec")()
	require("./Runner.spec")()
end)

if results.failed > 0 then
	error(`{results.failed} of {#results.tests} tests failed`, 0)
end
