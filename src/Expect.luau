--!strict

export type Matchers = {
	read toBe: (expected: unknown) -> (),
	read toEqual: (expected: unknown) -> (),
	read toBeNear: (expected: number, epsilon: number) -> (),
	read toBeNil: () -> (),
	read toBeTruthy: () -> (),
	read toThrow: (pattern: string?) -> (),
	read toContain: (item: unknown) -> (),
}

export type Expectation = setmetatable<{ read never: Matchers }, { __index: Matchers }>

type AnyTable = { [unknown]: unknown }

local MAX_SHOWN = 4
local MODULE_SOURCE = debug.info(1, "s")

local function throwAtCaller(message: string): never
	local level = 2
	while debug.info(level, "s") == MODULE_SOURCE do
		level += 1
	end
	error(message, level)
end

local function isIdentifier(key: unknown): boolean
	return type(key) == "string" and string.match(key, "^[%a_][%w_]*$") ~= nil
end

local function showFlat(value: unknown): string
	if type(value) == "string" then
		return string.format("%q", value)
	end
	if type(value) == "table" then
		return "{...}"
	end
	return tostring(value)
end

local function show(value: unknown): string
	if type(value) ~= "table" then
		return showFlat(value)
	end

	local parts: { string } = {}
	local nextIndex = 1
	for key, item in value :: AnyTable do
		if #parts == MAX_SHOWN then
			table.insert(parts, "...")
			break
		end

		if key == nextIndex then
			table.insert(parts, showFlat(item))
			nextIndex += 1
		elseif isIdentifier(key) then
			table.insert(parts, `{key} = {showFlat(item)}`)
		else
			table.insert(parts, `[{showFlat(key)}] = {showFlat(item)}`)
		end
	end

	if #parts == 0 then
		return "{}"
	end
	return "{ " .. table.concat(parts, ", ") .. " }"
end

local function pathStep(key: unknown): string
	if isIdentifier(key) then
		return `.{key}`
	end
	return `[{showFlat(key)}]`
end

local function findDifference(
	actual: unknown,
	expected: unknown,
	path: string,
	seen: { [AnyTable]: { [AnyTable]: true } }
): string?
	if actual == expected then
		return nil
	end
	if actual ~= actual and expected ~= expected then
		return nil
	end
	if type(actual) ~= "table" or type(expected) ~= "table" then
		return `{path}: got {show(actual)}, expected {show(expected)}`
	end

	local actualTable = actual :: AnyTable
	local expectedTable = expected :: AnyTable

	local compared = seen[actualTable]
	if compared == nil then
		compared = {}
		seen[actualTable] = compared
	end
	if compared[expectedTable] then
		return nil
	end
	compared[expectedTable] = true

	for key, value in expectedTable do
		local difference = findDifference(actualTable[key], value, path .. pathStep(key), seen)
		if difference then
			return difference
		end
	end

	for key, value in actualTable do
		if expectedTable[key] == nil then
			return `{path .. pathStep(key)}: got {show(value)}, expected nil`
		end
	end

	return nil
end

local function newMatchers(actual: unknown, negated: boolean): Matchers
	local function check(passed: boolean, message: string, negatedMessage: string): ()
		if passed == negated then
			throwAtCaller(if negated then negatedMessage else message)
		end
	end

	return {
		toBe = function(expected: unknown): ()
			check(
				actual == expected,
				`expected {show(actual)} to be {show(expected)}`,
				`expected {show(actual)} not to be {show(expected)}`
			)
		end,

		toEqual = function(expected: unknown): ()
			local difference = findDifference(actual, expected, "", {})
			local bothTables = type(actual) == "table" and type(expected) == "table"
			check(
				difference == nil,
				if bothTables
					then `expected tables to be equal, first difference at {difference}`
					else `expected {show(actual)} to equal {show(expected)}`,
				`expected {show(actual)} not to equal {show(expected)}`
			)
		end,

		toBeNear = function(expected: number, epsilon: number): ()
			local near = type(actual) == "number" and math.abs(actual - expected) <= epsilon
			check(
				near,
				`expected {show(actual)} to be within {epsilon} of {expected}`,
				`expected {show(actual)} not to be within {epsilon} of {expected}`
			)
		end,

		toBeNil = function(): ()
			check(actual == nil, `expected {show(actual)} to be nil`, "expected a value, got nil")
		end,

		toBeTruthy = function(): ()
			local truthy = actual ~= nil and actual ~= false
			check(truthy, `expected {show(actual)} to be truthy`, `expected {show(actual)} not to be truthy`)
		end,

		toThrow = function(pattern: string?): ()
			if type(actual) ~= "function" then
				throwAtCaller(`ToThrow expects a function, got {show(actual)}`)
			end

			local ok, err = pcall(actual :: () -> ())
			local thrown = tostring(err)

			if pattern == nil then
				check(
					not ok,
					"expected the function to throw, it returned",
					`expected the function not to throw, it threw: {thrown}`
				)
				return
			end

			check(
				not ok and string.find(thrown, pattern) ~= nil,
				if ok
					then `expected the function to throw an error matching {show(pattern)}, it returned`
					else `expected the function to throw an error matching {show(pattern)}, it threw: {thrown}`,
				`expected the function not to throw an error matching {show(pattern)}, it threw: {thrown}`
			)
		end,

		toContain = function(item: unknown): ()
			if type(actual) == "string" then
				local found = type(item) == "string" and string.find(actual, item, 1, true) ~= nil
				check(
					found,
					`expected {show(actual)} to contain {show(item)}`,
					`expected {show(actual)} not to contain {show(item)}`
				)
				return
			end

			if type(actual) ~= "table" then
				throwAtCaller(`ToContain expects a string or a table, got {show(actual)}`)
			end

			local found = false
			for _, value in actual :: AnyTable do
				if value == item then
					found = true
					break
				end
			end
			check(
				found,
				`expected {show(actual)} to contain {show(item)}`,
				`expected {show(actual)} not to contain {show(item)}`
			)
		end,
	}
end

local function expect(actual: unknown): Expectation
	local fields: { read never: Matchers } = { never = newMatchers(actual, true) }
	return setmetatable(fields, { __index = newMatchers(actual, false) })
end

return expect
