StatPaths = {
    "Public/DevouringAndDigesting/Stats/Generated/Data/Armor.txt",
    "Public/DevouringAndDigesting/Stats/Generated/Data/Potions.txt",
    "Public/DevouringAndDigesting/Stats/Generated/Data/Spell_Vore.txt",
    "Public/DevouringAndDigesting/Stats/Generated/Data/Items.txt",
}

Ext.Require("Utils/Utils.lua")
Ext.Require("Utils/VoreUtils.lua")
Ext.Require("Utils/Config.lua")

PersistentVars = {}

calculateRest = true

---Triggers on spell cast.
---@param caster CHARACTER
---@param spell string
---@param spellType string?
---@param spellElement string? Like fire, lightning, etc I think.
---@param storyActionID integer?
function SP_SpellCast(caster, spell, spellType, spellElement, storyActionID)
    -- Format of Regurgitate spells will always be 'SP_Regurgitate_' (which is 15 characters)
    -- followed by either the GUIDSTRING of the prey, or 'All.' Probably possible to add some sort
    -- of extra data to the custom spell, but this is way easier.
    if string.sub(spell, 0, 15) == 'SP_Regurgitate_' then
        -- grabs the GUIDSTRING of the prey, or the string 'All' if we're regurgitating everything
        local prey = string.sub(spell, 16)
        SP_RegurgitatePrey(caster, prey, spell)
        PersistentVars['PredPreyTable'] = SP_Deepcopy(PredPreyTable)
        PersistentVars['PreyPredPairs'] = SP_Deepcopy(PreyPredPairs)
    elseif string.sub(spell,0,10) == 'SP_Absorb_' then 
		local prey = string.sub(spell, 11) -- grabs the guid of the prey, or the string 'All' if we're regurgitating everything
        SP_RegurgitatePrey(caster, prey, 1, 'Absorb')
    elseif string.sub(spell,0,12) == 'SP_Disposal_' then 
		local prey = string.sub(spell, 13) -- grabs the guid of the prey, or the string 'All' if we're regurgitating everything
        SP_RegurgitatePrey(caster, prey, 1, spell)
    elseif ConfigVars.PerformanceMode.value and spell == "SP_Move_Prey_To_Me" then
        SP_TelePreyToPred(caster)
    end
end

---Triggers when a spell is cast with a target.
---@param caster CHARACTER
---@param target CHARACTER
---@param spell string
---@param spellType string?
---@param spellElement string? Like fire, lightning, etc I think.
---@param storyActionID integer?
function SP_OnSpellCastTarget(caster, target, spell, spellType, spellElement, storyActionID)
    if string.find(spell, "Vore") ~= nil and Osi.HasActiveStatus(target, "SP_Inedible") == 0 then
        if spell == 'SP_Target_Vore_Endo' then
            _P('Endo Vore attempt by ' .. caster .. ' on ' .. target)
            if SP_CanFitPrey(caster, target) then
                SP_DelayCallTicks(5, function() 
                    SP_SwallowPrey(caster, target, 'SP_Swallowed_Endo', true)
                    SP_DelayCallTicks(5, function() SP_UpdateWeight(caster) end)
                end)
            end
        end
        if spell == 'SP_Target_Vore_Lethal' then
            _P('Lethal Vore attempt by ' .. caster .. ' on ' .. target)
            if SP_CanFitPrey(caster, target) then
                SP_DelayCallTicks(5, function() SP_VoreCheck(caster, target, "SwallowLethalCheck") end)
            end
        end
    end
end

---Triggers whenever there's a skill check.
---@param eventName string Name of event passed from the func that called the roll.
---@param roller CHARACTER Roller.
---@param rollSubject CHARACTER Character they rolled against.
---@param resultType integer Result of roll. 0 == fail, 1 == success.
---@param isActiveRoll integer? Whether or not the rolling GUI popped up. 0 == no, 1 == yes.
---@param criticality CRITICALITYTYPE? Whether or not it was a crit and what kind. 0 == no crit, 1 == crit success, 2 == crit fail.
function SP_RollResults(eventName, roller, rollSubject, resultType, isActiveRoll, criticality)
    if eventName == "SwallowLethalCheck" and (resultType ~= 0 or ConfigVars.VoreSuccessChance.value == "debug") then
        _P('Lethal Swallow Success by ' .. roller .. ' on ' .. rollSubject)
        SP_SwallowPrey(roller, rollSubject, "SP_Swallowed_Lethal", true)
        SP_DelayCallTicks(5, function() SP_UpdateWeight(roller) end)
    end
    if eventName == "StruggleCheck" and (resultType ~= 0 or ConfigVars.VoreSuccessChance.value == "debug") then
        _P('Struggle Success by ' .. roller .. ' against ' .. rollSubject)
		SP_RegurgitatePrey(rollSubject, roller, 0, "") -- now only the prey who struggled out will escape
    end
