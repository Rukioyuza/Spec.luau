--!strict
--!optimize 2

--[=[
	Expect: the matchers behind Spec.Expect. A failed match throws a message that names the value it
	got and what it expected, at the line that called the matcher. Never flips every matcher

	ToBe compares with ==. ToEqual compares tables key by key in both directions, ignores metatables,
	counts NaN as equal to NaN, and names the path to the first difference. ToThrow given something
	other than a function, and ToContain given something other than a string or table, throw even under
	Never, because the test itself is wrong. The failing line is found by walking the stack past this
	module, since a fixed error level points at the wrong frame once --!optimize 2 inlines a helper

	Return type: the Expect function
	Example usage:
		Expect({ Items = { 1, 2 } }).ToEqual({ Items = { 1, 2 } })
		Expect(function() error("Locked") end).ToThrow("Locked")
		Expect(0.1 + 0.2).Never.ToBe(0.3)
--]=]

export type Matchers = {
	read ToBe: (Expected: unknown) -> (),
	read ToEqual: (Expected: unknown) -> (),
	read ToBeNear: (Expected: number, Epsilon: number) -> (),
	read ToBeNil: () -> (),
	read ToBeTruthy: () -> (),
	read ToThrow: (Pattern: string?) -> (),
	read ToContain: (Item: unknown) -> (),
}

export type Expectation = setmetatable<{ read Never: Matchers }, { __index: Matchers }>

type AnyTable = { [unknown]: unknown }

local MAX_SHOWN = 4
local MODULE_SOURCE = debug.info(1, "s")

local function ThrowAtCaller(Message: string): never
	local Level = 2
	while debug.info(Level, "s") == MODULE_SOURCE do
		Level += 1
	end
	error(Message, Level)
end

local function IsIdentifier(Key: unknown): boolean
	return type(Key) == "string" and string.match(Key, "^[%a_][%w_]*$") ~= nil
end

local function ShowFlat(Value: unknown): string
	if type(Value) == "string" then
		return string.format("%q", Value)
	end
	if type(Value) == "table" then
		return "{...}"
	end
	return tostring(Value)
end

local function Show(Value: unknown): string
	if type(Value) ~= "table" then
		return ShowFlat(Value)
	end

	local Parts: { string } = {}
	local NextIndex = 1
	for Key, Item in Value :: AnyTable do
		if #Parts == MAX_SHOWN then
			table.insert(Parts, "...")
			break
		end

		if Key == NextIndex then
			table.insert(Parts, ShowFlat(Item))
			NextIndex += 1
		elseif IsIdentifier(Key) then
			table.insert(Parts, `{Key} = {ShowFlat(Item)}`)
		else
			table.insert(Parts, `[{ShowFlat(Key)}] = {ShowFlat(Item)}`)
		end
	end

	if #Parts == 0 then
		return "{}"
	end
	return "{ " .. table.concat(Parts, ", ") .. " }"
end

local function PathStep(Key: unknown): string
	if IsIdentifier(Key) then
		return `.{Key}`
	end
	return `[{ShowFlat(Key)}]`
end

local function FindDifference(
	Actual: unknown,
	Expected: unknown,
	Path: string,
	Seen: { [AnyTable]: { [AnyTable]: true } }
): string?
	if Actual == Expected then
		return nil
	end
	if Actual ~= Actual and Expected ~= Expected then
		return nil
	end
	if type(Actual) ~= "table" or type(Expected) ~= "table" then
		return `{Path}: got {Show(Actual)}, expected {Show(Expected)}`
	end

	local ActualTable = Actual :: AnyTable
	local ExpectedTable = Expected :: AnyTable

	local Compared = Seen[ActualTable]
	if Compared == nil then
		Compared = {}
		Seen[ActualTable] = Compared
	end
	if Compared[ExpectedTable] then
		return nil
	end
	Compared[ExpectedTable] = true

	for Key, Value in ExpectedTable do
		local Difference = FindDifference(ActualTable[Key], Value, Path .. PathStep(Key), Seen)
		if Difference then
			return Difference
		end
	end

	for Key, Value in ActualTable do
		if ExpectedTable[Key] == nil then
			return `{Path .. PathStep(Key)}: got {Show(Value)}, expected nil`
		end
	end

	return nil
