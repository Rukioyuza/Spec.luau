--!strict
--!optimize 2

--[=[
	Spec: a small test framework that runs in Roblox and under the luau CLI. Run calls its body to
	collect suites and tests, runs every test in order, prints a report and returns the results

	Describe bodies run while Run collects and It bodies run after. BeforeEach hooks run outer suite
	first and AfterEach hooks inner suite first, and AfterEach runs even when the test failed. Once a
	Run has any Only, tests outside one count as skipped, and a Skip above a test wins over an Only.
	Runs nest, so a test can run a suite of its own and check what it reports

	Return type: a table of Describe, It, BeforeEach, AfterEach, Skip, Only, Expect, Run and Format
	Example usage:
		local Results = Spec.Run(function()
			Spec.Describe("Math", function()
				Spec.It("adds", function()
					Spec.Expect(1 + 1).ToBe(2)
				end)
			end)
		end)
--]=]

local Expect = require("@self/Expect")

export type Expectation = Expect.Expectation
export type Matchers = Expect.Matchers

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
		read Status: "Passed" | "Skipped",
		read Path: string,
		read Duration: number,
	}
	| {
		read Status: "Failed",
		read Path: string,
		read Duration: number,
		read Message: string,
	}

export type Results = {
	read Passed: number,
	read Failed: number,
	read Skipped: number,
	read Duration: number,
	read Tests: { TestResult },
}

export type Options = {
	read Silent: boolean?,
}

type Test = {
	read Type: "Test",
	read Name: string,
	read Mode: Mode,
	read Body: () -> (),
}

type Suite = {
	read Type: "Suite",
	read Name: string,
	read Mode: Mode,
	read Children: { Test | Suite },
	read BeforeEach: { () -> () },
	read AfterEach: { () -> () },
	CollectError: string?,
}

type Collection = {
	Suite: Suite,
	HasOnly: boolean,
}

type Scope = {
	read Path: { string },
	read BeforeEach: { () -> () },
	read AfterEach: { () -> () },
	read Skipped: boolean,
	read Selected: boolean,
}

local Collecting: Collection? = nil

local function CurrentCollection(Caller: string): Collection
	local Current = Collecting
	if Current == nil then
		error(
			`Spec.{Caller} was called outside Spec.Run and has nowhere to register; call it inside the body given to Run`,
			0
		)
	end
	return Current
end

local function NewSuite(Name: string, Mode: Mode): Suite
	return {
		Type = "Suite",
		Name = Name,
		Mode = Mode,
		Children = {},
		BeforeEach = {},
		AfterEach = {},
		CollectError = nil,
	}
end

local function AddSuite(Caller: string, Name: string, Mode: Mode, Body: () -> ()): ()
	local Current = CurrentCollection(Caller)
	local Parent = Current.Suite
	local Suite = NewSuite(Name, Mode)
	table.insert(Parent.Children, Suite)
	if Mode == MODE.Only then
		Current.HasOnly = true
	end

	Current.Suite = Suite
	local Ok, Err = pcall(Body)
	Current.Suite = Parent

	if not Ok then
		Suite.CollectError = tostring(Err)
	end
end

local function AddTest(Caller: string, Name: string, Mode: Mode, Body: () -> ()): ()
	local Current = CurrentCollection(Caller)
	local Test: Test = {
		Type = "Test",
		Name = Name,
		Mode = Mode,
		Body = Body,
	}
	table.insert(Current.Suite.Children, Test)
	if Mode == MODE.Only then
		Current.HasOnly = true
	end
end

local function JoinPath(Path: { string }, Name: string): string
	if #Path == 0 then
		return Name
	end
	return table.concat(Path, PATH_SEPARATOR) .. PATH_SEPARATOR .. Name
end

local function ScopeOf(Suite: Suite, Parent: Scope): Scope
	local Path = table.clone(Parent.Path)
	table.insert(Path, Suite.Name)

	local BeforeEach = table.clone(Parent.BeforeEach)
	for _, Hook in Suite.BeforeEach do
		table.insert(BeforeEach, Hook)
	end

	local AfterEach = table.clone(Suite.AfterEach)
	for _, Hook in Parent.AfterEach do
		table.insert(AfterEach, Hook)
	end

	return {
		Path = Path,
		BeforeEach = BeforeEach,
		AfterEach = AfterEach,
		Skipped = Parent.Skipped or Suite.Mode == MODE.Skip,
		Selected = Parent.Selected or Suite.Mode == MODE.Only,
	}
end

local function RunTest(Test: Test, Scope: Scope, Tests: { TestResult }): ()
	local Path = JoinPath(Scope.Path, Test.Name)
	local Skipped = Scope.Skipped or Test.Mode == MODE.Skip
	local Selected = Scope.Selected or Test.Mode == MODE.Only
	if Skipped or not Selected then
		local Result: TestResult = { Status = "Skipped", Path = Path, Duration = 0 }
		table.insert(Tests, Result)
		return
	end

	local Started = os.clock()
	local Failure: string? = nil

	for _, Hook in Scope.BeforeEach do
		local Ok, Err = pcall(Hook)
		if not Ok then
			Failure = `BeforeEach failed: {Err}`
			break
		end
	end

	if Failure == nil then
		local Ok, Err = pcall(Test.Body)
		if not Ok then
			Failure = tostring(Err)
		end
	end

	for _, Hook in Scope.AfterEach do
		local Ok, Err = pcall(Hook)
		if not Ok and Failure == nil then
			Failure = `AfterEach failed: {Err}`
		end
	end

	local Duration = os.clock() - Started
	local Result: TestResult = if Failure == nil
		then { Status = "Passed", Path = Path, Duration = Duration }
		else { Status = "Failed", Path = Path, Duration = Duration, Message = Failure }
	table.insert(Tests, Result)
