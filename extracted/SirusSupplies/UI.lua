--[[--------------------------------------------------------------------------
    SirusSupplies — файл 4: интерфейс.

    * окно «Поставки Джулии» — список поставок с суммой выкупа;
    * кнопка у аукциона (рядом с крестиком закрытия);
    * панель рядом с диалогом Джулии с ценой каждой поставки.
----------------------------------------------------------------------------]]

local SS = SirusSupplies

local MAX_ROWS = 14

local function CreateBackdrop(frame)
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Tooltip\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    frame:SetBackdropColor(0, 0, 0, 0.82)
end

local function AgeText(seconds)
    if not seconds then
        return "нет данных"
    end
    if seconds < 60 then
        return "только что"
    end
    if seconds < 3600 then
        return string.format("%d мин назад", math.floor(seconds / 60))
    end
    return string.format("%d ч назад", math.floor(seconds / 3600))
end

SS.AgeText = AgeText

--------------------------------------------------------------------------
-- Окно поставок
--------------------------------------------------------------------------
function SS:CreateMainFrame()
    if self.mainFrame then
        return self.mainFrame
    end

    local db = self.db
    local frame = CreateFrame("Frame", "SirusSuppliesFrame", UIParent)
    frame:SetWidth(372)
    frame:SetHeight(400)
    frame:SetPoint(
        db.pos.point or "CENTER",
        UIParent,
        db.pos.relativePoint or "CENTER",
        db.pos.x or 0,
        db.pos.y or 40
    )
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relativePoint, x, y = self:GetPoint()
        SS.db.pos = {
            point = point,
            relativePoint = relativePoint,
            x = x,
            y = y,
        }
    end)
    CreateBackdrop(frame)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -10)
    title:SetText("Поставки Джулии")
    title:SetTextColor(1, 0.82, 0)

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    close:SetScript("OnClick", function()
        SS:HideWindow()
    end)

    local status = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    status:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -28)
    status:SetTextColor(0.6, 0.6, 0.6)
    frame.status = status

    frame.rows = {}
    for index = 1, MAX_ROWS do
        local row = CreateFrame("Button", nil, frame)
        row:SetWidth(348)
        row:SetHeight(22)
        row:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -46 - (index - 1) * 22)
        row:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")

        local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("LEFT", row, "LEFT", 2, 0)
        label:SetWidth(158)
        label:SetJustifyH("LEFT")
        label:SetTextColor(0.9, 0.9, 0.9)
        row.label = label

        local cost = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        cost:SetPoint("RIGHT", row, "RIGHT", -70, 0)
        cost:SetTextColor(1, 0.82, 0)
        row.cost = cost

        local buy = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        buy:SetWidth(66)
        buy:SetHeight(18)
        buy:SetPoint("RIGHT", row, "RIGHT", -2, 0)
        buy:SetText("Купить")
        buy:SetScript("OnClick", function()
            local quest = row.quest
            if quest then
                SS:ShowBuyDialog(quest)
            end
        end)
        row.buyButton = buy

        row:SetScript("OnEnter", function(self)
            SS:ShowQuestTooltip(self)
        end)
        row:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
        row:SetScript("OnClick", function(self)
            if self.quest then
                SS:PrintQuest(self.quest)
            end
        end)

        row:Hide()
        frame.rows[index] = row
    end

    local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("TOP", frame, "TOP", 0, -60)
    hint:SetWidth(280)
    hint:SetJustifyH("CENTER")
    hint:SetText("Пока пусто.\nПрими поставки у Джулии — и аддон запомнит реагенты из журнала заданий.")
    hint:SetTextColor(0.7, 0.7, 0.7)
    frame.hint = hint

    local scanButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    scanButton:SetWidth(160)
    scanButton:SetHeight(22)
    scanButton:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 14, 12)
    scanButton:SetText("Сканировать цены")
    scanButton:SetScript("OnClick", function()
        SS:StartScan()
    end)
    frame.scanButton = scanButton

    local dumpButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    dumpButton:SetWidth(110)
    dumpButton:SetHeight(22)
    dumpButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -14, 12)
    dumpButton:SetText("Дамп")
    dumpButton:SetScript("OnClick", function()
        SS:Dump()
    end)
    frame.dumpButton = dumpButton

    self.mainFrame = frame
    return frame
end

