local TalentPlanner = {}
TalentPlanner.options = {
    learningEnabled = true,
    allowVirtualBuild = true, -- allows the planner to remove points actually assigned for planning purposes
    learningEnabled = true,
    assumedLevel = 60
}
TalentPlanner.hooked = {}
TalentPlanner.current = {}
TalentPlanner.ui = {}
TalentPlanner.exporters = {}
TalentPlanner.importers = {}

SARF_TP = TalentPlanner

function TalentPlanner:GetQueueTotal(tab, id)
    local amount = 0
    local first = nil
    local last = nil
    for k, v in ipairs(self.current) do
        if (v[1] == tab and v[2] == id) then 
            amount = amount + 1 
            if type(first) ~= "number" or first > k then first = k  end
            if type(last) ~= "number" or last < k then last = k end
        end
    end
    return amount, first, last
end

function TalentPlanner:PatchTalentButtonIfNeeded(name, parent)
    local virtualRank = _G[name]
    if not virtualRank then
        local fs = TalentPlanner.frame:CreateFontString("FontString", name, parent)
        fs:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE, MONOCHROME")
        fs:SetPoint("CENTER",parent:GetName(),"BOTTOMRIGHT", 0, 0)
        virtualRank = fs
    end
    return virtualRank
end

function TalentPlanner:PatchTalentAPI()
    local names = {} --{"GetTalentPrereqs"}
    TalentPlanner.hooked["GetTalentTabInfo"] = GetTalentTabInfo
    GetTalentTabInfo = function(tab)
        local a,b,c,d,e,f,g,h,i,j,k = TalentPlanner.hooked["GetTalentTabInfo"](tab)
        c = TalentPlanner:GetPointsSpentInTab(tab)
        return a,b,c,d,e,f,g,h,i,j,k
    end
    TalentPlanner.hooked["GetTalentPrereqs"] = GetTalentPrereqs
    GetTalentPrereqs = function(tab, id)
        local arr = {TalentPlanner.hooked["GetTalentPrereqs"](tab, id)}
        for i = 1, #arr, 3 do
            local rank, maxRank = select(5, GetTalentInfo(arr[i], arr[i+1]))
            if rank == maxRank then
                arr[i+2] = true
            end
        end
        return unpack(arr)
    end
    TalentPlanner.hooked["GetTalentInfo"] = GetTalentInfo
    GetTalentInfo = function(tab, id)
        local a,b,c,d,e,f,g,h,i,j,k = TalentPlanner.hooked["GetTalentInfo"](tab, id)
        --TalentPlanner:Print("GetTalentInfo(" .. tab .. ", ".. id ..") => " .. dumpValue({a,b,c,d,e,f,g,h,i,j,k}, 1, true))
        if a then
            if TalentPlanner.current.virtual then
                e = TalentPlanner:GetQueueTotal(tab, id)
            else
                -- non-virtual build means it is based on your current build and is, in fact, possible to apply.
                e = e + TalentPlanner:GetQueueTotal(tab, id)
            end
        end
        return a,b,c,d,e,f,g,h,i,j,k
    end

    TalentPlanner.hooked["UnitCharacterPoints"] = UnitCharacterPoints
    UnitCharacterPoints = function(unit)
        local a,b,c,d,e,f,g,h,i,j,k = TalentPlanner.hooked["UnitCharacterPoints"](unit)
        a = TalentPlanner:GetPointsLeft(TalentPlanner.options.assumedLevel)
        return a,b,c,d,e,f,g,h,i,j,k
    end
    
    for k, v in ipairs(names) do
        if TalentPlanner[v] and not TalentPlanner.hooked[v] then 
            TalentPlanner.hooked[v] = _G[v]
            _G[v] = TalentPlanner[v]
        end
    end
end