end

local function RunSuite(Suite: Suite, Scope: Scope, Tests: { TestResult }): ()
	for _, Child in Suite.Children do
		if Child.Type == "Test" then
			RunTest(Child, Scope, Tests)
			continue
		end

		local ChildScope = ScopeOf(Child, Scope)
		if Child.CollectError then
			local Result: TestResult = {
				Status = "Failed",
				Path = table.concat(ChildScope.Path, PATH_SEPARATOR),
				Duration = 0,
				Message = `Describe body failed: {Child.CollectError}`,
			}
			table.insert(Tests, Result)
		end
		RunSuite(Child, ChildScope, Tests)
	end
end

local function FormatDuration(Seconds: number): string
	return string.format("%.2f ms", Seconds * 1000)
end

local Spec = {
	Expect = Expect,
	Skip = {},
	Only = {},
}

function Spec.Describe(Name: string, Body: () -> ()): ()
	AddSuite("Describe", Name, MODE.Normal, Body)
end

function Spec.It(Name: string, Body: () -> ()): ()
	AddTest("It", Name, MODE.Normal, Body)
end

function Spec.Skip.Describe(Name: string, Body: () -> ()): ()
	AddSuite("Skip.Describe", Name, MODE.Skip, Body)
end

function Spec.Skip.It(Name: string, Body: () -> ()): ()
	AddTest("Skip.It", Name, MODE.Skip, Body)
end

function Spec.Only.Describe(Name: string, Body: () -> ()): ()
	AddSuite("Only.Describe", Name, MODE.Only, Body)
end

function Spec.Only.It(Name: string, Body: () -> ()): ()
	AddTest("Only.It", Name, MODE.Only, Body)
end

function Spec.BeforeEach(Hook: () -> ()): ()
	table.insert(CurrentCollection("BeforeEach").Suite.BeforeEach, Hook)
end

function Spec.AfterEach(Hook: () -> ()): ()
	table.insert(CurrentCollection("AfterEach").Suite.AfterEach, Hook)
end

function Spec.Run(Body: () -> (), Options: Options?): Results
	local Root = NewSuite("", MODE.Normal)
	local Collection: Collection = { Suite = Root, HasOnly = false }

	local Outer = Collecting
	Collecting = Collection
	local Collected, Err = pcall(Body)
	Collecting = Outer

	local Started = os.clock()
	local Tests: { TestResult } = {}
	if not Collected then
		local Result: TestResult =
			{ Status = "Failed", Path = "Spec.Run", Duration = 0, Message = `Run body failed: {Err}` }
		table.insert(Tests, Result)
	end

	local RootScope: Scope = {
		Path = {},
		BeforeEach = Root.BeforeEach,
		AfterEach = Root.AfterEach,
		Skipped = false,
		Selected = not Collection.HasOnly,
	}
	RunSuite(Root, RootScope, Tests)

	local Counts: { [Status]: number } = { Passed = 0, Failed = 0, Skipped = 0 }
	for _, Result in Tests do
		Counts[Result.Status] += 1
	end

	local Results: Results = {
		Passed = Counts.Passed,
		Failed = Counts.Failed,
		Skipped = Counts.Skipped,
		Duration = os.clock() - Started,
		Tests = Tests,
	}

	if Options == nil or not Options.Silent then
		print(Spec.Format(Results))
	end
	return Results
end

function Spec.Format(Results: Results): string
	local Lines: { string } = {}

	for _, Result in Results.Tests do
		local Label = STATUS_LABEL[Result.Status]
		if Result.Status == "Skipped" then
			table.insert(Lines, `{Label}  {Result.Path}`)
		else
			table.insert(Lines, `{Label}  {Result.Path} ({FormatDuration(Result.Duration)})`)
		end
	end

	if Results.Failed > 0 then
		table.insert(Lines, "")
		table.insert(Lines, "Failures:")

		local Number = 0
		for _, Result in Results.Tests do
			if Result.Status ~= "Failed" then
				continue
			end
			Number += 1
			local Message = string.gsub(Result.Message, "\n", "\n     ")
			table.insert(Lines, "")
			table.insert(Lines, `  {Number}) {Result.Path}`)
			table.insert(Lines, `     {Message}`)
		end
	end

	table.insert(Lines, "")
	table.insert(
		Lines,
		`{Results.Passed} passed, {Results.Failed} failed, {Results.Skipped} skipped, {#Results.Tests} total in {FormatDuration(
			Results.Duration
		)}`
	)

	return table.concat(Lines, "\n")
end

return Spec