end

---Runs on session load.
function SP_OnSessionLoaded()
    -- Persistent variables are only available after SessionLoaded is triggered!
    _P("Devouring and Digesting - v0.2.0")
    SP_GetConfigFromFile()
    if PersistentVars['PredPreyTable'] ~= nil then
        PredPreyTable = SP_Deepcopy(PersistentVars['PredPreyTable'])
    else
        PersistentVars['PredPreyTable'] = {}
    end
    if PersistentVars['PreyPredPairs'] ~= nil then

        PreyPredPairs = SP_Deepcopy(PersistentVars['PreyPredPairs'])
    else
        PersistentVars['PreyPredPairs'] = {}
    end
    -- tables to store prey weight, since it can change while in stomach for some reason
	-- fake table is for their pre-digestion weight
	if PersistentVars['PreyWeightTable'] == nil then
		PersistentVars['PreyWeightTable'] = {}
	end
	if PersistentVars['FakePreyWeightTable'] == nil then
		PersistentVars['FakePreyWeightTable'] = {}
	end
	-- if death throw passive should be restored
	if PersistentVars['DisableDownedPreyTable'] == nil then
		PersistentVars['DisableDownedPreyTable'] = {}
	end
    -- Lets you config during runtime
    Ext.RegisterConsoleCommand('VoreConfig', SP_Config);
    Ext.RegisterConsoleCommand('VoreConfigOptions', SP_ConfigOptions);
end

--Runs when reset command is sent to console.
function SP_On_reset_completed()
    for _, statPath in ipairs(StatPaths) do
        _P(statPath)
        Ext.Stats.LoadStatsFile(statPath, 1)
    end
    _P('Reloading stats!')
end

---Runs each turn in combat.
---@param character CHARACTER
function SP_OnTurn(character)
    _P("Turn Changed")
    for k, _ in pairs(PredPreyTable) do
        SP_TelePreyToPred(k)
    end
end

---Runs whenever you change game regions.
---@param levelName string? Name of new game region.
---@param isEditorMode integer?
function SP_OnLevelChange(levelName, isEditorMode)
    -- for some reason this triggers when you load game from main menu, tried changing to what event it's subscribed
	_P('LEVEL CHANGE')
	_D(level)
	_P('Level changed to ' .. level)

    for k, v in pairs(PreyTablePred) do
        SP_RegurgitatePrey(v, k, 2, "")
    end
	PreyTablePred = {}
	PersistentVars['PreyTablePred'] = {}
	PersistentVars['PreyWeightTable'] = {}
	PersistentVars['FakePreyWeightTable'] = {}
	PersistentVars['DisableDownedPreyTable'] = {}
end
end

---Runs each time a status is applied.
---@param object CHARACTER Recipient of status.
---@param status string Internal name of status.
---@param cause GUIDSTRING? Thing that caused status to be applied.
---@param storyActionID integer?
function SP_OnStatusApplied(object, status, cause, storyActionID)
    if status == 'SP_Digesting' then
        for _, v in ipairs(SP_GetAllPrey(object)) do
			local alive = (Osi.IsDead(v) == 0)
			if alive then
                if !ConfigVars.PerformanceMode.value then
				    Osi.TeleportTo(v, object, "", 0, 0, 0, 0, 0)
                end
				if Osi.HasActiveStatus(v, 'SP_Swallowed_Lethal') == 1 then
					SP_VoreCheck(object, v, "StruggleCheck")
				end
			end
        end 
    elseif status == 'SP_Inedible' then
        Osi.RemoveStatus(object, 'SP_Inedible', nil)

    elseif status == 'SP_PotionOfGluttony_Status' then
        Osi.RemoveStatus(object, 'SP_PotionOfGluttony_Status', nil)

    elseif status == 'SP_Item_Bound' then
        _P("Applied " .. status .. " Status to " .. object)
    end

end

---Runs when someone dies.
---@param character CHARACTER
function SP_OnDeath(character)
	 -- if character was prey
     if PreyTablePred[character] ~= nil then
        local pred = PreyTablePred[character]
		_P(character .. " was digested by " .. pred .. " and DIED")
		SP_RegurgitatePrey(character, 'All', 2, "")
		Osi.RemoveStatus(character, 'SP_Swallowed_Endo', pred)
		Osi.RemoveStatus(character, 'SP_Swallowed_Lethal', pred)
		Osi.ApplyStatus(character, 'SP_Swallowed_Dead', -1, 1, pred)
		-- temp characters' corpses are not saved is save file, so they might cause issues unless disposed of on death
		if Ext.Entity.Get(character).ServerCharacter.Temporary == true then
			_P("Absorbing temp character")
			SP_RegurgitatePrey(pred, character, 2, "Absorb")
		else
			-- digested but not released prey will be stored out of bounds
			Osi.TeleportToPosition(character, -100000, 0, -100000, "", 0, 0, 0, 1, 0)
		end
		
    end
	-- if character was pred, free their prey
	if Osi.HasActiveStatus(character, "SP_Stuffed") ~= 0 then
		SP_RegurgitatePrey(character, 'All', 2, "")
	end
