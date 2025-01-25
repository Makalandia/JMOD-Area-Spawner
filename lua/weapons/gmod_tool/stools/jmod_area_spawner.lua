-- lua/weapons/gmod_tool/stools/jmod_area_spawner.lua

TOOL.Category = "Construction"
TOOL.Name = "JMod Area Spawner"

if CLIENT then
    language.Add("tool.jmod_area_spawner.name", "JMod Area Spawner")
    language.Add("tool.jmod_area_spawner.desc", "Spawns predefined areas with entities")
    language.Add("tool.jmod_area_spawner.0", "Left-click to set the first point, right-click to set the second point and spawn objects")
    language.Add("tool.jmod_area_spawner.hideborders", "Не отображать границу зоны")
    language.Add("tool.jmod_area_spawner.spawninterval", "Интервал времени для спавна (в секундах)")
    language.Add("tool.jmod_area_spawner.maxobjects", "Максимальное количество объектов в зоне")
    language.Add("tool.jmod_area_spawner.spawnobject", "Объекты для спавна (разделенные точкой с запятой и пробелом)")
    language.Add("tool.jmod_area_spawner.npcweapon", "Оружие для НИПов")
    language.Add("tool.jmod_area_spawner.clearobjects", "Удалить все объекты")
    language.Add("tool.jmod_area_spawner.pausespawn", "Приостановить спавн")
    language.Add("tool.jmod_area_spawner.resumespawn", "Продолжить спавн")
    language.Add("tool.jmod_area_spawner.spawnchance", "Шанс спавна (0%-100%)")
end

TOOL.ClientConVar["zone"] = "Area1"
TOOL.ClientConVar["hideborders"] = "0"
TOOL.ClientConVar["spawninterval"] = "10"
TOOL.ClientConVar["maxobjects"] = "10"
TOOL.ClientConVar["spawnobject"] = ""
TOOL.ClientConVar["npcweapon"] = "weapon_smg1" -- Оружие по умолчанию для НИПов
TOOL.ClientConVar["spawnchance"] = "100" -- Шанс спавна по умолчанию 100%

TOOL.Point1 = nil
TOOL.Point2 = nil
TOOL.SpawnTimers = {} -- Таблица для хранения таймеров
TOOL.SpawnedEntities = {}
TOOL.SpawnPaused = false -- Флаг для отслеживания состояния спавна

function TOOL:LeftClick(trace)
    if CLIENT then return true end

    local ply = self:GetOwner()
    if not IsValid(ply) then return false end

    self.Point1 = trace.HitPos
    ply:ChatPrint("First point set at: " .. tostring(self.Point1))
    return true
end

function TOOL:RightClick(trace)
    if CLIENT then return true end

    local ply = self:GetOwner()
    if not IsValid(ply) then return false end

    self.Point2 = trace.HitPos
    ply:ChatPrint("Second point set at: " .. tostring(self.Point2))

    if self.Point1 and self.Point2 then
        self:SpawnEntitiesAndMarkers()
        self.Point1 = nil
        self.Point2 = nil
    end

    return true
end

function TOOL:SpawnEntitiesAndMarkers()
    local ply = self:GetOwner()
    if not IsValid(ply) then return end

    local selectedZone = self:GetClientInfo("zone")
    local hideBorders = self:GetClientNumber("hideborders") == 1
    local spawnInterval = self:GetClientNumber("spawninterval")
    local maxObjects = self:GetClientNumber("maxobjects")
    local spawnObjects = self:GetClientInfo("spawnobject")
    local npcWeapon = self:GetClientInfo("npcweapon")
    local spawnChance = self:GetClientNumber("spawnchance")

    if selectedZone == "Custom zone" and spawnObjects == "" then
        ply:ChatPrint("Please specify objects to spawn in the custom zone!")
        return
    end

    local area = nil

    if selectedZone ~= "Custom zone" then
        for _, a in ipairs(spawnareas) do
            if a.name == selectedZone then
                area = a
                break
            end
        end

        if not area then
            ply:ChatPrint("Invalid area selected!")
            return
        end
    end

    local min = Vector(math.min(self.Point1.x, self.Point2.x), math.min(self.Point1.y, self.Point2.y), math.min(self.Point1.z, self.Point2.z))
    local max = Vector(math.max(self.Point1.x, self.Point2.x), math.max(self.Point1.y, self.Point2.y), math.max(self.Point1.z, self.Point2.z))

    -- Создаем пропы для отображения границ зоны
    local marker1 = self:CreateMarker(min, hideBorders)
    local marker2 = self:CreateMarker(max, hideBorders)

    -- Создаем энтити для зоны
    local zoneEnt = ents.Create("prop_physics")
    zoneEnt:SetModel("models/hunter/blocks/cube025x025x025.mdl") -- Модель не важна, так как мы её скрываем
    zoneEnt:SetPos((min + max) / 2)
    zoneEnt:SetNoDraw(true) -- Скрываем модель
    zoneEnt:Spawn()

    -- Включаем коллизию для зоны только относительно мира, но не игроков
    zoneEnt:SetCollisionGroup(COLLISION_GROUP_WORLD)

    -- Замораживаем физику зоны
    local phys = zoneEnt:GetPhysicsObject()
    if IsValid(phys) then
        phys:EnableMotion(false) -- Замораживаем физику
    end

    -- Присоединяем маркеры к зоне
    if IsValid(marker1) then marker1:SetParent(zoneEnt) end
    if IsValid(marker2) then marker2:SetParent(zoneEnt) end

    -- Инициализируем таблицу для хранения заспавненных объектов
    self.SpawnedEntities[zoneEnt] = self.SpawnedEntities[zoneEnt] or {}

    -- Спавним объекты внутри зоны
    self:SpawnObjectsInZone(area, min, max, zoneEnt, maxObjects, spawnObjects, npcWeapon, spawnChance)

    -- Добавляем таймер для периодического спавна объектов
    local timerName = "JModAreaSpawner_Timer_" .. zoneEnt:EntIndex()
    self.SpawnTimers[zoneEnt:EntIndex()] = timerName
    timer.Create(timerName, spawnInterval, 0, function()
        if not IsValid(zoneEnt) or self.SpawnPaused then
            return
        end
        self:SpawnObjectsInZone(area, min, max, zoneEnt, maxObjects, spawnObjects, npcWeapon, spawnChance)
    end)

    -- Добавляем возможность удаления зоны по клавише Z
    undo.Create("JMod Area Zone")
    undo.AddEntity(zoneEnt)
    undo.SetPlayer(ply)
    undo.Finish()
