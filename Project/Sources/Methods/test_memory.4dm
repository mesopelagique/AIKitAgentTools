//%attributes = {}
// test_memory — Test AIToolMemory (in-memory key-value store for agents)

// =================================================================
// 1. Basic instantiation (in-memory, default config)
// =================================================================
var $tool:=cs.AIToolMemory.new()
ASSERT:C1129(OB Instance of:C1731($tool; cs.AIToolMemory); "Must be AIToolMemory instance")
ASSERT:C1129($tool.tools.length=4; "Must expose 4 tools (store, retrieve, list, delete)")
ASSERT:C1129($tool.tools[0].name="memory_store"; "Tool 0 = memory_store")
ASSERT:C1129($tool.tools[1].name="memory_retrieve"; "Tool 1 = memory_retrieve")
ASSERT:C1129($tool.tools[2].name="memory_list"; "Tool 2 = memory_list")
ASSERT:C1129($tool.tools[3].name="memory_delete"; "Tool 3 = memory_delete")
ASSERT:C1129($tool.maxEntries=1000; "Default maxEntries = 1000")
ASSERT:C1129($tool.maxKeyLength=200; "Default maxKeyLength = 200")
ASSERT:C1129($tool.maxValueLength=50000; "Default maxValueLength = 50000")
ASSERT:C1129($tool._persistent=False; "Default mode = in-memory (not persistent)")

// =================================================================
// 2. Custom config
// =================================================================
var $tool2:=cs.AIToolMemory.new({maxEntries: 10; maxKeyLength: 50; maxValueLength: 500})
ASSERT:C1129($tool2.maxEntries=10; "Custom maxEntries = 10")
ASSERT:C1129($tool2.maxKeyLength=50; "Custom maxKeyLength = 50")
ASSERT:C1129($tool2.maxValueLength=500; "Custom maxValueLength = 500")

// =================================================================
// 3. Store — basic key/value
// =================================================================
var $res : Text:=$tool.memory_store({key: "user_name"; value: "Alice"})
ASSERT:C1129(Position:C15("Stored"; $res)>0; "Store must confirm: "+$res)

$res:=$tool.memory_store({key: "project"; value: "4D AIKit Tools"; category: "context"; tags: "dev,4d"})
ASSERT:C1129(Position:C15("Stored"; $res)>0; "Store with category/tags must confirm: "+$res)

// =================================================================
// 4. Retrieve — exact key
// =================================================================
$res:=$tool.memory_retrieve({key: "user_name"})
var $parsed : Object:=JSON Parse:C1218($res)
ASSERT:C1129($parsed.key="user_name"; "Retrieve key must match")
ASSERT:C1129($parsed.value="Alice"; "Retrieve value must match")

// =================================================================
// 5. Retrieve — search query
// =================================================================
$res:=$tool.memory_retrieve({query: "AIKit"})
ASSERT:C1129(Position:C15("4D AIKit"; $res)>0; "Search must find matching value: "+Substring:C12($res; 1; 200))

$res:=$tool.memory_retrieve({query: "nonexistent_xyz"})
ASSERT:C1129(Position:C15("No memories found"; $res)>0; "Non-matching search must report not found: "+$res)

// =================================================================
// 6. Retrieve — filter by category
// =================================================================
$res:=$tool.memory_retrieve({category: "context"})
ASSERT:C1129(Position:C15("project"; $res)>0; "Category filter must find 'project': "+Substring:C12($res; 1; 200))

$res:=$tool.memory_retrieve({category: "nonexistent"})
ASSERT:C1129(Position:C15("No memories found"; $res)>0; "Non-matching category must return not found: "+$res)

// =================================================================
// 7. List — all entries
// =================================================================
$res:=$tool.memory_list({})
ASSERT:C1129(Position:C15("user_name"; $res)>0; "List must include user_name: "+Substring:C12($res; 1; 200))
ASSERT:C1129(Position:C15("project"; $res)>0; "List must include project: "+Substring:C12($res; 1; 200))

// =================================================================
// 8. List — filter by category
// =================================================================
$res:=$tool.memory_list({category: "context"})
ASSERT:C1129(Position:C15("project"; $res)>0; "List by category must include project")
ASSERT:C1129(Position:C15("user_name"; $res)=0; "List by category must NOT include user_name (no category)")

