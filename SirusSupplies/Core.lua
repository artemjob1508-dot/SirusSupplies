--[[--------------------------------------------------------------------------
    SirusSupplies — цены поставок Джулии (Sirus, 3.3.5a)

    Идея:
      * списки реагентов для поставок серверные, в клиенте их нет,
        поэтому аддон учится им из журнала заданий и окна квеста;
      * цены берутся с аукциона (QueryAuctionItems) и кешируются;
      * окно со списком поставок и суммами выкупа появляется у аукциона;
      * рядом с диалогом Джулии показывается панель с ценами.

    Файл 1 из 4: база, утилиты, события, слэш-команды.
----------------------------------------------------------------------------]]

SirusSupplies = {}
local SS = SirusSupplies

SS.VERSION = "0.4.2"

-- Сколько живёт цена, прежде чем считаться устаревшей (секунды).
SS.SCAN_TTL = 15 * 60
-- Сколько ждать ответа аукциона на один запрос.
SS.SCAN_TIMEOUT = 6
-- Пауза между запросами, чтобы не заспамить сервер.
SS.SCAN_DELAY = 0.25

--------------------------------------------------------------------------
-- Печать и строки
--------------------------------------------------------------------------
function SS:Print(text)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99[SirusSupplies]|r " .. tostring(text))
end

function SS:Trim(text)
    local s = tostring(text or "")
    s = s:gsub("^%s+", "")
    s = s:gsub("%s+$", "")
    return s
end

-- Убирает цвета и пробелы по краям.
function SS:Clean(text)
    if type(text) ~= "string" then
        return ""
    end
    local s = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    return self:Trim(s)
end

-- Ключ для таблицы: чистый текст, без хвоста "[500з]", без лишних пробелов.
function SS:TextKey(text)
    local s = self:Clean(text)
    s = s:gsub("%s*%[.-%]%s*$", "")
    s = s:gsub("%s+", " ")
    return self:Trim(s)
end

-- Это название поставки? ("Поставки: ...", "Дополнительные поставки: ...")
function SS:IsSupplyTitle(title)
    local s = self:Clean(title)
    return s:find("Поставк", 1, true) ~= nil or s:find("поставк", 1, true) ~= nil
end

-- Поставки, которые не нужно показывать и сканировать.
SS.IGNORE_PATTERNS = { "Кель'Данас", "Тол'Гарод" }

function SS:IsIgnoredTitle(title)
    local clean = self:Clean(title)
    for _, pattern in ipairs(self.IGNORE_PATTERNS) do
        if clean:find(pattern, 1, true) then
            return true
        end
    end
    return false
end

-- Задание есть в текущем списке Джулии? Если активный список пуст
-- (диалог ещё не открывали), считаем всё активным.
function SS:IsQuestActive(quest)
    local active = self.db and self.db.activeQuests
    if type(active) ~= "table" or next(active) == nil then
        return true
    end
    return active[self:TextKey(quest.title)] == true
end

-- Обрезка UTF-8 строки по числу символов (в Lua 5.1 нет utf8.sub).
function SS:Utf8Sub(text, maxChars)
    local s = tostring(text or "")
    local index, count = 1, 0
    while index <= #s and count < maxChars do
        local byte = s:byte(index)
        local length = 1
        if byte >= 240 then
            length = 4
        elseif byte >= 224 then
            length = 3
        elseif byte >= 192 then
            length = 2
        end
        index = index + length
        count = count + 1
    end
    if index <= #s then
        return s:sub(1, index - 1) .. "…"
    end
    return s
end

-- Длина UTF-8 строки в символах.
function SS:Utf8Length(text)
    local length, index = 0, 1
    local s = tostring(text or "")

    while index <= #s do
        local byte = s:byte(index)
        local step = 1
        if byte >= 240 then
            step = 4
        elseif byte >= 224 then
            step = 3
        elseif byte >= 192 then
            step = 2
        end
        index = index + step
        length = length + 1
    end

    return length
end

-- Обрезает текст ровно под ширину, добавляя многоточие.
function SS:FitText(fontString, text, maxWidth)
    text = tostring(text or "")
    fontString:SetText(text)

    if not fontString.GetStringWidth or not maxWidth or maxWidth <= 0 then
        return text
    end

    local width = fontString:GetStringWidth()
    if type(width) ~= "number" then
        return text
    end

    if width <= maxWidth then
        return text
    end

    local total = self:Utf8Length(text)
    local low, high, best = 1, total, "…"

    while low <= high do
        local middle = math.floor((low + high) / 2)
        local candidate = self:Utf8Sub(text, middle)
        fontString:SetText(candidate)

        local candidateWidth = fontString:GetStringWidth()
        if type(candidateWidth) ~= "number" then
            break
        end

        if candidateWidth <= maxWidth then
            best = candidate
            low = middle + 1
        else
            high = middle - 1
        end
    end

    fontString:SetText(best)
    return best