function SS:ShowQuestTooltip(row)
    local quest = row.quest
    if not quest then
        return
    end

    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:AddLine(quest.title, 1, 0.82, 0)

    if quest.gossipOnly then
        GameTooltip:AddLine("Задание сохранено из диалога Джулии.", 1, 1, 1, true)
        GameTooltip:AddLine(
            "Реагенты станут известны, когда возьмёшь задание (или откроешь его описание).",
            0.7, 0.7, 0.7, true)
        GameTooltip:Show()
        return
    end

    if not self:IsQuestActive(quest) then
        GameTooltip:AddLine("Сейчас этого задания у Джулии нет.", 0.6, 0.6, 0.6, true)
    end

    local plan = self:GetQuestPlan(quest)

    for _, item in ipairs(plan.items) do
        local left = item.count .. "x " .. item.name

        if item.toBuy == 0 then
            GameTooltip:AddDoubleLine(left, "есть в сумке (" .. item.have .. ")", 1, 1, 1, 0.2, 1, 0.2)
        elseif item.unit then
            local right = self:Money(item.cost)
            if item.covered > 0 then
                right = "есть " .. item.covered .. ", купить " .. item.toBuy .. " — " .. right
            end
            GameTooltip:AddDoubleLine(left, right, 1, 1, 1, 1, 0.82, 0)
        else
            local right = "нет цены"
            if item.covered > 0 then
                right = "есть " .. item.covered .. ", купить " .. item.toBuy .. " — нет цены"
            end
            GameTooltip:AddDoubleLine(left, right, 1, 1, 1, 0.6, 0.6, 0.6)
        end
    end

    GameTooltip:AddLine(" ")

    if plan.status == "ready" then
        GameTooltip:AddLine("Всё нужное уже есть в сумке — покупать нечего.", 0.2, 1, 0.2, true)
    elseif plan.buyKnown > 0 then
        local r, g, b = self:CostColor(plan.buyCost)
        local label = (plan.status == "partial") and "Докупить на" or "Итого"
        GameTooltip:AddDoubleLine(label, self:Money(plan.buyCost), 1, 1, 1, r, g, b)

        if plan.status == "partial" and plan.fullKnown == plan.count then
            GameTooltip:AddDoubleLine("Целиком стоило бы", self:Money(plan.fullCost),
                0.7, 0.7, 0.7, 0.7, 0.7, 0.7)
        end
        if plan.buyKnown < plan.buyNeeded then
            GameTooltip:AddLine("Часть позиций без цены — сумма неполная.", 0.8, 0.5, 0.5)
        end
    else
        GameTooltip:AddLine("Цен пока нет: открой аукцион и нажми «Сканировать».", 1, 0.5, 0.5, true)
    end

    GameTooltip:AddLine("Оценка по минимальной цене за штуку; покупка стопками может выйти дороже.", 0.7, 0.7, 0.7, true)
    GameTooltip:AddLine("Реагенты из сумки одной поставки не резервируются под другие.", 0.7, 0.7, 0.7, true)
    GameTooltip:Show()
end

function SS:PrintQuest(quest)
    self:Print("|cffffd100" .. quest.title .. "|r")

    if quest.gossipOnly then
        self:Print("  Задание сохранено из диалога Джулии; реагенты появятся, когда возьмёшь его.")
        return
    end

    local plan = self:GetQuestPlan(quest)

    for _, item in ipairs(plan.items) do
        local line = "  " .. item.count .. "x " .. item.name
        if item.toBuy == 0 then
            line = line .. " — |cff33ff33есть в сумке (" .. item.have .. ")|r"
        else
            if item.covered > 0 then
                line = line .. " — есть " .. item.covered .. ", купить " .. item.toBuy
            end
            if item.unit then
                line = line .. " — " .. self:Money(item.cost)
            else
                line = line .. " — нет цены"
            end
        end
        self:Print(line)
    end

    if plan.status == "ready" then
        self:Print("  Всё уже в сумке.")
    elseif plan.buyKnown > 0 then
        local label = (plan.status == "partial") and "  Докупить: " or "  Итого: "
        self:Print(label .. self:CostColorCode(plan.buyCost) .. self:Money(plan.buyCost) .. "|r"
            .. (plan.buyKnown < plan.buyNeeded and " (неполная сумма)" or ""))
    end
end

