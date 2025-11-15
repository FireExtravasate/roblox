--!strict
--!native
--!optimize 2

--[[ Documentation
	This is a Luau Octree implementation for Roblox. It is used to store parts and then quickly find them based off simple calculations based around their position.
	You can use this to find parts near eachother, which is especially useful for hitboxes.
	
	Inserted objects must stay in the same position, as the Octree will not automatically update their positions on movement,
	if you implement some heartbeat logic it would be possible, but for now it's only intended for stationary BaseParts.
	
	This version of the modulescript was modified to run standalone; the types and CreateBounds method were originally stored in separate modules.

    Copyright 2025 FireExtravasate

    This project is licensed under the terms of the MIT License.
    For the full license text, see the LICENSE file in the root directory of this source tree:
	https://github.com/FireExtravasate/roblox/blob/main/LICENSE
]]

export type OctreeNode = {
	parentNode:OctreeNode?,
	children:{OctreeNode}?,
	items:{BasePart},

	bounds:Bounds,
	depth:number,

	VisualizeOctree:(self:OctreeNode, color:BrickColor?) -> (),
	VisualizeNode:(self:OctreeNode) -> BasePart,
	visualization:Part?,

	IsInBounds:(self:OctreeNode, pos:Vector3, size:Vector3) -> boolean,
	Remove:(self:OctreeNode, part:BasePart) -> (),
	Insert:(self:OctreeNode, part:BasePart) -> OctreeNode?,
	Divide:(self:OctreeNode) -> boolean,
	Find:(self:OctreeNode, part:BasePart, strict:boolean?) -> OctreeNode?,

	Destroy:(self:OctreeNode) -> (),
}

export type Bounds = {
	min:Vector3,
	max:Vector3,
	center:Vector3,
	size:Vector3
}

local visualizations = Instance.new("Folder")
visualizations.Name = "Octree Visualizations"
visualizations.Parent = workspace

local NodeClass = {}
NodeClass.MaxNodeDepth = 6
NodeClass.Visualizations = visualizations

