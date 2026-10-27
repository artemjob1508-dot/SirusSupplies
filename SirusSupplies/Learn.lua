--[[--------------------------------------------------------------------------
    SirusSupplies — файл 2: обучение базе поставок.

    Откуда берём список реагентов:
      * журнал заданий: GetQuestLogLeaderBoard -> "Название: 0/20";
      * окно квеста (до принятия): QuestInfoObjectivesText.
    Всё, что нашли, складываем в SirusSuppliesDB.quests по названию квеста.
----------------------------------------------------------------------------]]

local SS = SirusSupplies

-- Разбирает строку цели вида "Руническая ткань: 0/20".
-- Возвращает название и требуемое количество.
local function ParseObjective(text)
    if type(text) ~= "string" then
        return nil
    end

    local clean = SS:Clean(text)
    clean = clean:gsub("^%s*[%-•]%s*", "")
    if clean == "" then
        return nil
    end

    local name, _, need = clean:match("^(.-):%s*(%d+)%s*/%s*(%d+)")
    if name and name ~= "" then
        local count = tonumber(need)
        if count and count > 0 then
            return SS:Trim(name), count
        end
    end

    -- "20 x Руническая ткань"
    local count2, name2 = clean:match("^(%d+)%s*[xXхХ]%s*(.+)$")
    if count2 and name2 then
        return SS:Trim(name2), tonumber(count2)
    end

    -- "Руническая ткань (20)"
    local name3, count3 = clean:match("^(.-)%s*%((%d+)%)%s*$")
    if name3 and name3 ~= "" then
        local count = tonumber(count3)
        if count and count > 0 then
            return SS:Trim(name3), count
        end
    end

    return nil
end

SS.ParseObjective = ParseObjective

--------------------------------------------------------------------------
-- Запись в базу
--------------------------------------------------------------------------
function SS:LearnQuest(title, items, source)
    title = SS:Clean(title)
    if title == "" or type(items) ~= "table" or #items == 0 then
        return false
    end

    local key = self:TextKey(title)
    local quest = self.db.quests[key]
    if not quest then
        quest = { title = title, items = {} }
        self.db.quests[key] = quest
    end

    -- Сливаем с тем, что уже знаем: новые данные уточняют старые.
    local merged, order = {}, {}
    for _, item in ipairs(quest.items or {}) do
        if not merged[item.name] then
            merged[item.name] = item.count
            table.insert(order, item.name)
        end
    end
    for _, item in ipairs(items) do
        if not merged[item.name] then
            table.insert(order, item.name)
        end
        merged[item.name] = item.count
    end

    local result = {}
    for _, name in ipairs(order) do
        table.insert(result, { name = name, count = merged[name] })
    end
    table.sort(result, function(a, b) return a.name < b.name end)

    quest.items = result
    quest.title = title
    quest.updated = time()
    quest.source = source
    return true
end

--------------------------------------------------------------------------
-- Журнал заданий
--------------------------------------------------------------------------
function SS:ScanQuestLog()
    if not self.db then
        return
    end

    local found = 0

    for index = 1, GetNumQuestLogEntries() do
        local title, _, _, _, isHeader = GetQuestLogTitle(index)
        if not isHeader and self:IsSupplyTitle(title) then
            local items = {}

            for objective = 1, GetNumQuestLeaderBoards(index) do
                local text, objType = GetQuestLogLeaderBoard(objective, index)
                local name, count = ParseObjective(text)
                if name and count then
                    table.insert(items, { name = name, count = count })
                end
            end

            if #items > 0 and self:LearnQuest(title, items, "log") then
                found = found + 1
            end
        end
    end

    if found > 0 and self.Refresh then
        self:Refresh()
    end
end

--------------------------------------------------------------------------
-- Окно квеста (можно подсмотреть список до принятия)
--------------------------------------------------------------------------
function SS:ScanQuestDetail()
    if not self.db then
        return
    end

    local title = GetTitleText and GetTitleText()
    if not self:IsSupplyTitle(title) then
        return
    end

    local text
    if QuestInfoObjectivesText and QuestInfoObjectivesText.GetText then
        text = QuestInfoObjectivesText:GetText()
    end
    if type(text) ~= "string" then
        return
    end

    self.db.lastDetail = {
        time = date("%Y-%m-%d %H:%M:%S"),
        title = title,
        text = text,
    }

    local items = {}
    for line in string.gmatch(text, "[^\n]+") do
        local name, count = ParseObjective(line)
        if name and count then
            table.insert(items, { name = name, count = count })
        end
    end

    if #items > 0 and self:LearnQuest(title, items, "detail") and self.Refresh then
        self:Refresh()
    end