function SS:Refresh()
    local frame = self.mainFrame
    if not frame then
        return
    end

    local quests, seen = {}, {}

    for key, quest in pairs(self.db.quests) do
        if quest.items and #quest.items > 0 and not self:IsIgnoredTitle(quest.title) then
            table.insert(quests, quest)
            seen[key] = true
        end
    end

    -- Задания, которые сохранились из диалога Джулии, но ещё не изучены.
    for key, gossip in pairs(self.db.gossipQuests or {}) do
        if not seen[key] and not self:IsIgnoredTitle(gossip.title) then
            table.insert(quests, {
                title = gossip.title,
                gossipOnly = true,
            })
        end
    end

    -- Сначала активные (есть у Джулии сейчас), потом остальные.
    table.sort(quests, function(a, b)
        local activeA = self:IsQuestActive(a)
        local activeB = self:IsQuestActive(b)
        if activeA ~= activeB then
            return activeA
        end
        return a.title < b.title
    end)

    for index = 1, MAX_ROWS do
        local row = frame.rows[index]
        local quest = quests[index]

        if quest then
            local plan = self:GetQuestPlan(quest)
            local active = self:IsQuestActive(quest)

            row.quest = quest
            row.active = active

            if active then
                row.label:SetTextColor(1, 1, 1)
            else
                row.label:SetTextColor(0.55, 0.55, 0.55)
            end

            row.label:SetText(self:Utf8Sub(quest.title, 27))

            -- В строке показываем то, что осталось докупить: если часть
            -- реагентов уже в сумке, сумма меньше полной стоимости.
            if plan.status == "unknown" or plan.buyKnown == 0 and plan.status ~= "ready" then
                row.cost:SetText("?")
                row.cost:SetTextColor(0.6, 0.6, 0.6)
                row.buyButton:SetText((plan.status == "partial") and "Докупить" or "Купить")
            elseif plan.status == "ready" then
                row.cost:SetText("в сумке")
                row.cost:SetTextColor(0.2, 1, 0.2)
                row.buyButton:SetText("Есть")
            else
                local prefix = (plan.status == "partial") and "докуп " or ""
                row.buyButton:SetText((plan.status == "partial") and "Докупить" or "Купить")

                if plan.buyKnown < plan.buyNeeded then
                    row.cost:SetText(prefix .. "~ " .. self:Money(plan.buyCost, true) .. "*")
                    row.cost:SetTextColor(0.9, 0.7, 0.3)
                else
                    local r, g, b = self:CostColor(plan.buyCost)
                    row.cost:SetText(prefix .. "~ " .. self:Money(plan.buyCost, true))
                    row.cost:SetTextColor(r, g, b)
                end
            end

            if not active then
                row.cost:SetTextColor(0.55, 0.55, 0.55)
            end

            -- Кнопка покупки активна, когда есть что докупать, у всех таких
            -- реагентов известны цена и itemID (иначе купим половину), и
            -- задание сейчас доступно.
            local buyList, _, missing = self:BuildBuyList(quest)
            if active and #buyList > 0 and #missing == 0 then
                row.buyButton:Enable()
            else
                row.buyButton:Disable()
            end

            row:Show()
        else
            row.quest = nil
            row.buyButton:Disable()
            row:Hide()
        end
    end

    if #quests == 0 then
        frame.hint:Show()
    else
        frame.hint:Hide()
    end

    if self:IsScanning() then
        frame.status:SetText(string.format("Скан: %d из %d…", self.scan.done, self.scan.total))
        frame.scanButton:Disable()
    else
        frame.status:SetText("Цены: " .. AgeText(self:PricesAge()))
        frame.scanButton:Enable()
    end
end

function SS:ShowWindow()
    self:CreateMainFrame()
    self.mainFrame:Show()
    self.db.shown = true
    self:Refresh()
end

function SS:HideWindow()
    if self.mainFrame then
        self.mainFrame:Hide()
    end
    self.db.shown = false
end

function SS:Toggle()
    if self.mainFrame and self.mainFrame:IsShown() then
        self:HideWindow()
    else
        self:ShowWindow()
    end
end

--------------------------------------------------------------------------
-- Кнопка у аукциона и на миникарте, отслеживание открытия аукциона
--------------------------------------------------------------------------
function SS:AHFrame()
    return _G.AuctionHouseFrame or _G.AuctionFrame
end

function SS:IsAHOpen()
    local frame = self:AHFrame()
    return frame ~= nil and frame:IsShown()
end

function SS:CheckAHState()
    local open = self:IsAHOpen()

    if open and not self.ahOpen then
        self:OnAHOpened()
    elseif not open and self.ahOpen then
        self:OnAHClosed()
    end
