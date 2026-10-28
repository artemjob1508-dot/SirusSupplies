--[[--------------------------------------------------------------------------
    SirusSupplies — файл 3: цены с аукциона.

    На клиенте Sirus аукцион современный (C_AuctionHouse / AuctionHouseFrame),
    поэтому используется C_AuctionHouse.SendBrowseQuery: ищем предмет по
    названию, получаем агрегированные результаты (minPrice за штуку,
    totalQuantity) и запоминаем минимальную цену.

    Если современного API нет (обычный 3.3.5), работает старый путь через
    QueryAuctionItems + GetAuctionItemInfo.
----------------------------------------------------------------------------]]

local SS = SirusSupplies

SS.hasModernAH = (type(C_AuctionHouse) == "table")

function SS:IsScanning()
    return self.scan ~= nil and self.scan.active == true
end

-- Уникальные названия реагентов, которые ещё надо докупить: то, что уже
-- лежит в сумке, не сканируем.
function SS:BuildScanQueue()
    local seen, queue = {}, {}

    for _, quest in pairs(self.db.quests) do
        if not self:IsIgnoredTitle(quest.title) and self:IsQuestActive(quest) then
            local plan = self:GetQuestPlan(quest)
            for _, item in ipairs(plan.items) do
                if item.name and item.toBuy > 0 and not seen[item.name] then
                    seen[item.name] = true
                    table.insert(queue, item.name)
                end
            end
        end
    end

    return queue
end

