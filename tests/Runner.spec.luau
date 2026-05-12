--!strict

local Spec = require("../src")

local describe = Spec.describe
local it = Spec.it
local expect = Spec.expect

type Results = Spec.Results

local SILENT: Spec.Options = { silent = true }

local function statusByPath(results: Results): { [string]: Spec.Status }
	local statuses: { [string]: Spec.Status } = {}
	for _, result in results.tests do
		statuses[result.path] = result.status
	end
	return statuses
end

local function messageOf(results: Results, path: string): string?
	for _, result in results.tests do
		if result.path == path and result.status == "Failed" then
			return result.message
		end
	end
	return nil
end

return function(): ()
	describe("Results", function()
		it("counts passed, failed and skipped tests", function()
			local results = Spec.run(function()
				describe("Inner", function()
					it("passes", function() end)
					it("fails", function()
						expect(1).toBe(2)
					end)
					Spec.skip.it("is skipped", function() end)
				end)
			end, SILENT)

			expect(results.passed).toBe(1)
			expect(results.failed).toBe(1)
			expect(results.skipped).toBe(1)
			expect(#results.tests).toBe(3)
		end)

		it("names each test by its full path in order", function()
			local results = Spec.run(function()
				it("top", function() end)
				describe("Outer", function()
					describe("Inner", function()
						it("deep", function() end)
					end)
					it("shallow", function() end)
				end)
			end, SILENT)

			local paths = {}
			for _, result in results.tests do
				table.insert(paths, result.path)
			end
			expect(paths).toEqual({ "top", "Outer > Inner > deep", "Outer > shallow" })
		end)

		it("keeps the failure message of a failed test", function()
			local results = Spec.run(function()
				describe("Inner", function()
					it("fails", function()
						expect("a").toBe("b")
					end)
				end)
			end, SILENT)

			expect(messageOf(results, "Inner > fails")).toBeTruthy()
			expect(messageOf(results, "Inner > fails") :: string).toContain('expected "a" to be "b"')
		end)

		it("reports an error that is not a string", function()
			local results = Spec.run(function()
				it("throws a table", function()
					error({ code = 7 })
				end)
			end, SILENT)

			expect(results.failed).toBe(1)
			expect(messageOf(results, "throws a table")).toBeTruthy()
		end)

		it("times every test that ran", function()
			local results = Spec.run(function()
				it("passes", function() end)
			end, SILENT)

			expect(results.tests[1].duration >= 0).toBe(true)
			expect(results.duration >= results.tests[1].duration).toBe(true)
		end)
	end)

	describe("Hooks", function()
		it("runs BeforeEach outer first and AfterEach inner first", function()
			local log: { string } = {}
			Spec.run(function()
				Spec.beforeEach(function()
					table.insert(log, "before outer")
				end)
				Spec.afterEach(function()
					table.insert(log, "after outer")
				end)
				describe("Inner", function()
					Spec.beforeEach(function()
						table.insert(log, "before inner")
					end)
					Spec.afterEach(function()
						table.insert(log, "after inner")
					end)
					it("runs", function()
						table.insert(log, "test")
					end)
				end)
			end, SILENT)

			expect(log).toEqual({ "before outer", "before inner", "test", "after inner", "after outer" })
		end)

		it("runs hooks once for each test", function()
			local count = 0
			Spec.run(function()
				Spec.beforeEach(function()
					count += 1
				end)
				it("one", function() end)
				it("two", function() end)
			end, SILENT)

			expect(count).toBe(2)
		end)

		it("runs AfterEach after a failed test", function()
			local cleaned = false
			Spec.run(function()
				Spec.afterEach(function()
					cleaned = true
				end)
				it("fails", function()
					error("Broken")
				end)
			end, SILENT)

			expect(cleaned).toBe(true)
		end)

		it("fails the test and skips its body when BeforeEach throws", function()
			local bodyRan = false
			local results = Spec.run(function()
				Spec.beforeEach(function()
					error("No database")
				end)
				it("needs setup", function()
					bodyRan = true
				end)
			end, SILENT)

			expect(bodyRan).toBe(false)
			expect(messageOf(results, "needs setup") :: string).toContain("beforeEach failed")
		end)

		it("fails a passing test when AfterEach throws", function()
			local results = Spec.run(function()
				Spec.afterEach(function()
					error("Leak")
				end)
				it("passes", function() end)
			end, SILENT)

			expect(messageOf(results, "passes") :: string).toContain("afterEach failed")
		end)
	end)

	describe("Skip and Only", function()
		it("skips every test in a skipped suite", function()
			local results = Spec.run(function()
				Spec.skip.describe("Off", function()
					it("one", function()
						error("should not run")
					end)
				end)
				it("on", function() end)
			end, SILENT)

			expect(statusByPath(results)).toEqual({ ["Off > one"] = "Skipped", ["on"] = "Passed" })
		end)

		it("runs only focused tests once any Only is registered", function()
			local results = Spec.run(function()
				it("unfocused", function() end)
				describe("Suite", function()
					Spec.only.it("focused", function() end)
					it("sibling", function() end)
				end)
			end, SILENT)

			expect(statusByPath(results)).toEqual({
				["unfocused"] = "Skipped",
				["Suite > focused"] = "Passed",
				["Suite > sibling"] = "Skipped",
			})
		end)

		it("runs every test inside a focused suite", function()
			local results = Spec.run(function()
				Spec.only.describe("Focused", function()
					it("one", function() end)
					it("two", function() end)
				end)
				it("outside", function() end)
			end, SILENT)

			expect(results.passed).toBe(2)
			expect(results.skipped).toBe(1)
		end)

		it("lets Skip win over Only", function()
			local results = Spec.run(function()
				Spec.skip.describe("Off", function()
					Spec.only.it("focused", function() end)
				end)
			end, SILENT)

			expect(statusByPath(results)).toEqual({ ["Off > focused"] = "Skipped" })
		end)
	end)

	describe("Collection", function()
		it("reports a Describe body that throws", function()
			local results = Spec.run(function()
				describe("Broken", function()
					it("registered first", function() end)
					error("Typo in setup")
				end)
			end, SILENT)

			expect(messageOf(results, "Broken") :: string).toContain("Describe body failed")
			expect(messageOf(results, "Broken") :: string).toContain("Typo in setup")
			expect(statusByPath(results)["Broken > registered first"]).toBe("Passed")
		end)

		it("reports a Run body that throws", function()
			local results = Spec.run(function()
				error("Missing module")
			end, SILENT)

			expect(results.failed).toBe(1)
			expect(messageOf(results, "Spec.run") :: string).toContain("Missing module")
		end)

		it("refuses It once collection has finished", function()
			expect(function()
				it("stray", function() end)
			end).toThrow("outside Spec%.run")
		end)

		it("restores the outer Run after a nested one", function()
			local results = Spec.run(function()
				Spec.run(function()
					it("inner", function() end)
				end, SILENT)
				it("outer", function() end)
			end, SILENT)

			expect(statusByPath(results)).toEqual({ ["outer"] = "Passed" })
		end)
	end)

	describe("Format", function()
		it("lists each test, the failures and a summary", function()
			local results = Spec.run(function()
				describe("Inner", function()
					it("passes", function() end)
					it("fails", function()
						expect(1).toBe(2)
					end)
					Spec.skip.it("waits", function() end)
				end)
			end, SILENT)

			local report = Spec.format(results)
			expect(report).toContain("PASS  Inner > passes (")
			expect(report).toContain("FAIL  Inner > fails (")
			expect(report).toContain("SKIP  Inner > waits")
			expect(report).toContain("Failures:")
			expect(report).toContain("1) Inner > fails")
			expect(report).toContain("expected 1 to be 2")
			expect(report).toContain("1 passed, 1 failed, 1 skipped, 3 total in")
		end)

		it("leaves out the failures section when nothing failed", function()
			local results = Spec.run(function()
				it("passes", function() end)
			end, SILENT)

			expect(Spec.format(results)).never.toContain("Failures:")
		end)
	end)
end
