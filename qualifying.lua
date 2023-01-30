DEBUG = true
local sim = ac.getSim()
local cars = {}
local pcar = ac.getCar(0)



-- ON OFF TOGGLE FOR TEST
local enable = false
local activate = ac.OnlineEvent({
    key=ac.StructItem.key('F1O_Quali'),
    enable=ac.StructItem.boolean()
}, function (sender, message)
    if message.enable then
        enable = true
    else
        enable = false
    end
    ac.debug("enable", enable)
end)

local function sendActivate(bool)
    activate({enable=bool}, true)
end

ac.onChatMessage(function (message, senderCarIndex, senderSessionID)
    if message == "quali" and senderCarIndex == 0 and ac.getSim().isAdmin then
        sendActivate(true)
        return true
    elseif message == "ABORT" and senderCarIndex == 0 and ac.getSim().isAdmin then
        sendActivate(false)
        return true
    end
    return false
end)

ac.onSessionStart(function (sessionIndex, restarted)
    if restarted == false then
        enable = false 
    end
end)

-- REAL SCRIPT

local carsCount = sim.carsCount
local currentSession = "" -- start, Q1, Q2, Q3, finish

local leaderBoard = {}
for i=0, carsCount-1 do
    car = ac.getCar(i)
    leaderBoard[i] = {
        index = car.index,
        name = ac.getDriverName(car.index),
        time = nil,
        Q1 = false,
        Q2 = false,
        Q3 = false,
        pos = nil
    }
end

local function debug_leaderboard()
    for i=0, carsCount-1 do
        if leaderBoard[i].time ~= nil then
            ac.debug("leaderboard_time_"..i, leaderBoard[i].time)
        end
    end
end

local currentSessionCarsLapCount = {}
local function updateCarsLapCount()
    for k=0, sim.carsCount-1 do
        car = ac.getCar(k)
        currentSessionCarsLapCount[k] = car.lapCount
    end
end

local currentSessionCarsBestTime = {}

local function debug_updateCarsTime()
    currentSessionCarsBestTime[0] = 16
    for k=1, sim.carsCount-1 do
        car = ac.getCar(k)
        currentSessionCarsBestTime[k] = k
    end
end

local function updateCarsTime()
    for k=0, sim.carsCount-1 do
        car = ac.getCar(k)
        if car.lapCount > currentSessionCarsLapCount[k] then -- New Lap Registered
            if currentSessionCarsBestTime[k] == nil then -- no previous lap, register new lap
                currentSessionCarsBestTime[k] = car.previousLapTimeMs
            else -- check if new lap is better than the previous one
                currentSessionCarsBestTime[k] = math.min(car.previousLapTimeMs, currentSessionCarsBestTime[k])
            end
        end
    end
end

local function resetCarsBestTime()
    for k=0, sim.carsCount-1 do
        car = ac.getCar(k)
        currentSessionCarsBestTime[k] = nil
    end
end

local function computeLeaderboardSession()
    local carSlower = 0
    local ownBestLap = currentSessionCarsBestTime[0]
    if ownBestLap == nil then -- if user did not put a lap, he is always last
        return sim.carsCount
    end
    for k=0, sim.carsCount-1 do
        car = ac.getCar(k)
        if k ~= 0 then
            if currentSessionCarsBestTime[k] == nil then -- Opponent did not put a lap
                carSlower = carSlower + 1
            else
                if ownBestLap <= currentSessionCarsBestTime[k] then -- opponent did a lap, but slower
                    carSlower = carSlower + 1
                end
            end
        end
    end
    ac.debug("Computed position", sim.carsCount - carSlower)
    return sim.carsCount - carSlower
end

local currentPos = ac.OnlineEvent({
    ac.StructItem.key('F1O_Position'),
    pos = ac.StructItem.uint16(),
    time = ac.StructItem.double(),
}, function (sender, message)
    local index = sender.index
    leaderBoard[index].name = ac.getDriverName(index)
    leaderBoard[index].time = message.time
    leaderBoard[index].pos = message.pos
    ac.debug("Got from "..sender.index, "time:"..tostring(message.time)..", pos:"..tostring(message.pos))
end)

