MoneyMakingAssistant = {}

local _ = {}

local Events = Library.retrieve("Events", "^2.0.0")
local Coroutine = Library.retrieve("Coroutine", "^2.0.0")
local Bags = Library.retrieve("Bags", "^2.0.5")
local Array = Library.retrieve("Array", "^2.0.0")
local Set = Library.retrieve("Set", "^1.1.0")

_.AUCTION_HOUSE_CUT = 0.05

_.isCancelling = false

--- Adds a buy and sell task for an item.
--- @param itemID number The item ID.
--- @param maximumUnitPriceToBuyFor number The maximum unit price to buy for in gold.
--- @param maximumTotalQuantityToPutIntoAuctionHouse number The maximum total quantity to put into the auction house.
--- @param maximumQuantityToPutIntoAuctionHouseAtATime number The maximum quantity to put into the auction house at a time.
--- @param minimumSellPricePerUnit number The minimum sell price per unit.
function MoneyMakingAssistant.buyAndSell(
  itemID,
  maximumUnitPriceToBuyFor,
  maximumTotalQuantityToPutIntoAuctionHouse,
  maximumQuantityToPutIntoAuctionHouseAtATime,
  minimumSellPricePerUnit
)
  Coroutine.runAsCoroutineImmediately(function()
    _.doIfIsCommodityOrShowInfoOtherwise(itemID, function()
      _.setBuyTask(itemID, maximumTotalQuantityToPutIntoAuctionHouse,
        maximumQuantityToPutIntoAuctionHouseAtATime,
        minimumSellPricePerUnit)
      _.setSellTask(itemID, maximumUnitPriceToBuyFor)
      _.runLoop()
    end)
  end)
end

--- Adds a buy task for an item.
--- @param itemID number The item ID.
--- @param maximumUnitPriceToBuyFor number The maximum unit price to buy for in gold.
function MoneyMakingAssistant.buy(itemID, maximumUnitPriceToBuyFor)
  Coroutine.runAsCoroutineImmediately(function()
    _.doIfIsCommodityOrShowInfoOtherwise(itemID, function()
      _.setSellTask(itemID, maximumUnitPriceToBuyFor)
      _.runLoop()
    end)
  end)
end

--- Adds a sell task for an item.
--- @param itemID number The item ID.
--- @param maximumTotalQuantityToPutIntoAuctionHouse number The maximum total quantity to put into the auction house.
--- @param maximumQuantityToPutIntoAuctionHouseAtATime number The maximum quantity to put into the auction house at a time.
--- @param minimumSellPricePerUnit number The minimum sell price per unit.
function MoneyMakingAssistant.sell(
  itemID,
  maximumTotalQuantityToPutIntoAuctionHouse,
  maximumQuantityToPutIntoAuctionHouseAtATime,
  minimumSellPricePerUnit
)
  Coroutine.runAsCoroutineImmediately(function()
    _.doIfIsCommodityOrShowInfoOtherwise(itemID, function()
      _.setBuyTask(itemID, maximumTotalQuantityToPutIntoAuctionHouse,
        maximumQuantityToPutIntoAuctionHouseAtATime,
        minimumSellPricePerUnit)
      _.runLoop()
    end)
  end)
end

--- Cancel auctions which are estimated to run out.
function MoneyMakingAssistant.cancelAuctions()
  if _.isAuctionHouseOpen() then
    Coroutine.runAsCoroutineImmediately(function()
      _.cancelAuctions()

      print("Auctions have been cancelled.")
    end)
  end
end

do
  BINDING_HEADER_MONEY_MAKING_ASSISTANT = "Money Making Assistant"
  local prefix = "Money Making Assistant: "
  BINDING_NAME_MONEY_MAKING_ASSISTANT_CONFIRM_BUTTON = prefix .. "Confirm"
  BINDING_NAME_MONEY_MAKING_ASSISTANT_STOP = prefix .. "Stop"
end