function TalentPlanner:CreateTalentList(useHooked)
    local GetTalentInfoFunc = GetTalentInfo
    if useHooked then
        GetTalentInfoFunc = function(a, b) return self:CallHookedGlobal("GetTalentInfo", a, b) end
    end
    local talentList = {}
    for tab = 1, 3 do
        local tabList = {}
        local tabRanks = 0
        local tierRanks = {}
        local reverseTier = {}
        local reverseColumn = {}
        for talent = 1, MAX_NUM_TALENTS or 20 do
            local name, _, t, c, rank, maxRank = GetTalentInfoFunc(tab, talent)
            if not name then break end
            tierRanks[t] = (tierRanks[t] or 0) + rank
            tabRanks = tabRanks + rank
            reverseTier[t] = talent
            reverseColumn[c] = talent
            table.insert(tabList, { name = name, tier = c, column = c, rank = rank, maxRank = maxRank })
        end
        tabList.tab = tab
        tabList.ranks = tabRanks
        tabList.tierRanks = tierRanks
        tabList.reverseTier = reverseTier
        tabList.reverseColumn = reverseColumn
        table.insert(talentList, tabList)
    end
    return talentList
end

function TalentPlanner:Virtualize(build)
    if not build.virtual then
        local total = 1
        for tab = 1, 3 do 
            for talent = 1, MAX_NUM_TALENTS or 20 do
                local name, _, _, _, rank, maxRank = self.hooked["GetTalentInfo"](tab, talent)
                if not name then break end 
                while rank > 0 do
                    table.insert(build, total, { tab, talent})
                    rank = rank - 1
                    total = total + 1
                end
            end
        end
        build.virtual = true
    end
end

-- function TalentPlanner:Devirtualize(build) build.virtual = false end

function TalentPlanner:RemovePointFrom(tab, id)
    local name, _, _, _, rank, maxRank = GetTalentInfo(tab, id)
    if rank <= 0 then return end
    local amount, first, last = self:GetQueueTotal(tab, id)
    if amount <= 0 then
        if self.options.allowVirtualBuild then
            if not self.current.isVirtual then
                self:Virtualize(self.current)
                self:RemovePointFrom(tab, id)
                return
            end
        else
            return false, "can not reduce below actual talent" 
        end
    end

    -- Last talent point spent, no checks needs to be made
    if last == #self.current then
        table.remove(self.current, last)
    else
        -- le sigh
        local talentList = self:CreateTalentList()
        local tabInfo = talentList[tab]
        local currentTier = tabInfo.reverseTier[id] or 0
        local nextTierPoints = tabInfo.tierRanks[currentTier + 1] or 0
        if nextTierPoints > 0 and tabInfo.tierRanks[currentTier] <= 5 then
            return false, "can not remove, there are talents in tiers above"
        end
        
        local _, _, t, c, rank, maxRank = self.hooked["GetTalentInfo"](tab, id)
        -- LE SIIIIIIIIIGH
        for i = 1, MAX_NUM_TALENTS or 20 do
            local name, _, _, _, r = GetTalentInfo(tab, i)
            if not name then break end
            if (r > 0) then
                local response = {GetTalentPrereqs(tab, i)}
                for j = 1, #response, 3 do
                    if response[j] == t and response[j+1] == c then
                        return false, "is prerequisite for other talent"
                    end
                end
            end
        end
    end
    TalentFrame_Update()
    return true
end

function TalentPlanner:GetPointsSpentInTab(tab)
    local total = 0
    for id = 1, 20 do
        local name, _, _, _, rank = GetTalentInfo(tab, id)
        if not name then break end
        total = total + (rank or 0)
    end
    return total
end

function TalentPlanner:GetPointsSpentTotal()
    local total = 0
    for tab = 1, 3 do
        total = total + self:GetPointsSpentInTab(tab)
    end
    return total
end

function TalentPlanner:GetPointsLeft(assumedLevel)
    return (assumedLevel or (UnitLevel("player") - 10)) - self:GetPointsSpentTotal()
end

function TalentPlanner:AddPointIn(tab, id)
    local name, iconTexture, tier, column, rank, maxRank, isExceptional, available = GetTalentInfo(tab, id)
    if not name then return false end
    if(rank < maxRank) and self:GetPointsLeft(60) > 0 then
        table.insert(self.current, { tab, id })
        TalentFrame_Update()
        return true
    end
    return false