// =================================================================
// 9. Update — store with existing key overwrites
// =================================================================
$res:=$tool.memory_store({key: "user_name"; value: "Bob"})
ASSERT:C1129(Position:C15("Updated"; $res)>0; "Re-store must report Updated: "+$res)

$res:=$tool.memory_retrieve({key: "user_name"})
$parsed:=JSON Parse:C1218($res)
ASSERT:C1129($parsed.value="Bob"; "Updated value must be Bob")

// =================================================================
// 10. Delete
// =================================================================
$res:=$tool.memory_delete({key: "user_name"})
ASSERT:C1129(Position:C15("Deleted"; $res)>0; "Delete must confirm: "+$res)

$res:=$tool.memory_retrieve({key: "user_name"})
ASSERT:C1129(Position:C15("No memory found"; $res)>0; "Deleted key must not be retrievable: "+$res)

// Delete non-existent key
$res:=$tool.memory_delete({key: "does_not_exist"})
ASSERT:C1129(Position:C15("Error"; $res)>0; "Delete non-existent must report error: "+$res)

// =================================================================
// 11. Validation — empty key
// =================================================================
$res:=$tool.memory_store({key: ""; value: "test"})
ASSERT:C1129(Position:C15("Error"; $res)>0; "Empty key must fail: "+$res)

// =================================================================
// 12. Validation — key too long
// =================================================================
var $longKey : Text:=""
var $k : Integer
For ($k; 1; 250)
	$longKey:=$longKey+"x"
End for 
$res:=$tool.memory_store({key: $longKey; value: "test"})
ASSERT:C1129(Position:C15("Error"; $res)>0; "Key too long must fail: "+$res)

// =================================================================
// 13. Validation — retrieve with no params
// =================================================================
$res:=$tool.memory_retrieve({})
ASSERT:C1129(Position:C15("Error"; $res)>0; "Retrieve with no params must fail: "+$res)

// =================================================================
// 14. Entry limit enforcement
// =================================================================
var $limitTool:=cs.AIToolMemory.new({maxEntries: 2})
$limitTool.memory_store({key: "a"; value: "1"})
$limitTool.memory_store({key: "b"; value: "2"})
$res:=$limitTool.memory_store({key: "c"; value: "3"})
ASSERT:C1129(Position:C15("full"; $res)>0; "Must reject when memory full: "+$res)

// But updating an existing key should still work when full
$res:=$limitTool.memory_store({key: "a"; value: "updated"})
ASSERT:C1129(Position:C15("Updated"; $res)>0; "Update must work even when full: "+$res)

// =================================================================
// 15. Search by tags
// =================================================================
$tool.memory_store({key: "todo1"; value: "Buy groceries"; category: "task"; tags: "personal,shopping"})
$tool.memory_store({key: "todo2"; value: "Deploy release"; category: "task"; tags: "work,urgent"})

$res:=$tool.memory_retrieve({query: "urgent"})
ASSERT:C1129(Position:C15("Deploy release"; $res)>0; "Tag search must find matching entry: "+Substring:C12($res; 1; 200))

// =================================================================
// 16. Persistent mode config (just verify config, no actual DB)
// =================================================================
var $dbTool:=cs.AIToolMemory.new({\
	dataclass: "AgentMemory"; \
	fields: {key: "memKey"; value: "memValue"; category: "memCat"}\
	})
ASSERT:C1129($dbTool._persistent=True; "Must be persistent when dataclass configured")
ASSERT:C1129($dbTool._dataclass="AgentMemory"; "Dataclass name must be AgentMemory")
ASSERT:C1129($dbTool._fields.key="memKey"; "Key field mapping must be memKey")
ASSERT:C1129($dbTool._fields.value="memValue"; "Value field mapping must be memValue")
ASSERT:C1129($dbTool._fields.category="memCat"; "Category field mapping must be memCat")
// Default field mappings for unmapped fields
ASSERT:C1129($dbTool._fields.tags="tags"; "Tags field must use default: tags")
ASSERT:C1129($dbTool._fields.createdAt="createdAt"; "CreatedAt field must use default: createdAt")

ALERT:C41("✅ test_memory — All assertions passed")