end

function SS:OnAHOpened()
    if self.ahOpen or not self.db then
        return
    end

    self.ahOpen = true
    self:ScanBags()
    self:RecordAH()
    self:EnsureAHButton()
    if self.ahButton then
        self:PositionAHButton()
        self.ahButton:Show()
    else
        self.buttonDeadline = GetTime() + 5
    end

    if self.db.autoShow then
        self:ShowWindow()
    end

    if self.db.autoScan and self:ShouldAutoScan() and #self:BuildScanQueue() > 0 then
        self:StartScan()
    end
end

function SS:OnAHClosed()
    if not self.ahOpen then
        return
    end

    self.ahOpen = false

    if self.ahButton then
        self.ahButton:Hide()
    end

    -- Закрываем окно поставок и диалог покупки вместе с аукционом.
    self:HideWindow()

    if self.buyDialog then
        self.buyDialog:Hide()
    end

    if self.buy and self.buy.active then
        self:StopBuy("Аукцион закрыт — покупка остановлена.")
    end

    if self:IsScanning() then
        self:StopScan("Аукцион закрыт — сканирование остановлено.")
    end
end

--------------------------------------------------------------------------
-- Поиск звезды/строки поиска в шапке аукциона
--------------------------------------------------------------------------
local function FindChildContaining(root, patterns, maxDepth)
    local found

    local function walk(frame, depth)
        if found or depth > maxDepth then
            return
        end

        local ok, children = pcall(function()
            return { frame:GetChildren() }
        end)
        if not ok or type(children) ~= "table" then
            return
        end

        for _, child in ipairs(children) do
            local name = child.GetName and child:GetName()
            if name then
                local lower = string.lower(name)
                for _, pattern in ipairs(patterns) do
                    if lower:find(pattern, 1, true) then
                        found = child
                        return
                    end
                end
            end
            walk(child, depth + 1)
        end
    end

    walk(root, 1)
    return found
end

function SS:FindAHStarAnchor()
    local frame = self:AHFrame()
    if not frame then
        return nil
    end

    local anchor = FindChildContaining(
        frame, { "favorite", "favourite", "favorites" }, 5)

    if not anchor then
        anchor = FindChildContaining(
            frame, { "searchbox", "searchbar", "searchfield" }, 5)
    end

    return anchor
end

function SS:PositionAHButton()
    local button = self.ahButton
    local frame = self:AHFrame()
    if not button or not frame then
        return
    end

    button:ClearAllPoints()

    if self.db and self.db.buttonOffset then
        button:SetPoint("TOPLEFT", frame, "TOPLEFT",
            self.db.buttonOffset.x, self.db.buttonOffset.y)
        return
    end

    local anchor = self:FindAHStarAnchor()

    if anchor then
        -- Рядом со звездой/строкой поиска в шапке аукциона.
        button:SetPoint("RIGHT", anchor, "LEFT", -4, 0)
    elseif _G.AuctionHouseFrame then
        -- Запасная позиция в шапке слева, где обычно и стоит звезда.
        button:SetPoint("TOPLEFT", frame, "TOPLEFT", 168, -45)
    else
        button:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -40, -8)
    end
end

function SS:SaveAHButtonPosition()
    local button = self.ahButton
    local frame = self:AHFrame()
    if not button or not frame or not self.db then
        return
    end

    local frameLeft, frameTop = frame:GetLeft(), frame:GetTop()
    local buttonLeft, buttonTop = button:GetLeft(), button:GetTop()

    if frameLeft and frameTop and buttonLeft and buttonTop then
        self.db.buttonOffset = {
            x = buttonLeft - frameLeft,
            y = buttonTop - frameTop,
        }
        self:PositionAHButton()
    end
end

