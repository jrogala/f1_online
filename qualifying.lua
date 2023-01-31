DEBUG = true
local sim = ac.getSim()
local cars = {}
local pcar = ac.getCar(0)
local plap = pcar.lapCount

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
local currentSession = "" -- ST, Q1, Q2, Q3, EN


-- Self info
local bestTimeInfo = {Q1 = nil, Q2 = nil, Q3 = nil}

-- RealTime leaderboard for everyone
local leaderBoard = {}
for i=0, carsCount-1 do
    car = ac.getCar(i)
    leaderBoard[i] = {
        index = car.index,
        name = ac.getDriverName(car.index),
        Q1time = nil,
        Q2time = nil,
        Q3time = nil,
        Q1pos = nil,
        Q2pos = nil,
        Q3pos = nil
    }
end

local function debugLeaderboard()
    for i=0, carsCount-1 do
        ac.debug("Q1: Car at pos "..i, leaderBoard[i].name)
    end
end

local function orderLeaderboard(sessionName)
    if sessionName == "Q1" then
        table.sort(leaderBoard, function (a, b)
            if a.Q1time ~= nil and b.Q1time ~= nil then
                return a.Q1time < b.Q1time
            elseif a.Q1time ~= nil and b.Q1time == nil then
                return true
            elseif a.Q1time == nil and b.Q1time ~= nil then
                return false
            else
                return a.name < b.name --TODO: better than alphabetical order
            end
        end)
        for i=0, carsCount-1 do
            leaderBoard[i].Q1pos = i
        end
    end
    debugLeaderboard()
end

local function currentPlace(sessionName)
    for i=0, carsCount -1 do
        if leaderBoard[i].index == 0 then
            return leaderBoard[i].pos
        end
    end
    ac.debug("HUGE ERROR", "ERROR")
end


local lapTime = ac.OnlineEvent({
    ac.StructItem.key('F1O_sendLapTime'),
    bestTimeQ1 = ac.StructItem.double(),
    bestTimeQ2 = ac.StructItem.double(),
    bestTimeQ3 = ac.StructItem.double(),
}, function (sender, message)
    if message.bestTimeQ1 then
        leaderBoard[sender.index].Q1time = message.bestTimeQ1
        orderLeaderboard("Q1")
    end
    if message.bestTimeQ2 then
        leaderBoard[sender.index].Q2time = message.bestTimeQ2
        orderLeaderboard("Q2")
    end
    if message.bestTimeQ3 then
        leaderBoard[sender.index].Q3time = message.bestTimeQ3
        orderLeaderboard("Q3")
    end
end)

local function send_lapTime()
    lapTime({bestTimeInfo.Q1, bestTimeInfo.Q2, bestTimeInfo.Q3}, true)
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
local stbTime = .1
local Q1time = 2
local Q2time = 5
local Q3time = 5

local timeEndSessionMarker = {
    start = connectionTime*min,
    Q1 = connectionTime*min + Q1time*min,
    Q1OT = connectionTime*min + Q1time*min + overTime*min,
    Q1END = connectionTime*min + Q1time*min + overTime*min + stbTime*min,
}

local allowedOut = false
local overtime = false
local ending = false


local function debug_currentGoThrough()
    ac.debug("Allowed out", allowedOut)
end

local function lockInPit(currentSession)
    car = ac.getCar(0)
    if not car.isInPitlane and not allowedOut then
        physics.setCarPenalty(ac.PenaltyType.TeleportToPits, 0)
    end
end

local function timeLeftSession(time)
    if     currentSession == "ST" then
        return timeEndSessionMarker.start - time
    elseif currentSession == "Q1" then
        local remainingTime = timeEndSessionMarker.Q1 - time
        if remainingTime >= 0 then
            return remainingTime
        else
            return 0
        end
    end
end

local function onNewLap(car, currentSession)
    plap = car.lapCount
    if not pcar.isLastLapValid then -- last lap not valid so we remove it
        return
    end
    local prevBestLap = bestTimeInfo[currentSession]
    local currBestLap = pcar.previousLapTimeMs
    if currBestLap < prevBestLap then
        bestTimeInfo[currentSession] = currBestLap
        send_lapTime()
        orderLeaderboard("Q1")
    end
end

local first = true
function script.update(dt)
    if not enable then
        return
    end
    local time = - sim.timeToSessionStart / 1000
    local pcar = ac.getCar(0)
    if DEBUG then
        ac.debug("TimeLeft", timeLeftSession(time))
        ac.debug("CurrentSession", currentSession)
        ac.debug("CurrentSession overtime", overtime)
        ac.debug("CurrentSession ending", ending)
        ac.debug("Allowed out", allowedOut)
        debug_currentGoThrough()
    end
    if (sim.raceSessionType ~= ac.SessionType.Qualify) and (sim.raceSessionType ~= ac.SessionType.Race) then
        return
    end

    if sim.raceSessionType == ac.SessionType.Race then
        -- Stuff to do on the race to reorder the grid
        return
    end

    lockInPit()
    -- CurrentSession update
    if time < timeEndSessionMarker.start then -- before Q1
        currentSession = "ST"
        overtime = false
        ending = false
    elseif time < timeEndSessionMarker.Q1END then -- Q1
        currentSession = "Q1"
        if time < timeEndSessionMarker.Q1 then
            overtime = false
            ending = false
        elseif time < timeEndSessionMarker.Q1OT then
            overtime = true
            ending = false
        else
            ending = true
            overtime = false
        end
    -- elseif time < timeEndSessionMarker.Q2END then -- Q1
    --     currentSession = "Q2" 
    -- elseif time < timeEndSessionMarker.Q3END then -- Q1
    --     currentSession = "Q3"
    else
        currentSession = "FI"
    end

    -- reset at start
    if currentSession == "ST" then
        allowedOut = false
        lockInPit()
        physics.overrideRacingFlag(ac.FlagType.SessionSuspended)
    end
    if currentSession == "Q1" then
        if not overtime and not ending then
            allowedOut = true
            if pcar.isInPitlane then
                physics.overrideRacingFlag(ac.FlagType.Start)
            else
                physics.overrideRacingFlag(ac.FlagTypeNone)
            end
            if pcar.lapCount > plap then -- new lap routine
                onNewLap(pcar, currentSession)
            end
        end
        if overtime then
            if pcar.isInPitlane then
                physics.overrideRacingFlag(ac.FlagType.SessionSuspended)
            else
                physics.overrideRacingFlag(ac.FlagType.OneLapLeft)
            end
            if pcar.lapCount > plap then -- new lap routine
                allowedOut = false
                onNewLap(pcar, currentSession)
                physics.overrideRacingFlag(ac.FlagType.SessionSuspended)
            end
            lockInPit()
            return
        end
        if ending then
            allowedOut = false
            if pcar.isInPitlane then
                physics.overrideRacingFlag(ac.FlagType.SessionSuspended)
            else
                ac.debug("BIG ERROR", "SOMEONE ON TRACK DURING Q1END")
                physics.overrideRacingFlag(ac.FlagType.SessionSuspended)
            end
            if first then
                orderLeaderboard("Q1")
                first = false
                if currentPlace(currentSession) <= 15 then
                    allowedOut = true
                end
                currentSession = "Wait"
            end
            lockInPit()
            return
        end
    end
end

function script.drawUI()
    if not enable then
        return
    end
end