end

function TOOL:SpawnObjectsInZone(area, min, max, zoneEnt, maxObjects, spawnObjects, npcWeapon, spawnChance)
    -- Удаляем невалидные объекты из таблицы
    self.SpawnedEntities[zoneEnt] = self.SpawnedEntities[zoneEnt] or {}
    for i = #self.SpawnedEntities[zoneEnt], 1, -1 do
        if not IsValid(self.SpawnedEntities[zoneEnt][i]) then
            table.remove(self.SpawnedEntities[zoneEnt], i)
        end
    end

    -- Проверяем, достигнуто ли максимальное количество объектов
    if #self.SpawnedEntities[zoneEnt] >= maxObjects then
        return
    end

    local items = area and area.items or string.Split(spawnObjects, "; ")

    for _, item in ipairs(items) do
        if #self.SpawnedEntities[zoneEnt] >= maxObjects then
            break
        end

        -- Проверяем шанс спавна
        if math.random(100) > spawnChance then
            -- Пропускаем текущую итерацию, если шанс спавна не выпал
            goto skip_spawn
        end

        -- Поднимаем позицию спавна на 50 юнитов вверх
        local pos = Vector(math.random(min.x, max.x), math.random(min.y, max.y), math.random(min.z, max.z) + 50)
        local angle = Angle(0, math.random(0, 360), 0) -- Случайный угол поворота в плоскости XY

        local ent
        if item:sub(-4) == ".mdl" then
            -- Спавним пропы
            ent = ents.Create("prop_physics")
            ent:SetModel(item)
        elseif string.match(item, "^npc_") then
            -- Спавним NPC
            ent = ents.Create(item)
            ent:SetKeyValue("additionalequipment", npcWeapon)
        elseif item == "Seat_Airboat" then
            -- Спавним сиденье
            ent = ents.Create("prop_vehicle_prisoner_pod")
            ent:SetModel("models/nova/airboat_seat.mdl")
            ent:SetKeyValue("vehiclescript", "scripts/vehicles/prisoner_pod.txt")
        elseif item == "Jeep" then
            -- Спавним транспортное средство Jeep
            ent = ents.Create("prop_vehicle_jeep")
            ent:SetModel("models/buggy.mdl")
            ent:SetKeyValue("vehiclescript", "scripts/vehicles/jeep_test.txt")
        else
            -- Спавним другие энтити
            ent = ents.Create(item)
        end

        if IsValid(ent) then
            ent:SetPos(pos)
            ent:SetAngles(angle) -- Устанавливаем случайный угол поворота
            ent:Spawn()

            table.insert(self.SpawnedEntities[zoneEnt], ent)
        else
            print("Failed to create entity of type " .. item)
        end

        ::skip_spawn::
    end
end

-- Добавляем функцию для удаления всех объектов, созданных всеми зонами
function TOOL:ClearAllSpawnedEntities()
    for _, entities in pairs(self.SpawnedEntities) do
        for _, ent in ipairs(entities) do
            if IsValid(ent) then
                ent:Remove()
            end
        end
    end
end

-- Добавляем функции для приостановки и продолжения спавна
function TOOL:PauseSpawning()
    self.SpawnPaused = true
end

function TOOL:ResumeSpawning()
    self.SpawnPaused = false
end

