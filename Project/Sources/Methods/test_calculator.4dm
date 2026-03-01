//%attributes = {}
// test_calculator — Test AIToolCalculator (sandboxed math expressions)

// -----------------------------------------------------------------
// 1. Basic instantiation
// -----------------------------------------------------------------
var $tool:=cs.agtools.AITToolCalculator.new()
ASSERT(OB Instance of($tool; cs.agtools.AITToolCalculator); "Must be AIToolCalculator instance")
ASSERT($tool.tools.length=1; "Must expose 1 tool (evaluate_expression)")
ASSERT($tool.tools[0].name="evaluate_expression"; "Tool name must be evaluate_expression")
ASSERT($tool.maxExpressionLength=1000; "Default maxExpressionLength must be 1000")

// -----------------------------------------------------------------
// 2. Custom config
// -----------------------------------------------------------------
var $tool2:=cs.agtools.AITToolCalculator.new({maxExpressionLength: 200})
ASSERT($tool2.maxExpressionLength=200; "Custom maxExpressionLength must be 200")

// -----------------------------------------------------------------
// 3. Validation — empty expression
// -----------------------------------------------------------------
var $res : Text:=$tool.evaluate_expression({expression: ""})
var $parsed : Object:=JSON Parse($res)
ASSERT(Not(Bool($parsed.success)); "Empty expression must fail")
ASSERT($parsed.error="An expression is required"; "Must report empty expression error")

// -----------------------------------------------------------------
// 4. Validation — expression too long
// -----------------------------------------------------------------
var $longExpr : Text:=""
var $i : Integer
For ($i; 1; 1100)
	$longExpr:=$longExpr+"1"
End for 
$res:=$tool.evaluate_expression({expression: $longExpr})
$parsed:=JSON Parse($res)
ASSERT(Not(Bool($parsed.success)); "Too-long expression must fail")

// -----------------------------------------------------------------
// 5. Basic arithmetic
// -----------------------------------------------------------------
$res:=$tool.evaluate_expression({expression: "2 + 3"})
$parsed:=JSON Parse($res)
ASSERT(Bool($parsed.success); "2 + 3 must succeed")
ASSERT($parsed.result=5; "2 + 3 must equal 5")
ASSERT($parsed.type="number"; "Type must be number")

$res:=$tool.evaluate_expression({expression: "2 + 3 * 4"})
$parsed:=JSON Parse($res)
ASSERT($parsed.result=14; "2 + 3 * 4 must equal 14 (order of operations)")

$res:=$tool.evaluate_expression({expression: "10 / 3"})
$parsed:=JSON Parse($res)
var $divResult : Real:=Num($parsed.result)
ASSERT(($divResult>3.33) & ($divResult<3.34); "10 / 3 must be ~3.333")

$res:=$tool.evaluate_expression({expression: "10 % 3"})
$parsed:=JSON Parse($res)
ASSERT($parsed.result=1; "10 % 3 must equal 1")

$res:=$tool.evaluate_expression({expression: "2 ^ 10"})
$parsed:=JSON Parse($res)
ASSERT($parsed.result=1024; "2 ^ 10 must equal 1024")

// -----------------------------------------------------------------
// 6. Math functions
// -----------------------------------------------------------------
$res:=$tool.evaluate_expression({expression: "abs(-42)"})
$parsed:=JSON Parse($res)
ASSERT($parsed.result=42; "abs(-42) must equal 42")

$res:=$tool.evaluate_expression({expression: "sqrt(144)"})
$parsed:=JSON Parse($res)
ASSERT($parsed.result=12; "sqrt(144) must equal 12")

$res:=$tool.evaluate_expression({expression: "pow(2, 8)"})
$parsed:=JSON Parse($res)
ASSERT($parsed.result=256; "pow(2, 8) must equal 256")

$res:=$tool.evaluate_expression({expression: "round(3.14159, 2)"})
$parsed:=JSON Parse($res)
ASSERT($parsed.result=3.14; "round(3.14159, 2) must equal 3.14")

$res:=$tool.evaluate_expression({expression: "floor(3.7)"})
$parsed:=JSON Parse($res)
ASSERT($parsed.result=3; "floor(3.7) must equal 3")

$res:=$tool.evaluate_expression({expression: "floor(-3.7)"})
$parsed:=JSON Parse($res)
ASSERT($parsed.result=-4; "floor(-3.7) must equal -4")

$res:=$tool.evaluate_expression({expression: "ceil(3.2)"})
$parsed:=JSON Parse($res)
ASSERT($parsed.result=4; "ceil(3.2) must equal 4")

$res:=$tool.evaluate_expression({expression: "ceil(-3.2)"})
$parsed:=JSON Parse($res)
ASSERT($parsed.result=-3; "ceil(-3.2) must equal -3")

$res:=$tool.evaluate_expression({expression: "max(10, 20)"})
$parsed:=JSON Parse($res)
ASSERT($parsed.result=20; "max(10, 20) must equal 20")

$res:=$tool.evaluate_expression({expression: "min(10, 20)"})
$parsed:=JSON Parse($res)
ASSERT($parsed.result=10; "min(10, 20) must equal 10")

$res:=$tool.evaluate_expression({expression: "mod(17, 5)"})
$parsed:=JSON Parse($res)
ASSERT($parsed.result=2; "mod(17, 5) must equal 2")