function SS:EnsureAHButton()
    if self.ahButton then
        return
    end

    local frame = self:AHFrame()
    if not frame then
        return
    end

    -- Отдельная кнопка поверх UIParent: её не прячет и не обрезает окно
    -- аукциона, в отличие от кнопки-ребёнка.
    local button = CreateFrame("Button", "SirusSuppliesStarButton", UIParent)
    button:SetWidth(28)
    button:SetHeight(28)
    button:SetFrameStrata("DIALOG")
    button:SetFrameLevel(100)
    button:SetNormalTexture("Interface\\Icons\\INV_Misc_Coin_06")
    button:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    button:Hide()

    button:SetScript("OnClick", function()
        SS:Toggle()
    end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Поставки Джулии")
        GameTooltip:AddLine("ЛКМ — открыть/закрыть окно", 1, 1, 1)
        GameTooltip:AddLine("Тащи мышкой — переместить кнопку", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    button:RegisterForDrag("LeftButton")
    button:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    button:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SS:SaveAHButtonPosition()
    end)

    self.ahButton = button
    self:PositionAHButton()
    self:RecordAH()
end

function SS:PositionMinimapButton()
    local button = self.minimapButton
    if not button or not Minimap then
        return
    end

    local angle = math.rad(self.db.minimapAngle or 220)
    local radius = 80

    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER",
        math.cos(angle) * radius, math.sin(angle) * radius)
end

function SS:MinimapDragUpdate()
    local button = self.minimapButton
    if not button or not button.dragging or not Minimap then
        return
    end

    local mapX, mapY = Minimap:GetCenter()
    if not mapX then
        return
    end

    local scale = Minimap:GetEffectiveScale()
    local cursorX, cursorY = GetCursorPosition()
    cursorX, cursorY = cursorX / scale, cursorY / scale

    local angle
    if math.atan2 then
        angle = math.deg(math.atan2(cursorY - mapY, cursorX - mapX))
    else
        angle = math.deg(math.atan(cursorY - mapY, cursorX - mapX))
    end

    self.db.minimapAngle = angle
    self:PositionMinimapButton()
end

