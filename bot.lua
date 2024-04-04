-- Initializing global variables to store the latest game state and game host process.
LatestGameState = LatestGameState or {}
InAction = false -- Prevents the agent from taking multiple actions at once.
BeingAttacked = false

local colors = {
    red = "\27[31m",
    green = "\27[32m",
    blue = "\27[34m",
    reset = "\27[0m",
    gray = "\27[90m",
    yellow = "\27[33m",
}

local function distance(x1, y1, x2, y2)
    return math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2)
end

local function inRange(x1, y1, x2, y2, range)
    return distance(x1, y1, x2, y2) <= range
end

local function getDirections(x1, y1, x2, y2)
    local dx, dy = x2 - x1, y2 - y1
    local dirX, dirY = "", ""
    if dx > 0 then dirX = "Right" else dirX = "Left" end
    if dy > 0 then dirY = "Down" else dirY = "Up" end
    return dirX, dirY
end

local function randomDirection()
    local directions = { "Up", "Down", "Left", "Right" }
    return directions[math.random(1, #directions)]
end

-- Game state analysis
local function analyzeGameState()
    local player = LatestGameState.Players[ao.id]
    local targets = {}

    for id, state in pairs(LatestGameState.Players) do
        if id ~= ao.id then
            local dist = distance(player.x, player.y, state.x, state.y)
            table.insert(targets, { id = id, state = state, dist = dist })
        end
    end

    table.sort(targets, function(a, b) return a.dist < b.dist end)
    return targets
end

-- Strategy decision-making
local function decideBestStrategy()
    local player = LatestGameState.Players[ao.id]
    local targets = analyzeGameState()

    -- Attack if a target is within range and has lower health
    for _, target in ipairs(targets) do
        if inRange(player.x, player.y, target.state.x, target.state.y, 1) and
            player.energy > target.state.energy then
            return "attack", target.id
        end
    end

    -- Retreat if low on health and being attacked
    if player.health < 20 and BeingAttacked then
        local retreatDir
        for _, target in ipairs(targets) do
            if target.dist <= 2 then
                retreatDir = getDirections(player.x, player.y, target.state.x, target.state.y)
                break
            end
        end
        return "retreat", retreatDir
    end

    -- Move towards the nearest target
    if #targets > 0 then
        local nearest = targets[1]
        local moveDir = getDirections(player.x, player.y, nearest.state.x, nearest.state.y)
        return "move", table.concat(moveDir, "")
    end

    -- No targets, move randomly
    return "random"
end

local function executeStrategy()
    local strategy, param = decideBestStrategy()

    if strategy == "attack" then
        print("Attacking player " .. param)
        ao.send({
            Target = Game,
            Action = "PlayerAttack",
            Player = ao.id,
            AttackEnergy = tostring(LatestGameState.Players[ao.id].energy)
        })
    elseif strategy == "retreat" then
        print("Retreating in direction: " .. param)
        ao.send({
            Target = Game,
            Action = "PlayerMove",
            Player = ao.id,
            Direction = param
        })
    elseif strategy == "move" then
        print("Moving towards target in direction: " .. param)
        ao.send({
            Target = Game,
            Action = "PlayerMove",
            Player = ao.id,
            Direction = param
        })
    else
        print("No targets, moving randomly")
        ao.send({
            Target = Game,
            Action = "PlayerMove",
            Player = ao.id,
            Direction = randomDirection()
        })
    end
end

-- Event handlers
Handlers.add("UpdateGameState", Handlers.utils.hasMatchingTag("Action", "GameState"), function(msg)
    local json = require("json")
    LatestGameState = json.decode(msg.Data)
    executeStrategy()
end)

Handlers.add("ReturnAttack", Handlers.utils.hasMatchingTag("Action", "Hit"), function(msg)
    BeingAttacked = true
    executeStrategy()
end)

Handlers.add("PrintAnnouncements", Handlers.utils.hasMatchingTag("Action", "Announcement"), function(msg)
    if msg.Event == "Started-Waiting-Period" then
        ao.send({
            Target = ao.id,
            Action = "AutoPay"
        })
    elseif (msg.Event == "Tick" or msg.Event == "Started-Game") and not InAction then
        InAction = true
        ao.send({ Target = Game, Action = "GetGameState" })
    elseif InAction then
        print("[PrintAnnouncements]Previous action still in progress. Skipping.")
    end
    print(colors.green .. msg.Event .. ": " .. msg.Data .. colors.reset)
end)

Handlers.add("GetGameStateOnTick", Handlers.utils.hasMatchingTag("Action", "Tick"), function()
    if not InAction then
        InAction = true
        print(colors.gray .. "Getting game state..." .. colors.reset)
        ao.send({ Target = Game, Action = "GetGameState" })
    else
        print("[GetGameStateOnTick]Previous action still in progress. Skipping.")
    end
end)

Handlers.add("AutoPay", Handlers.utils.hasMatchingTag("Action", "AutoPay"), function(msg)
    print("Auto-paying confirmation fees.")
    ao.send({ Target = Game, Action = "Transfer", Recipient = Game, Quantity = "1000" })
end)

Game = "bmgDDTk5sJk7ohDidto3Vmm-ur2BopjJtmX0mVYF-ig"

Send({ Target = Game, Action = "Register" })