local alreadySent = {Q1 = {pos = nil, time = nil}, Q2 = {pos = nil, time = nil}, Q3 = {pos = nil, time = nil}}
local function send_currentPos()
    local pos = computeLeaderboardSession()
    local time = currentSessionCarsBestTime[0]
    if currentSession == "Q1" or currentSession == "Q2" or currentSession == "Q3" then
        if alreadySent[currentSession].pos ~= pos or alreadySent[currentSession].time ~= time then
            if currentPos({pos = pos, time = time}, true) then
                alreadySent[currentSession].pos = pos
                alreadySent[currentSession].time = time
                ac.debug("Position sent at sessuib "..tostring(currentSession), pos)
            end
        end
    end
end


-- local timeStartSessionMarker = {
--     Q1 = 1*60,
--     W1 = 19*60,
--     Q2 = 19*60+1,
--     W2 = 19*60+1 + 15*60,
--     Q3 = 19*60+1 + 15*60+1,
--     W3 = 19*60+1 + 15*60+1 + 12*60,
-- }

local min = 60
local connectionTime = 1
local overTime = 1
local stbTime = 1
local Q1time = 10
local Q2time = 5
local Q3time = 5

local timeStartSessionMarker = {
    start = connectionTime*min,
    Q1 = connectionTime*min + Q1time*min,
    Q1OT = connectionTime*min + Q1time*min + overTime*min,
    Q1END = connectionTime*min + Q1time*min + overTime*min + stbTime*min,
}

local currentGoThrough = {
    Q1 = false,
    Q2 = false,
    Q3 = false,
}


local function debug_currentGoThrough()
    ac.debug("Allowed out Q1", currentGoThrough.Q1)
    ac.debug("Allowed out Q2", currentGoThrough.Q2)
    ac.debug("Allowed out Q3", currentGoThrough.Q3)
end

local function lockInPit()
    car = ac.getCar(0)
    if not car.isInPitlane then
        physics.setCarPenalty(ac.PenaltyType.TeleportToPits, 0)
    end
end

local function timeLeftSession(time)
    if     currentSession == "W0" then
        return timeStartSessionMarker.Q1 - time
    elseif currentSession == "Q1" then
        return timeStartSessionMarker.W1 - time
    elseif currentSession == "W1" then
        return timeStartSessionMarker.Q2 - time
    elseif currentSession == "Q2" then
        return timeStartSessionMarker.W2 - time
    elseif currentSession == "W2" then
        return timeStartSessionMarker.Q3 - time
    elseif currentSession == "Q3" then
        return timeStartSessionMarker.W3 - time
    elseif currentSession == "W3" then
        return 0
    end
end

local first = true

function script.update(dt)
    if not enable then
        return
    end
    local time = - sim.timeToSessionStart / 1000
    if DEBUG then
        debug_leaderboard()
        ac.debug("TimeLeft", timeLeftSession(time))
        ac.debug("CurrentSession", currentSession)
        debug_currentGoThrough()
    end
    if (sim.raceSessionType ~= ac.SessionType.Qualify) and (sim.raceSessionType ~= ac.SessionType.Race) then
        return
    end

    if sim.raceSessionType == ac.SessionType.Race then
        -- Stuff to do on the race to reorder the grid
        return
    end

    if time < timeStartSessionMarker.start then -- before Q1
        lockInPit()
        updateCarsLapCount()
        physics.overrideRacingFlag(ac.FlagType.SessionSuspended)
    end
    if time < timeStartSessionMarker.Q1 then -- Q1
        currentSession = "Q1"
        physics.overrideRacingFlag(ac.FlagTypeNone)
    
    elseif time < timeStartSessionMarker.Q1OT then
        if first then
            physics.overrideRacingFlag(ac.FlagType.Finished)
            -- local lastLap = 
        end

    elseif time < timeStartSessionMarker.Q1END then
        currentSession = "Wait"
        physics.overrideRacingFlag(ac.FlagType.SessionSuspended)
        lockInPit()
        updateCarsLapCount()

    end
end

function script.drawUI()
    if not enable then
        return
    end
    if currentSession == "W1" or currentSession == "W2" or currentSession == "W3" then
        physics.overrideRacingFlag(ac.FlagType.Finished)
    end
end