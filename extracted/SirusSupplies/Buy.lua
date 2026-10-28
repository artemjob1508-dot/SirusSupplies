--[[--------------------------------------------------------------------------
    SirusSupplies — файл 4: выкуп реагентов.

    Покупка идёт через современный аукцион:
      C_AuctionHouse.StartCommoditiesPurchase(itemID, quantity)
      C_AuctionHouse.ConfirmCommoditiesPurchase(itemID, quantity)

    Перед покупкой показывается подтверждение со сметой. Покупка возможна
    только когда открыт аукцион и для всех реагентов известны itemID и цена
    (то есть после сканирования).
----------------------------------------------------------------------------]]

local SS = SirusSupplies

-- Список покупки: только то, чего не хватает в сумке. Для докупаемых
-- позиций нужны цена и itemID; позиции, уже лежащие в сумке, не покупаем.
-- Возвращает: список, смету, названия без данных, план поставки.
function SS:BuildBuyList(quest)
    local plan = self:GetQuestPlan(quest)
    local list, total, missing = {}, 0, {}

    for _, item in ipairs(plan.items) do
        if item.toBuy > 0 then
            if item.unit and item.itemID then
                total = total + item.unit * item.toBuy
                table.insert(list, {
                    name = item.name,
                    count = item.toBuy,
                    itemID = item.itemID,
                    unit = item.unit,
                    have = item.have,
                    need = item.count,
                })
            else
                table.insert(missing, item.name)
            end
        end
    end

    return list, total, missing, plan
end

--------------------------------------------------------------------------
-- Диалог подтверждения
--------------------------------------------------------------------------
function SS:CreateBuyDialog()
    if self.buyDialog then
        return self.buyDialog
    end

    local frame = CreateFrame("Frame", "SirusSuppliesBuyDialog", UIParent)
    frame:SetWidth(380)
    frame:SetHeight(170)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
    end)
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Tooltip\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    frame:SetBackdropColor(0, 0, 0, 0.9)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", frame, "TOP", 0, -12)
    title:SetText("Покупка реагентов")
    title:SetTextColor(1, 0.82, 0)

    local text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -36)
    text:SetWidth(348)
    text:SetJustifyH("LEFT")
    frame.text = text

    local yes = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    yes:SetWidth(130)
    yes:SetHeight(22)
    yes:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 40, 16)
    yes:SetText("Купить")
    yes:SetScript("OnClick", function()
        SS:StartBuy()
    end)

    local no = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    no:SetWidth(130)
    no:SetHeight(22)
    no:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -40, 16)
    no:SetText("Отмена")
    no:SetScript("OnClick", function()
        frame:Hide()
    end)

    frame:Hide()
    self.buyDialog = frame
    return frame
end

function SS:ShowBuyDialog(quest)
    if quest.gossipOnly then
        self:Print("Реагенты этого задания ещё неизвестны — возьми его у Джулии один раз.")
        return
    end

    if not self:IsQuestActive(quest) then
        self:Print("Этого задания сейчас нет у Джулии — покупка недоступна.")
        return
    end

    local list, total, missing, plan = self:BuildBuyList(quest)

    if plan.status == "ready" then
        self:Print("Всё для «" .. quest.title .. "» уже есть в сумке — покупать нечего.")
        return
    end

    if #list == 0 then
        self:Print("Нет цен и itemID. Открой аукцион и нажми «Сканировать цены».")
        return
    end

    if #missing > 0 then
        self:Print("Не хватает данных для: " .. table.concat(missing, ", "))
        self:Print("Покупка отменена, чтобы не купить половину.")
        return
    end

    if not self.ahOpen then
        self:Print("Аукцион должен быть открыт.")
        return
    end

    local dialog = self:CreateBuyDialog()
    dialog.quest = quest
    dialog.list = list
    dialog.total = total

    local lines = {}
    if plan.status == "partial" then
        table.insert(lines, "Докупить реагенты для «" .. quest.title .. "»?")
        table.insert(lines, string.format("В сумке уже есть %d из %d шт.", plan.coveredUnits, plan.needUnits))
    else
        table.insert(lines, "Купить реагенты для «" .. quest.title .. "»?")
    end

    for _, item in ipairs(list) do
        if item.have > 0 then
            table.insert(lines, string.format("  %s: есть %d, купить %d", item.name, item.have, item.count))
        else
            table.insert(lines, string.format("  %s: купить %d", item.name, item.count))
        end
    end

    table.insert(lines, "Примерная стоимость: " .. self:Money(total) .. ".")
    table.insert(lines, "Цена может отличаться: покупаются самые дешёвые лоты.")

    dialog.text:SetText(table.concat(lines, "\n"))
    dialog:SetHeight(86 + 13 * #lines)
    dialog:Show()
end

--------------------------------------------------------------------------
-- Покупка
--------------------------------------------------------------------------
function SS:StartBuy()
    local dialog = self.buyDialog
    if not dialog or not dialog.quest then
        return
    end

    dialog:Hide()

    self.buy = {
        active = true,
        quest = dialog.quest,
        items = dialog.list,
        index = 1,
        phase = "start",
        waitUntil = 0,
        total = dialog.total,
        done = 0,
    }

    self:Print("Покупаю реагенты для «" .. dialog.quest.title .. "»…")
end

function SS:StopBuy(message)
    if self.buy then
        self.buy.active = false
    end
    if message then
        self:Print(message)
    end
end

function SS:BuyUpdate()
    local buy = self.buy
    if not buy or not buy.active then
        return
    end

    if not self.ahOpen then
        self:StopBuy("Аукцион закрыт — покупка остановлена.")
        return
    end

    local now = GetTime()
    if now < (buy.waitUntil or 0) then
        return
    end

    local item = buy.items[buy.index]
    if not item then
        self:StopBuy(string.format("Покупка завершена: %d из %d позиций.", buy.done, #buy.items))
        return
    end

    if buy.phase == "start" then
        C_AuctionHouse.StartCommoditiesPurchase(item.itemID, item.count)
        buy.phase = "confirm"
        buy.waitUntil = now + 0.6

    elseif buy.phase == "confirm" then
        C_AuctionHouse.ConfirmCommoditiesPurchase(item.itemID, item.count)
        buy.done = buy.done + 1
        buy.phase = "next"
        buy.waitUntil = now + 0.8

    else
        buy.index = buy.index + 1
        buy.phase = "start"
        buy.waitUntil = now
    end
end

--------------------------------------------------------------------------
-- События покупки
--------------------------------------------------------------------------
SS:On("COMMODITY_PURCHASE_SUCCEEDED", function(self)
    if self.buy and self.buy.active then
        -- Ничего не считаем: прогресс ведёт BuyUpdate, тут только лог.
        self:Print("Лот выкуплен.")
    end
end)

SS:On("COMMODITY_PURCHASE_FAILED", function(self)
    if self.buy and self.buy.active then
        self:Print("Аукцион не дал купить лот — возможно, его уже выкупили.")
    end
end)
