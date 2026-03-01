// AIToolMemory — Key-value memory for AI agents (in-memory or ORDA-persisted)
//
// Inspired by the MCP Knowledge Graph Memory Server and LangChain memory patterns.
// Lets the agent store facts, preferences, and context across tool calls.
//
// Modes:
//   - In-memory (default): entries stored in a collection on the instance
//   - Database: entries persisted to an ORDA dataclass when configured
//
// Usage (in-memory):
//   var $memory:=cs.AIToolMemory.new()
//   $helper.registerTools($memory)
//
// Usage (database-persisted):
//   var $memory:=cs.AIToolMemory.new({ \
//     dataclass: "Memory"; \
//     fields: {key: "memoryKey"; value: "memoryValue"; category: "memoryCategory"} \
//   })
//   $helper.registerTools($memory)

property tools : Collection
property maxEntries : Integer
property maxKeyLength : Integer
property maxValueLength : Integer
property _store : Collection  // In-memory entries: [{key, value, category, tags, createdAt, updatedAt}]
property _dataclass : Text  // Dataclass name for ORDA persistence (empty = in-memory only)
property _fields : Object  // Field name mapping: {key, value, category, tags, createdAt, updatedAt}
property _persistent : Boolean  // True when using ORDA storage

Class constructor($config : Object)
	
	If ($config=Null)
		$config:={}
	End if 
	
	// --- Configuration ---
	This.maxEntries:=($config.maxEntries#Null) ? $config.maxEntries : 1000
	This.maxKeyLength:=($config.maxKeyLength#Null) ? $config.maxKeyLength : 200
	This.maxValueLength:=($config.maxValueLength#Null) ? $config.maxValueLength : 50000  // 50KB per value
	
	// --- Storage mode ---
	This._dataclass:=($config.dataclass#Null) ? String($config.dataclass) : ""
	This._persistent:=(Length(This._dataclass)>0)
	
	// --- Field mapping (for ORDA persistence) ---
	var $f : Object:=($config.fields#Null) ? $config.fields : {}
	This._fields:={}
	This._fields.key:=($f.key#Null) ? String($f.key) : "key"
	This._fields.value:=($f.value#Null) ? String($f.value) : "value"
	This._fields.category:=($f.category#Null) ? String($f.category) : "category"
	This._fields.tags:=($f.tags#Null) ? String($f.tags) : "tags"
	This._fields.createdAt:=($f.createdAt#Null) ? String($f.createdAt) : "createdAt"
	This._fields.updatedAt:=($f.updatedAt#Null) ? String($f.updatedAt) : "updatedAt"
	
	// --- In-memory store (always initialised; used as cache even with ORDA) ---
	This._store:=New collection()
	
	// --- Tool definitions ---
	This.tools:=[]
	
	// 1. memory_store
	This.tools.push({\
		name: "memory_store"; \
		description: "Store a fact, preference, or piece of information in memory. If the key already exists, the value is updated. Use meaningful keys (e.g. 'user_name', 'project_deadline', 'preferred_language')."; \
		parameters: {\
		type: "object"; \
		properties: {\
		key: {type: "string"; description: "Unique memory key (e.g. 'user_name', 'todo_list', 'last_search_results')"}; \
		value: {type: "string"; description: "The content to store. Can be plain text, a JSON string, or any textual value."}; \
		category: {type: "string"; description: "Optional category to organise memories (e.g. 'preference', 'fact', 'context', 'task')"}; \
		tags: {type: "string"; description: "Optional comma-separated tags for filtering (e.g. 'important,personal')"}\
		}; \
		required: ["key"; "value"]; \
		additionalProperties: False\
		}\
		})
	
	// 2. memory_retrieve
	This.tools.push({\
		name: "memory_retrieve"; \
		description: "Retrieve memories. Provide either 'key' for exact lookup, or 'query' to search across keys, values, and categories. You can also filter by category."; \
		parameters: {\
		type: "object"; \
		properties: {\
		key: {type: "string"; description: "Exact memory key to retrieve"}; \
		query: {type: "string"; description: "Search text — matches against keys, values, and categories (case-insensitive)"}; \
		category: {type: "string"; description: "Filter results to a specific category"}\
		}; \
		additionalProperties: False\
		}\
		})
	
	// 3. memory_list
	This.tools.push({\
		name: "memory_list"; \
		description: "List all stored memory keys with their categories. Optionally filter by category. Returns key, category, and a truncated preview of each value."; \
		parameters: {\
		type: "object"; \
		properties: {\
		category: {type: "string"; description: "Optional — only list memories in this category"}\
		}; \
		additionalProperties: False\
		}\
		})
	
	// 4. memory_delete
	This.tools.push({\
		name: "memory_delete"; \
		description: "Delete a memory entry by its exact key. Returns confirmation or error if key not found."; \
		parameters: {\
		type: "object"; \
		properties: {\
		key: {type: "string"; description: "The exact key of the memory to delete"}\
		}; \
		required: ["key"]; \
		additionalProperties: False\
		}\
		})
	
	// -----------------------------------------------------------------
	// MARK:- Tool handlers
	// -----------------------------------------------------------------

Function memory_store($params : Object) : Text
	
	var $key : Text:=String($params.key)
	var $value : Text:=String($params.value)
	var $category : Text:=($params.category#Null) ? String($params.category) : ""
	var $tags : Text:=($params.tags#Null) ? String($params.tags) : ""
	
	// --- Validate ---
	If (Length($key)=0)
		return "Error: 'key' is required."
	End if 
	
	If (Length($key)>This.maxKeyLength)
		return "Error: key exceeds maximum length of "+String(This.maxKeyLength)+" characters."
	End if 
	
	If (Length($value)>This.maxValueLength)
		return "Error: value exceeds maximum length of "+String(This.maxValueLength)+" characters."
	End if 
	
	var $now : Text:=String(Current date; ISO date; Current time)
	
	// --- Persistent mode (ORDA) ---
	If (This._persistent)
		return This._dbStore($key; $value; $category; $tags; $now)
	End if 
	
	// --- In-memory mode ---
	// Check for existing key (update)
	var $i : Integer
	var $entry : Object
	For ($i; 0; This._store.length-1)
		$entry:=This._store[$i]
		If ($entry.key=$key)
			$entry.value:=$value
			$entry.category:=$category
			$entry.tags:=$tags
			$entry.updatedAt:=$now
			return "Updated memory '"+$key+"'."
		End if 
	End for 
	
	// New entry — check limit
	If (This._store.length>=This.maxEntries)
		return "Error: memory is full ("+String(This.maxEntries)+" entries). Delete some entries first."
	End if 
	
	This._store.push({key: $key; value: $value; category: $category; tags: $tags; createdAt: $now; updatedAt: $now})
	return "Stored memory '"+$key+"'."
	
Function memory_retrieve($params : Object) : Text
	
	var $key : Text:=($params.key#Null) ? String($params.key) : ""
	var $query : Text:=($params.query#Null) ? String($params.query) : ""
	var $category : Text:=($params.category#Null) ? String($params.category) : ""
	
	If ((Length($key)=0) & (Length($query)=0) & (Length($category)=0))
		return "Error: provide at least one of 'key', 'query', or 'category'."
	End if 
	
	// --- Persistent mode ---
	If (This._persistent)
		return This._dbRetrieve($key; $query; $category)
	End if 
	
	// --- In-memory: exact key lookup ---
	If (Length($key)>0)
		var $entry : Object:=This._findByKey($key)
		If ($entry#Null)
			return JSON Stringify($entry; *)
		End if 
		return "No memory found for key '"+$key+"'."
	End if 
	
	// --- In-memory: search ---
	var $results : Collection:=New collection()
	var $e : Object
	var $lowerQuery : Text:=Lowercase($query)
	
	For each ($e; This._store)
		var $match : Boolean:=False
		
		If (Length($query)>0)
			If ((Position($lowerQuery; Lowercase($e.key))>0) | (Position($lowerQuery; Lowercase($e.value))>0) | (Position($lowerQuery; Lowercase($e.category))>0) | (Position($lowerQuery; Lowercase($e.tags))>0))
				$match:=True
			End if 
		Else 
			$match:=True  // No query filter, will be filtered by category below
		End if 
		
		If ($match & (Length($category)>0))
			If (Lowercase($e.category)#Lowercase($category))
				$match:=False
			End if 
		End if 
		
		If ($match)
			$results.push($e)
		End if 
	End for each 
	
	If ($results.length=0)
		return "No memories found matching your criteria."
	End if 
	
	return JSON Stringify($results; *)
	
Function memory_list($params : Object) : Text
	
	var $category : Text:=($params.category#Null) ? String($params.category) : ""
	
	// --- Persistent mode ---
	If (This._persistent)
		return This._dbList($category)
	End if 
	
	// --- In-memory ---
	If (This._store.length=0)
		return "Memory is empty."
	End if 
	
	var $results : Collection:=New collection()
	var $e : Object
	
	For each ($e; This._store)
		var $include : Boolean:=True
		If (Length($category)>0)
			If (Lowercase($e.category)#Lowercase($category))
				$include:=False
			End if 
		End if 
		
		If ($include)
			var $preview : Text:=$e.value
			If (Length($preview)>100)
				$preview:=Substring($preview; 1; 100)+"…"
			End if 
			$results.push({key: $e.key; category: $e.category; preview: $preview; updatedAt: $e.updatedAt})
		End if 
	End for each 
	
	If ($results.length=0)
		return "No memories found in category '"+$category+"'."
	End if 
	
	return JSON Stringify($results; *)
	
Function memory_delete($params : Object) : Text
	
	var $key : Text:=String($params.key)
	
	If (Length($key)=0)
		return "Error: 'key' is required."
	End if 
	
	// --- Persistent mode ---
	If (This._persistent)
		return This._dbDelete($key)
	End if 
	
	// --- In-memory ---
	var $i : Integer
	For ($i; 0; This._store.length-1)
		If (This._store[$i].key=$key)
			This._store.remove($i)
			return "Deleted memory '"+$key+"'."
		End if 
	End for 
	
	return "Error: no memory found with key '"+$key+"'."
	
	// -----------------------------------------------------------------
	// MARK:- ORDA persistence helpers
	// -----------------------------------------------------------------

Function _dbStore($key : Text; $value : Text; $category : Text; $tags : Text; $now : Text) : Text
	
	Try
		var $dc : cs.DataClass:=ds[This._dataclass]
		If ($dc=Null)
			return "Error: dataclass '"+This._dataclass+"' not found."
		End if 
		
		var $fKey : Text:=This._fields.key
		var $fValue : Text:=This._fields.value
		var $fCategory : Text:=This._fields.category
		var $fTags : Text:=This._fields.tags
		var $fCreatedAt : Text:=This._fields.createdAt
		var $fUpdatedAt : Text:=This._fields.updatedAt
		
		// Look for existing record with this key
		var $selection : Object:=$dc.query($fKey+" = :1"; $key)
		
		If ($selection.length>0)
			// Update existing
			var $record : Object:=$selection.first()
			$record[$fValue]:=$value
			If (Length($category)>0)
				$record[$fCategory]:=$category
			End if 
			If (Length($tags)>0)
				$record[$fTags]:=$tags
			End if 
			$record[$fUpdatedAt]:=$now
			$record.save()
			return "Updated memory '"+$key+"' (persisted)."
		End if 
		
		// Check entry limit
		If ($dc.all().length>=This.maxEntries)
			return "Error: memory is full ("+String(This.maxEntries)+" entries). Delete some entries first."
		End if 
		
		// Create new record
		var $newRecord : Object:=$dc.new()
		$newRecord[$fKey]:=$key
		$newRecord[$fValue]:=$value
		$newRecord[$fCategory]:=$category
		$newRecord[$fTags]:=$tags
		$newRecord[$fCreatedAt]:=$now
		$newRecord[$fUpdatedAt]:=$now
		$newRecord.save()
		
		return "Stored memory '"+$key+"' (persisted)."
		
	Catch
		return "Error storing memory: "+Last errors.last().message
	End try
	
Function _dbRetrieve($key : Text; $query : Text; $category : Text) : Text
	
	Try
		var $dc : cs.DataClass:=ds[This._dataclass]
		If ($dc=Null)
			return "Error: dataclass '"+This._dataclass+"' not found."
		End if 
		
		var $fKey : Text:=This._fields.key
		var $fValue : Text:=This._fields.value
		var $fCategory : Text:=This._fields.category
		var $fTags : Text:=This._fields.tags
		
		// Exact key lookup
		If (Length($key)>0)
			var $selection : Object:=$dc.query($fKey+" = :1"; $key)
			If ($selection.length>0)
				var $rec : Object:=$selection.first()
				var $result : Object:={}
				$result.key:=$rec[$fKey]
				$result.value:=$rec[$fValue]
				$result.category:=$rec[$fCategory]
				$result.tags:=$rec[$fTags]
				return JSON Stringify($result; *)
			End if 
			return "No memory found for key '"+$key+"'."
		End if 
		
		// Search query — ORDA query across key, value, category, tags
		var $queryParts : Collection:=New collection()
		var $queryParams : Collection:=New collection()
		var $paramIndex : Integer:=1
		
		If (Length($query)>0)
			var $likePattern : Text:="%"+$query+"%"
			$queryParts.push("("+$fKey+" = :"+String($paramIndex)+" OR "+$fValue+" = :"+String($paramIndex+1)+" OR "+$fCategory+" = :"+String($paramIndex+2)+" OR "+$fTags+" = :"+String($paramIndex+3)+")")
			// Use keyword @ for contains matching
			$queryParams.push($likePattern)
			$queryParams.push($likePattern)
			$queryParams.push($likePattern)
			$queryParams.push($likePattern)
			$paramIndex:=$paramIndex+4
		End if 
		
		If (Length($category)>0)
			$queryParts.push($fCategory+" = :"+String($paramIndex))
			$queryParams.push($category)
			$paramIndex:=$paramIndex+1
		End if 
		
		var $queryStr : Text:=$queryParts.join(" AND ")
		var $results : Object
		
		Case of 
			: ($queryParams.length=1)
				$results:=$dc.query($queryStr; $queryParams[0])
			: ($queryParams.length=2)
				$results:=$dc.query($queryStr; $queryParams[0]; $queryParams[1])
			: ($queryParams.length=4)
				$results:=$dc.query($queryStr; $queryParams[0]; $queryParams[1]; $queryParams[2]; $queryParams[3])
			: ($queryParams.length=5)
				$results:=$dc.query($queryStr; $queryParams[0]; $queryParams[1]; $queryParams[2]; $queryParams[3]; $queryParams[4])
			Else 
				$results:=$dc.all()
		End case 
		
		If ($results.length=0)
			return "No memories found matching your criteria."
		End if 
		
		var $output : Collection:=New collection()
		var $r : Object
		For each ($r; $results)
			$output.push({key: $r[$fKey]; value: $r[$fValue]; category: $r[$fCategory]; tags: $r[$fTags]})
		End for each 
		
		return JSON Stringify($output; *)
		
	Catch
		return "Error retrieving memory: "+Last errors.last().message
	End try
	
Function _dbList($category : Text) : Text
	
	Try
		var $dc : cs.DataClass:=ds[This._dataclass]
		If ($dc=Null)
			return "Error: dataclass '"+This._dataclass+"' not found."
		End if 
		
		var $fKey : Text:=This._fields.key
		var $fValue : Text:=This._fields.value
		var $fCategory : Text:=This._fields.category
		var $fUpdatedAt : Text:=This._fields.updatedAt
		
		var $selection : Object
		If (Length($category)>0)
			$selection:=$dc.query($fCategory+" = :1"; $category)
		Else 
			$selection:=$dc.all()
		End if 
		
		If ($selection.length=0)
			If (Length($category)>0)
				return "No memories found in category '"+$category+"'."
			End if 
			return "Memory is empty."
		End if 
		
		var $results : Collection:=New collection()
		var $r : Object
		For each ($r; $selection)
			var $preview : Text:=String($r[$fValue])
			If (Length($preview)>100)
				$preview:=Substring($preview; 1; 100)+"…"
			End if 
			$results.push({key: $r[$fKey]; category: $r[$fCategory]; preview: $preview; updatedAt: String($r[$fUpdatedAt])})
		End for each 
		
		return JSON Stringify($results; *)
		
	Catch
		return "Error listing memories: "+Last errors.last().message
	End try
	
Function _dbDelete($key : Text) : Text
	
	Try
		var $dc : cs.DataClass:=ds[This._dataclass]
		If ($dc=Null)
			return "Error: dataclass '"+This._dataclass+"' not found."
		End if 
		
		var $fKey : Text:=This._fields.key
		var $selection : Object:=$dc.query($fKey+" = :1"; $key)
		
		If ($selection.length=0)
			return "Error: no memory found with key '"+$key+"'."
		End if 
		
		$selection.first().drop()
		return "Deleted memory '"+$key+"' (persisted)."
		
	Catch
		return "Error deleting memory: "+Last errors.last().message
	End try
	
	// -----------------------------------------------------------------
	// MARK:- Internal helpers
	// -----------------------------------------------------------------

Function _findByKey($key : Text) : Object
	
	var $e : Object
	For each ($e; This._store)
		If ($e.key=$key)
			return $e
		End if 
	End for each 
	
	return Null
