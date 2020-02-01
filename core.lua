local addon, ns = ...
local cfg = ns.cfg
local E, M = unpack(yaCore);

-- Create frame for handling events
local eventCatcher = CreateFrame('Frame', addon .. 'Frame')
eventCatcher:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")

-- Variables used to prevent flooding on AoE interrupts
local lastTime, lastSpellID

-- Local names for globals used in CLEU handler
local GetSpellLink = GetSpellLink
local IsInGroup = IsInGroup
local IsInRaid = IsInRaid
local PlaySoundFile = PlaySoundFile
local UnitClass = UnitClass
local UnitCreatureFamily = UnitCreatureFamily
local UnitName = UnitName

-- Split a string into whitespace delimited parts and return them as a list
-- Note: Simple and slow, but we only use it to parse the slash commands.
local function SplitString(s)
	local t = {}
	-- Loop over matches of non-whitespace sequences in s, adding them to t
	for w in s:gmatch('%S+') do
		t[#t + 1] = w
	end
	return unpack(t)
end

-- Create possessive form by appending 's to the string, unless it ends
-- with s, x, or z, in which case only ' is added.
local function StringOwns(s)
	if s:sub(-1):find('[sxzSXZ]') then
		return s .. '\''
	else
		return s .. '\'s'
	end
end

-- Get name of player
-- Note: We cannot read the name into a local variable on load since
-- UnitName may return UNKNOWNOBJECT until the player has fully loaded.
-- We could potentially use the GUID instead.
local GetPlayerName
do
	local playerName

	function GetPlayerName()
		if not playerName then
			local a = UnitName('player')
			if a and a ~= UNKNOWNOBJECT then
				playerName = a
			end
		end
		return playerName
	end
end

-- Get spell link for a spellID
local GetSpellLinkCached
do
	local spellLinkCache = {}

	function GetSpellLinkCached(spellID)
		local a = spellLinkCache[spellID]
		if not a then
			a = GetSpellLink(spellID)
			spellLinkCache[spellID] = a
		end
		return a
	end
end

-- Announce message to self or channel based on mode
-- Note: mode has to be self, say, party, raid, or instance
function eventCatcher:AnnounceInterrupt(mode, msg, sound)
	if mode == 'self' then
		E:Print(msg)
	else
		-- If we are announcing to instance, change mode to INSTANCE_CHAT.
		if (mode == 'instance') then mode = 'INSTANCE_CHAT' end

		-- Here mode is say, party, raid, or INSTANCE_CHAT
		SendChatMessage(msg, mode:upper())
	end
	if sound ~= '' then
		PlaySoundFile(sound)
	end
end

-- The actual combat log event handler
-- Note: Naming the args was faster than select, and Lua adjusts the number
-- of arguments automatically.
function eventCatcher:COMBAT_LOG_EVENT_UNFILTERED(timeStamp, subEvent, _, _, sourceName, sourceFlags, _, _, destName, _, destRaidFlags, spellID, _, _, extraSpellID)
	-- Check if event was a spell interrupt
	if subEvent ~= 'SPELL_INTERRUPT' then return end

	-- Check if time and ID was same as last
	-- Note: This is to prevent flooding announcements on AoE interrupts.
	if timeStamp == lastTime and spellID == lastSpellID then return end

	E:Print("yupp")
	-- Update last time and ID
	lastTime, lastSpellID = timeStamp, spellID

	-- Figure out grouping status
	-- Note: Passing LE_PARTY_CATEGORY_INSTANCE to IsInGroup() and IsInRaid()
	-- appears to check if we are in a group assembled through the instance
	-- finder (LFG/LFR/BG/etc.), where the chat channel is now INSTANCE_CHAT.
	-- Passing LE_PARTY_CATEGORY_HOME checks if we are in a normal group. If
	-- you join the instance finder as a group, you will be in both the
	-- original group/raid and the instance group. Passing nothing checks for
	-- either.
	local inInstance = IsInGroup(LE_PARTY_CATEGORY_INSTANCE)
	local inGroup, inRaid = IsInGroup(), IsInRaid()

	-- Check if source was the player or player's pet
	if sourceName == GetPlayerName() then

		-- Announce interrupt
		self:AnnounceInterrupt(config.own, string.format('Interrupted %s%s %s', StringOwns(destName or '?'), GetSpellLinkCached(extraSpellID)))
	elseif bit.band(sourceFlags, COMBATLOG_OBJECT_AFFILIATION_MINE) ~= 0 then

		-- Announce interrupt
		self:AnnounceInterrupt(config.own, string.format('My %s interrupted %s%s %s', sourceName or '?', StringOwns(destName or '?'), GetSpellLinkCached(extraSpellID)))
	end
end