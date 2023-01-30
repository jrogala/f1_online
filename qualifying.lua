DEBUG = true
local sim = ac.getSim()
local cars = {}
local pcar = ac.getCar(0)
local carsCount = sim.carsCount

local currentSession = ""

local leaderBoard = {}
for i=0, carsCount-1 do
    car = ac.getCar(i)
    leaderBoard[i] = {
        index = car.index,
        name = ac.getDriverName(car.index),
        time = nil,
        Q1 = false,
        Q2 = false,
        Q3 = false
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
    local carsInFront = 0
    local ownBestLap = currentSessionCarsBestTime[0]
    if ownBestLap == nil then -- if user did not put a lap, he is always last
        return 20
    end
    for k=0, sim.carsCount-1 do
        car = ac.getCar(k)
        if k ~= 0 then
            if currentSessionCarsBestTime[k] == nil then -- Opponent did not put a lap
                carsInFront = carsInFront + 1
            else
                if ownBestLap >= currentSessionCarsBestTime[k] then -- opponent did a lap, but slower
                    carsInFront = carsInFront + 1
                end
            end
        end
    end
    ac.debug("Computed position", carsInFront)
    return carsInFront
end

local currentPos = ac.OnlineEvent({
    ac.StructItem.key('F1O_Position'),
    pos = ac.StructItem.uint16(),
    time = ac.StructItem.double(),
}, function (sender, message)
    local index = sender.index
    leaderBoard[index].name = ac.getDriverName(index)
    leaderBoard[index].time = message.time
end)

local alreadySent = {Q1 = false, Q2 = false, Q3 = false}
local function send_currentPos()
    if not alreadySent[currentSession] then
        local pos = computeLeaderboardSession()
        local time = currentSessionCarsBestTime[0]
        if currentPos({pos = pos, time = time}, true) then
            alreadySent[currentSession] = true
            ac.debug("Position sent at time "..tostring(time), pos)
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

local min = 120
local timeStartSessionMarker = {
    Q1 = 1*min,
    W1 = 2*min,
    Q2 = 3*min,
    W2 = 4*min,
    Q3 = 5*min,
    W3 = 6*min,
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

local function lock(sessionName)
    car = ac.getCar(0)
    if sessionName == "Q1" then
        if not currentGoThrough.Q1 then
            -- Is locked
            if not car.isInPitlane then
                physics.setCarPenalty(ac.PenaltyType.TeleportToPits, 0)
            end
        end
    elseif sessionName == "Q2" then
        if not currentGoThrough.Q2 then
            -- Is locked
            if not car.isInPitlane then
                physics.setCarPenalty(ac.PenaltyType.TeleportToPits, 0)
            end
        end
    elseif sessionName == "Q3" then
        if not currentGoThrough.Q3 then
            -- Is locked
            if not car.isInPitlane then
                physics.setCarPenalty(ac.PenaltyType.TeleportToPits, 0)
            end
        end
    elseif sessionName == "W0" then
            -- Is locked
        if not car.isInPitlane then
            physics.setCarPenalty(ac.PenaltyType.TeleportToPits, 0)
        end
    elseif sessionName == "W1" then
        if not currentGoThrough.Q2 then
            -- Is locked
            if not car.isInPitlane then
                physics.setCarPenalty(ac.PenaltyType.TeleportToPits, 0)
            end
        end
    elseif sessionName == "W2" then
        if not currentGoThrough.Q3 then
            -- Is locked
            if not car.isInPitlane then
                physics.setCarPenalty(ac.PenaltyType.TeleportToPits, 0)
            end
        end
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

function script.update(dt)
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

    if currentSessionCarsLapCount[0] == nil then
        updateCarsLapCount()
    end

    local first = true

    if time < timeStartSessionMarker.Q1 then -- W0
        currentSession = "W0"
        currentGoThrough.Q1 = true
        currentGoThrough.Q2 = false
        currentGoThrough.Q3 = false
        lock(currentSession)
        updateCarsLapCount()
        if first then
            send_currentPos()
            first = false
        end

    elseif time < timeStartSessionMarker.W1 then -- Q1
        currentSession = "Q1"
        currentGoThrough.Q1 = true
        currentGoThrough.Q2 = false
        currentGoThrough.Q3 = false
        lock(currentSession)
        updateCarsTime()
        first = true


    elseif time < timeStartSessionMarker.Q2 then -- W1
        currentSession = "W1"
        if first then
            if computeLeaderboardSession() <= 15 then
                currentGoThrough.Q2 = true
            else
                send_currentPos()
            end
            first = false
        end
        lock(currentSession)
        updateCarsLapCount()
        resetCarsBestTime()

    elseif time < timeStartSessionMarker.W2 then -- Q2
        currentSession = "Q2"
        lock(currentSession)
        updateCarsTime()
        first = true

    elseif time < timeStartSessionMarker.Q3 then
        currentSession = "W2"
        lock(currentSession)
        if not currentGoThrough.Q3 then
            if computeLeaderboardSession() <= 10 then
                currentGoThrough.Q3 = true
            end
            updateCarsLapCount()
            resetCarsBestTime()
        end
        if first then
            send_currentPos()
            first = false
        end

    elseif time < timeStartSessionMarker.W3 then -- Q3
        currentSession = "Q3"
        lock(currentSession)
        updateCarsTime()
        first = true

    else
        currentSession = "W3"
        if first then
            send_currentPos()
            first = false
        end
        -- Send information for race
    end
end