end

---runs whenever item is added
---@param objectTemplate ROOT
---@param object2 GUIDSTRING
---@param inventoryHolder GUIDSTRING
---@param addType string
function SP_OnItemAdded(objectTemplate, object2, inventoryHolder, addType)
	if objectTemplate == 'SP_Prey_Weight_f80c2fd2-5222-44aa-a68e-b2faa808171b' then -- binds weight
		Osi.ApplyStatus(object2, 'SP_Item_Bound', -1)
	elseif objectTemplate == 'SP_Prey_Weight_Fixer_8d3b74d4-0fe6-465f-9e96-36b416f4ea6f' then
		Osi.TemplateRemoveFrom('8d3b74d4-0fe6-465f-9e96-36b416f4ea6f', inventoryHolder, 9999)
	end
end

---fires once per short rest
---@param character CHARACTER
function SP_OnShortRest(character)
	-- this is necessary to avoid multiple calls of this function (for each party member)
	if calculateRest == false then
		return
	end
	calculateRest = false
	
	_P('SP_OnShortRest')
	
	for k, v in pairs(PersistentVars['PreyWeightTable']) do
		if Osi.IsDead(k) == 1 then
			-- local preyWeightDiff = PersistentVars['FakePreyWeightTable'][k] // 5
			local preyWeightDiff = 20
			-- prey's weight after digestion should not be smaller then 1/5th of their original (fake) weight
			if (v - preyWeightDiff) < (PersistentVars['FakePreyWeightTable'][k] // 5) then
				preyWeightDiff = v - PersistentVars['FakePreyWeightTable'][k] // 5
			end
			SP_ReduceWeightRecursive(k, preyWeightDiff)
		end
    end
	
	local preds = SP_GetUniquePreds()
	for k, v in pairs(preds) do
        SP_UpdateWeight(k)
    end
	_D(PersistentVars['PreyWeightTable'])
	_D(PersistentVars['FakePreyWeightTable'])
	-- this is necessary to avoid multiple calls of this function (for each party member)
	SP_DelayCall(50, function() calculateRest = true end)
end

---fires once after long rest
function SP_OnLongRest()
	_P('SP_OnLongRest')
	
	for k, v in pairs(PersistentVars['PreyWeightTable']) do
		if Osi.IsDead(k) == 1 then
			-- local preyWeightDiff = PersistentVars['FakePreyWeightTable'][k] // 5
			local preyWeightDiff = 70
			-- prey's weight after digestion should not be smaller then 1/5th of their original (fake) weight
			if (v - preyWeightDiff) < (PersistentVars['FakePreyWeightTable'][k] // 5) then
				preyWeightDiff = v - PersistentVars['FakePreyWeightTable'][k] // 5
			end
			SP_ReduceWeightRecursive(k, preyWeightDiff)
		end
    end
	
	local preds = SP_GetUniquePreds()
	for k, v in pairs(preds) do
        SP_UpdateWeight(k)
    end
	_D(PersistentVars['PreyWeightTable'])
	_D(PersistentVars['FakePreyWeightTable'])
end

-- If you know where to get type hints for this, please let me know.
if Ext.Osiris == nil then Ext.Osiris = {} end

Ext.Osiris.RegisterListener("UsingSpellOnTarget", 6, "after", SP_OnSpellCastTarget)
Ext.Osiris.RegisterListener("CastedSpell", 5, "after", SP_SpellCast)
Ext.Osiris.RegisterListener("RollResult", 6, "after", SP_RollResults)
Ext.Osiris.RegisterListener("LevelUnloading", 1, "before", SP_OnLevelChange)
Ext.Osiris.RegisterListener("StatusApplied", 4, "after", SP_OnStatusApplied)
Ext.Osiris.RegisterListener("TemplateAddedTo", 4, "after", SP_OnItemAdded)
Ext.Osiris.RegisterListener("Died", 1, "before", SP_OnDeath)
Ext.Osiris.RegisterListener("ShortRested", 1, "after", SP_OnShortRest)
Ext.Osiris.RegisterListener("LongRestFinished", 0, "after", SP_OnLongRest)

Ext.Events.SessionLoaded:Subscribe(SP_OnSessionLoaded)
Ext.Events.ResetCompleted:Subscribe(SP_On_reset_completed)