local tasks = {}

local remainingQuantitiesToSell = {}
local sellTasks = {}
local purchaseTasks = {}

MoneyMakingAssistant.thread = nil
MoneyMakingAssistant.isEnabled = false

local confirmButton

--- Confirms the action.
--- Can be done via button click or key press.
function MoneyMakingAssistant.confirm()
  confirmButton:Hide()
  if MoneyMakingAssistant.thread then
    local thread = MoneyMakingAssistant.thread
    MoneyMakingAssistant.thread = nil
    Coroutine.resumeWithShowingError(thread, true)
  end
end

--- Stops the process.
function MoneyMakingAssistant.stop()
  MoneyMakingAssistant.isEnabled = false
  if confirmButton:IsShown() then
    confirmButton:Hide()
    if MoneyMakingAssistant.thread then
      local thread = MoneyMakingAssistant.thread
      MoneyMakingAssistant.thread = nil
      Coroutine.resumeWithShowingError(thread, false)
    end
  end
end

local sorts = {
  {
    sortOrder = Enum.AuctionHouseSortOrder.Price,
    reverseSort = false,
  },
}

local averageSoldPerDayMultiplier = 2 -- to account for that the stat has been derived from TSM users and that some players might not use TSM.

function _.cancelAuctions()
  _.isCancelling = true

  if not C_AuctionHouse.HasFullOwnedAuctionResults() then
    C_AuctionHouse.QueryOwnedAuctions(g_auctionHouseSortsBySearchContext
      [AuctionHouseSearchContext.AllAuctions])
    Events.waitForEventCondition("OWNED_AUCTIONS_UPDATED", function()
      return C_AuctionHouse.HasFullOwnedAuctionResults()
    end)
  end

  local auctions = C_AuctionHouse.GetOwnedAuctions()
  local itemIDs = Set.create()
  Array.forEach(auctions, function(auction)
    local itemID = auction.itemKey.itemID
    if _.isCommodityItem(itemID) then
      itemIDs:add(itemID)
    end
  end)

  for itemID in itemIDs:iterator() do
    local amountSoldPerDay = (TSM_API.GetCustomPriceValue("dbregionsoldperday*1000",
      "i:" .. itemID) or 0) * averageSoldPerDayMultiplier / 1000
    if amountSoldPerDay then
      local itemKey = { itemID = itemID, }
      C_AuctionHouse.SendSearchQuery(
        itemKey,
        sorts,
        true
      )
      local wasSuccessful, event, argument1 = Events
        .waitForOneOfEventsAndCondition(
          { "COMMODITY_SEARCH_RESULTS_UPDATED", "AUCTION_HOUSE_SHOW_ERROR", },
          function(self, event, argument1)
            if event == "COMMODITY_SEARCH_RESULTS_UPDATED" then
              local itemID = argument1
              return itemID == itemKey.itemID
            elseif event == "AUCTION_HOUSE_SHOW_ERROR" then
              return true
            end
          end, 3)
      if event == "AUCTION_HOUSE_SHOW_ERROR" and argument1 == 10 then
        Events.waitForEvent("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
      end
      if event == "COMMODITY_SEARCH_RESULTS_UPDATED" then
        local numberOfCommoditySearchResults = C_AuctionHouse
          .GetNumCommoditySearchResults(itemID)
        local results = {}
        for index = 1, numberOfCommoditySearchResults do
          local result = C_AuctionHouse.GetCommoditySearchResultInfo(itemID,
            index)
          if result then
            table.insert(results, result)
          end
        end

        local quantity = 0
        Array.forEach(results, function(result)
          if result.containsOwnerItem then
            local estimatedAmountThatSellsUntilTheAuctionRunsOut =
              amountSoldPerDay * (result.timeLeftSeconds / (24 * 60 * 60))
            if quantity > estimatedAmountThatSellsUntilTheAuctionRunsOut then
              _.loadItem(result.itemID)
              local itemLink = select(2, GetItemInfo(result.itemID))
              print("Cancelling " ..
                result.numOwnerItems .. " x " .. itemLink .. ".")
              if MoneyMakingAssistant.showConfirmButton() then
                C_AuctionHouse.CancelAuction(result.auctionID)
                Events.waitForEventCondition("AUCTION_CANCELED",
                  function(self, event, auctionID)
                    return auctionID == result.auctionID
                  end)
              end
            end
          end
          quantity = quantity + result.quantity
        end)
      end
    end
  end

  _.isCancelling = false
end

function _.setBuyTask(itemID, maximumTotalQuantityToPutIntoAuctionHouse,
  maximumQuantityToPutIntoAuctionHouseAtATime,
  minimumSellPricePerUnit)
  minimumSellPricePerUnit = minimumSellPricePerUnit * 10000

  _.loadItem(itemID)
  local npcVendorSellPrice = select(11, GetItemInfo(itemID))
  if npcVendorSellPrice >= minimumSellPricePerUnit * (1 - _.AUCTION_HOUSE_CUT) then
    minimumSellPricePerUnit = _.removeCopper(npcVendorSellPrice /
      (1 - _.AUCTION_HOUSE_CUT) + 100)
    local itemLink = select(2, GetItemInfo(itemID))
    print("The minimum sell price per unit for " ..
      itemLink ..
      " was set lower than the NPC vendor sell price with consideration of the auction house cut (" ..
      (_.AUCTION_HOUSE_CUT * 100) ..
      "%). The minimum sell price has been automatically set to the lowest value where more profit can be made than selling the goods to the NPC vendor (" ..
      GetMoneyString(minimumSellPricePerUnit) ..
      "). If the goods are in for a price lower than this sell price, you can also consider to sell the goods directly to the NPC vendor.")
  end

  if not remainingQuantitiesToSell[itemID] then
    remainingQuantitiesToSell[itemID] = 0
  end
  remainingQuantitiesToSell[itemID] = maximumTotalQuantityToPutIntoAuctionHouse

  local task = {
    type = "sell",
    itemID = itemID,
    maximumTotalQuantityToPutIntoAuctionHouse =
      maximumTotalQuantityToPutIntoAuctionHouse,
    maximumQuantityToPutIntoAuctionHouseAtATime =
      maximumQuantityToPutIntoAuctionHouseAtATime,
    minimumSellPricePerUnit = minimumSellPricePerUnit,
  }
  _.setTask(task)
end

function _.setSellTask(itemID, maximumUnitPriceToBuyFor)
  local task = {
    type = "buy",
    itemID = itemID,
    maximumUnitPriceToBuyFor = maximumUnitPriceToBuyFor * 10000,
  }
  _.setTask(task)
end

function _.setTask(task)
  if not tasks[task.itemID] then
    tasks[task.itemID] = {}
  end

  tasks[task.itemID][task.type] = task
end

local isLoopRunning = false

function _.runLoop()
  if not isLoopRunning then
    MoneyMakingAssistant.isEnabled = true
    isLoopRunning = true

    print("Commodity buyer and seller process has started.")

    local isAuctionHouseOpen = AuctionHouseFrame:IsShown()

    local onAuctionHouseShowListener = Events.listenForEvent(
      "AUCTION_HOUSE_SHOW", function()
        isAuctionHouseOpen = true
      end)

    local onAuctionHouseClosedListener = Events.listenForEvent(
      "AUCTION_HOUSE_CLOSED", function()
        isAuctionHouseOpen = false
      end)

    local function keepRunning()
      return isAuctionHouseOpen and MoneyMakingAssistant.isEnabled
    end

    Coroutine.runAsCoroutineImmediately(function()
      while keepRunning() do
        if not _.isCancelling then
          for itemID, __ in pairs(tasks) do
            if not keepRunning() then
              break
            end

            local itemKey = { itemID = itemID, }
            C_AuctionHouse.SendSearchQuery(
              itemKey,
              sorts,
              true
            )
            local wasSuccessful, event, argument1 = Events
              .waitForOneOfEventsAndCondition(
                { "COMMODITY_SEARCH_RESULTS_UPDATED", "AUCTION_HOUSE_SHOW_ERROR", },
                function(self, event, argument1)
                  if event == "COMMODITY_SEARCH_RESULTS_UPDATED" then
                    local itemID = argument1
                    return itemID == itemKey.itemID
                  elseif event == "AUCTION_HOUSE_SHOW_ERROR" then
                    return true
                  end
                end, 3)

            if not keepRunning() then
              break
            end

            if event == "AUCTION_HOUSE_SHOW_ERROR" and argument1 == 10 then
              Events.waitForEvent("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
            elseif event == "COMMODITY_SEARCH_RESULTS_UPDATED" then
              local buyTask = tasks[itemID].buy
              if buyTask then
                local maximumUnitPriceToBuyFor = buyTask
                  .maximumUnitPriceToBuyFor

                local numberOfCommoditySearchResults = C_AuctionHouse
                  .GetNumCommoditySearchResults(itemID)
                local quantity = 0
                local moneyLeft = GetMoney()
                for index = 1, numberOfCommoditySearchResults do
                  local result = C_AuctionHouse.GetCommoditySearchResultInfo(
                    itemID, index)
                  if result.unitPrice <= maximumUnitPriceToBuyFor then
                    local buyableQuantity = math.min(result.quantity,
                      math.floor(moneyLeft / result.unitPrice))
                    quantity = quantity + buyableQuantity
                    moneyLeft = moneyLeft - buyableQuantity * result.unitPrice
                    if moneyLeft < maximumUnitPriceToBuyFor then
                      break
                    end
                  else
                    break
                  end
                end
                if quantity >= 1 then
                  local purchaseTask = {
                    itemID = itemID,
                    quantity = quantity,
                    maximumUnitPriceToBuyFor = maximumUnitPriceToBuyFor,
                  }
                  table.insert(purchaseTasks, purchaseTask)
                  _.workThroughPurchaseTasks()
                end
              end

              local sellTask = tasks[itemID].sell
              if sellTask then
                if Bags.hasItem(itemID) then
                  local maximumQuantityToPutIntoAuctionHouseAtATime = sellTask
                    .maximumQuantityToPutIntoAuctionHouseAtATime
                  local minimumSellPricePerUnit = sellTask
                    .minimumSellPricePerUnit

                  local unitPrice = _.determineUnitPrice(itemID)
                  if unitPrice then
                    if unitPrice >= minimumSellPricePerUnit then
                      local quantityAlreadyOnTopInAuctionHouse = _
                        .determineQuantityAlreadyOnTopInAuctionHouse(sellTask)
                      _.queueSellTaskAndWorkThroughSellTasks(sellTask, unitPrice,
                        quantityAlreadyOnTopInAuctionHouse)
                      if remainingQuantitiesToSell[itemID] == 0 or not Bags.hasItem(itemID) then
                        tasks[itemID].sell = nil
                      end
                    elseif _.isNewPriceFall(itemID, unitPrice) then
                      _.registerPriceFall(itemID, unitPrice)
                      _.loadItem(itemID)
                      local itemLink = select(2, GetItemInfo(itemID))
                      print(itemLink ..
                        " has fallen below the minimum sell price (" ..
                        GetMoneyString(unitPrice) ..
                        " < " .. GetMoneyString(minimumSellPricePerUnit) .. ").")
                    end
                  end
                else
                  tasks[itemID].sell = nil
                end
              end
            end
          end
        end

        Coroutine.yieldAndResume()
      end

      tasks = {}
      sellTasks = {}
      purchaseTasks = {}
      onAuctionHouseShowListener:stopListening()
      onAuctionHouseClosedListener:stopListening()
      isLoopRunning = false

      print("Commodity buyer and seller process has stopped.")
    end)
  end
end

function _.determineUnitPrice(itemID)
  local numberOfCommoditySearchResults = C_AuctionHouse
    .GetNumCommoditySearchResults(itemID)
  if numberOfCommoditySearchResults >= 1 then
    local result = C_AuctionHouse.GetCommoditySearchResultInfo(itemID, 1)
    if result then
      return result.unitPrice
    end
  end

  return nil
end

function _.determineQuantityAlreadyOnTopInAuctionHouse(task)
  local itemID = task.itemID
  local quantity = 0
  local numberOfCommoditySearchResults = C_AuctionHouse
    .GetNumCommoditySearchResults(itemID)
  for index = 1, numberOfCommoditySearchResults do
    local result = C_AuctionHouse.GetCommoditySearchResultInfo(itemID, index)
    if result.numOwnerItems == 0 then
      break
    end
    quantity = quantity + result.numOwnerItems
  end
  return quantity
end

function _.queueSellTaskAndWorkThroughSellTasks(task, unitPrice,
  quantityAlreadyOnTopInAuctionHouse)
  local itemID = task.itemID
  local quantityLeftToPutIntoAuctionHouse = math.min(
    remainingQuantitiesToSell[itemID], Bags.countItem(itemID),
    task.maximumQuantityToPutIntoAuctionHouseAtATime -
    quantityAlreadyOnTopInAuctionHouse)
  if quantityLeftToPutIntoAuctionHouse >= 1 then
    local sellTask = {
      itemID = itemID,
      quantity = quantityLeftToPutIntoAuctionHouse,
      unitPrice = unitPrice,
    }
    table.insert(sellTasks, sellTask)
    _.workThroughSellTasks()
  end
end

function _.workThroughSellTasks()
  while Array.hasElements(sellTasks) do
    local sellTask = table.remove(sellTasks, 1)
    local itemID = sellTask.itemID
    local quantity = sellTask.quantity
    local unitPrice = sellTask.unitPrice

    local containerIndex, slotIndex = Bags.findItem(itemID)
    if containerIndex and slotIndex then
      local item = ItemLocation:CreateFromBagAndSlot(containerIndex, slotIndex)
      local duration = 1
      -- TODO: Does it work if the item is distributed over multiple slots?
      local itemLink = C_Item.GetItemLink(item)
      print("Trying to put in " ..
        quantity ..
        " x " .. itemLink .. " (each for " .. GetMoneyString(unitPrice) .. ").")
      if MoneyMakingAssistant.showConfirmButton() then
        local requiresConfirmation = C_AuctionHouse.PostCommodity(item, duration,
          quantity, unitPrice)
        if requiresConfirmation then
          C_AuctionHouse.ConfirmPostCommodity(item, duration, quantity, unitPrice)
        end
        -- TODO: Events for error?
        local wasSuccessful = Events.waitForEvent(
          "AUCTION_HOUSE_AUCTION_CREATED", 3)
        if wasSuccessful then
          print("Have put in " ..
            quantity ..
            " x " ..
            itemLink .. " (each for " .. GetMoneyString(unitPrice) .. ").")
          remainingQuantitiesToSell[itemID] = math.max(
            remainingQuantitiesToSell[itemID] - quantity, 0)
        else
          print("Error putting in " .. quantity .. " x " .. itemLink .. ".")
        end
      end
    end
  end
end

confirmButton = CreateFrame("Button", nil, UIParent, "UIPanelButtonTemplate")
MoneyMakingAssistant.confirmButton = confirmButton
confirmButton:SetSize(144, 48)
confirmButton:SetText("Confirm")
confirmButton:SetPoint("CENTER", 0, 0)
confirmButton:SetScript("OnClick", function()
  MoneyMakingAssistant.confirm()
end)
confirmButton:SetFrameStrata("HIGH")
confirmButton:Hide()

function MoneyMakingAssistant.showConfirmButton()
  confirmButton:Show()
  MoneyMakingAssistant.thread = coroutine.running()
  local continue = coroutine.yield()
  return continue
end

function _.workThroughPurchaseTasks()
  while Array.hasElements(purchaseTasks) do
    local purchaseTask = table.remove(purchaseTasks, 1)
    local itemID = purchaseTask.itemID
    local quantity = purchaseTask.quantity
    local maximumUnitPriceToBuyFor = purchaseTask.maximumUnitPriceToBuyFor

    _.loadItem(itemID)
    local itemLink = select(2, GetItemInfo(itemID))
    print("Trying to buy " ..
      quantity ..
      " x " ..
      itemLink ..
      " (for a maximum unit price of " ..
      GetMoneyString(maximumUnitPriceToBuyFor) .. ").")
    if MoneyMakingAssistant.showConfirmButton() then
      C_AuctionHouse.StartCommoditiesPurchase(itemID, quantity)
      local wasSuccessful, event, unitPrice, totalPrice = Events
        .waitForOneOfEvents(
          { "COMMODITY_PRICE_UPDATED", "COMMODITY_PRICE_UNAVAILABLE", },
          3)
      if event == "COMMODITY_PRICE_UPDATED" then
        if unitPrice <= maximumUnitPriceToBuyFor then
          C_AuctionHouse.ConfirmCommoditiesPurchase(itemID, quantity)
          local wasSuccessful, event = Events.waitForOneOfEvents(
            { "COMMODITY_PURCHASE_SUCCEEDED", "COMMODITY_PURCHASE_FAILED", },
            3)
          if wasSuccessful and event == "COMMODITY_PURCHASE_SUCCEEDED" then
            print("Have bought " ..
              quantity ..
              " x " ..
              itemLink ..
              " (for a unit price of " .. GetMoneyString(unitPrice) .. ").")
          end
        end
      end
    end
  end
end

function _.loadItem(itemID)
  local item = Item:CreateFromItemID(itemID)
  if not item:IsItemDataCached() then
    local thread = coroutine.running()

    item:ContinueOnItemLoad(function()
      Coroutine.resumeWithShowingError(thread)
    end)

    coroutine.yield()
  end
end

function _.isCommodityItem(itemIdentifier)
  local classID, subclassID = select(6, GetItemInfoInstant(itemIdentifier))
  return (
    classID == Enum.ItemClass.Consumable or
    classID == Enum.ItemClass.Gem or
    classID == Enum.ItemClass.Tradegoods or
    classID == Enum.ItemClass.ItemEnhancement or
    classID == Enum.ItemClass.Questitem or
    (classID == Enum.ItemClass.Miscellaneous and subclassID ~= Enum.ItemMiscellaneousSubclass.Mount) or
    classID == Enum.ItemClass.Glyph or
    classID == Enum.ItemClass.Key
  )
end

function _.doIfIsCommodityOrShowInfoOtherwise(itemID, fn)
  if _.isCommodityItem(itemID) then
    fn()
  else
    _.showInfoThatItemSeemsToBeOfAnotherClassThanCommodities(itemID)
  end
end

function _.showInfoThatItemSeemsToBeOfAnotherClassThanCommodities(itemID)
  _.loadItem(itemID)
  local itemLink = select(2, GetItemInfo(itemID))
  print("Commodity buyer and seller currently only supports commodity items. " ..
    itemLink .. " (" .. itemID .. ") seems to be of another class.")
end

function _.isAuctionHouseOpen()
  return AuctionHouseFrame:IsShown()
end

function _.removeCopper(value)
  return math.floor(value / 100) * 100
end

local priceFalls = {}

function _.isNewPriceFall(itemID, unitPrice)
  return not priceFalls[itemID] or unitPrice < priceFalls[itemID]
end

function _.registerPriceFall(itemID, unitPrice)
  priceFalls[itemID] = unitPrice
end