function NodeClass.CreateOctree(pos:Vector3, size:Vector3, parent:OctreeNode?): OctreeNode
	-- Assert args
	do
		assert(typeof(pos) == "Vector3", "pos must be a Vector3!")
		assert(typeof(size) == "Vector3", "size must be a Vector3!")
		assert(size.X >= 0 and size.Y >= 0 and size.Z >= 0, "size must be fully positive!")

		assert(not parent or typeof(parent) == "table", "parent must be a OctreeNode!")
		assert(not parent or parent.depth + 1 <= NodeClass.MaxNodeDepth, "Can't create node, past maximum node depth.")
	end

	local octree = {} :: OctreeNode
	octree.parentNode = parent
	octree.items = {}

	octree.bounds = NodeClass.CreateBounds(pos, size)
	octree.depth = parent and parent.depth + 1 or 0

	-- If part fits in a sub-node it will attempt to create it or get it to return.
	local function GetOrCreateSubnode(part:BasePart): OctreeNode?
		-- Would the part be too big for the child octrees?
		local childSize = octree.bounds.size * 0.5
		if childSize.Magnitude <= part.Size.Magnitude then return end

		-- Create the offset
		local center = octree.bounds.center
		local pos = part.Position
		local offset = Vector3.new(
			pos.X > center.X and 1 or 0,
			pos.Y > center.Y and 1 or 0,
			pos.Z > center.Z and 1 or 0
		)

		-- Get the child node's index
		local index = (offset.X * 4) + (offset.Y * 2) + offset.Z + 1
		if index > 0 and index < 9 then octree:Divide() else return end

		-- Return child octree or nil
		return octree.children and octree.children[index]
	end

	-- Returns the deepest existing sub-node the part fits in.
	local function GetSubnode(part:BasePart)
		if not octree.children then return end

		-- Would the part be too big for the child octrees?
		local childSize = octree.bounds.size * 0.5
		if childSize.Magnitude <= part.Size.Magnitude then return end

		-- Create the offset
		local center = octree.bounds.center
		local pos = part.Position
		local offset = Vector3.new(
			pos.X > center.X and 1 or 0,
			pos.Y > center.Y and 1 or 0,
			pos.Z > center.Z and 1 or 0
		)

		-- Get the child node's index and return it
		local index = (offset.X * 4) + (offset.Y * 2) + offset.Z + 1
		return octree.children[index]
	end

	-- Octree methods
	do
		-- Visualizes self and all descendants.
		function octree:VisualizeOctree(color)
			assert(not color or typeof(color) == "BrickColor", "color must be a BrickColor!")

			local newColor = BrickColor.random()
			local color = color or BrickColor.random()

			self:VisualizeNode().BrickColor = color

			for _, child:OctreeNode in ipairs(self.children or {}) do
				child:VisualizeOctree(newColor)
			end
		end

		-- Visualizes self.
		function octree:VisualizeNode()
			if self.visualization then return self.visualization end

			local size = self.bounds.size
			if size.X > 2048 or size.Y > 2048 or size.Z > 2048 then
				warn(`The max size for a part is 2048 x 2048 x 2048, visualizing this octree of the size {self.bounds.size} will not be accurate!`)
			end

			local part = Instance.new("Part")
			part.Anchored = true
			part.CanQuery = false
			part.CanCollide = false
			part.CanTouch = false
			part.Transparency =  1 - (self.depth < 10 and self.depth * 0.05 or 0.5)
			part.BrickColor = BrickColor.random()
			part.Position = self.bounds.center
			part.Size = self.bounds.size
			part.Name = `Octree Depth {self.depth}`
			part.Parent = visualizations
			self.visualization = part
			return part
		end

		-- Compares min maxes to see if the pos and size fits in self.
		function octree:IsInBounds(pos, size)
			assert(typeof(pos) == "Vector3", "pos must be a Vector3!")
			assert(typeof(size) == "Vector3", "size must be a Vector3!")

			local min1 = self.bounds.min
			local max1 = self.bounds.max

			local half = size / 2
			local min2 = pos - half
			local max2 = pos + half

			-- Compare the min maxes to see if they overlap; to avoid edge-cases only some of them use a =< or >=
			return min1.X < max2.X and max1.X >= min2.X and min1.Y < max2.Y and max1.Y >= min2.Y and min1.Z < max2.Z and max1.Z >= min2.Z
		end

		-- Destroys each sub-node, and removes self from parent.
		function octree:Destroy()
			for _, child:OctreeNode in ipairs(self.children or {}) do
				child:Destroy()
			end

			local visualization = self.visualization
			if visualization then visualization:Destroy() end

			self.visualization = nil
			self.parentNode = nil
			self.children = nil
			self.items = {}
		end

		-- Runs self:Find() using strict to remove the part from any child node.
		function octree:Remove(part)
			assert(typeof(part) == "Instance" and part:IsA("BasePart"), "part must be a BasePart!")

			local index = table.find(self.items, part)
			if index then table.remove(self.items, index) return end
			
			-- Recursive search child nodes to find it
			local node = self:Find(part, true)
			if node then node:Remove(part) end
		end

		-- Finds the lowest possible sub-node the part would fit in, adds it, and returns it.
		function octree:Insert(part)
			assert(typeof(part) == "Instance" and part:IsA("BasePart"), "part must be a BasePart!")

			-- Return early if found in self
			if table.find(self.items, part) then return end

			local selfSize = self.bounds.size
			local size = part.Size
			local pos = part.Position

			-- Check requirements
			if not self:IsInBounds(pos, size) or selfSize.X < size.X or selfSize.Y < size.Y then return end

			-- Recursive search
			local child = GetOrCreateSubnode(part)
			local result = child and child:Insert(part)
			if result then return result end

			-- Add to this node if it failed
			table.insert(self.items, part)
			return self
		end

		-- If octree.children doesn't exist it creates it with 8 sub-nodes.
		function octree:Divide()
			-- Check requirements
			do
				if self.children then return false end
				if self.depth+1 > NodeClass.MaxNodeDepth then return false end
			end

			-- Get info to create children
			local centerOffset = self.bounds.size * 0.25
			local childSize = self.bounds.size * 0.5
			local center = self.bounds.center

			local children = {}	

			for i = 0, 7 do
				local newCenter = Vector3.new(
					center.X + (centerOffset.X * (bit32.band(i, 4) == 0 and -1 or 1)),
					center.Y + (centerOffset.Y * (bit32.band(i, 2) == 0 and -1 or 1)),
					center.Z + (centerOffset.Z * (bit32.band(i, 1) == 0 and -1 or 1))
				)

				local subnode = NodeClass.CreateOctree(newCenter, childSize, self)
				children[i + 1] = subnode
			end

			self.children = children

			return true
		end

		-- When strict it will only return the node if the part has been inserted. Otherwise, returns the lowest sub-node it would fit in.
		function octree:Find(part, strict)
			assert(typeof(part) == "Instance" and part:IsA("BasePart"), "part must be a BasePart!")
			assert(not strict or typeof(strict) == "boolean", "strict must be a boolean!")

			-- Return early if found in self
			if table.find(self.items, part) then return self end

			-- Check requirements
			local size = part.Size
			if not self:IsInBounds(part.Position, size) or self.bounds.size.Magnitude < size.Magnitude then return end

			-- Recursive search child nodes
			local child = strict and GetSubnode(part) or GetOrCreateSubnode(part)
			local result = child and child:Find(part, strict)

			-- Return result, or self depending on strict
			return result or not strict and self or nil
		end
	end

	return octree
end

function NodeClass.CreateBounds(pos:Vector3, size:Vector3): Bounds
	local half = size / 2

	return {
		min = pos - half,
		max = pos + half,
		center = pos,
		size = size,
	}
end


return NodeClass
