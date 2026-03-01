// AIToolCalculator — Evaluate math expressions safely via ExpressionLanguage
//
// Uses the ExpressionLanguage component (cs.exl.Language) to evaluate
// mathematical expressions without executing arbitrary 4D code.
// The expression engine is sandboxed: no access to 4D commands, file I/O,
// network, or database. Only explicitly registered math functions are available.
//
// Security: sandboxed expression evaluator, no code execution, expression length cap
//
// Usage:
//   var $tool:=cs.agtools.AITToolCalculator.new()
//   $helper.registerTools($tool)

property tools : Collection
property _lang : Object  // cs.exl.Language instance
property maxExpressionLength : Integer

Class constructor($config : Object)
	
	If ($config=Null)
		$config:={}
	End if 
	
	// --- Configuration ---
	This.maxExpressionLength:=($config.maxExpressionLength#Null) ? $config.maxExpressionLength : 1000
	
	// --- Initialize expression language engine ---
	This._lang:=cs.exl.Language.new()
	This._registerFunctions()
	This._registerTransforms()
	
	// --- Tool definitions ---
	This.tools:=[]
	
	This.tools.push({\
		name: "evaluate_expression"; \
		description: "Evaluate a mathematical expression. Supports arithmetic (+, -, *, /, %, ^), comparisons (==, !=, >, >=, <, <=), logic (&&, ||, !), ternary (cond ? a : b), and functions: abs, round, sqrt, pow, log, exp, sin, cos, tan, asin, acos, atan, floor, ceil, min, max, mod, pi, e, random, int, dec. Collection operations: [1,2,3]|sum, |avg, |min, |max, |count, |sort, |reverse. Pass named variables via the 'variables' parameter. Do NOT use this for non-math operations."; \
		parameters: {\
		type: "object"; \
		properties: {\
		expression: {type: "string"; description: "The mathematical expression to evaluate. Examples: '2 + 3 * 4', 'sqrt(144)', 'max(a, b) + pow(2, 10)', '[1,2,3,4,5]|avg', 'price * (1 + tax_rate)'"}; \
		variables: {type: "object"; description: "Optional named variables. Example: {\"a\": 10, \"b\": 20, \"price\": 99.99, \"tax_rate\": 0.2}"}\
		}; \
		required: ["expression"]; \
		additionalProperties: False\
		}\
		})
	
	// -----------------------------------------------------------------
	// MARK:- Tool handler
	// -----------------------------------------------------------------
Function evaluate_expression($params : Object) : Text
	
	var $expression : Text:=String($params.expression)
	
	// --- Validate expression ---
	If (Length($expression)=0)
		return JSON Stringify({success: False; error: "An expression is required"})
	End if 
	
	If (Length($expression)>This.maxExpressionLength)
		return JSON Stringify({success: False; error: "Expression exceeds maximum length of "+String(This.maxExpressionLength)+" characters"})
	End if 
	
	// --- Build context from variables ---
	var $context : Object
	If ($params.variables#Null)
		$context:=$params.variables
	Else 
		$context:={}
	End if 
	
	// --- Evaluate ---
	var $result : Variant:=This._lang.eval($expression; $context)
	
	// --- Format result ---
	var $response : Object:={success: True; expression: $expression}
	
	Case of 
		: (Value type($result)=Is real) | (Value type($result)=Is longint) | (Value type($result)=Is integer)
			$response.result:=$result
			$response.type:="number"
		: (Value type($result)=Is boolean)
			$response.result:=$result
			$response.type:="boolean"
		: (Value type($result)=Is text)
			$response.result:=$result
			$response.type:="text"
		: (Value type($result)=Is collection)
			$response.result:=$result
			$response.type:="collection"
		: (Value type($result)=Is object)
			$response.result:=$result
			$response.type:="object"
		: ($result=Null)
			$response.result:=Null
			$response.type:="null"
		Else 
			$response.result:=String($result)
			$response.type:="other"
	End case 
	
	return JSON Stringify($response)
	
	
	// -----------------------------------------------------------------
	// MARK:- Register math functions
	// -----------------------------------------------------------------
Function _registerFunctions()
	
	// --- Basic math ---
	This._lang.addFunction("abs"; Formula(Abs($1)))
	This._lang.addFunction("round"; Formula(Round($1; $2)))  // round(x) or round(x, decimals)
	// int: truncate toward zero (Int() rounds toward -∞, so adjust for negative fractions)
	This._lang.addFunction("int"; Formula(Choose(($1>=0) | (Dec($1)=0); Int($1); Int($1)+1)))
	This._lang.addFunction("dec"; Formula(Dec($1)))  // decimal part
	This._lang.addFunction("mod"; Formula(Mod($1; $2)))  // also available as %
	
	// --- Power / roots ---
	This._lang.addFunction("sqrt"; Formula(Square root($1)))
	This._lang.addFunction("pow"; Formula($1^$2))  // also available as ^ operator
	
	// --- Logarithmic / exponential ---
	This._lang.addFunction("log"; Formula(Log($1)))  // natural logarithm (ln)
	This._lang.addFunction("ln"; Formula(Log($1)))  // alias for log
	This._lang.addFunction("exp"; Formula(Exp($1)))  // e^x
	
	// --- Trigonometric (radians) ---
	This._lang.addFunction("sin"; Formula(Sin($1)))
	This._lang.addFunction("cos"; Formula(Cos($1)))
	This._lang.addFunction("tan"; Formula(Tan($1)))
	This._lang.addFunction("atan"; Formula(Arctan($1)))
	This._lang.addFunction("asin"; Formula(Arctan($1/Square root(1-$1*$1))))
	This._lang.addFunction("acos"; Formula(Arctan(Square root(1-$1*$1)/$1)))
	
	// --- Min / Max (two values) ---
	This._lang.addFunction("max"; Formula(Choose($1>=$2; $1; $2)))
	This._lang.addFunction("min"; Formula(Choose($1<=$2; $1; $2)))
	
	// --- Floor / Ceil ---
	// 4D Int() already rounds toward -∞, so it IS floor
	This._lang.addFunction("floor"; Formula(Int($1)))
	// ceil: smallest integer >= x
	This._lang.addFunction("ceil"; Formula(Choose(Dec($1)=0; Int($1); Int($1)+1)))
	
	// --- Constants ---
	This._lang.addFunction("pi"; Formula(3.14159265358979323846))
	This._lang.addFunction("e"; Formula(Exp(1)))
	
	// --- Random ---
	This._lang.addFunction("random"; Formula(Random/32767))  // 0..1
	
	
	// -----------------------------------------------------------------
	// MARK:- Register transforms (pipe operators)
	// -----------------------------------------------------------------
Function _registerTransforms()
	
	// --- Collection transforms ---
	This._lang.addTransform("sum"; Formula($1.sum()))
	This._lang.addTransform("avg"; Formula($1.average()))
	This._lang.addTransform("min"; Formula($1.min()))
	This._lang.addTransform("max"; Formula($1.max()))
	This._lang.addTransform("count"; Formula($1.length))
	This._lang.addTransform("sort"; Formula($1.sort()))
	This._lang.addTransform("reverse"; Formula($1.reverse()))
	
	// --- Number transforms ---
	This._lang.addTransform("abs"; Formula(Abs($1)))
	This._lang.addTransform("round"; Formula(Round($1; 0)))
	This._lang.addTransform("floor"; Formula(Int($1)))
	This._lang.addTransform("ceil"; Formula(Choose(Dec($1)=0; Int($1); Int($1)+1)))