end

function TalentPlanner:TalentFrameTalentButton_OnClick(button, mouseButton)
    if button:IsEnabled() then
        local id = button:GetID()
        local tab = PanelTemplates_GetSelectedTab(TalentFrame)
        
        if (mouseButton == "RightButton") then
            TalentPlanner:RemovePointFrom(tab, id)
        else
            TalentPlanner:AddPointIn(tab, id)
        end
    end
end

function TalentPlanner:Reset()
    local queue = self.current
    while(#queue > 0) do table.remove(queue, 1) end
    for k, v in pairs(queue) do queue[k] = nil end
    TalentFrame_Update()
end

function TalentPlanner:CreateButton(n, text, x, onClick)
    local applyButton = _G[n] or CreateFrame("Button", n, TalentFrame, "UIPanelButtonTemplate")
    applyButton:SetText(text)
    --applyButton:SetFrameStrata("NORMAL")
    applyButton:SetWidth(60)
    applyButton:SetHeight(18)
    applyButton:SetScript("OnClick", onClick)
    applyButton:SetPoint("CENTER","TalentFrame","TOPLEFT", x, -420)
end

function TalentPlanner:PatchTalentButtons()
    local i = 1
    local n = "TalentFrameTalent"..i
    local button = _G[n]
    local func = function(button, mouseButton) return TalentPlanner:TalentFrameTalentButton_OnClick(button, mouseButton) end
    local handler = "OnClick"
    while button do
        if not TalentPlanner.hooked[n] then TalentPlanner.hooked[n] = {} end
        if not TalentPlanner.hooked[n][handler] then
            TalentPlanner.hooked[n][handler] = button:GetScript(handler)
            button:SetScript(handler, func)
        end
        i = i + 1
        n = "TalentFrameTalent"..i
        button = _G[n] 
    end
end

function TalentPlanner:CallHookedGlobal(name, ...)
    local func = self.hooked[name]
    if type(func) ~= "function" then
        func = _G[name]
    end
    return func(select(1, ...))
end
function TalentPlanner:TalentFrame_Update()
    self:CallHookedGlobal("TalentFrame_Update")
    -- apply part
    local applyState = true
    local resetState = true
    if self.current.virtual then
        -- TODO: create fontString that shows ("virtual build") preferably with tooltip ("diverged from actual current build, can not be applied")
        applyState = false
    end
    if #self.current <= 0 then
        applyState = false
        resetState = false
    end
    if applyState then
        TalentFrameApplyButton:Enable()
    else
        TalentFrameApplyButton:Disable()
    end
    if resetState then
        TalentFrameResetButton:Enable()
    else
        TalentFrameResetButton:Disable()
    end
end

function TalentPlanner:Colourize(text, colour)
    local colourText = colour
    if colour == "RED" then colourText = "FFEF1212" end
    if colour == "GREEN" then colourText = "FF12EF12" end
    if colour == "BLUE" then colourText = "FF1212EF" end
    if colour == "LIGHTBLUE" then colourText = "FF5252EF" end
    if colour == "RB" then colourText = "FFEF12EF" end
    if colour == "YELLOW" then colourText = "FFEFEF12" end
    if colour == "CYAN" then colourText = "FF12EFEF" end
    if colour == "WHITE" then colourText = "FFFFFFEF" end
    return "|c" .. colourText .. text .. "|r"
end

function TalentPlanner:Print(msg)
    ChatFrame1:AddMessage(self:Colourize("TP", "GREEN") .. ": " .. tostring(msg), 1, 1, 0)
end

function TalentPlanner:Apply()
    local talentPoints = self:CallHookedGlobal("UnitCharacterPoints", "player");
    local queue = self.current
    if (not self.current.virtual and talentPoints >= 0 or TalentPlanner.options.learningEnabled) and #queue > 0 then
        local entry = table.remove(queue, 1)
        local name, _, _, _, rank, maxRank, _, available = self:CallHookedGlobal("GetTalentInfo", entry[1], entry[2])
        local nameRankStr = name
        if(maxRank > 1) then nameRankStr = nameRankStr .. " (" .. (rank+1) .. "/" .. maxRank .. ")" end
        if rank >= maxRank or not available then
            TalentPlanner:Print("Attempting to learn " .. nameRankStr .. " but it is unlikely to work...")
        else
            TalentPlanner:Print("Attempting to learn " .. nameRankStr)
        end
        if TalentPlanner.options.learningEnabled then 
            LearnTalent(entry[1], entry[2])
            local _, _, _, _, newRank = self:CallHookedGlobal("GetTalentInfo", entry[1], entry[2]);
            if newRank > rank then
                local extra = ""
                if maxRank > 1 then
                    extra = extra .. string.format(" (%d / %d)", newRank, maxRank)
                end
                TalentPlanner:Print("Learnt " .. nameRankStr .. extra)
            end
        end
    end
end


function TalentPlanner:TalentUILoaded()
    self:Print("Patching TalentUILoaded")
    self:PatchTalentAPI()
    pcall(function() TalentPlanner.frame:UnregisterEvent("ADDON_LOADED") end)
    self:PatchTalentButtons()

    local hookGlobal = {"TalentFrame_Update"}
    
    for k, n in ipairs(hookGlobal) do
        if type(TalentPlanner[n]) == "function" and not TalentPlanner.hooked[n] then
            TalentPlanner.hooked[n] =  _G[n]
            _G[n] = function() return TalentPlanner[n](TalentPlanner) end
        end
    end
    
    if not self.ui.TalentFrameApplyButton then
        self.ui.TalentFrameApplyButton = self:CreateButton("TalentFrameApplyButton", "Apply", 45, function() return TalentPlanner:Apply() end)
    end
    if not self.ui.TalentFrameResetButton then
        self.ui.TalentFrameResetButton = self:CreateButton("TalentFrameResetButton", "Reset", 105, function() return TalentPlanner:Reset() end)
    end
end

getString = function(k)
    if type(k) == "boolean" then if(k) then return "true" else return "false" end end
    return tostring(k)
end

dumpValue = function(str, level, noNewLine)
    if type(str) ~= "table" then return getString(str) end
    if type(level) ~= "number" then level = 1 end
    local q = ""
    local nl = "\n"
    if noNewLine then nl = ", " end
    for i = 1, level do q = q .. "{" end
    for k, v in ipairs(str) do
        q = q .. " " .. getString(k) .. " => " .. dumpValue(v, level + 1, noNewLine) .. nl
    end
    for i = 1, level do q = q .. "}" end
    return q
end



TalentPlanner.ADDON_LOADED = function(addon)
    if(addon == "Blizzard_TalentUI") then
        TalentPlanner:TalentUILoaded()
    end
end

TalentPlanner.frame = CreateFrame("Frame")
TalentPlanner.frame:SetScript("OnEvent", function(frame, ...)
    local event = select(1, ...)
    if type(TalentPlanner[event]) == "function" then TalentPlanner[event](select(2, ...)) end
end)
if TalentFrameTalent_OnClick or IsAddOnLoaded("Blizzard_TalentUI") then 
    TalentPlanner:TalentUILoaded()
else
    TalentPlanner.frame:RegisterEvent("ADDON_LOADED")
end



function TalentPlanner:ExporterWoWHeadClassic()
    local megaStr = ""
    for tab = 1, 3 do
        if not map[tab] then map[tab] = {} end
        local actual = {}
        for id = 1, 20 do
            local name, _, tier, column, rank = GetTalentInfo(tab, id)
            if not name then break end
            if not actual[tier] then actual[tier] = {} end
            actual[tier][column] = rank
        end
        local tier = 1
        local tabStr = ""
        while actual[tier] do
            for i = 1, 10 do
                if not actual[tier][i] then break end
                tabStr = tabStr .. actual[tier][i]
            end
            tier = tier + 1
        end
        if megaStr:len() > 0 then megaStr = megaStr.."-" end
        megaStr = megaStr .. tabStr
    end
    return "https://classic.wowhead.com/talent-calc/hunter/" .. megaStr
end




