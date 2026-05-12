--!strict

--[=[
	Runner.spec: Spec.Run collects and runs suites the way its header says, and reports failures. Each
	test runs a small suite of its own with Silent set and checks the results it returns

	Return type: a body for Spec.Run
--]=]

local Spec = require("../src")

local Describe = Spec.Describe
local It = Spec.It
local Expect = Spec.Expect

type Results = Spec.Results

local SILENT: Spec.Options = { Silent = true }

local function StatusByPath(Results: Results): { [string]: Spec.Status }
	local Statuses: { [string]: Spec.Status } = {}
	for _, Result in Results.Tests do
		Statuses[Result.Path] = Result.Status
	end
	return Statuses
end

local function MessageOf(Results: Results, Path: string): string?
	for _, Result in Results.Tests do
		if Result.Path == Path and Result.Status == "Failed" then
			return Result.Message
		end
	end
	return nil
end

return function(): ()
	Describe("Results", function()
		It("counts passed, failed and skipped tests", function()
			local Results = Spec.Run(function()
				Describe("Inner", function()
					It("passes", function() end)
					It("fails", function()
						Expect(1).ToBe(2)
					end)
					Spec.Skip.It("is skipped", function() end)
				end)
			end, SILENT)

			Expect(Results.Passed).ToBe(1)
			Expect(Results.Failed).ToBe(1)
			Expect(Results.Skipped).ToBe(1)
			Expect(#Results.Tests).ToBe(3)
		end)

		It("names each test by its full path in order", function()
			local Results = Spec.Run(function()
				It("top", function() end)
				Describe("Outer", function()
					Describe("Inner", function()
						It("deep", function() end)
					end)
					It("shallow", function() end)
				end)
			end, SILENT)

			local Paths = {}
			for _, Result in Results.Tests do
				table.insert(Paths, Result.Path)
			end
			Expect(Paths).ToEqual({ "top", "Outer > Inner > deep", "Outer > shallow" })
		end)

		It("keeps the failure message of a failed test", function()
			local Results = Spec.Run(function()
				Describe("Inner", function()
					It("fails", function()
						Expect("a").ToBe("b")
					end)
				end)
			end, SILENT)

			Expect(MessageOf(Results, "Inner > fails")).ToBeTruthy()
			Expect(MessageOf(Results, "Inner > fails") :: string).ToContain('expected "a" to be "b"')
		end)

		It("reports an error that is not a string", function()
			local Results = Spec.Run(function()
				It("throws a table", function()
					error({ Code = 7 })
				end)
			end, SILENT)

			Expect(Results.Failed).ToBe(1)
			Expect(MessageOf(Results, "throws a table")).ToBeTruthy()
		end)

		It("times every test that ran", function()
			local Results = Spec.Run(function()
				It("passes", function() end)
			end, SILENT)

			Expect(Results.Tests[1].Duration >= 0).ToBe(true)
			Expect(Results.Duration >= Results.Tests[1].Duration).ToBe(true)
		end)
	end)

	Describe("Hooks", function()
		It("runs BeforeEach outer first and AfterEach inner first", function()
			local Log: { string } = {}
			Spec.Run(function()
				Spec.BeforeEach(function()
					table.insert(Log, "before outer")
				end)
				Spec.AfterEach(function()
					table.insert(Log, "after outer")
				end)
				Describe("Inner", function()
					Spec.BeforeEach(function()
						table.insert(Log, "before inner")
					end)
					Spec.AfterEach(function()
						table.insert(Log, "after inner")
					end)
					It("runs", function()
						table.insert(Log, "test")
					end)
				end)
			end, SILENT)

			Expect(Log).ToEqual({ "before outer", "before inner", "test", "after inner", "after outer" })
		end)

		It("runs hooks once for each test", function()
			local Count = 0
			Spec.Run(function()
				Spec.BeforeEach(function()
					Count += 1
				end)
				It("one", function() end)
				It("two", function() end)
			end, SILENT)

			Expect(Count).ToBe(2)
		end)

		It("runs AfterEach after a failed test", function()
			local Cleaned = false
			Spec.Run(function()
				Spec.AfterEach(function()
					Cleaned = true
				end)
				It("fails", function()
					error("Broken")
				end)
			end, SILENT)

			Expect(Cleaned).ToBe(true)
		end)

		It("fails the test and skips its body when BeforeEach throws", function()
			local BodyRan = false
			local Results = Spec.Run(function()
				Spec.BeforeEach(function()
					error("No database")
				end)
				It("needs setup", function()
					BodyRan = true
				end)
			end, SILENT)

			Expect(BodyRan).ToBe(false)
			Expect(MessageOf(Results, "needs setup") :: string).ToContain("BeforeEach failed")
		end)

		It("fails a passing test when AfterEach throws", function()
			local Results = Spec.Run(function()
				Spec.AfterEach(function()
					error("Leak")
				end)
				It("passes", function() end)
			end, SILENT)

			Expect(MessageOf(Results, "passes") :: string).ToContain("AfterEach failed")
		end)
	end)

	Describe("Skip and Only", function()
		It("skips every test in a skipped suite", function()
			local Results = Spec.Run(function()
				Spec.Skip.Describe("Off", function()
					It("one", function()
						error("should not run")
					end)
				end)
				It("on", function() end)
			end, SILENT)

			Expect(StatusByPath(Results)).ToEqual({ ["Off > one"] = "Skipped", ["on"] = "Passed" })
		end)

		It("runs only focused tests once any Only is registered", function()
			local Results = Spec.Run(function()
				It("unfocused", function() end)
				Describe("Suite", function()
					Spec.Only.It("focused", function() end)
					It("sibling", function() end)
				end)
			end, SILENT)

			Expect(StatusByPath(Results)).ToEqual({
				["unfocused"] = "Skipped",
				["Suite > focused"] = "Passed",
				["Suite > sibling"] = "Skipped",
			})
		end)

		It("runs every test inside a focused suite", function()
			local Results = Spec.Run(function()
				Spec.Only.Describe("Focused", function()
					It("one", function() end)
					It("two", function() end)
				end)
				It("outside", function() end)
			end, SILENT)

			Expect(Results.Passed).ToBe(2)
			Expect(Results.Skipped).ToBe(1)
		end)

		It("lets Skip win over Only", function()
			local Results = Spec.Run(function()
				Spec.Skip.Describe("Off", function()
					Spec.Only.It("focused", function() end)
				end)
			end, SILENT)

			Expect(StatusByPath(Results)).ToEqual({ ["Off > focused"] = "Skipped" })
		end)
	end)

	Describe("Collection", function()
		It("reports a Describe body that throws", function()
			local Results = Spec.Run(function()
				Describe("Broken", function()
					It("registered first", function() end)
					error("Typo in setup")
				end)
			end, SILENT)

			Expect(MessageOf(Results, "Broken") :: string).ToContain("Describe body failed")
			Expect(MessageOf(Results, "Broken") :: string).ToContain("Typo in setup")
			Expect(StatusByPath(Results)["Broken > registered first"]).ToBe("Passed")
		end)

		It("reports a Run body that throws", function()
			local Results = Spec.Run(function()
				error("Missing module")
			end, SILENT)

			Expect(Results.Failed).ToBe(1)
			Expect(MessageOf(Results, "Spec.Run") :: string).ToContain("Missing module")
		end)

		It("refuses It once collection has finished", function()
			Expect(function()
				It("stray", function() end)
			end).ToThrow("outside Spec%.Run")
		end)

		It("restores the outer Run after a nested one", function()
			local Results = Spec.Run(function()
				Spec.Run(function()
					It("inner", function() end)
				end, SILENT)
				It("outer", function() end)
			end, SILENT)

			Expect(StatusByPath(Results)).ToEqual({ ["outer"] = "Passed" })
		end)
	end)

	Describe("Format", function()
		It("lists each test, the failures and a summary", function()
			local Results = Spec.Run(function()
				Describe("Inner", function()
					It("passes", function() end)
					It("fails", function()
						Expect(1).ToBe(2)
					end)
					Spec.Skip.It("waits", function() end)
				end)
			end, SILENT)

			local Report = Spec.Format(Results)
			Expect(Report).ToContain("PASS  Inner > passes (")
			Expect(Report).ToContain("FAIL  Inner > fails (")
			Expect(Report).ToContain("SKIP  Inner > waits")
			Expect(Report).ToContain("Failures:")
			Expect(Report).ToContain("1) Inner > fails")
			Expect(Report).ToContain("expected 1 to be 2")
			Expect(Report).ToContain("1 passed, 1 failed, 1 skipped, 3 total in")
		end)

		It("leaves out the failures section when nothing failed", function()
			local Results = Spec.Run(function()
				It("passes", function() end)
			end, SILENT)

			Expect(Spec.Format(Results)).Never.ToContain("Failures:")
		end)
	end)
end
