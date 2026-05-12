--!strict

--[=[
	Run: the self-test entry point. Runs every spec under tests with the luau CLI and throws when any
	test failed, so the process exits with an error code for CI

	Example usage:
		luau tests/Run.luau
--]=]

local Spec = require("../src")

local Results = Spec.Run(function()
	require("./Expect.spec")()
	require("./Runner.spec")()
end)

if Results.Failed > 0 then
	error(`{Results.Failed} of {#Results.Tests} tests failed`, 0)
end
