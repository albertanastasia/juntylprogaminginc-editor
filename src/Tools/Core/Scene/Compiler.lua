local Types = require(script.Parent.Types)

type SceneConfig = {
	Name: string?,
	CompileMode: string?,
}

type AttachedSymbolsHolder = { any: () -> nil? }

type ChunkObject = {
	ObjectIdentifier: string?,
	ObjectData: { any },
	GroupData: { any },
	SavedProperties: { any },
	ObjectType: string,
	SymbolsAttached: AttachedSymbolsHolder,
}

local ALIAS_OBJECTS_NAMES = {
	Layer = "UiBase",
	Static = "UiBase",
	Dynamic = "Rigidbody",

	-- Base
	Rigidbody = "Rigidbody",
	UiBase = "UiBase",
}

local package = script.Parent.Parent.Parent.Parent
local objects = script.Parent.Objects
local components = package.Components

local Promise = require(components.Library.Promise)
local Symbols = require(script.Parent.Symbols)
local TaskDistributor = require(components.Library.TaskDistributor).new()
local Settings = require(package.Settings)

local CompilerObjects = {
	--Rigidbody = require(objects.Rigidbody),
	--UiBase = require(objects.UiBase),
	UiBase = require(objects.PUiBase),
	Rigidbody = require(objects.PRigidbody),
}

local sceneCaches = {}
local scenePointers = {}

local function IsSymbol(tableIndex: any): boolean
	if typeof(tableIndex) == "table" and tableIndex.Name ~= nil then
		return true
	end

	return false
end

local Compiler = {}

Compiler.CompilerDistributor = TaskDistributor

function Compiler.Prototype_MapSceneData(sceneData: { [number]: any }): { [number]: ChunkObject }
	local chunkObjects = {}
	local savedProperties = {}
	local objectType = nil

	local function ProcessAndMerge(object, group, saved, type): { [number]: Types.Prototype_ChunkObject }
		local objectData = {
			Properties = {},
			Symbols = {},
			ObjectType = type,
		}

		local function Process(propertyTable: { [string]: any })
			if propertyTable then
				for propertyName, value in pairs(propertyTable) do
					if IsSymbol(propertyName) then
						objectData.Symbols[propertyName] = value

						continue
					end

					objectData.Properties[propertyName] = value
				end
			end
		end

		-- Order is very important
		-- This order prioritises object's properties more than the ones declared in either the saved or the group properties
		Process(saved)
		Process(select(2, Symbols.FindSymbol(group, "Property")))
		Process(object)

		if objectData.Properties.Class == nil then
			objectData.Properties.Class = "Frame"
		end

		return objectData
	end

	for _, sceneCategory in pairs(sceneData) do
		if typeof(sceneCategory) ~= "table" then
			continue
		end

		-- Check if we can find a table with a [property] symbol attached
		-- As well as find the type of the category
		savedProperties = select(2, Symbols.FindSymbol(sceneCategory, "Property"))
		objectType = select(2, Symbols.FindSymbol(sceneCategory, "Type"))

		for groupKey, groupData in pairs(sceneCategory) do
			if IsSymbol(groupKey) then
				continue
			end

			for objectKey, objectData in pairs(groupData) do
				if IsSymbol(objectKey) then
					continue
				end

				table.insert(chunkObjects, ProcessAndMerge(objectData, groupData, savedProperties, objectType))
			end
		end
	end

	return chunkObjects
end

function Compiler.CacheScene(sceneData: { [string]: any })
	local sceneChunk =
		TaskDistributor.GenerateChunk(Compiler.Prototype_MapSceneData(sceneData), Settings.CompilerChunkSize)

	local reservedId = #sceneCaches + 1
	sceneCaches[reservedId] = sceneChunk
	scenePointers[sceneData.Name] = reservedId

	return sceneChunk
end

-- Used to get a scene's data
-- If it does not exist, it gets cached for later to skip
-- having to iterate all over the data again
function Compiler.GetScene(sceneData: { [string]: any })
	if scenePointers[sceneData.Name] == nil then
		return Compiler.CacheScene(sceneData)
	end

	return sceneCaches[scenePointers[sceneData.Name]]
end

-- TODO: Add function to compile an object by itself
function Compiler.Prototype_Compile(sceneData: { [string]: any }): { [number]: Instance }
	local compiledObjects = {}

	-- Simplified the data
	return Promise.new(function(resolve)
		TaskDistributor:Distribute(Compiler.GetScene(sceneData), function(object: Types.Prototype_ChunkObject)
			table.insert(compiledObjects, {
				Symbols = object.Symbols,
				Object = CompilerObjects[ALIAS_OBJECTS_NAMES[object.ObjectType]](object),
			})
		end):await()

		resolve(compiledObjects)
	end):catch(warn)
end

return Compiler
