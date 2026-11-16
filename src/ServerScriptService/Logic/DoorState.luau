--!strict
--[[
	DoorState — pure house-door rules (GDD §6.4, §9 Engineer).

	Night : doors start closed with full HP. The wolf needs 5 hits (pup 10).
	        The occupant may open the door but can never close it again.
	Day   : a door broken last night shows repair marks; it is back to normal
	        the following night.
	Engineer: reinforce = full HP and double max HP. A daytime reinforcement
	        lasts through the coming night; everything resets each morning.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

export type Door = {
	HP: number,
	MaxHP: number,
	State: string, -- "Closed" | "Open" | "Broken"
	RepairLook: boolean, -- planks visible (broken last night)
	Reinforced: boolean,
}

local DoorState = {}

function DoorState.new(): Door
	return {
		HP = Config.Door.MaxHP,
		MaxHP = Config.Door.MaxHP,
		State = "Closed",
		RepairLook = false,
		Reinforced = false,
	}
end

-- Night starts: every door is shut. A daytime reinforcement is kept.
function DoorState.beginNight(door: Door)
	door.State = "Closed"
	door.RepairLook = false
	if not door.Reinforced then
		door.MaxHP = Config.Door.MaxHP
	end
	door.HP = door.MaxHP
end

-- Morning: broken doors get their repair marks, reinforcements wear off.
function DoorState.beginDay(door: Door)
	door.RepairLook = door.State == "Broken"
	door.State = "Closed"
	door.Reinforced = false
	door.MaxHP = Config.Door.MaxHP
	door.HP = door.MaxHP
end

-- Returns true when this hit broke the door. Only closed doors take damage.
function DoorState.damage(door: Door, amount: number): boolean
	if door.State ~= "Closed" then
		return false
	end
	door.HP = math.max(0, door.HP - amount)
	if door.HP == 0 then
		door.State = "Broken"
		return true
	end
	return false
end

-- Returns true if the door was closed and is now open (it stays open).
function DoorState.open(door: Door): boolean
	if door.State ~= "Closed" then
		return false
	end
	door.State = "Open"
	return true
end

-- Engineer ability. Returns false for a door that is already broken.
function DoorState.reinforce(door: Door): boolean
	if door.State == "Broken" then
		return false
	end
	door.Reinforced = true
	door.MaxHP = Config.Door.MaxHP * Config.Door.ReinforceMultiplier
	door.HP = door.MaxHP
	return true
end

-- Task "repair a broken door": removes the repair marks.
function DoorState.repair(door: Door): boolean
	if not door.RepairLook then
		return false
	end
	door.RepairLook = false
	return true
end

return DoorState
