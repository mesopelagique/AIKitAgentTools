// AIToolFileSystem — File and folder operations using 4D.File / 4D.Folder
//
// Security: path sandboxing via allowedPaths/deniedPaths, optional readOnly mode
//
// Usage:
//   var $tool:=cs.AIToolFileSystem.new({allowedPaths: ["/Users/me/project/"]; readOnly: True})
//   $helper.registerTools($tool)

property tools : Collection
property allowedPaths : Collection
property deniedPaths : Collection
property readOnly : Boolean
property maxFileSize : Integer

Class constructor($config : Object)
	
	If ($config=Null)
		$config:={}
	End if 
	
	// --- Configuration ---
	This.allowedPaths:=($config.allowedPaths#Null) ? $config.allowedPaths : New collection()  // empty = ⚠️ all paths (dangerous)
	This.deniedPaths:=($config.deniedPaths#Null) ? $config.deniedPaths : New collection("*.env"; "*.pem"; "*.key"; "*.secret"; "*/.git/*"; "*/node_modules/*")
	This.readOnly:=Bool($config.readOnly)
	This.maxFileSize:=($config.maxFileSize#Null) ? $config.maxFileSize : 500000  // 500KB default
	
	// --- Tool definitions ---
	This.tools:=[]
	
	This.tools.push({\
		name: "list_directory"; \
		description: "List all files and subdirectories in a directory. Returns entries prefixed with [DIR] or [FILE]."; \
		parameters: {\
		type: "object"; \
		properties: {\
		path: {type: "string"; description: "Absolute path of the directory to list"}\
		}; \
		required: ["path"]; \
		additionalProperties: False\
		}\
		})
	
	This.tools.push({\
		name: "read_file"; \
		description: "Read the text content of a file."; \
		parameters: {\
		type: "object"; \
		properties: {\
		file_path: {type: "string"; description: "Absolute path of the file to read"}\
		}; \
		required: ["file_path"]; \
		additionalProperties: False\
		}\
		})
	
	If (Not(This.readOnly))
		
		This.tools.push({\
			name: "write_file"; \
			description: "Write text content to a file. Creates the file if it does not exist, overwrites if it does."; \
			parameters: {\
			type: "object"; \
			properties: {\
			file_path: {type: "string"; description: "Absolute path of the file to write"}; \
			content: {type: "string"; description: "The text content to write"}\
			}; \
			required: ["file_path"; "content"]; \
			additionalProperties: False\
			}\
			})
		
		This.tools.push({\
			name: "create_directory"; \
			description: "Create a new directory (including parent directories if needed)."; \
			parameters: {\
			type: "object"; \
			properties: {\
			path: {type: "string"; description: "Absolute path of the directory to create"}\
			}; \
			required: ["path"]; \
			additionalProperties: False\
			}\
			})
		
		This.tools.push({\
			name: "delete_file"; \
			description: "Delete a file permanently."; \
			parameters: {\
			type: "object"; \
			properties: {\
			file_path: {type: "string"; description: "Absolute path of the file to delete"}\
			}; \
			required: ["file_path"]; \
			additionalProperties: False\
			}\
			})
		
		This.tools.push({\
			name: "move_item"; \
			description: "Move or rename a file or folder."; \
			parameters: {\
			type: "object"; \
			properties: {\
			source_path: {type: "string"; description: "Current path of the file or folder"}; \
			destination_path: {type: "string"; description: "New path for the file or folder"}\
			}; \
			required: ["source_path"; "destination_path"]; \
			additionalProperties: False\
			}\
			})
		
		This.tools.push({\
			name: "copy_file"; \
			description: "Copy a file to a new location."; \
			parameters: {\
			type: "object"; \
			properties: {\
			source_path: {type: "string"; description: "Path of the file to copy"}; \
			destination_path: {type: "string"; description: "Destination path for the copy"}\
			}; \
			required: ["source_path"; "destination_path"]; \
			additionalProperties: False\
			}\
			})
		
	End if 
	
	// -----------------------------------------------------------------
	// MARK:- Tool handlers
	// -----------------------------------------------------------------
	
Function list_directory($params : Object) : Text
	var $path : Text:=String($params.path)
	
	If (Not(This._isPathAllowed($path)))
		return "Error: Path '"+$path+"' is outside the allowed scope."
	End if 
	
	var $folder:=Folder($path; fk posix path)
	If (Not($folder.exists))
		return "Error: Directory '"+$path+"' does not exist."
	End if 
	
	Try
		var $entries : Collection:=New collection()
		var $subfolder : Object
		For each ($subfolder; $folder.folders())
			var $subPath : Text:=$subfolder.path
			If (This._isPathAllowed($subPath))
				$entries.push("[DIR] "+$subfolder.name)
			End if 
		End for each 
		
		var $file : Object
		For each ($file; $folder.files())
			var $filePath : Text:=$file.path
			If (This._isPathAllowed($filePath))
				$entries.push("[FILE] "+$file.name)
			End if 
		End for each 
		
		If ($entries.length=0)
			return "The directory '"+$path+"' is empty (or all entries are filtered out)."
		End if 
		
		return $entries.join("\n")
		
	Catch
		return "Error listing directory: "+Last errors.last().message
	End try
	
Function read_file($params : Object) : Text
	var $path : Text:=String($params.file_path)
	
	If (Not(This._isPathAllowed($path)))
		return "Error: Path '"+$path+"' is outside the allowed scope."
	End if 
	
	var $file:=File($path; fk posix path)
	If (Not($file.exists))
		return "Error: File '"+$path+"' not found."
	End if 
	
	// --- Size check ---
	If ($file.size>This.maxFileSize)
		return "Error: File size ("+String($file.size)+" bytes) exceeds the maximum allowed ("+String(This.maxFileSize)+" bytes)."
	End if 
	
	Try
		var $content : Text:=$file.getText()
		return $content
	Catch
		return "Error reading file: "+Last errors.last().message
	End try
	
Function write_file($params : Object) : Text
	If (This.readOnly)
		return "Error: File system is in read-only mode."
	End if 
	
	var $path : Text:=String($params.file_path)
	var $content : Text:=String($params.content)
	
	If (Not(This._isPathAllowed($path)))
		return "Error: Path '"+$path+"' is outside the allowed scope."
	End if 
	
	Try
		var $file:=File($path; fk posix path)
		$file.setText($content)
		return "Successfully wrote to file '"+$path+"'."
	Catch
		return "Error writing file: "+Last errors.last().message
	End try
	
Function create_directory($params : Object) : Text
	If (This.readOnly)
		return "Error: File system is in read-only mode."
	End if 
	
	var $path : Text:=String($params.path)
	
	If (Not(This._isPathAllowed($path)))
		return "Error: Path '"+$path+"' is outside the allowed scope."
	End if 
	
	Try
		var $folder:=Folder($path; fk posix path)
		If (Not($folder.exists))
			$folder.create()
		End if 
		return "Successfully created directory '"+$path+"'."
	Catch
		return "Error creating directory: "+Last errors.last().message
	End try
	
Function delete_file($params : Object) : Text
	If (This.readOnly)
		return "Error: File system is in read-only mode."
	End if 
	
	var $path : Text:=String($params.file_path)
	
	If (Not(This._isPathAllowed($path)))
		return "Error: Path '"+$path+"' is outside the allowed scope."
	End if 
	
	var $file:=File($path; fk posix path)
	If (Not($file.exists))
		return "Error: File '"+$path+"' not found."
	End if 
	
	Try
		$file.delete()
		return "Successfully deleted file '"+$path+"'."
	Catch
		return "Error deleting file: "+Last errors.last().message
	End try
	
Function move_item($params : Object) : Text
	If (This.readOnly)
		return "Error: File system is in read-only mode."
	End if 
	
	var $source : Text:=String($params.source_path)
	var $destination : Text:=String($params.destination_path)
	
	If (Not(This._isPathAllowed($source)))
		return "Error: Source path '"+$source+"' is outside the allowed scope."
	End if 
	If (Not(This._isPathAllowed($destination)))
		return "Error: Destination path '"+$destination+"' is outside the allowed scope."
	End if 
	
	Try
		// Try as file first, then as folder
		var $file:=File($source; fk posix path)
		If ($file.exists)
			var $destFolder:=Folder(File($destination; fk posix path).parent.platformPath; fk platform path)
			$file.moveTo($destFolder; File($destination; fk posix path).name)
			return "Successfully moved '"+$source+"' to '"+$destination+"'."
		End if 
		
		var $folder:=Folder($source; fk posix path)
		If ($folder.exists)
			var $destParent:=Folder($destination; fk posix path).parent
			$folder.moveTo($destParent; Folder($destination; fk posix path).name)
			return "Successfully moved '"+$source+"' to '"+$destination+"'."
		End if 
		
		return "Error: Source '"+$source+"' not found."
	Catch
		return "Error moving item: "+Last errors.last().message
	End try
	
Function copy_file($params : Object) : Text
	If (This.readOnly)
		return "Error: File system is in read-only mode."
	End if 
	
	var $source : Text:=String($params.source_path)
	var $destination : Text:=String($params.destination_path)
	
	If (Not(This._isPathAllowed($source)))
		return "Error: Source path '"+$source+"' is outside the allowed scope."
	End if 
	If (Not(This._isPathAllowed($destination)))
		return "Error: Destination path '"+$destination+"' is outside the allowed scope."
	End if 
	
	var $file:=File($source; fk posix path)
	If (Not($file.exists))
		return "Error: Source file '"+$source+"' not found."
	End if 
	
	Try
		var $destFolder:=Folder(File($destination; fk posix path).parent.platformPath; fk platform path)
		$file.copyTo($destFolder; File($destination; fk posix path).name; fk overwrite)
		return "Successfully copied '"+$source+"' to '"+$destination+"'."
	Catch
		return "Error copying file: "+Last errors.last().message
	End try
	
	// -----------------------------------------------------------------
	// MARK:- Internal helpers
	// -----------------------------------------------------------------
	
Function _isPathAllowed($path : Text) : Boolean
	If (Length($path)=0)
		return False
	End if 
	
	// Resolve to absolute path and normalize
	var $normalized : Text:=$path
	
	// Block path traversal attempts
	If (Position(".."; $normalized)>0)
		return False
	End if 
	
	// Check denied patterns first (always applied)
	var $denied : Text
	For each ($denied; This.deniedPaths)
		If ($normalized=($denied))  // 4D @ pattern
			return False
		End if 
	End for each 
	
	// If no allowed paths configured, allow everything (not recommended)
	If (This.allowedPaths.length=0)
		return True
	End if 
	
	// Check if path starts with any allowed path
	var $allowed : Text
	For each ($allowed; This.allowedPaths)
		If ($normalized=($allowed+"@"))
			return True
		End if 
	End for each 
	
	return False
	