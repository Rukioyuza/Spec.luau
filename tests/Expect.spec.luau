--!strict

local Spec = require("../src")

local describe = Spec.describe
local it = Spec.it
local expect = Spec.expect

local function failureOf(body: () -> ()): string
	local ok, err = pcall(body)
	if ok then
		error("expected the matcher to fail, it passed", 2)
	end
	return tostring(err)
end

return function(): ()
	describe("ToBe", function()
		it("passes for the same value", function()
			expect(5).toBe(5)
			expect("Text").toBe("Text")
			expect(true).toBe(true)
		end)

		it("compares tables by reference", function()
			local shared = {}
			expect(shared).toBe(shared)
			expect({}).never.toBe({})
		end)

		it("names both values when it fails", function()
			local message = failureOf(function()
				expect(1).toBe(2)
			end)
			expect(message).toContain("expected 1 to be 2")
		end)

		it("points the failure at the line that called it", function()
			local message = failureOf(function()
				expect(1).toBe(2)
			end)
			expect(message).toContain("Expect.spec")
		end)

		it("quotes strings in the message", function()
			local message = failureOf(function()
				expect("a").toBe("b")
			end)
			expect(message).toContain('expected "a" to be "b"')
		end)
	end)

	describe("Never", function()
		it("passes when the matcher would fail", function()
			expect(1).never.toBe(2)
			expect(nil).never.toBeTruthy()
			expect({ 1, 2 }).never.toContain(3)
		end)

		it("fails when the matcher would pass", function()
			local message = failureOf(function()
				expect(1).never.toBe(1)
			end)
			expect(message).toContain("expected 1 not to be 1")
		end)
	end)

	describe("ToEqual", function()
		it("passes for tables equal by value", function()
			expect({ name = "Sword", stats = { damage = 10, tags = { "Melee" } } }).toEqual({
				name = "Sword",
				stats = { damage = 10, tags = { "Melee" } },
			})
		end)

		it("passes for equal plain values", function()
			expect(3).toEqual(3)
			expect("Text").toEqual("Text")
		end)

		it("counts NaN as equal to NaN", function()
			expect({ 0 / 0 }).toEqual({ 0 / 0 })
		end)

		it("names the path to the first difference", function()
			local message = failureOf(function()
				expect({ items = { { name = "a" }, { name = "b" } } }).toEqual({
					items = { { name = "a" }, { name = "c" } },
				})
			end)
			expect(message).toContain('first difference at .items[2].name: got "b", expected "c"')
		end)

		it("reports a key missing from the actual table", function()
			local message = failureOf(function()
				expect({ a = 1 }).toEqual({ a = 1, b = 2 })
			end)
			expect(message).toContain(".b: got nil, expected 2")
		end)

		it("reports an extra key in the actual table", function()
			local message = failureOf(function()
				expect({ a = 1, b = 2 }).toEqual({ a = 1 })
			end)
			expect(message).toContain(".b: got 2, expected nil")
		end)

		it("writes keys that are not identifiers in brackets", function()
			local message = failureOf(function()
				expect({ ["two words"] = 1 }).toEqual({ ["two words"] = 2 })
			end)
			expect(message).toContain('["two words"]: got 1, expected 2')
		end)

		it("compares tables that refer to themselves", function()
			local left: { [string]: any } = { name = "Loop" }
			left.self = left
			local right: { [string]: any } = { name = "Loop" }
			right.self = right
			expect(left).toEqual(right)
		end)

		it("names both values when plain values differ", function()
			local message = failureOf(function()
				expect(1).toEqual("1")
			end)
			expect(message).toContain('expected 1 to equal "1"')
		end)

		it("fails under Never for equal tables", function()
			local message = failureOf(function()
				expect({ 1 }).never.toEqual({ 1 })
			end)
			expect(message).toContain("not to equal")
		end)
	end)

	describe("ToBeNear", function()
		it("passes within the epsilon", function()
			expect(0.1 + 0.2).toBeNear(0.3, 1e-9)
			expect(10).toBeNear(10.5, 0.5)
		end)

		it("fails outside the epsilon", function()
			local message = failureOf(function()
				expect(1).toBeNear(2, 0.5)
			end)
			expect(message).toContain("expected 1 to be within 0.5 of 2")
		end)

		it("fails for a value that is not a number", function()
			failureOf(function()
				expect("1").toBeNear(1, 1)
			end)
		end)
	end)

	describe("ToBeNil and ToBeTruthy", function()
		it("tells nil from false", function()
			expect(nil).toBeNil()
			expect(false).never.toBeNil()
			expect(false).never.toBeTruthy()
		end)

		it("counts 0 and empty strings as truthy", function()
			expect(0).toBeTruthy()
			expect("").toBeTruthy()
		end)

		it("names the value when ToBeNil fails", function()
			local message = failureOf(function()
				expect(5).toBeNil()
			end)
			expect(message).toContain("expected 5 to be nil")
		end)
	end)

	describe("ToThrow", function()
		it("passes when the function throws", function()
			expect(function()
				error("Locked")
			end).toThrow()
		end)

		it("matches the error against a pattern", function()
			expect(function()
				error("Slot 3 is locked")
			end).toThrow("Slot %d is locked")
		end)

		it("fails when the function returns", function()
			local message = failureOf(function()
				expect(function() end).toThrow()
			end)
			expect(message).toContain("expected the function to throw, it returned")
		end)

		it("fails when the error does not match", function()
			local message = failureOf(function()
				expect(function()
					error("Busy")
				end).toThrow("Locked")
			end)
			expect(message).toContain('matching "Locked", it threw:')
			expect(message).toContain("Busy")
		end)

		it("passes under Never when the function returns", function()
			expect(function() end).never.toThrow()
		end)

		it("refuses a value that is not a function, even under Never", function()
			local message = failureOf(function()
				expect(5).never.toThrow()
			end)
			expect(message).toContain("ToThrow expects a function, got 5")
		end)
	end)

	describe("ToContain", function()
		it("finds a plain substring", function()
			expect("a.b.c").toContain(".b.")
			expect("abc").never.toContain("%a")
		end)

		it("finds a value in an array or a map", function()
			expect({ "Red", "Blue" }).toContain("Blue")
			expect({ main = "Sword" }).toContain("Sword")
		end)

		it("shows the table when it fails", function()
			local message = failureOf(function()
				expect({ 1, 2 }).toContain(3)
			end)
			expect(message).toContain("expected { 1, 2 } to contain 3")
		end)

		it("refuses a value that is not a string or table", function()
			local message = failureOf(function()
				expect(5).toContain(5)
			end)
			expect(message).toContain("ToContain expects a string or a table, got 5")
		end)
	end)
end