end

-- "1 234"
function SS:Num(number)
    local s = tostring(math.floor(tonumber(number) or 0))
    local out = ""
    local first = #s % 3
    if first > 0 then
        out = s:sub(1, first)
        s = s:sub(first + 1)
    end
    while #s > 0 do
        if out ~= "" then
            out = out .. " "
        end
        out = out .. s:sub(1, 3)
        s = s:sub(4)
    end
    return out
end

-- Медь -> "1 234g 56s 78c" (short = только старшая часть).
function SS:Money(copper, short)    copper = math.floor(tonumber(copper) or 0)
    if copper <= 0 then
        return "0c"
    end

    local gold = math.floor(copper / 10000)
    local silver = math.floor((copper % 10000) / 100)
    local rest = copper % 100

    local parts = {}
    if gold > 0 then table.insert(parts, self:Num(gold) .. "g") end
    if silver > 0 then table.insert(parts, silver .. "s") end
    if rest > 0 then table.insert(parts, rest .. "c") end

    if short and #parts > 1 then
        return parts[1]
    end
    return table.concat(parts, " ")
end

--------------------------------------------------------------------------
-- Цветовая градация стоимости
--   зелёный  — 500g и дешевле
--   жёлтый   — от 500g до 800g
--   красный  — 800g и дороже
--------------------------------------------------------------------------
SS.COST_GREEN_MAX = 500 * 10000
SS.COST_RED_MIN = 800 * 10000

function SS:CostColor(total)
    if not total or total <= 0 then
        return 0.6, 0.6, 0.6
    end
    if total <= self.COST_GREEN_MAX then
        return 0.2, 1, 0.2
    end
    if total < self.COST_RED_MIN then
        return 1, 0.82, 0
    end
    return 1, 0.2, 0.2
end

function SS:CostColorCode(total)
    if not total or total <= 0 then
        return "|cff999999"
    end
    if total <= self.COST_GREEN_MAX then
        return "|cff33ff33"
    end
    if total < self.COST_RED_MIN then
        return "|cffffd100"
    end
    return "|cffff4040"
end

--------------------------------------------------------------------------
-- База
--------------------------------------------------------------------------
function SS:InitDB()
    if type(SirusSuppliesDB) ~= "table" then
        SirusSuppliesDB = {}
    end

    local db = SirusSuppliesDB
    if type(db.quests) ~= "table" then db.quests = {} end
    if type(db.prices) ~= "table" then db.prices = {} end
    if type(db.gossipQuests) ~= "table" then db.gossipQuests = {} end
    if type(db.pos) ~= "table" then
        db.pos = { point = "CENTER", relativePoint = "CENTER", x = 0, y = 40 }
    end
    if db.shown == nil then db.shown = false end
    if db.autoShow == nil then db.autoShow = true end
    if db.autoScan == nil then db.autoScan = true end
    if db.minimapAngle == nil then db.minimapAngle = 220 end

    self.db = db
end

--------------------------------------------------------------------------
-- События
--------------------------------------------------------------------------
SS.eventFrame = CreateFrame("Frame")
SS.handlers = {}

function SS:On(event, handler)
    self.handlers[event] = self.handlers[event] or {}
    table.insert(self.handlers[event], handler)

    -- На разных сборках клиента набор событий отличается: неизвестное
    -- событие не должно ломать загрузку аддона.
    local ok = pcall(self.eventFrame.RegisterEvent, self.eventFrame, event)
    if not ok then
        self.handlers[event] = nil
    end
end

SS.eventFrame:SetScript("OnEvent", function(_, event, ...)
    local list = SS.handlers[event]
    if not list then
        return
    end
    for index = 1, #list do
        list[index](SS, event, ...)
    end
end)

--------------------------------------------------------------------------
-- Стоимость поставки
--------------------------------------------------------------------------
-- Возвращает: сумма в меди, сколько позиций с ценой, сколько всего, список
-- позиций без цены.
function SS:GetQuestCost(quest)
    local total, known, count, missing = 0, 0, 0, {}

    for _, item in ipairs(quest.items or {}) do
        count = count + 1
        local price = self.db.prices[item.name]
        if price and price.unit and price.unit > 0 then
            total = total + price.unit * item.count
            known = known + 1
        else
            table.insert(missing, item.name)
        end
    end

    return total, known, count, missing
end

function SS:GetQuestByText(text)
    -- Названия и в журнале, и в диалоге приходят из игры, поэтому сравниваем
    -- точно, лишь убирая цвета, лишние пробелы и хвост вида "[500з]".
    return self.db.quests[self:TextKey(text)]
end

-- Насколько устарели цены (секунд с самого старого обновления).
function SS:PricesAge()
    local oldest
    for _, price in pairs(self.db.prices) do
        if price.time and (not oldest or price.time < oldest) then
            oldest = price.time
        end
    end
    if not oldest then
        return nil
    end
    return time() - oldest
