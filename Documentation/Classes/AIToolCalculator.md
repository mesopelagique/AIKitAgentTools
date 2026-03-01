# AIToolCalculator

Evaluate mathematical expressions safely using the [ExpressionLanguage](https://github.com/mesopelagique/ExpressionLanguage) component — a sandboxed expression evaluator that **cannot execute arbitrary 4D code**.

This is the recommended alternative to giving the LLM a "run code" tool. The expression engine has no access to 4D commands, file I/O, network, or database. Only the math functions explicitly registered below are available.

## Quick start

```4d
var $tool:=cs.agtools.AIToolCalculator.new()
$helper.registerTools($tool)
```

## Constructor

```4d
cs.agtools.AIToolCalculator.new({$config : Object})
```

| Parameter | Type | Description |
|---|---|---|
| `$config` | Object | Optional configuration (see below) |

### Configuration options

| Key | Type | Default | Description |
|---|---|---|---|
| `maxExpressionLength` | Integer | `1000` | Reject expressions longer than this |

## Exposed tools

| Tool name | Description |
|---|---|
| `evaluate_expression` | Evaluate a math expression string. Returns a JSON object with the result, its type, and the original expression. |

### evaluate_expression parameters

| Parameter | Type | Required | Description |
|---|---|---|---|
| `expression` | string | Yes | The mathematical expression to evaluate |
| `variables` | object | No | Named variables to inject into the expression context |

### Response format

```json
{
  "success": true,
  "expression": "sqrt(pow(a, 2) + pow(b, 2))",
  "result": 5,
  "type": "number"
}
```

Result `type` is one of: `number`, `boolean`, `text`, `collection`, `object`, `null`.

## Available functions

### Arithmetic

| Function | Description | Example |
|---|---|---|
| `abs(x)` | Absolute value | `abs(-42)` → `42` |
| `round(x)` | Round to integer | `round(3.7)` → `4` |
| `round(x, n)` | Round to `n` decimal places | `round(3.14159, 2)` → `3.14` |
| `floor(x)` | Largest integer ≤ x | `floor(3.7)` → `3`, `floor(-3.7)` → `-4` |
| `ceil(x)` | Smallest integer ≥ x | `ceil(3.2)` → `4`, `ceil(-3.2)` → `-3` |
| `int(x)` | Truncate toward zero | `int(3.9)` → `3`, `int(-3.9)` → `-3` |
| `dec(x)` | Decimal part | `dec(3.14)` → `0.14` |
| `mod(a, b)` | Modulo (also: `a % b`) | `mod(17, 5)` → `2` |
| `min(a, b)` | Minimum of two values | `min(10, 20)` → `10` |
| `max(a, b)` | Maximum of two values | `max(10, 20)` → `20` |

### Power & Roots

| Function | Description | Example |
|---|---|---|
| `sqrt(x)` | Square root | `sqrt(144)` → `12` |
| `pow(x, n)` | Power (also: `x ^ n`) | `pow(2, 10)` → `1024` |

### Logarithmic & Exponential

| Function | Description | Example |
|---|---|---|
| `log(x)` | Natural logarithm (ln) | `log(e())` → `1` |
| `ln(x)` | Alias for `log` | `ln(10)` → `2.302...` |
| `exp(x)` | e raised to power x | `exp(1)` → `2.718...` |

### Trigonometric (radians)

| Function | Description | Example |
|---|---|---|
| `sin(x)` | Sine | `sin(pi() / 2)` → `1` |
| `cos(x)` | Cosine | `cos(0)` → `1` |
| `tan(x)` | Tangent | `tan(pi() / 4)` → `1` |
| `asin(x)` | Inverse sine | `asin(1)` → `1.5707...` |
| `acos(x)` | Inverse cosine | `acos(1)` → `0` |
| `atan(x)` | Inverse tangent | `atan(1)` → `0.7853...` |

### Constants

| Function | Description | Value |
|---|---|---|
| `pi()` | π | `3.14159265...` |
| `e()` | Euler's number | `2.71828182...` |
| `random()` | Random number 0..1 | varies |

## Operators

| Category | Operators |
|---|---|
| Arithmetic | `+` `-` `*` `/` `%` `^` |
| Comparison | `==` `!=` `>` `>=` `<` `<=` |
| Logic | `&&` `\|\|` `!` |
| Ternary | `condition ? a : b` |
| Containment | `in` |

## Collection transforms (pipe operator)

Use `|` to apply a transform to a collection:

| Transform | Description | Example |
|---|---|---|
| `\|sum` | Sum of all elements | `[1, 2, 3, 4, 5]\|sum` → `15` |
| `\|avg` | Average | `[10, 20, 30]\|avg` → `20` |
| `\|min` | Minimum element | `[5, 1, 8]\|min` → `1` |
| `\|max` | Maximum element | `[5, 1, 8]\|max` → `8` |
| `\|count` | Number of elements | `[1, 2, 3]\|count` → `3` |
| `\|sort` | Sort ascending | `[3, 1, 2]\|sort` → `[1, 2, 3]` |
| `\|reverse` | Reverse order | `[1, 2, 3]\|reverse` → `[3, 2, 1]` |

Number transforms: `|abs`, `|round`, `|floor`, `|ceil`.

## Examples

### Basic math

```4d
var $tool:=cs.agtools.AIToolCalculator.new()
$tool.evaluate_expression({expression: "2 + 3 * 4"})
// → {"success":true, "result":14, "type":"number", "expression":"2 + 3 * 4"}
```

### With variables

```4d
$tool.evaluate_expression({\
  expression: "price * (1 + tax_rate)"; \
  variables: {price: 99.99; tax_rate: 0.2}\
})
// → {"success":true, "result":119.988, "type":"number", ...}
```

### Pythagorean theorem

```4d
$tool.evaluate_expression({\
  expression: "sqrt(pow(a, 2) + pow(b, 2))"; \
  variables: {a: 3; b: 4}\
})
// → {"success":true, "result":5, ...}
```

### Circle area

```4d
$tool.evaluate_expression({\
  expression: "round(pi() * pow(r, 2), 2)"; \
  variables: {r: 5}\
})
// → {"success":true, "result":78.54, ...}
```

### Collection statistics

```4d
$tool.evaluate_expression({expression: "[85, 92, 78, 95, 88]|avg"})
// → {"success":true, "result":87.6, ...}
```

### Conditional

```4d
$tool.evaluate_expression({\
  expression: "score >= 60 ? 'pass' : 'fail'"; \
  variables: {score: 75}\
})
// → {"success":true, "result":"pass", "type":"text", ...}
```

## Security considerations

| Risk | Level | Mitigation |
|---|---|---|
| **Code execution** | 🟢 None | The expression engine is sandboxed — it cannot call 4D commands, access files, network, or database. |
| **Function scope** | 🟢 Controlled | Only the math functions listed above are available. No custom function can be injected from an expression. |
| **Resource exhaustion** | 🟡 Low | `maxExpressionLength` caps input size. Very deeply nested expressions could theoretically be slow, but practical expressions complete instantly. |
| **Variable injection** | 🟢 None | Variables are read-only from the expression's perspective. The expression produces a return value without modifying context. |

### Why this is safer than a "run 4D code" tool

A tool that executes arbitrary 4D code (e.g. via `Formula(...)` or `EXECUTE FORMULA`) gives the LLM full access to:
- File system (`4D.File`, `DOCUMENT`)
- Network (`4D.HTTPRequest`, `HTTP Get`)
- Database (`ds`, `QUERY`, `CREATE RECORD`)
- Shell (`4D.SystemWorker`, `LAUNCH EXTERNAL PROCESS`)
- Memory/process manipulation

**AIToolCalculator cannot do any of this.** The only operations available are pure mathematical computations with no side effects. This is the recommended approach when an LLM needs to perform calculations.
