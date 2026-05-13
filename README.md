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
- **Hooks.** `beforeEach` and `afterEach` apply to every test in their suite and the suites inside it.
- **Skip and Only.** `Spec.skip.it`, `Spec.skip.describe`, `Spec.only.it` and `Spec.only.describe`.
- **Readable failures.** `toEqual` names the path to the first difference, like `.items[2].count`.
- **Results you can act on.** `run` prints a report and returns a table, so CI can fail on failures.

---

### Usage

```luau
--!strict

local Spec = require("./Spec")

local describe = Spec.describe
local it = Spec.it
local expect = Spec.expect

local results = Spec.run(function()
	describe("Inventory", function()
		local items: { { name: string, count: number } } = {}

		Spec.beforeEach(function()
			items = { { name = "Sword", count = 1 } }
		end)

		it("stacks items", function()
			items[1].count += 1
			expect(items).toEqual({ { name = "Sword", count = 2 } })
		end)

		it("refuses a negative count", function()
			expect(function()
				error("Count must be positive")
			end).toThrow("positive")
		end)

		Spec.skip.it("sorts by rarity", function() end)
	end)
end)

if results.failed > 0 then
	error(`{results.failed} tests failed`, 0)
end
```

Describe bodies run while `run` collects, and It bodies run after, in the order they were written. A test passes when its body returns without throwing.

---

### Matchers

| Matcher | Passes when |
| --- | --- |
| `toBe(value)` | the value `==` the expected value |
| `toEqual(value)` | tables match key by key, nested tables included |
| `toBeNear(value, epsilon)` | a number is within `epsilon` of `value` |
| `toBeNil()` | the value is `nil` |
| `toBeTruthy()` | the value is neither `nil` nor `false` |
| `toThrow(pattern?)` | the function throws, with an error matching `pattern` if given |
| `toContain(item)` | a string contains the substring, or a table holds the value |

Put `.never` before any matcher to flip it: `Expect(value).never.toBeNil()`.

---

### Focus and skip

- **Skip.** A skipped test or suite is reported as `SKIP` and never runs.
- **Only.** Once any `only` is registered in a run, everything outside an `only` is skipped.
- **Skip wins.** A test under a skipped suite stays skipped even when it is marked `only`.

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

Pass `{ silent = true }` as the second argument to `run` to skip printing, and call `Spec.format(results)` for the text yourself.

---

### Results

| Field | Type | Purpose |
| --- | --- | --- |
| `passed` | `number` | Tests that passed |
| `failed` | `number` | Tests that failed, including a suite body that threw |
| `skipped` | `number` | Tests skipped by `skip` or left out by `only` |
| `duration` | `number` | Seconds the run took, from `os.clock` |
| `tests` | `{ TestResult }` | Each test's `path`, `status`, `duration` and, when failed, `message` |

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
