--!strict
--!native
--!optimize 2

--[[ Documentation
	This is a Luau Quadtree implementation for Roblox. It is used to store parts and then quickly find them based off simple calculations based around their position.
	You can use this to find parts near eachother, which is especially useful for hitboxes.
	
	Inserted objects must stay in the same position, as the Quadtree will not automatically update their positions on movement,
	if you implement some heartbeat logic it would be possible, but for now it's only intended for stationary BaseParts.
	
	This version of the modulescript was modified to run standalone; the types and CreateBounds method were originally stored in separate modules.

    Copyright 2025 FireExtravasate

    This project is licensed under the terms of the MIT License.
    For the full license text, see the LICENSE file in the root directory of this source tree:
	https://github.com/FireExtravasate/roblox/blob/main/LICENSE
]]

export type QuadtreeNode = {
	parentNode:QuadtreeNode?,
	children:{QuadtreeNode}?,
	items:{BasePart},

	bounds:Bounds2D,
	depth:number,

	VisualizeQuadtree:(self:QuadtreeNode, color:BrickColor?) -> (),
	VisualizeNode:(self:QuadtreeNode) -> BasePart,
	visualization:Part?,

	IsInBounds:(self:QuadtreeNode, pos:Vector2, size:Vector2) -> boolean,
	Remove:(self:QuadtreeNode, part:BasePart) -> (),
	Insert:(self:QuadtreeNode, part:BasePart) -> QuadtreeNode?,
	Divide:(self:QuadtreeNode) -> boolean,
	Find:(self:QuadtreeNode, part:BasePart, strict:boolean?) -> QuadtreeNode?,

	Destroy:(self:QuadtreeNode) -> (),
}

export type Bounds2D = {
	min:Vector2,
	max:Vector2,
	center:Vector2,
	size:Vector2
}

local visualizations = Instance.new("Folder")
visualizations.Name = "Quadtree Visualizations"
visualizations.Parent = workspace

local NodeClass = {}
NodeClass.MaxNodeDepth = 6
NodeClass.Visualizations = visualizations