end

--------------------------------------------------------------------------
-- Диалог (сюда же складываем тексты для дампа)
--------------------------------------------------------------------------
local function Pack(...)
    return { n = select("#", ...), ... }
end

-- Запасной путь: тексты кнопок стандартного госсипа.
local function ReadGossipButtons()
    local texts = {}

    for index = 1, 32 do
        local button = _G["GossipTitleButton" .. index]
        if button then
            local text = button.GetText and button:GetText()
            if type(text) == "string" and text ~= "" then
                table.insert(texts, text)
            end
        end
    end

    return texts
end

-- Ещё один запасной путь: обходим фрейм диалога и собираем тексты.
local function CollectRegionTexts(frame, texts, depth)
    if depth > 3 or #texts >= 40 then
        return
    end

    local ok, regions = pcall(function()
        return { frame:GetRegions() }
    end)
    if ok and type(regions) == "table" then
        for _, region in ipairs(regions) do
            if region.GetText then
                local text = region:GetText()
                if type(text) == "string" and text ~= "" then
                    table.insert(texts, text)
                end
            end
        end
    end

    local ok2, children = pcall(function()
        return { frame:GetChildren() }
    end)
    if ok2 and type(children) == "table" then
        for _, child in ipairs(children) do
            CollectRegionTexts(child, texts, depth + 1)
        end
    end
end

function SS:CaptureGossip()
    local texts = {}

    local ok, packed = pcall(function()
        return Pack(GetGossipOptions())
    end)

    if ok and packed and packed.n and packed.n > 1 then
        for index = 1, math.floor(packed.n / 2) do
            local text = packed[(index - 1) * 2 + 1]
            if type(text) == "string" and text ~= "" then
                table.insert(texts, text)
            end
        end
    end

    if #texts == 0 then
        texts = ReadGossipButtons()
    end

    if #texts == 0 and GossipFrame then
        CollectRegionTexts(GossipFrame, texts, 1)

        local filtered = {}
        for _, text in ipairs(texts) do
            if self:IsSupplyTitle(text) then
                table.insert(filtered, text)
            end
        end
        texts = filtered
    end

    -- Игнорируемые поставки не показываем и не запоминаем как активные.
    local filtered = {}
    for _, text in ipairs(texts) do
        if not self:IsIgnoredTitle(text) then
            table.insert(filtered, text)
        end
    end
    texts = filtered

    self.lastGossipOptions = texts

    if self.db then
        local matches = {}
        local active = {}

        self.db.gossipQuests = self.db.gossipQuests or {}

        for _, text in ipairs(texts) do
            local quest = self:GetQuestByText(text)
            if quest then
                local total, known = self:GetQuestCost(quest)
                matches[text] = { found = true, known = known, total = total }
            else
                matches[text] = { found = false }
            end

            if self:IsSupplyTitle(text) then
                local key = self:TextKey(text)
                active[key] = true
                self.db.gossipQuests[key] = {
                    title = self:Clean(text),
                    seen = time(),
                }
            end
        end

        -- Активные задания: те, что сейчас реально есть у Джулии.
        if next(active) ~= nil then
            self.db.activeQuests = active
            self.db.activeTime = time()
        end

        self.db.lastGossip = {
            time = date("%Y-%m-%d %H:%M:%S"),
            source = GossipFrame and GossipFrame:GetName(),
            options = texts,
            matches = matches,
        }
    end

    return texts
end

-- Для диагностики: что вообще есть в открытом окне диалога.
function SS:DebugGossipTexts()
    local texts = {}
    if GossipFrame then
        CollectRegionTexts(GossipFrame, texts, 1)
    end
    return texts
end

--------------------------------------------------------------------------
-- События
--------------------------------------------------------------------------
SS:On("QUEST_LOG_UPDATE", function(self)
    self:ScanQuestLog()
end)

SS:On("QUEST_DETAIL", function(self)
    self:ScanQuestDetail()
end)

SS:On("GOSSIP_SHOW", function(self)
    self:CaptureGossip()
end)

SS:On("PLAYER_ENTERING_WORLD", function(self)
    self:ScanQuestLog()
end)