function TOOL:CreateMarker(pos, hideBorders)
    local marker = ents.Create("prop_physics")
    marker:SetModel("models/hunter/blocks/cube025x025x025.mdl")
    marker:SetPos(pos)
    marker:Spawn()
    marker:SetCollisionGroup(COLLISION_GROUP_WORLD) -- Отключаем коллизию для маркеров
    marker:SetRenderMode(RENDERMODE_TRANSCOLOR)
    marker:SetColor(Color(255, 0, 0, 150)) -- Полупрозрачный красный цвет
    if hideBorders then
        marker:SetNoDraw(true) -- Скрываем маркеры, если выбрано
    end
    return marker
end

function TOOL.BuildCPanel(CPanel)
    CPanel:AddControl("Header", { Description = "Spawns predefined areas with entities" })

    local zoneList = vgui.Create("DComboBox", CPanel)
    zoneList:SetValue("Select Zone")
    zoneList:AddChoice("Custom zone") -- Добавляем пункт для пользовательской зоны
    for _, area in ipairs(spawnareas) do
        zoneList:AddChoice(area.name)
    end

    zoneList.OnSelect = function(panel, index, value)
        RunConsoleCommand("jmod_area_spawner_zone", value)
    end

    CPanel:AddItem(zoneList)

    -- Добавляем чекбокс для скрытия границ зоны
    CPanel:AddControl("Checkbox", {
        Label = "#tool.jmod_area_spawner.hideborders",
        Command = "jmod_area_spawner_hideborders"
    })

    -- Добавляем поле для ввода времени спавна
    CPanel:AddControl("Slider", {
        Label = "#tool.jmod_area_spawner.spawninterval",
        Command = "jmod_area_spawner_spawninterval",
        Type = "Float",
        Min = "1",
        Max = "60"
    })

    -- Добавляем поле для ввода максимального количества объектов
    CPanel:AddControl("Slider", {
        Label = "#tool.jmod_area_spawner.maxobjects",
        Command = "jmod_area_spawner_maxobjects",
        Type = "Int",
        Min = "1",
        Max = "100"
    })

    -- Добавляем поле для ввода объектов спавна для пользовательской зоны
    CPanel:AddControl("TextBox", {
        Label = "#tool.jmod_area_spawner.spawnobject",
        Command = "jmod_area_spawner_spawnobject",
        MaxLength = "256",
    })

    -- Добавляем поле для ввода оружия для НИПов
    CPanel:AddControl("TextBox", {
        Label = "#tool.jmod_area_spawner.npcweapon",
        Command = "jmod_area_spawner_npcweapon",
        MaxLength = "256",
    })

    -- Добавляем поле для ввода шанса спавна
    CPanel:AddControl("Slider", {
        Label = "#tool.jmod_area_spawner.spawnchance",
        Command = "jmod_area_spawner_spawnchance",
        Type = "Int",
        Min = "0",
        Max = "100"
    })

    -- Добавляем кнопку для удаления всех объектов
    CPanel:AddControl("Button", {
        Label = "#tool.jmod_area_spawner.clearobjects",
        Command = "jmod_area_spawner_clearobjects",
        Text = "Удалить все объекты",
    })

    -- Добавляем кнопку для приостановки спавна
    CPanel:AddControl("Button", {
        Label = "#tool.jmod_area_spawner.pausespawn",
        Command = "jmod_area_spawner_pausespawn",
        Text = "Приостановить спавн",
    })

    -- Добавляем кнопку для продолжения спавна
    CPanel:AddControl("Button", {
        Label = "#tool.jmod_area_spawner.resumespawn",
        Command = "jmod_area_spawner_resumespawn",
        Text = "Продолжить спавн",
    })
end

-- Обрабатываем команды для удаления всех объектов, приостановки и продолжения спавна
if SERVER then
    concommand.Add("jmod_area_spawner_clearobjects", function(ply, cmd, args)
        if IsValid(ply) and ply:IsAdmin() then
            local tool = ply:GetWeapon("gmod_tool").Tool["jmod_area_spawner"]
            if tool then
                tool:ClearAllSpawnedEntities()
                ply:ChatPrint("All spawned entities have been removed.")
            else
                ply:ChatPrint("Failed to find the JMod Area Spawner tool.")
            end
        else
            ply:ChatPrint("You do not have permission to use this command.")
        end
    end)

    concommand.Add("jmod_area_spawner_pausespawn", function(ply, cmd, args)
        if IsValid(ply) and ply:IsAdmin() then
            local tool = ply:GetWeapon("gmod_tool").Tool["jmod_area_spawner"]
            if tool then
                tool:PauseSpawning()
                ply:ChatPrint("Spawning has been paused.")
            else
                ply:ChatPrint("Failed to find the JMod Area Spawner tool.")
            end
        else
            ply:ChatPrint("You do not have permission to use this command.")
        end
    end)

    concommand.Add("jmod_area_spawner_resumespawn", function(ply, cmd, args)
        if IsValid(ply) and ply:IsAdmin() then
            local tool = ply:GetWeapon("gmod_tool").Tool["jmod_area_spawner"]
            if tool then
                tool:ResumeSpawning()
                ply:ChatPrint("Spawning has been resumed.")
            else
                ply:ChatPrint("Failed to find the JMod Area Spawner tool.")
            end
        else
            ply:ChatPrint("You do not have permission to use this command.")
        end
    end)
end