function NodeClass.CreateQuadtree(pos:Vector2, size:Vector2, parent:QuadtreeNode?): QuadtreeNode
	-- Assert args
	do
		assert(typeof(pos) == "Vector2", "pos must be a Vector2!")
		assert(typeof(size) == "Vector2", "size must be a Vector2!")
		assert(size.X >= 0 and size.Y >= 0, "size must be fully positive!")

		assert(not parent or typeof(parent) == "table", "parent must be a QuadtreeNode!")
		assert(not parent or parent.depth + 1 <= NodeClass.MaxNodeDepth, "Can't create node, past maximum node depth.")
	end

	local quadtree = {} :: QuadtreeNode
	quadtree.parentNode = parent
	quadtree.items = {}

	quadtree.bounds = NodeClass.CreateBounds2D(pos, size)
	quadtree.depth = parent and parent.depth + 1 or 0

	-- If part fits in a sub-node it will attempt to create it or get it to return.
	local function GetOrCreateSubnode(part:BasePart): QuadtreeNode?
		-- Would the part be too big for the child quadtrees?
		local childSize = quadtree.bounds.size * 0.5
		if childSize.Magnitude <= part.Size.Magnitude then return end

		-- Create the offset
		local center = quadtree.bounds.center
		local pos = part.Position
		local offset = Vector3.new(
			pos.X > center.X and 1 or 0,
			pos.Y > center.Y and 1 or 0
		)

		-- Get the child node's index
		local index = (offset.X * 2) + offset.Y + 1
		if index > 0 and index < 5 then quadtree:Divide() else return end

		-- Return child quadtree or nil
		return quadtree.children and quadtree.children[index]
	end

	-- Returns the deepest existing sub-node the part fits in.
	local function GetSubnode(part:BasePart)
		if not quadtree.children then return end

		-- Would the part be too big for the child quadtrees?
		local childSize = quadtree.bounds.size * 0.5
		if childSize.Magnitude <= part.Size.Magnitude then return end

		-- Create the offset
		local center = quadtree.bounds.center
		local pos = part.Position
		local offset = Vector3.new(
			pos.X > center.X and 1 or 0,
			pos.Y > center.Y and 1 or 0
		)

		-- Get the child node's index and return it
		local index = (offset.X * 2) + offset.Y + 1
		return quadtree.children[index]
	end

	-- Quadtree methods
	do
		-- Visualizes self and all descendants.
		function quadtree:VisualizeQuadtree(color)
			assert(not color or typeof(color) == "BrickColor", "color must be a BrickColor!")

			local newColor = BrickColor.random()
			local color = color or BrickColor.random()

			self:VisualizeNode().BrickColor = color

			-- Recursively visualize all children
			for _, child:QuadtreeNode in ipairs(self.children or {}) do
				child:VisualizeQuadtree(newColor)
			end
		end

		-- Visualizes self.
		function quadtree:VisualizeNode()
			if self.visualization then return self.visualization end

			local pos = self.bounds.center
			local size = self.bounds.size

			-- Warning if too big
			if size.X > 2048 or size.Y > 2048 then
				warn(`The max size for a part is 2048 x 2048 x 2048, visualizing this octree of the size {self.bounds.size} will not be accurate!`)
			end

			local part = Instance.new("Part")
			part.Anchored = true
			part.CanQuery = false
			part.CanCollide = false
			part.CanTouch = false
			part.Transparency = 1 - (self.depth < 10 and self.depth * 0.05 or 0.5)
			part.BrickColor = BrickColor.random()
			part.Position = Vector3.new(pos.X, pos.Y)
			part.Size = Vector3.new(size.X, size.Y)
			part.Name = `Quadtree Depth {self.depth}`
			part.Parent = visualizations
			self.visualization = part
			return part
		end

		-- Compares min maxes to see if the pos and size fits in self.
		function quadtree:IsInBounds(pos, size)
			assert(typeof(pos) == "Vector2", "pos must be a Vector2!")
			assert(typeof(size) == "Vector2", "size must be a Vector2!")

			local min1 = self.bounds.min
			local max1 = self.bounds.max

			local half = size / 2
			local min2 = pos - half
			local max2 = pos + half

			-- Compare the min maxes to see if they overlap; to avoid edge-cases only some of them use a =< or >=
			return min1.X < max2.X and max1.X >= min2.X and min1.Y < max2.Y and max1.Y >= min2.Y
		end

		-- Destroys each sub-node, and destroys visualization.
		function quadtree:Destroy()
			for _, child:QuadtreeNode in ipairs(self.children or {}) do
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
		function quadtree:Remove(part)
			assert(typeof(part) == "Instance" and part:IsA("BasePart"), "part must be a BasePart!")

			local index = table.find(self.items, part)
			if index then table.remove(self.items, index) return end

			-- Recursive search child nodes to find it
			local node = self:Find(part, true)
			if node then node:Remove(part) end
		end

		-- Finds the lowest possible sub-node the part would fit in, adds it, and returns it.
		function quadtree:Insert(part)
			assert(typeof(part) == "Instance" and part:IsA("BasePart"), "part must be a BasePart!")

			-- Return early if found in self
			if table.find(self.items, part) then return end

			local selfSize = self.bounds.size
			local size = Vector2.new(part.Size.X, part.Size.Y)
			local pos = Vector2.new(part.Position.X, part.Position.Y)

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

		-- If quadtree.children doesn't exist it creates it with 4 sub-nodes.
		function quadtree:Divide()
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

			for i = 0, 3 do
				local newCenter = Vector2.new(
					center.X + (centerOffset.X * (bit32.band(i, 2) == 0 and -1 or 1)),
					center.Y + (centerOffset.Y * (bit32.band(i, 1) == 0 and -1 or 1))
				)

				local subnode = NodeClass.CreateQuadtree(newCenter, childSize, self)
				children[i + 1] = subnode
			end

			self.children = children

			return true
		end

		-- When strict it will only return the node if the part has been inserted. Otherwise, returns the lowest sub-node it would fit in.
		function quadtree:Find(part, strict)
			assert(typeof(part) == "Instance" and part:IsA("BasePart"), "part must be a BasePart!")
			assert(not strict or typeof(strict) == "boolean", "strict must be a boolean!")

			-- Return early if found in self
			if table.find(self.items, part) then return self end

			-- Check requirements
			local pos = Vector2.new(part.Position.X, part.Position.Y)
			local size = Vector2.new(part.Size.X, part.Size.Y)
			if not self:IsInBounds(pos, size) or self.bounds.size.Magnitude < size.Magnitude then return end

			-- Recursive search child nodes
			local child = strict and GetSubnode(part) or GetOrCreateSubnode(part)
			local result = child and child:Find(part, strict)

			-- Return result, or self depending on strict
			return result or not strict and self or nil
		end
	end

	return quadtree
end

function NodeClass.CreateBounds2D(pos:Vector2, size:Vector2): Bounds2D
	local half = size / 2

	return {
		min = pos - half,
		max = pos + half,
		center = pos,
		size = size,
	}
end


return NodeClass