end

--------------------------------------------------------------------------
-- Диагностика: /sup dump и автоснимок при выходе
-- Пишет всё в SavedVariables, чтобы аддон можно было доработать по фактам.
--------------------------------------------------------------------------
SS.ahOpen = false

function SS:BuildDump(tag)
    local data = {
        time = date("%Y-%m-%d %H:%M:%S"),
        tag = tag,
        version = self.VERSION,
        questLog = {},
        gossip = self.db.lastGossip,
        gossipDebug = self.DebugGossipTexts and self:DebugGossipTexts() or nil,
        gossipQuests = self.db.gossipQuests,
        lastDetail = self.db.lastDetail,
        ah = self.db.lastAH,
        frames = {},
        quests = self.db.quests,
        prices = self.db.prices,
    }

    if type(GetNumQuestLogEntries) == "function" then
        for index = 1, GetNumQuestLogEntries() do
            local title, _, _, _, isHeader, _, _, _, questID = GetQuestLogTitle(index)
            if not isHeader then
                local entry = { title = title, questID = questID, objectives = {} }
                for objective = 1, GetNumQuestLeaderBoards(index) do
                    local text, objType, finished = GetQuestLogLeaderBoard(objective, index)
                    table.insert(entry.objectives, {
                        text = text,
                        type = objType,
                        finished = finished and true or false,
                    })
                end
                table.insert(data.questLog, entry)
            end
        end
    end

    data.frames = {
        AuctionFrame = (AuctionFrame ~= nil),
        AuctionFrameCloseButton = (AuctionFrameCloseButton ~= nil),
        GossipFrame = (GossipFrame ~= nil),
        QuestInfoObjectivesText = (QuestInfoObjectivesText ~= nil),
        ahOpen = self.ahOpen and true or false,
        IsAddOnLoaded = (type(IsAddOnLoaded) == "function"),
    }

    if type(IsAddOnLoaded) == "function" then
        data.frames.Auctionator = IsAddOnLoaded("Auctionator") and true or false
    end

    return data
end

function SS:Dump()
    local data = self:BuildDump("manual")
    local db = self.db

    db.dumps = db.dumps or {}
    table.insert(db.dumps, data)
    while #db.dumps > 3 do
        table.remove(db.dumps, 1)
    end

    db.dump = data

    self:Print("Дамп записан в SavedVariables. Сделай /reload или выйди из игры — потом скажи мне, я прочитаю файл.")
    self:Print("Файл: WTF\\Account\\<аккаунт>\\SavedVariables\\SirusSupplies.lua")
end

--------------------------------------------------------------------------
-- Слэш-команды
--------------------------------------------------------------------------
SLASH_SIRUSSUPPLIES1 = "/sup"
SLASH_SIRUSSUPPLIES2 = "/supplies"
SlashCmdList["SIRUSSUPPLIES"] = function(message)
    local command = string.lower(SS:Trim(message))

    if command == "" or command == "toggle" then
        SS:Toggle()

    elseif command == "scan" then
        SS:StartScan()

    elseif command == "dump" then
        SS:Dump()

    elseif command == "auto" then
        SS.db.autoShow = not SS.db.autoShow
        SS.db.autoScan = SS.db.autoShow
        SS:Print("Автопоказ и автоскан: " .. (SS.db.autoShow and "вкл" or "выкл"))

    elseif command == "reset" then
        SS.db.quests = {}
        SS.db.prices = {}
        SS:Print("База поставок и цены очищены.")

    elseif command == "help" then
        SS:Print("|cffffd100/sup|r — окно поставок")
        SS:Print("|cffffd100/sup scan|r — обновить цены (у аукциона)")
        SS:Print("|cffffd100/sup dump|r — сохранить диагностику в файл")
        SS:Print("|cffffd100/sup auto|r — автопоказ/автоскан у аукциона")
        SS:Print("|cffffd100/sup reset|r — очистить базу")

    else
        SS:Print("Неизвестная команда: " .. command .. ". Набери /sup help")
    end
end

SS:On("ADDON_LOADED", function(self, _, addonName)
    if addonName == "SirusSupplies" then
        self:InitDB()
        if self.OnDBLoaded then
            self:OnDBLoaded()
        end
    end
end)

-- Автоснимок при выходе/перезагрузке: не нужно помнить про /sup dump.
SS:On("PLAYER_LOGOUT", function(self)
    if not self.db then
        return
    end

    local ok, data = pcall(function()
        return self:BuildDump("logout")
    end)
    if not ok or not data then
        return
    end

    self.db.dumps = self.db.dumps or {}
    table.insert(self.db.dumps, data)
    while #self.db.dumps > 3 do
        table.remove(self.db.dumps, 1)
    end
end)
