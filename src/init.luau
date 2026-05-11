--!strict

local expect = require("@self/Expect")

export type Expectation = expect.Expectation
export type Matchers = expect.Matchers

local MODE = {
	Normal = "Normal" :: "Normal",
	Skip = "Skip" :: "Skip",
	Only = "Only" :: "Only",
}

local STATUS_LABEL = {
	Passed = "PASS",
	Failed = "FAIL",
	Skipped = "SKIP",
}

local PATH_SEPARATOR = " > "

type Mode = keyof<typeof(MODE)>

export type Status = keyof<typeof(STATUS_LABEL)>

export type TestResult =
	{
		read status: "Passed" | "Skipped",
		read path: string,
		read duration: number,
	}
	| {
		read status: "Failed",
		read path: string,
		read duration: number,
		read message: string,
	}

export type Results = {
	read passed: number,
	read failed: number,
	read skipped: number,
	read duration: number,
	read tests: { TestResult },
}

export type Options = {
	read silent: boolean?,
}

type Test = {
	read type: "Test",
	read name: string,
	read mode: Mode,
	read body: () -> (),
}

type Suite = {
	read type: "Suite",
	read name: string,
	read mode: Mode,
	read children: { Test | Suite },
	read beforeEach: { () -> () },
	read afterEach: { () -> () },
	collectError: string?,
}

type Collection = {
	suite: Suite,
	hasOnly: boolean,
}

type Scope = {
	read path: { string },
	read beforeEach: { () -> () },
	read afterEach: { () -> () },
	read skipped: boolean,
	read selected: boolean,
}

local collecting: Collection? = nil

local function currentCollection(caller: string): Collection
	local current = collecting
	if current == nil then
		error(
			`Spec.{caller} was called outside Spec.run and has nowhere to register; call it inside the body given to Spec.run`,
			0
		)
	end
	return current
end

local function newSuite(name: string, mode: Mode): Suite
	return {
		type = "Suite",
		name = name,
		mode = mode,
		children = {},
		beforeEach = {},
		afterEach = {},
		collectError = nil,
	}
end

local function addSuite(caller: string, name: string, mode: Mode, body: () -> ()): ()
	local current = currentCollection(caller)
	local parent = current.suite
	local suite = newSuite(name, mode)
	table.insert(parent.children, suite)
	if mode == MODE.Only then
		current.hasOnly = true
	end

	current.suite = suite
	local ok, err = pcall(body)
	current.suite = parent

	if not ok then
		suite.collectError = tostring(err)
	end
end

local function addTest(caller: string, name: string, mode: Mode, body: () -> ()): ()
	local current = currentCollection(caller)
	local test: Test = {
		type = "Test",
		name = name,
		mode = mode,
		body = body,
	}
	table.insert(current.suite.children, test)
	if mode == MODE.Only then
		current.hasOnly = true
	end
end

local function joinPath(path: { string }, name: string): string
	if #path == 0 then
		return name
	end
	return table.concat(path, PATH_SEPARATOR) .. PATH_SEPARATOR .. name
end

local function scopeOf(suite: Suite, parent: Scope): Scope
	local path = table.clone(parent.path)
	table.insert(path, suite.name)

	local beforeEach = table.clone(parent.beforeEach)
	for _, hook in suite.beforeEach do
		table.insert(beforeEach, hook)
	end

	local afterEach = table.clone(suite.afterEach)
	for _, hook in parent.afterEach do
		table.insert(afterEach, hook)
	end

	return {
		path = path,
		beforeEach = beforeEach,
		afterEach = afterEach,
		skipped = parent.skipped or suite.mode == MODE.Skip,
		selected = parent.selected or suite.mode == MODE.Only,
	}
end

local function runTest(test: Test, scope: Scope, tests: { TestResult }): ()
	local path = joinPath(scope.path, test.name)
	local skipped = scope.skipped or test.mode == MODE.Skip
	local selected = scope.selected or test.mode == MODE.Only
	if skipped or not selected then
		local result: TestResult = { status = "Skipped", path = path, duration = 0 }
		table.insert(tests, result)
		return
	end

	local started = os.clock()
	local failure: string? = nil

	for _, hook in scope.beforeEach do
		local ok, err = pcall(hook)
		if not ok then
			failure = `beforeEach failed: {err}`
			break
		end
	end

	if failure == nil then
		local ok, err = pcall(test.body)
		if not ok then
			failure = tostring(err)
		end
	end

	for _, hook in scope.afterEach do
		local ok, err = pcall(hook)
		if not ok and failure == nil then
			failure = `afterEach failed: {err}`
		end
	end

	local duration = os.clock() - started
	local result: TestResult = if failure == nil
		then { status = "Passed", path = path, duration = duration }
		else { status = "Failed", path = path, duration = duration, message = failure }
	table.insert(tests, result)