function SS:CreateMinimapButton()
    if self.minimapButton or not Minimap then
        return
    end

    local button = CreateFrame("Button", "SirusSuppliesMinimapButton", Minimap)
    button:SetWidth(28)
    button:SetHeight(28)
    button:SetFrameStrata("MEDIUM")
    button:SetNormalTexture("Interface\\Icons\\INV_Misc_Coin_06")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    button:SetScript("OnClick", function()
        SS:Toggle()
    end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Поставки Джулии")
        GameTooltip:AddLine("ЛКМ — открыть/закрыть окно", 1, 1, 1)
        GameTooltip:AddLine("Тащи мышкой — переместить значок", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    button:RegisterForDrag("LeftButton")
    button:SetScript("OnDragStart", function(self)
        self.dragging = true
        self:SetScript("OnUpdate", function()
            SS:MinimapDragUpdate()
        end)
    end)
    button:SetScript("OnDragStop", function(self)
        self.dragging = false
        self:SetScript("OnUpdate", nil)
    end)

    self.minimapButton = button
    self:PositionMinimapButton()
end

--------------------------------------------------------------------------
-- Панель у Джулии
--------------------------------------------------------------------------
--------------------------------------------------------------------------
-- Панель у Джулии: крупный игровой шрифт и растягивание мышкой
--------------------------------------------------------------------------
local GOSSIP_SCALE = 0.5
local GOSSIP_FONT_SIZE = math.floor(22 * GOSSIP_SCALE)
local GOSSIP_ROW_HEIGHT = math.floor(34 * GOSSIP_SCALE)
local GOSSIP_TITLE_SIZE = math.floor(20 * GOSSIP_SCALE)
local GOSSIP_HINT_SIZE = math.floor(14 * GOSSIP_SCALE)
local GOSSIP_HEADER = math.floor(44 * GOSSIP_SCALE)
local GOSSIP_MAX_ROWS = 12
local GOSSIP_FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"

function SS:LayoutGossipPanel()
    local panel = self.gossipPanel
    if not panel then
        return
    end

    local width = panel:GetWidth() or 460
    local height = panel:GetHeight() or 120
    local labelWidth = math.max(120, width - 170)

    local maxRows = math.floor((height - GOSSIP_HEADER) / GOSSIP_ROW_HEIGHT)
    if maxRows < 0 then
        maxRows = 0
    end

    local visible = math.min(self.gossipVisibleCount or 0, maxRows, GOSSIP_MAX_ROWS)

    for index, row in ipairs(panel.rows) do
        row:SetWidth(width - 24)
        row.label:SetWidth(labelWidth)

        if index <= visible and row.fullText then
            -- Текст подгоняется под ширину: широко — видно всё,
            -- узко — многоточие, лишние строки уходят за высоту.
            self:FitText(row.label, row.fullText, labelWidth)
            row:Show()
        else
            row:Hide()
        end
    end
end

function SS:CreateGossipPanel()
    if self.gossipPanel then
        return self.gossipPanel
    end

    local width = self.db.gossipWidth or 460
    local height = self.db.gossipHeight or (GOSSIP_HEADER + 6 * GOSSIP_ROW_HEIGHT)

    local panel = CreateFrame("Frame", "SirusSuppliesGossip", UIParent)
    panel:SetWidth(width)
    panel:SetHeight(height)
    CreateBackdrop(panel)
    panel:SetFrameStrata("DIALOG")
    panel:SetFrameLevel(100)
    panel:SetClampedToScreen(true)

    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -10)
    title:SetText("Поставки Джулии")
    title:SetTextColor(1, 0.82, 0)
    title:SetFont(GOSSIP_FONT, GOSSIP_TITLE_SIZE)
    panel.title = title

    local hint = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -14, -12)
    hint:SetText("цены с аукциона")
    hint:SetTextColor(0.7, 0.7, 0.7)
    hint:SetFont(GOSSIP_FONT, GOSSIP_HINT_SIZE)

    panel.rows = {}
    for index = 1, GOSSIP_MAX_ROWS do
        local row = CreateFrame("Frame", nil, panel)
        row:SetHeight(GOSSIP_ROW_HEIGHT)
        row:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -GOSSIP_HEADER - (index - 1) * GOSSIP_ROW_HEIGHT)

        local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("LEFT", row, "LEFT", 0, 0)
        label:SetJustifyH("LEFT")
        label:SetTextColor(1, 1, 1)
        label:SetFont(GOSSIP_FONT, GOSSIP_FONT_SIZE)
        row.label = label

        local cost = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        cost:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        cost:SetTextColor(1, 0.82, 0)
        cost:SetFont(GOSSIP_FONT, GOSSIP_FONT_SIZE)
        row.cost = cost

        row:Hide()
        panel.rows[index] = row
    end

    -- Уголок для растягивания: тянем мышкой, размер запоминается.
    local grip = CreateFrame("Button", nil, panel)
    grip:SetWidth(16)
    grip:SetHeight(16)
    grip:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -2, 2)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function(self)
        self.resizing = true
        local scale = panel:GetEffectiveScale()
        local x, y = GetCursorPosition()
        self.startX, self.startY = x / scale, y / scale
        self.startW, self.startH = panel:GetWidth(), panel:GetHeight()
    end)
    grip:SetScript("OnMouseUp", function(self)
        self.resizing = false
        SS.db.gossipWidth = panel:GetWidth()
        SS.db.gossipHeight = panel:GetHeight()
    end)
    panel.grip = grip

    panel:SetScript("OnUpdate", function(self)
        local grip = self.grip
        if not grip or not grip.resizing then
            return
        end

        local scale = panel:GetEffectiveScale()
        local x, y = GetCursorPosition()

        local width = grip.startW + (x / scale - grip.startX)
        local height = grip.startH - (y / scale - grip.startY)

        width = math.max(340, math.min(820, width))
        height = math.max(90, math.min(700, height))

        panel:SetWidth(width)
        panel:SetHeight(height)
        SS:LayoutGossipPanel()
    end)

    self.gossipPanel = panel
    self:LayoutGossipPanel()
    return panel
end

