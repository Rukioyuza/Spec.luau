--!strict

--[=[
	Expect.spec: every matcher passes and fails when it should, Never flips it, and a failure message
	names the values involved and, for ToEqual, the path to the first difference

	Return type: a body for Spec.Run
--]=]

local Spec = require("../src")

local Describe = Spec.Describe
local It = Spec.It
local Expect = Spec.Expect

local function FailureOf(Body: () -> ()): string
	local Ok, Err = pcall(Body)
	if Ok then
		error("expected the matcher to fail, it passed", 2)
	end
	return tostring(Err)
end

return function(): ()
	Describe("ToBe", function()
		It("passes for the same value", function()
			Expect(5).ToBe(5)
			Expect("Text").ToBe("Text")
			Expect(true).ToBe(true)
		end)

		It("compares tables by reference", function()
			local Shared = {}
			Expect(Shared).ToBe(Shared)
			Expect({}).Never.ToBe({})
		end)

		It("names both values when it fails", function()
			local Message = FailureOf(function()
				Expect(1).ToBe(2)
			end)
			Expect(Message).ToContain("expected 1 to be 2")
		end)

		It("points the failure at the line that called it", function()
			local Message = FailureOf(function()
				Expect(1).ToBe(2)
			end)
			Expect(Message).ToContain("Expect.spec")
		end)

		It("quotes strings in the message", function()
			local Message = FailureOf(function()
				Expect("a").ToBe("b")
			end)
			Expect(Message).ToContain('expected "a" to be "b"')
		end)
	end)

	Describe("Never", function()
		It("passes when the matcher would fail", function()
			Expect(1).Never.ToBe(2)
			Expect(nil).Never.ToBeTruthy()
			Expect({ 1, 2 }).Never.ToContain(3)
		end)

		It("fails when the matcher would pass", function()
			local Message = FailureOf(function()
				Expect(1).Never.ToBe(1)
			end)
			Expect(Message).ToContain("expected 1 not to be 1")
		end)
	end)

	Describe("ToEqual", function()
		It("passes for tables equal by value", function()
			Expect({ Name = "Sword", Stats = { Damage = 10, Tags = { "Melee" } } }).ToEqual({
				Name = "Sword",
				Stats = { Damage = 10, Tags = { "Melee" } },
			})
		end)

		It("passes for equal plain values", function()
			Expect(3).ToEqual(3)
			Expect("Text").ToEqual("Text")
		end)

		It("counts NaN as equal to NaN", function()
			Expect({ 0 / 0 }).ToEqual({ 0 / 0 })
		end)

		It("names the path to the first difference", function()
			local Message = FailureOf(function()
				Expect({ Items = { { Name = "a" }, { Name = "b" } } }).ToEqual({
					Items = { { Name = "a" }, { Name = "c" } },
				})
			end)
			Expect(Message).ToContain('first difference at .Items[2].Name: got "b", expected "c"')
		end)

		It("reports a key missing from the actual table", function()
			local Message = FailureOf(function()
				Expect({ A = 1 }).ToEqual({ A = 1, B = 2 })
			end)
			Expect(Message).ToContain(".B: got nil, expected 2")
		end)

		It("reports an extra key in the actual table", function()
			local Message = FailureOf(function()
				Expect({ A = 1, B = 2 }).ToEqual({ A = 1 })
			end)
			Expect(Message).ToContain(".B: got 2, expected nil")
		end)

		It("writes keys that are not identifiers in brackets", function()
			local Message = FailureOf(function()
				Expect({ ["two words"] = 1 }).ToEqual({ ["two words"] = 2 })
			end)
			Expect(Message).ToContain('["two words"]: got 1, expected 2')
		end)

		It("compares tables that refer to themselves", function()
			local Left: { [string]: any } = { Name = "Loop" }
			Left.Self = Left
			local Right: { [string]: any } = { Name = "Loop" }
			Right.Self = Right
			Expect(Left).ToEqual(Right)
		end)

		It("names both values when plain values differ", function()
			local Message = FailureOf(function()
				Expect(1).ToEqual("1")
			end)
			Expect(Message).ToContain('expected 1 to equal "1"')
		end)

		It("fails under Never for equal tables", function()
			local Message = FailureOf(function()
				Expect({ 1 }).Never.ToEqual({ 1 })
			end)
			Expect(Message).ToContain("not to equal")
		end)
	end)

	Describe("ToBeNear", function()
		It("passes within the epsilon", function()
			Expect(0.1 + 0.2).ToBeNear(0.3, 1e-9)
			Expect(10).ToBeNear(10.5, 0.5)
		end)

		It("fails outside the epsilon", function()
			local Message = FailureOf(function()
				Expect(1).ToBeNear(2, 0.5)
			end)
			Expect(Message).ToContain("expected 1 to be within 0.5 of 2")
		end)

		It("fails for a value that is not a number", function()
			FailureOf(function()
				Expect("1").ToBeNear(1, 1)
			end)
		end)
	end)

	Describe("ToBeNil and ToBeTruthy", function()
		It("tells nil from false", function()
			Expect(nil).ToBeNil()
			Expect(false).Never.ToBeNil()
			Expect(false).Never.ToBeTruthy()
		end)

		It("counts 0 and empty strings as truthy", function()
			Expect(0).ToBeTruthy()
			Expect("").ToBeTruthy()
		end)

		It("names the value when ToBeNil fails", function()
			local Message = FailureOf(function()
				Expect(5).ToBeNil()
			end)
			Expect(Message).ToContain("expected 5 to be nil")
		end)
	end)

	Describe("ToThrow", function()
		It("passes when the function throws", function()
			Expect(function()
				error("Locked")
			end).ToThrow()
		end)

		It("matches the error against a pattern", function()
			Expect(function()
				error("Slot 3 is locked")
			end).ToThrow("Slot %d is locked")
		end)

		It("fails when the function returns", function()
			local Message = FailureOf(function()
				Expect(function() end).ToThrow()
			end)
			Expect(Message).ToContain("expected the function to throw, it returned")
		end)

		It("fails when the error does not match", function()
			local Message = FailureOf(function()
				Expect(function()
					error("Busy")
				end).ToThrow("Locked")
			end)
			Expect(Message).ToContain('matching "Locked", it threw:')
			Expect(Message).ToContain("Busy")
		end)

		It("passes under Never when the function returns", function()
			Expect(function() end).Never.ToThrow()
		end)

		It("refuses a value that is not a function, even under Never", function()
			local Message = FailureOf(function()
				Expect(5).Never.ToThrow()
			end)
			Expect(Message).ToContain("ToThrow expects a function, got 5")
		end)
	end)

	Describe("ToContain", function()
		It("finds a plain substring", function()
			Expect("a.b.c").ToContain(".b.")
			Expect("abc").Never.ToContain("%a")
		end)

		It("finds a value in an array or a map", function()
			Expect({ "Red", "Blue" }).ToContain("Blue")
			Expect({ Main = "Sword" }).ToContain("Sword")
		end)

		It("shows the table when it fails", function()
			local Message = FailureOf(function()
				Expect({ 1, 2 }).ToContain(3)
			end)
			Expect(Message).ToContain("expected { 1, 2 } to contain 3")
		end)

		It("refuses a value that is not a string or table", function()
			local Message = FailureOf(function()
				Expect(5).ToContain(5)
			end)
			Expect(Message).ToContain("ToContain expects a string or a table, got 5")
		end)
	end)
end