end

local function runSuite(suite: Suite, scope: Scope, tests: { TestResult }): ()
	for _, child in suite.children do
		if child.type == "Test" then
			runTest(child, scope, tests)
			continue
		end

		local childScope = scopeOf(child, scope)
		if child.collectError then
			local result: TestResult = {
				status = "Failed",
				path = table.concat(childScope.path, PATH_SEPARATOR),
				duration = 0,
				message = `Describe body failed: {child.collectError}`,
			}
			table.insert(tests, result)
		end
		runSuite(child, childScope, tests)
	end
end

local function formatDuration(seconds: number): string
	return string.format("%.2f ms", seconds * 1000)
end

local Spec = {
	expect = expect,
	skip = {},
	only = {},
}

function Spec.describe(name: string, body: () -> ()): ()
	addSuite("describe", name, MODE.Normal, body)
end

function Spec.it(name: string, body: () -> ()): ()
	addTest("it", name, MODE.Normal, body)
end

function Spec.skip.describe(name: string, body: () -> ()): ()
	addSuite("skip.describe", name, MODE.Skip, body)
end

function Spec.skip.it(name: string, body: () -> ()): ()
	addTest("skip.it", name, MODE.Skip, body)
end

function Spec.only.describe(name: string, body: () -> ()): ()
	addSuite("only.describe", name, MODE.Only, body)
end

function Spec.only.it(name: string, body: () -> ()): ()
	addTest("only.it", name, MODE.Only, body)
end

function Spec.beforeEach(hook: () -> ()): ()
	table.insert(currentCollection("beforeEach").suite.beforeEach, hook)
end

function Spec.afterEach(hook: () -> ()): ()
	table.insert(currentCollection("afterEach").suite.afterEach, hook)
end

function Spec.run(body: () -> (), options: Options?): Results
	local root = newSuite("", MODE.Normal)
	local collection: Collection = { suite = root, hasOnly = false }

	local outer = collecting
	collecting = collection
	local collected, err = pcall(body)
	collecting = outer

	local started = os.clock()
	local tests: { TestResult } = {}
	if not collected then
		local result: TestResult =
			{ status = "Failed", path = "Spec.run", duration = 0, message = `Run body failed: {err}` }
		table.insert(tests, result)
	end

	local rootScope: Scope = {
		path = {},
		beforeEach = root.beforeEach,
		afterEach = root.afterEach,
		skipped = false,
		selected = not collection.hasOnly,
	}
	runSuite(root, rootScope, tests)

	local counts: { [Status]: number } = { Passed = 0, Failed = 0, Skipped = 0 }
	for _, result in tests do
		counts[result.status] += 1
	end

	local results: Results = {
		passed = counts.Passed,
		failed = counts.Failed,
		skipped = counts.Skipped,
		duration = os.clock() - started,
		tests = tests,
	}

	if options == nil or not options.silent then
		print(Spec.format(results))
	end
	return results
end

function Spec.format(results: Results): string
	local lines: { string } = {}

	for _, result in results.tests do
		local label = STATUS_LABEL[result.status]
		if result.status == "Skipped" then
			table.insert(lines, `{label}  {result.path}`)
		else
			table.insert(lines, `{label}  {result.path} ({formatDuration(result.duration)})`)
		end
	end

	if results.failed > 0 then
		table.insert(lines, "")
		table.insert(lines, "Failures:")

		local number = 0
		for _, result in results.tests do
			if result.status ~= "Failed" then
				continue
			end
			number += 1
			local message = string.gsub(result.message, "\n", "\n     ")
			table.insert(lines, "")
			table.insert(lines, `  {number}) {result.path}`)
			table.insert(lines, `     {message}`)
		end
	end

	table.insert(lines, "")
	table.insert(
		lines,
		`{results.passed} passed, {results.failed} failed, {results.skipped} skipped, {#results.tests} total in {formatDuration(
			results.duration
		)}`
	)

	return table.concat(lines, "\n")
end

return Spec