function SS:StartScan()
    if self:IsScanning() then
        self:Print("Сканирование уже идёт.")
        return
    end

    if not self.db then
        return
    end

    if not self.ahOpen then
        self:Print("Открой аукцион: запросы цен работают только у него.")
        return
    end

    -- Сначала читаем сумку: сканируем аукцион только по недостающему.
    self:ScanBags()

    local queue = self:BuildScanQueue()
    if #queue == 0 then
        if next(self.db.quests) ~= nil then
            self:Print("Всё нужное для активных поставок уже есть в сумке — сканировать нечего.")
        else
            self:Print("Список реагентов пуст. Прими поставки у Джулии — аддон запишет их из журнала.")
        end
        return
    end

    self.scan = {
        active = true,
        queue = queue,
        index = 0,
        done = 0,
        total = #queue,
        pending = nil,
        pendingAt = 0,
        nextAt = 0,
    }

    self:Print("Сканирую цены: " .. #queue .. " предмет(ов). Аукцион не закрывай.")
    if self.Refresh then self:Refresh() end
end

function SS:StopScan(message)
    if self.scan then
        self.scan.active = false
    end
    if message then
        self:Print(message)
    end
    if self.Refresh then self:Refresh() end
end

--------------------------------------------------------------------------
-- Запрос цены
--------------------------------------------------------------------------
function SS:QueryPrice(name)
    if self.hasModernAH then
        C_AuctionHouse.SendBrowseQuery({
            searchString = name,
            filters = {},
            itemClassFilters = {},
            sorts = {},
        })
    else
        QueryAuctionItems(name, 0, 0, 0, false, 0)
    end
end

-- Современный аукцион: агрегированные результаты.
-- minPrice — цена за штуку, totalQuantity — сколько всего есть.
-- strict = true: не принимать результат без совпадения имени (защита от
-- устаревших данных при опросе).
function SS:ProcessBrowseResults(target, strict)
    local results = C_AuctionHouse.GetBrowseResults()
    if type(results) ~= "table" then
        return false
    end

    local single = (#results == 1) and not strict
    local bestUnit, bestStock, bestID

    for _, result in ipairs(results) do
        local itemKey = result.itemKey
        local itemID = itemKey and itemKey.itemID
        local price = result.minPrice
        local quantity = result.totalQuantity or 0

        if itemID and price and price > 0 and quantity > 0 then
            local matches = false
            local itemName = GetItemInfo(itemID)

            if itemName then
                matches = (self:Clean(itemName) == target)
            elseif single then
                -- Название ещё не закешировалось, но результат один.
                matches = true
            end

            if matches and (not bestUnit or price < bestUnit) then
                bestUnit = price
                bestStock = quantity
                bestID = itemID
            end
        end
    end

    if not bestUnit then
        return false
    end

    self.db.prices[target] = {
        unit = math.floor(bestUnit + 0.5),
        itemID = bestID,
        stock = bestStock,
        time = time(),
    }

    return true
end

-- Старый 3.3.5: разбираем список лотов вручную.
function SS:ProcessAuctionList(target)
    local numItems = GetNumAuctionItems("list")
    local bestUnit, bestStock, bestLink

    for index = 1, numItems do
        local name, _, count, _, _, _, _, _, buyout = GetAuctionItemInfo("list", index)

        if name and buyout and buyout > 0 and count and count > 0 then
            if self:Clean(name) == target then
                local unit = buyout / count
                if not bestUnit or unit < bestUnit then
                    bestUnit = unit
                    bestStock = count
                    bestLink = GetAuctionItemLink("list", index)
                end
            end
        end
    end

    if not bestUnit then
        return false
    end

    local itemID
    if bestLink then
        itemID = tonumber(bestLink:match("item:(%d+)"))
    end

    self.db.prices[target] = {
        unit = math.floor(bestUnit + 0.5),
        itemID = itemID,
        link = bestLink,
        stock = bestStock,
        time = time(),
    }

    return true
end

--------------------------------------------------------------------------
-- Драйвер
--------------------------------------------------------------------------
function SS:ScanUpdate()
    local scan = self.scan
    if not scan or not scan.active then
        return
    end

    if not self.ahOpen then
        self:StopScan("Аукцион закрыт — сканирование остановлено.")
        return
    end

    local now = GetTime()

    if scan.pending then
        if now - scan.pendingAt > self.SCAN_TIMEOUT then
            self:Print("Нет ответа аукциона по: " .. scan.pending)
            scan.pending = nil
            scan.nextAt = now + self.SCAN_DELAY
        else
            -- Страховка: если событие аукциона не пришло, забираем
            -- результаты опросом (на нестандартных сборках бывает).
            if self.hasModernAH and C_AuctionHouse.GetBrowseResults
                and now - scan.pendingAt > 0.25
                and now - (scan.lastPoll or 0) > 0.25 then
                scan.lastPoll = now
                if self:ProcessBrowseResults(scan.pending, true) then
                    self:FinishQuery(true)
                    return
                end
            end
            return
        end
    end

    if scan.index >= scan.total then
        self.db.lastScan = time()
        self:StopScan(string.format("Готово: %d из %d позиций с ценой.", scan.done, scan.total))
        return
    end

    if now < scan.nextAt then
        return
    end

    -- Современный аукцион иногда просит подождать перед следующим запросом.
    if self.hasModernAH
        and C_AuctionHouse.IsThrottledMessageSystemReady
        and not C_AuctionHouse.IsThrottledMessageSystemReady() then
        scan.nextAt = now + 0.5
        return
    end

    scan.index = scan.index + 1
    scan.pending = scan.queue[scan.index]
    scan.pendingAt = now

    self:QueryPrice(scan.pending)
end

function SS:FinishQuery(success)
    local scan = self.scan
    if not scan or not scan.active then
        return
    end

    scan.pending = nil
    scan.lastPoll = nil
    if success then
        scan.done = scan.done + 1
    end
    scan.nextAt = GetTime() + self.SCAN_DELAY

    if self.Refresh then
        self:Refresh()
    end
end

SS:On("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", function(self)
    local scan = self.scan
    if not scan or not scan.active or not scan.pending then
        return
    end
    self:FinishQuery(self:ProcessBrowseResults(scan.pending))
end)

SS:On("AUCTION_ITEM_LIST_UPDATE", function(self)
    local scan = self.scan
    if not scan or not scan.active or not scan.pending then
        return
    end
    self:FinishQuery(self:ProcessAuctionList(scan.pending))
end)

SS:On("AUCTION_HOUSE_BROWSE_FAILURE", function(self)
    local scan = self.scan
    if not scan or not scan.active or not scan.pending then
        return
    end
    self:Print("Аукцион отклонил запрос цен — продолжаю со следующего.")
    self:FinishQuery(false)
end)

--------------------------------------------------------------------------
-- Возраст цен
--------------------------------------------------------------------------
-- Считаем по реагентам, которые надо докупать: цены на то, что уже лежит
-- в сумке, не обновляются и не должны делать «устаревшими» остальные.
function SS:PricesAge()
    local oldest
    local queue = self:BuildScanQueue()

    local function consider(price)
        if price and price.time and (not oldest or price.time < oldest) then
            oldest = price.time
        end
    end

    if #queue > 0 then
        for _, name in ipairs(queue) do
            consider(self.db.prices[name])
        end
    else
        for _, price in pairs(self.db.prices) do
            consider(price)
        end
    end

    if not oldest then
        return nil
    end
    return time() - oldest
end

function SS:ShouldAutoScan()
    for _, name in ipairs(self:BuildScanQueue()) do
        local price = self.db.prices[name]
        if not (price and price.time) or time() - price.time > self.SCAN_TTL then
            return true
        end
    end
    return false
end

--------------------------------------------------------------------------
-- Привод
--------------------------------------------------------------------------
local driver = CreateFrame("Frame")
driver:SetScript("OnUpdate", function()
    SS:ScanUpdate()
    if SS.BagUpdate then
        SS:BagUpdate()
    end
    if SS.BuyUpdate then
        SS:BuyUpdate()
    end
    if SS.CheckAHState then
        SS:CheckAHState()
    end
    if SS.CheckGossipState then
        SS:CheckGossipState()
    end
    if SS.UpdateAHButton then
        SS:UpdateAHButton()
    end
end)
