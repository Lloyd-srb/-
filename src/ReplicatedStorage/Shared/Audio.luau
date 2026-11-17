--!strict
--[[
	Audio — client-side sound playback for both places (GDD §6.5).

	Sounds are named by their key in Config.Sounds. An ID of 0 means the owner
	has not picked that sound yet: nothing plays and nothing is created, so
	the game works silently until the IDs arrive (OWNER_TODO section 2).

	  Audio.play(key)          a 2D sound (UI, jingles, announcements)
	  Audio.play(key, at)      a 3D sound at a world position; it fades out
	                           over Config.Audio.Radius[key] studs
	  Audio.loop(key, on)      music / ambience that repeats until turned off
	  Audio.hookButtons(gui)   every button under `gui` clicks
]]

local SoundService = game:GetService("SoundService")

local Config = require(script.Parent.Config)

local CLEANUP_SECONDS = 30 -- a sound that never reports "Ended" is removed after this

local Audio = {}

local loops: { [string]: Sound } = {}
local hooked: { [Instance]: boolean } = {}

-- A Sound for `key`, or nil while its ID is not set.
function Audio.make(key: string): Sound?
	local id = (Config.Sounds :: any)[key]
	if type(id) ~= "number" or id == 0 then
		return nil
	end
	local sound = Instance.new("Sound")
	sound.Name = key
	sound.SoundId = "rbxassetid://" .. tostring(id)
	sound.Volume = Config.Audio.Volume[key] or Config.Audio.DefaultVolume
	return sound
end

local function cleanUp(sound: Sound, holder: Instance)
	sound.Ended:Connect(function()
		holder:Destroy()
	end)
	task.delay(CLEANUP_SECONDS, function()
		if holder.Parent then
			holder:Destroy()
		end
	end)
end

function Audio.play(key: string, at: Vector3?)
	local sound = Audio.make(key)
	if not sound then
		return
	end
	if at then
		-- An attachment in Terrain = a point in the world the sound comes from.
		local holder = Instance.new("Attachment")
		holder.Name = "Sound_" .. key
		holder.Position = at
		sound.RollOffMode = Enum.RollOffMode.InverseTapered
		sound.RollOffMaxDistance = Config.Audio.Radius[key] or Config.Audio.DefaultRadius
		sound.Parent = holder
		holder.Parent = workspace.Terrain
		cleanUp(sound, holder)
	else
		sound.Parent = SoundService
		cleanUp(sound, sound)
	end
	sound:Play()
end

function Audio.loop(key: string, on: boolean)
	local current = loops[key]
	if on and not current then
		local sound = Audio.make(key)
		if sound then
			sound.Looped = true
			sound.Parent = SoundService
			sound:Play()
			loops[key] = sound
		end
	elseif not on and current then
		loops[key] = nil
		current:Destroy()
	end
end

-- Every GuiButton under `root` (now and later) plays the click sound.
function Audio.hookButtons(root: Instance)
	local function hook(instance: Instance)
		if instance:IsA("GuiButton") and not hooked[instance] then
			hooked[instance] = true
			instance.Activated:Connect(function()
				Audio.play("UIClick")
			end)
			instance.Destroying:Connect(function()
				hooked[instance] = nil
			end)
		end
	end
	root.DescendantAdded:Connect(hook)
	for _, instance in root:GetDescendants() do
		hook(instance)
	end
end

return Audio