function SS:UpdateGossipPanel()
    if not GossipFrame or not GossipFrame:IsShown() then
        return
    end

    local options = self:CaptureGossip()
    local supplies = {}

    for _, text in ipairs(options) do
        if self:IsSupplyTitle(text) then
            table.insert(supplies, text)
        end
    end

    if #supplies == 0 then
        if self.gossipPanel then
            self.gossipPanel:Hide()
        end
        return
    end

    local panel = self:CreateGossipPanel()
    panel:ClearAllPoints()

    local width = panel:GetWidth() or 460
    local scale = UIParent:GetEffectiveScale() or 1
    local screenWidth = GetScreenWidth() / scale
    local gossipLeft = GossipFrame:GetLeft() or 0
    local gossipRight = GossipFrame:GetRight() or 0

    if gossipRight + width + 12 <= screenWidth then
        panel:SetPoint("TOPLEFT", GossipFrame, "TOPRIGHT", 8, -24)
    elseif gossipLeft - width - 12 >= 0 then
        panel:SetPoint("TOPRIGHT", GossipFrame, "TOPLEFT", -8, -24)
    else
        -- Диалог занимает весь экран: ставим панель у правого края.
        panel:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -20, -80)
    end

    if not self.db.gossipHeight then
        panel:SetHeight(GOSSIP_HEADER + math.min(#supplies, GOSSIP_MAX_ROWS) * GOSSIP_ROW_HEIGHT)
    end

    self.gossipVisibleCount = #supplies

    for index = 1, GOSSIP_MAX_ROWS do
        local row = panel.rows[index]
        local option = supplies[index]
        if option then
            local quest = self:GetQuestByText(option)

            -- В госсипе Сирус отдаёт название с цветовым кодом |cff000000,
            -- поэтому чистим цвета перед показом.
            row.fullText = self:Clean(option)
            row.label:SetText(row.fullText)

            if quest then
                local plan = self:GetQuestPlan(quest)
                if plan.status == "ready" then
                    row.cost:SetText("всё в сумке")
                    row.cost:SetTextColor(0.2, 1, 0.2)
                elseif plan.buyKnown > 0 then
                    local r, g, b = self:CostColor(plan.buyCost)
                    local prefix = (plan.status == "partial") and "докуп " or ""
                    local star = (plan.buyKnown < plan.buyNeeded) and "*" or ""
                    row.cost:SetText(prefix .. "~ " .. self:Money(plan.buyCost, true) .. star)
                    row.cost:SetTextColor(r, g, b)
                else
                    row.cost:SetText("нет цен")
                    row.cost:SetTextColor(0.6, 0.6, 0.6)
                end
            else
                row.cost:SetText("?")
                row.cost:SetTextColor(0.6, 0.6, 0.6)
            end
        else
            row.fullText = nil
        end
    end

    self:LayoutGossipPanel()
    panel:Show()
end

-- GOSSIP_SHOW на этой сборке может не приходить — опрашиваем состояние.
function SS:CheckGossipState()
    local shown = GossipFrame and GossipFrame:IsShown()

    if not shown then
        if self.gossipOpen then
            self.gossipOpen = false
            if self.gossipPanel then
                self.gossipPanel:Hide()
            end
        end
        return
    end

    self.gossipOpen = true

    local now = GetTime()
    if not self.gossipNextUpdate or now >= self.gossipNextUpdate then
        self.gossipNextUpdate = now + 0.5
        self:UpdateGossipPanel()
    end
end

--------------------------------------------------------------------------
-- События
--------------------------------------------------------------------------
function SS:RecordAH()
    if not self.db then
        return
    end

    local frame = self:AHFrame()
    local close = (frame and frame.CloseButton)
        or _G.AuctionHouseFrameCloseButton
        or _G.AuctionFrameCloseButton
    local anchor = self:FindAHStarAnchor()

    self.db.lastAH = {
        time = date("%Y-%m-%d %H:%M:%S"),
        frame = frame and frame:GetName(),
        auctionatorFrame = _G.AuctionatorAHFrame and _G.AuctionatorAHFrame:GetName(),
        closeButton = close and close:GetName(),
        starAnchor = anchor and anchor:GetName(),
        auctionator = (type(IsAddOnLoaded) == "function") and IsAddOnLoaded("Auctionator") or nil,
    }
end

-- Если AuctionFrame появляется с задержкой (LoD-аддон), пробуем ещё пару секунд.
function SS:UpdateAHButton()
    if self.ahButton or not self.buttonDeadline then
        return
    end

    if GetTime() > self.buttonDeadline then
        self.buttonDeadline = nil
        return
    end

    self:EnsureAHButton()
    if self.ahButton then
        self.buttonDeadline = nil
        self:PositionAHButton()
        self.ahButton:Show()
    end
end

SS:On("AUCTION_HOUSE_SHOW", function(self)
    self:OnAHOpened()
end)

SS:On("AUCTION_HOUSE_CLOSED", function(self)
    self:OnAHClosed()
end)

SS:On("GOSSIP_SHOW", function(self)
    self:UpdateGossipPanel()
end)

SS:On("GOSSIP_CLOSED", function(self)
    if self.gossipPanel then
        self.gossipPanel:Hide()
    end
end)

SS:On("PLAYER_LOGIN", function(self)
    self:CreateMinimapButton()
    self:EnsureAHButton()
    if self.db.shown then
        self:ShowWindow()
    end
end)

SS:On("ADDON_LOADED", function(self, _, addonName)
    if addonName == "Blizzard_AuctionUI" or addonName == "Auctionator" then
        self:EnsureAHButton()
    end
end)