end

local function NewMatchers(Actual: unknown, Negated: boolean): Matchers
	local function Check(Passed: boolean, Message: string, NegatedMessage: string): ()
		if Passed == Negated then
			ThrowAtCaller(if Negated then NegatedMessage else Message)
		end
	end

	return {
		ToBe = function(Expected: unknown): ()
			Check(
				Actual == Expected,
				`expected {Show(Actual)} to be {Show(Expected)}`,
				`expected {Show(Actual)} not to be {Show(Expected)}`
			)
		end,

		ToEqual = function(Expected: unknown): ()
			local Difference = FindDifference(Actual, Expected, "", {})
			local BothTables = type(Actual) == "table" and type(Expected) == "table"
			Check(
				Difference == nil,
				if BothTables
					then `expected tables to be equal, first difference at {Difference}`
					else `expected {Show(Actual)} to equal {Show(Expected)}`,
				`expected {Show(Actual)} not to equal {Show(Expected)}`
			)
		end,

		ToBeNear = function(Expected: number, Epsilon: number): ()
			local Near = type(Actual) == "number" and math.abs(Actual - Expected) <= Epsilon
			Check(
				Near,
				`expected {Show(Actual)} to be within {Epsilon} of {Expected}`,
				`expected {Show(Actual)} not to be within {Epsilon} of {Expected}`
			)
		end,

		ToBeNil = function(): ()
			Check(Actual == nil, `expected {Show(Actual)} to be nil`, "expected a value, got nil")
		end,

		ToBeTruthy = function(): ()
			local Truthy = Actual ~= nil and Actual ~= false
			Check(Truthy, `expected {Show(Actual)} to be truthy`, `expected {Show(Actual)} not to be truthy`)
		end,

		ToThrow = function(Pattern: string?): ()
			if type(Actual) ~= "function" then
				ThrowAtCaller(`ToThrow expects a function, got {Show(Actual)}`)
			end

			local Ok, Err = pcall(Actual :: () -> ())
			local Thrown = tostring(Err)

			if Pattern == nil then
				Check(
					not Ok,
					"expected the function to throw, it returned",
					`expected the function not to throw, it threw: {Thrown}`
				)
				return
			end

			Check(
				not Ok and string.find(Thrown, Pattern) ~= nil,
				if Ok
					then `expected the function to throw an error matching {Show(Pattern)}, it returned`
					else `expected the function to throw an error matching {Show(Pattern)}, it threw: {Thrown}`,
				`expected the function not to throw an error matching {Show(Pattern)}, it threw: {Thrown}`
			)
		end,

		ToContain = function(Item: unknown): ()
			if type(Actual) == "string" then
				local Found = type(Item) == "string" and string.find(Actual, Item, 1, true) ~= nil
				Check(
					Found,
					`expected {Show(Actual)} to contain {Show(Item)}`,
					`expected {Show(Actual)} not to contain {Show(Item)}`
				)
				return
			end

			if type(Actual) ~= "table" then
				ThrowAtCaller(`ToContain expects a string or a table, got {Show(Actual)}`)
			end

			local Found = false
			for _, Value in Actual :: AnyTable do
				if Value == Item then
					Found = true
					break
				end
			end
			Check(
				Found,
				`expected {Show(Actual)} to contain {Show(Item)}`,
				`expected {Show(Actual)} not to contain {Show(Item)}`
			)
		end,
	}
end

local function Expect(Actual: unknown): Expectation
	local Fields: { read Never: Matchers } = { Never = NewMatchers(Actual, true) }
	return setmetatable(Fields, { __index = NewMatchers(Actual, false) })
end

return Expect
