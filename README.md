<h1 align="left">Spec</h1>

<p align="left">
  <img src="https://img.shields.io/badge/Roblox-181717?style=for-the-badge&logo=roblox&logoColor=white" />
  <img src="https://img.shields.io/badge/Luau-181717?style=for-the-badge&logo=luau&logoColor=00A2FF" />
  <img src="https://img.shields.io/badge/CLI-luau-181717?style=for-the-badge" />
</p>

A small test framework for Luau. The same tests run in Roblox and under the standalone `luau` CLI.

---

### About

Spec has no dependencies and uses no Roblox globals, so a suite written for a Roblox module can run on your machine or in CI with `luau.exe`.

- **Describe and It.** Group tests into suites and nest them as deep as you like.
- **Hooks.** `BeforeEach` and `AfterEach` apply to every test in their suite and the suites inside it.
- **Skip and Only.** `Spec.Skip.It`, `Spec.Skip.Describe`, `Spec.Only.It` and `Spec.Only.Describe`.
- **Readable failures.** `ToEqual` names the path to the first difference, like `.Items[2].Count`.
- **Results you can act on.** `Run` prints a report and returns a table, so CI can fail on failures.

---

### Usage

```luau
--!strict

local Spec = require("./Spec")

local Describe = Spec.Describe
local It = Spec.It
local Expect = Spec.Expect

local Results = Spec.Run(function()
	Describe("Inventory", function()
		local Items: { { Name: string, Count: number } } = {}

		Spec.BeforeEach(function()
			Items = { { Name = "Sword", Count = 1 } }
		end)

		It("stacks items", function()
			Items[1].Count += 1
			Expect(Items).ToEqual({ { Name = "Sword", Count = 2 } })
		end)

		It("refuses a negative count", function()
			Expect(function()
				error("Count must be positive")
			end).ToThrow("positive")
		end)

		Spec.Skip.It("sorts by rarity", function() end)
	end)
end)

if Results.Failed > 0 then
	error(`{Results.Failed} tests failed`, 0)
end
```

Describe bodies run while `Run` collects, and It bodies run after, in the order they were written. A test passes when its body returns without throwing.

---

### Matchers

| Matcher | Passes when |
| --- | --- |
| `ToBe(Value)` | the value `==` the expected value |
| `ToEqual(Value)` | tables match key by key, nested tables included |
| `ToBeNear(Value, Epsilon)` | a number is within `Epsilon` of `Value` |
| `ToBeNil()` | the value is `nil` |
| `ToBeTruthy()` | the value is neither `nil` nor `false` |
| `ToThrow(Pattern?)` | the function throws, with an error matching `Pattern` if given |
| `ToContain(Item)` | a string contains the substring, or a table holds the value |

Put `.Never` before any matcher to flip it: `Expect(Value).Never.ToBeNil()`.

---

### Focus and skip

- **Skip.** A skipped test or suite is reported as `SKIP` and never runs.
- **Only.** Once any `Only` is registered in a run, everything outside an `Only` is skipped.
- **Skip wins.** A test under a skipped suite stays skipped even when it is marked `Only`.

---

### Report

A run where one test fails prints this:

```
FAIL  Inventory > stacks items (0.05 ms)
PASS  Inventory > refuses a negative count (0.01 ms)
SKIP  Inventory > sorts by rarity

Failures:

  1) Inventory > stacks items
     ./Inventory.spec.luau:19: expected tables to be equal, first difference at [1].Count: got 2, expected 3

1 passed, 1 failed, 1 skipped, 3 total in 0.06 ms
```

Pass `{ Silent = true }` as the second argument to `Run` to skip printing, and call `Spec.Format(Results)` for the text yourself.

---

### Results

| Field | Type | Purpose |
| --- | --- | --- |
| `Passed` | `number` | Tests that passed |
| `Failed` | `number` | Tests that failed, including a suite body that threw |
| `Skipped` | `number` | Tests skipped by `Skip` or left out by `Only` |
| `Duration` | `number` | Seconds the run took, from `os.clock` |
| `Tests` | `{ TestResult }` | Each test's `Path`, `Status`, `Duration` and, when failed, `Message` |

---

### Install

- **Rojo.** Sync `src` with the included `default.project.json`; it builds a ModuleScript named `Spec`.
- **By hand.** Copy `src/init.luau` as a ModuleScript named `Spec` and `src/Expect.luau` as its child `Expect`.
- **CLI.** Require `src` by a relative path from your test entry file.

---

### Tests

Spec tests itself with Spec. From the repo root:

```bash
luau tests/Run.luau
```

The entry throws when a test fails, so the process exits with an error code.
