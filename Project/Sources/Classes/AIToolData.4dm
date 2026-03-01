// AIToolData — Query 4D database via ORDA
//
// Security: dataclass whitelist, record limit, read-only by default, attribute projection
//
// Usage:
//   var $tool:=cs.AIToolData.new({allowedDataclasses: ["Employee"; "Product"]; maxRecords: 50})
//   $helper.registerTools($tool)

property tools : Collection
property allowedDataclasses : Collection
property maxRecords : Integer
property readOnly : Boolean

Class constructor($config : Object)
	
	If ($config=Null)
		$config:={}
	End if 
	
	// --- Configuration ---
	This.allowedDataclasses:=($config.allowedDataclasses#Null) ? $config.allowedDataclasses : New collection()  // empty = ⚠️ all dataclasses
	This.maxRecords:=($config.maxRecords#Null) ? $config.maxRecords : 100
	This.readOnly:=($config.readOnly#Null) ? $config.readOnly : True  // Read-only by default
	
	// --- Tool definitions ---
	This.tools:=[]
	
	This.tools.push({\
		name: "list_dataclasses"; \
		description: "List all available dataclasses (tables) in the 4D database."; \
		parameters: {\
		type: "object"; \
		properties: {}; \
		additionalProperties: False\
		}\
		})
	
	This.tools.push({\
		name: "get_dataclass_info"; \
		description: "Get the schema/structure of a dataclass: attribute names, types, and kinds."; \
		parameters: {\
		type: "object"; \
		properties: {\
		dataclass: {type: "string"; description: "Name of the dataclass to inspect"}\
		}; \
		required: ["dataclass"]; \
		additionalProperties: False\
		}\
		})
	
	This.tools.push({\
		name: "query_data"; \
		description: "Query records from a dataclass using ORDA query string syntax. Returns results as JSON. Example queries: 'name = :1' with params, 'salary > 50000', 'name = \"Smith\"'."; \
		parameters: {\
		type: "object"; \
		properties: {\
		dataclass: {type: "string"; description: "Name of the dataclass to query"}; \
		query: {type: "string"; description: "ORDA query string (e.g. 'name = \"Smith\"', 'age > 30'). Leave empty for all records."}; \
		attributes: {type: "string"; description: "Comma-separated list of attributes to return (e.g. 'name,email,salary'). Leave empty for all attributes."}\
		}; \
		required: ["dataclass"]; \
		additionalProperties: False\
		}\
		})
	
	// -----------------------------------------------------------------
	// MARK:- Tool handlers
	// -----------------------------------------------------------------
	
Function list_dataclasses($params : Object) : Text
	
	Try
		var $datastore:=ds
		var $names : Collection:=New collection()
		
		var $name : Text
		For each ($name; $datastore)
			If (This._isDataclassAllowed($name))
				var $dc : cs.DataClass:=$datastore[$name]
				If ($dc#Null)
					$names.push($name)
				End if 
			End if 
		End for each 
		
		If ($names.length=0)
			return "No accessible dataclasses found."
		End if 
		
		return "Available dataclasses:\n"+$names.join("\n")
		
	Catch
		return "Error listing dataclasses: "+Last errors.last().message
	End try
	
Function get_dataclass_info($params : Object) : Text
	
	var $dcName : Text:=String($params.dataclass)
	
	If (Not(This._isDataclassAllowed($dcName)))
		return "Error: Dataclass '"+$dcName+"' is not accessible."
	End if 
	
	Try
		var $datastore:=ds
		var $dc : cs.DataClass:=$datastore[$dcName]
		
		If ($dc=Null)
			return "Error: Dataclass '"+$dcName+"' not found."
		End if 
		
		var $output : Text:="Schema for dataclass '"+$dcName+"':\n\n"
		
		// Get attribute info by reading the dataclass structure
		var $attrName : Text
		For each ($attrName; $dc)
			var $attr : Variant:=$dc[$attrName]
			If ($attr#Null)
				var $kind : Text:=String($attr.kind)
				var $type : Text:=String($attr.type)
				$output:=$output+"  - "+$attrName+" ("+$type
				If (Length($kind)>0)
					$output:=$output+", "+$kind
				End if 
				$output:=$output+")\n"
			End if 
		End for each 
		
		return $output
		
	Catch
		return "Error getting dataclass info: "+Last errors.last().message
	End try
	
Function query_data($params : Object) : Text
	
	var $dcName : Text:=String($params.dataclass)
	var $queryStr : Text:=String($params.query)
	var $attributes : Text:=String($params.attributes)
	
	If (Not(This._isDataclassAllowed($dcName)))
		return "Error: Dataclass '"+$dcName+"' is not accessible."
	End if 
	
	Try
		var $datastore:=ds
		var $dc : cs.DataClass:=$datastore[$dcName]
		
		If ($dc=Null)
			return "Error: Dataclass '"+$dcName+"' not found."
		End if 
		
		// --- Execute query ---
		var $selection : Object
		If (Length($queryStr)>0)
			$selection:=$dc.query($queryStr)
		Else 
			$selection:=$dc.all()
		End if 
		
		// --- Record count info ---
		var $totalCount : Integer:=$selection.length
		var $output : Text:=""
		
		// --- Limit records ---
		If ($totalCount>This.maxRecords)
			$selection:=$selection.slice(0; This.maxRecords)
			$output:="⚠️ Showing "+String(This.maxRecords)+" of "+String($totalCount)+" total records.\n\n"
		End if 
		
		// --- Convert to collection with attribute projection ---
		var $results : Collection
		If (Length($attributes)>0)
			$results:=$selection.toCollection($attributes)
		Else 
			$results:=$selection.toCollection()
		End if 
		
		$output:=$output+JSON Stringify($results; *)
		
		return $output
		
	Catch
		return "Error querying data: "+Last errors.last().message
	End try
	
	// -----------------------------------------------------------------
	// MARK:- Internal helpers
	// -----------------------------------------------------------------
	
Function _isDataclassAllowed($name : Text) : Boolean
	If (Length($name)=0)
		return False
	End if 
	
	// If no whitelist configured, allow all (⚠️ not recommended)
	If (This.allowedDataclasses.length=0)
		return True
	End if 
	
	var $allowed : Text
	For each ($allowed; This.allowedDataclasses)
		If (Lowercase($name)=Lowercase($allowed))
			return True
		End if 
	End for each 
	
	return False
	