// -----------------------------------------------------------------
// 7. Trig functions
// -----------------------------------------------------------------
$res:=$tool.evaluate_expression({expression: "sin(0)"})
$parsed:=JSON Parse($res)
ASSERT($parsed.result=0; "sin(0) must equal 0")

$res:=$tool.evaluate_expression({expression: "cos(0)"})
$parsed:=JSON Parse($res)
ASSERT($parsed.result=1; "cos(0) must equal 1")

// -----------------------------------------------------------------
// 8. Constants
// -----------------------------------------------------------------
$res:=$tool.evaluate_expression({expression: "pi()"})
$parsed:=JSON Parse($res)
var $piVal : Real:=Num($parsed.result)
ASSERT(($piVal>3.14159) & ($piVal<3.14160); "pi() must be ~3.14159")

$res:=$tool.evaluate_expression({expression: "e()"})
$parsed:=JSON Parse($res)
var $eVal : Real:=Num($parsed.result)
ASSERT(($eVal>2.71828) & ($eVal<2.71829); "e() must be ~2.71828")

// -----------------------------------------------------------------
// 9. Variables
// -----------------------------------------------------------------
$res:=$tool.evaluate_expression({expression: "price * (1 + tax)"; variables: {price: 100; tax: 0.2}})
$parsed:=JSON Parse($res)
ASSERT($parsed.result=120; "100 * (1 + 0.2) must equal 120")

$res:=$tool.evaluate_expression({expression: "max(a, b) + min(c, d)"; variables: {a: 10; b: 20; c: 5; d: 3}})
$parsed:=JSON Parse($res)
ASSERT($parsed.result=23; "max(10,20) + min(5,3) must equal 23")

// -----------------------------------------------------------------
// 10. Collection transforms
// -----------------------------------------------------------------
$res:=$tool.evaluate_expression({expression: "[1, 2, 3, 4, 5]|sum"})
$parsed:=JSON Parse($res)
ASSERT($parsed.result=15; "[1,2,3,4,5]|sum must equal 15")

$res:=$tool.evaluate_expression({expression: "[10, 20, 30]|avg"})
$parsed:=JSON Parse($res)
ASSERT($parsed.result=20; "[10,20,30]|avg must equal 20")

$res:=$tool.evaluate_expression({expression: "[5, 1, 8, 3]|min"})
$parsed:=JSON Parse($res)
ASSERT($parsed.result=1; "[5,1,8,3]|min must equal 1")

$res:=$tool.evaluate_expression({expression: "[5, 1, 8, 3]|max"})
$parsed:=JSON Parse($res)
ASSERT($parsed.result=8; "[5,1,8,3]|max must equal 8")

$res:=$tool.evaluate_expression({expression: "[5, 1, 8, 3]|count"})
$parsed:=JSON Parse($res)
ASSERT($parsed.result=4; "[5,1,8,3]|count must equal 4")

// -----------------------------------------------------------------
// 11. Comparisons and logic
// -----------------------------------------------------------------
$res:=$tool.evaluate_expression({expression: "10 > 5"})
$parsed:=JSON Parse($res)
ASSERT(Bool($parsed.result); "10 > 5 must be true")
ASSERT($parsed.type="boolean"; "Type must be boolean")

$res:=$tool.evaluate_expression({expression: "x > 0 ? 'positive' : 'non-positive'"; variables: {x: 42}})
$parsed:=JSON Parse($res)
ASSERT($parsed.result="positive"; "Ternary with x=42 must return 'positive'")

// -----------------------------------------------------------------
// 12. Complex expressions
// -----------------------------------------------------------------
$res:=$tool.evaluate_expression({expression: "sqrt(pow(a, 2) + pow(b, 2))"; variables: {a: 3; b: 4}})
$parsed:=JSON Parse($res)
ASSERT($parsed.result=5; "sqrt(3² + 4²) must equal 5 (Pythagorean)")

$res:=$tool.evaluate_expression({expression: "round(pi() * pow(r, 2), 2)"; variables: {r: 5}})
$parsed:=JSON Parse($res)
ASSERT($parsed.result=78.54; "Area of circle r=5 must be ~78.54")

// -----------------------------------------------------------------
// 13. Tool integration with chat helper
// -----------------------------------------------------------------
var $client:=TestOpenAI()
If ($client#Null)
	var $helper:=$client.chat.create("You are a helpful assistant that can do math. Use the evaluate_expression tool for any calculation."; {model: "gpt-4o-mini"})
	$helper.autoHandleToolCalls:=True
	$helper.registerTools($tool)
	ASSERT($helper.tools.length>=1; "Tool must be registered on helper")
	
	// Ask the LLM to compute something — it should use the calculator tool
	var $result:=$helper.prompt("What is the square root of 144 plus 2 to the power of 8? Give me only the number.")
	ASSERT(Bool($result.success); "Prompt must succeed: "+JSON Stringify($result.errors))
	
	// The answer should be 12 + 256 = 268
	var $answer : Text:=$result.choice.message.text
	ASSERT(Position("268"; $answer)>0; "Answer must contain 268, got: "+$answer)
End if 

ALERT("✅ test_calculator passed")
