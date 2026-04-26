--[[
0.9.2
	- new: Cluster's trajectory management with wind corretions, server mode and local mode, munitions tested BLU-108 BLU-97Band MK 118 (CBU-99) only
	- fix clustor box axe calculation
	- fix multi-cluster trajectory management (deepcopy)
	- begining of inline documentation
	- fix life request for scenary objects

0.9.1
	- new: Cluster's trajectory management, munitions tested BLU-108 only
	- fix clustor box
	- added dispersion of clusters extended depending of the altitude

0.9.0
	mains additions for this 1st version.
	- new: Munition type management and behaviour according of his category and subcategory, except guns
	- new: Blast wave management rewrited with Kingery-Bulmashis data algorythms.
	- new: Optimization of the radius effect depending of the ground unit attribute (vehicle or infantry)
	- new: Damages are apply to vehicles in addition to the infantry ground units
	- new: Cluster's trajectory management and carpet of bomblets simulation with increased damages, with wind corretions
	- new: Statistics management for global shot, hit, ect... and Pilots statistics
	- new: Telemetry feature from the shot to the hit including trajecttory datas, stored in csv file
	- new: Log file used to store the informations of Blast Damage execution
	- new: Exclusion area management to define areas where no effect must be applied (circle and polygon)
 	- internal : complete code rewrite
--]]


do
	local blast = nil
	
	---@class vec3
	---@field x number
	---@field y number
	---@field z number
	local vec3 = {}

	---@class BLAST Damage
	BLAST = {
		className_ = "BLAST", -- class name
		exclusionAreas = {}, -- list of zone where effects are excluded
		trackedWeapons = {}, -- list of tracked weapons (mainly bombs)
		trackedClusters = {}, -- list of tracked clusters (only clusters)
		hTrackWeapons = false, -- store the handle of the scheduled function trackWeapons
		hTrackClusters = false, -- store the handle of the scheduled function trackClusters
		startTime = 0,    -- time to start measures
		windStep = 100,   -- meters between 2 measures of wind

		-- menus
		mnuMain = nil,                     -- add the main menu
		mnuState = { ON = nil, OFF = nil }, -- add a menu enable/disable
		mnuDebug = { ON = nil, OFF = nil }, -- add a menu enable/disable debug mode
		mnuMsgInGame = { ON = nil, OFF = nil }, -- add a menu to enable/disable messages in game
		mnuStatistics = { ON = nil, OFF = nil }, -- add a menu to enable/disable messages in game

		isMultiPlayer = false,             -- false when the script is running in local mode
		version = "0.9.2",                 -- current version
	}
	BLAST.__index = BLAST

	----[[ ##### SCRIPT CONFIGURATION ##### ]]----
	---@class BLAST.options
	BLAST.options = {
		explosionsManaged = true, -- enable enhanced explosions management
		blastwaveManaged = true,  -- enable blast wave management
		clusterManaged = true,    -- enable cluster management
		trajectory = false,       -- 2 methods : trajectory or cluster detection

		blastDiffusionDelay = 10, -- speed of the effect from the center of explosion to the peripheral (10 = 0.1 sec/meter)

		staticBoost = 1.0,        -- apply extra damage to Unit.Category.STRUCTURE
		sceneryBoost = 2.0,       -- apply extra damage to Unit.Category.SCENERY
		rocketBoost = 2.0,        -- apply a coefficient of power for rockets

		flareVisualEffect = true, -- activate visual effect of white flare, consumes a lot of resources
		flareNumber = 2,          -- number of flare effect (more = less fps)

		areasPattern = "#BLAST#", -- tag contained in the name of an exclusion aera

		damageManaged = true,     -- allow blast wave to affect ground unit movement and fire
		vehicleMovementThreshold = 70, -- below the threshold the movements are disabled to simulate severe injury
		vehicleFireThreshold = 80, -- below the threshold the ROE are set to ON HOLD to simulate severe injury
		infantryMovementThreshold = 70, -- below the threshold the movements are disabled to simulate severe injury
		infantryFireThreshold = 80, -- below the threshold the ROE are set to ON HOLD to simulate severe injury

		-- timer management, do not set value below 0.01s, change carrefuly the default values
		timerOnShot = 0.05, -- each 0.05s S_EVENT_SHOT event is checked
		timerOnTrack = 0.05, -- delay between 2 checks of weapons tracked, do not set a too much long time

		-- debug mode
		debugManaged = false,            -- enable trace log
		msgInGame = false,               -- enable messages in game for players
		msgStatistics = true,            -- log for statistics

		smoke = false,                    -- show a smoke for the impact point or zones
		smokeColor = trigger.smokeColor.White, -- available colors : Green Red White Orange Blue


		-- telemetry to trace munitions between start tracking and when DCS destroy munition
		telemetryManaged = false, -- if telemetry enabled, you have to unsanitize "lfs" in MissionScript.lua
		telemetryFilename = "bd_telemetry.csv",
		hTelemetry = false, -- file handle to store datas from telemetry

		-- state of blast damage
		state = false, -- true when script is active, at the start it's false. let it to false
		startAuto = true -- start automatically when state is false with the mission
	}

	-- store statistics usage
	BLAST.stats = {
		-- statistics by weapons and units
		weapons = {}, -- list of weapons tracked during the mission
		weaponsOther = {}, -- list of weapons not tracked during the mission
		players = {}, -- statistics by players
		targets = {}, -- list of units killed

		-- global statistics
		shotCount = 0,   -- number of shots for existing weapons
		trackCount = 0,  -- number of tracked weapons
		otherCount = 0,  -- number of weapons excluded of the tracking
		hitCount = 0,    -- number of direct hits for existing weapons
		blastCount = 0,  -- number of objects hits by the blast effect
		killCount = 0,   -- number of objects kill (for DCS bda)
		deadCount = 0,   -- number of objects dead (for DCS and blast)
		weaponHoldCount = 0, -- number of objects having damages with ROE = Weapon hold
		movementHoldCount = 0, -- number of objects having damages with movements hold
	}

	-- munitions: bombs, missiles and rockets, for each munition type the value of equivalent TNT
	-- new means that this munitions was not present at the origin (splash)
	-- 0 means that there is no explosive charge, AGM-154A for example
	BLAST.weapons = {
		-- bombs
		["250-2"] = { category = Weapon.Category.BOMB, TNTe = 80 },   -- New, China Asset Pack by Deka Ironwork Simulations and Eagle Dynamics
		["250-3"] = { category = Weapon.Category.BOMB, TNTe = 80 },   -- New, China Asset Pack by Deka Ironwork Simulations and Eagle Dynamics
		["AB_250_2_SD_10A"] = { category = Weapon.Category.BOMB, TNTe = 0.12 }, -- New, World War II AI Units by Eagle Dynamics
		["AB_250_2_SD_2"] = { category = Weapon.Category.BOMB, TNTe = 0.12 }, -- New, World War II AI Units by Eagle Dynamics
		["AB_500_1_SD_10A"] = { category = Weapon.Category.BOMB, TNTe = 0.9 }, -- New, World War II AI Units by Eagle Dynamics
		["AGM_62"] = { category = Weapon.Category.BOMB, TNTe = 400 },
		["AGM_62_I"] = { category = Weapon.Category.BOMB, TNTe = 149.6 }, -- New
		["AN_M30A1"] = { category = Weapon.Category.BOMB, TNTe = 45 }, -- ("AN-M30A1 - 100lb GP Bomb LD")
		["AN_M57"] = { category = Weapon.Category.BOMB, TNTe = 100 }, -- ("AN-M57 - 250lb GP Bomb LD")
		["AN_M64"] = { category = Weapon.Category.BOMB, TNTe = 121 }, -- New
		["AN_M65"] = { category = Weapon.Category.BOMB, TNTe = 400 }, -- ("AN-M65 - 1000lb GP Bomb LD")
		["AN_M66"] = { category = Weapon.Category.BOMB, TNTe = 800 }, -- ("AN-M66 - 2000lb GP Bomb LD")
		["KMGU_2_AO_2_5RT"] = { category = Weapon.Category.BOMB, TNTe = 1.2 }, -- New
		["BAP_100"] = { category = Weapon.Category.BOMB, TNTe = 3.5 }, -- New
		["BAP-100"] = { category = Weapon.Category.BOMB, TNTe = 3.5 }, -- New
		["BAP-120"] = { category = Weapon.Category.BOMB, TNTe = 10.8 }, -- New
		["BDU_33"] = { category = Weapon.Category.BOMB, TNTe = 0 },   -- New
		["BDU_45"] = { category = Weapon.Category.BOMB, TNTe = 0 },   -- New
		["BDU_45B"] = { category = Weapon.Category.BOMB, TNTe = 0 },  -- New
		["BDU_45LGB"] = { category = Weapon.Category.BOMB, TNTe = 0 }, -- New
		["BDU_50HD"] = { category = Weapon.Category.BOMB, TNTe = 0 }, -- New
		["BDU_50LD"] = { category = Weapon.Category.BOMB, TNTe = 0 }, -- New
		["BDU_50LGB"] = { category = Weapon.Category.BOMB, TNTe = 0 }, -- New
		["BEER_BOMB"] = { category = Weapon.Category.BOMB, TNTe = 1 }, -- New
		["BELOUGA"] = { category = Weapon.Category.BOMB, TNTe = 94 }, -- New
		["BETAB-500M"] = { category = Weapon.Category.BOMB, TNTe = 551.6 }, -- New
		["BETAB-500S"] = { category = Weapon.Category.BOMB, TNTe = 280 }, -- New
		["BIN_200"] = { category = Weapon.Category.BOMB, TNTe = 20 }, -- New
		["BKF_AO2_5RT"] = { category = Weapon.Category.BOMB, TNTe = 1.2 }, -- New
		["BKF_PTAB2_5KO"] = { category = Weapon.Category.BOMB, TNTe = 0.65 }, -- New
		["BLG66"] = { category = Weapon.Category.BOMB, TNTe = 94 },   -- New
		["BLG66_BELOUGA"] = { category = Weapon.Category.BOMB, TNTe = 32 },
		["BLU-3B_GROUP"] = { category = Weapon.Category.BOMB, TNTe = 0.17 }, -- New
		["BLU-3_GROUP"] = { category = Weapon.Category.BOMB, TNTe = 0.17 }, -- New
		["BL_755"] = { category = Weapon.Category.BOMB, TNTe = 0.5 }, -- New
		["BR_250"] = { category = Weapon.Category.BOMB, TNTe = 118 },
		["BR_500"] = { category = Weapon.Category.BOMB, TNTe = 118 },
		["BetAB_500"] = { category = Weapon.Category.BOMB, TNTe = 98 },
		["BetAB_500ShP"] = { category = Weapon.Category.BOMB, TNTe = 107 },
		["British_AP_25LBNo1_3INCHNo1"] = { category = Weapon.Category.BOMB, TNTe = 4 }, -- ("RP-3 25lb AP Mk.I")
		["British_GP_250LB_Bomb_Mk1"] = { category = Weapon.Category.BOMB, TNTe = 100 }, -- ("250 lb GP Mk.I")
		["British_GP_250LB_Bomb_Mk4"] = { category = Weapon.Category.BOMB, TNTe = 100 }, -- ("250 lb GP Mk.IV")
		["British_GP_250LB_Bomb_Mk5"] = { category = Weapon.Category.BOMB, TNTe = 100 }, -- ("250 lb GP Mk.V")
		["British_GP_500LB_Bomb_Mk1"] = { category = Weapon.Category.BOMB, TNTe = 213 }, -- ("500 lb GP Mk.I")
		["British_GP_500LB_Bomb_Mk4"] = { category = Weapon.Category.BOMB, TNTe = 213 }, -- ("500 lb GP Mk.IV")
		["British_GP_500LB_Bomb_Mk4_Short"] = { category = Weapon.Category.BOMB, TNTe = 213 }, -- ("500 lb GP Short tail")
		["British_GP_500LB_Bomb_Mk5"] = { category = Weapon.Category.BOMB, TNTe = 213 }, -- ("500 lb GP Mk.V")
		["British_HE_60LBSAPNo2_3INCHNo1"] = { category = Weapon.Category.BOMB, TNTe = 4 }, -- ("RP-3 60lb SAP No2 Mk.I")
		["British_HE_60LBFNo1_3INCHNo1"] = { category = Weapon.Category.BOMB, TNTe = 4 }, -- ("RP-3 60lb F No1 Mk.I")
		["British_MC_250LB_Bomb_Mk1"] = { category = Weapon.Category.BOMB, TNTe = 100 }, -- ("250 lb MC Mk.I")
		["British_MC_250LB_Bomb_Mk2"] = { category = Weapon.Category.BOMB, TNTe = 100 }, -- ("250 lb MC Mk.II")
		["British_MC_500LB_Bomb_Mk1_Short"] = { category = Weapon.Category.BOMB, TNTe = 213 }, -- ("500 lb MC Short tail")
		["British_MC_500LB_Bomb_Mk2"] = { category = Weapon.Category.BOMB, TNTe = 213 }, -- ("500 lb MC Mk.II")
		["British_SAP_250LB_Bomb_Mk5"] = { category = Weapon.Category.BOMB, TNTe = 100 }, -- ("250 lb S.A.P.")
		["British_SAP_500LB_Bomb_Mk5"] = { category = Weapon.Category.BOMB, TNTe = 213 }, -- ("500 lb S.A.P.")
		["CBU_103"] = { category = Weapon.Category.BOMB, TNTe = 0 },                 -- New
		["CBU_105"] = { category = Weapon.Category.BOMB, TNTe = 0 },                 -- New
		["CBU_52B"] = { category = Weapon.Category.BOMB, TNTe = 0 },

		["CBU_87"] = { category = Weapon.Category.BOMB, flare = true, clusterName = "BLU-97B" },
		["CBU_97"] = { category = Weapon.Category.BOMB, flare = true, clusterName = "BLU-108" },
		["CBU_99"] = { category = Weapon.Category.BOMB, flare = true, clusterName = "BLU-108" },
		["ROCKEYE"] = { category = Weapon.Category.BOMB, flare = true, clusterName = "Mk 118" },

		["Durandal"] = { category = Weapon.Category.BOMB, TNTe = 320 }, -- New
		["FAB-250-M62"] = { category = Weapon.Category.BOMB, TNTe = 80 }, -- New
		["FAB-250M54"] = { category = Weapon.Category.BOMB, TNTe = 226 }, -- New
		["FAB_250M54TU"] = { category = Weapon.Category.BOMB, TNTe = 100 },
		["FAB_500M54"] = { category = Weapon.Category.BOMB, TNTe = 428 }, -- New
		["FAB_500M54TU"] = { category = Weapon.Category.BOMB, TNTe = 428 }, -- New
		["FAB_500SL"] = { category = Weapon.Category.BOMB, TNTe = 440 }, -- New
		["FAB_500TA"] = { category = Weapon.Category.BOMB, TNTe = 382 }, -- New
		["FAB_100"] = { category = Weapon.Category.BOMB, TNTe = 45 },
		["FAB_100M"] = { category = Weapon.Category.BOMB, TNTe = 45 }, -- New
		["FAB_100SV"] = { category = Weapon.Category.BOMB, TNTe = 40 }, -- New
		["FAB_1500"] = { category = Weapon.Category.BOMB, TNTe = 675 },
		["FAB_250"] = { category = Weapon.Category.BOMB, TNTe = 100 },
		["FAB_50"] = { category = Weapon.Category.BOMB, TNTe = 25 }, -- New
		["FAB_500"] = { category = Weapon.Category.BOMB, TNTe = 213 },
		["GBU_10"] = { category = Weapon.Category.BOMB, TNTe = 582 },
		["GBU_12"] = { category = Weapon.Category.BOMB, TNTe = 118 },
		["GBU_15_V_31_B"] = { category = Weapon.Category.BOMB, TNTe = 349.6 }, -- New
		["GBU_16"] = { category = Weapon.Category.BOMB, TNTe = 274 },
		["GBU_24"] = { category = Weapon.Category.BOMB, TNTe = 582 },
		["GBU_31"] = { category = Weapon.Category.BOMB, TNTe = 582 },
		["GBU_31_V_2B"] = { category = Weapon.Category.BOMB, TNTe = 582 },
		["GBU_31_V_3B"] = { category = Weapon.Category.BOMB, TNTe = 582 },
		["GBU_31_V_4B"] = { category = Weapon.Category.BOMB, TNTe = 582 },
		["GBU_32_V_2B"] = { category = Weapon.Category.BOMB, TNTe = 202 },
		["GBU_38"] = { category = Weapon.Category.BOMB, TNTe = 118, flare = true },
		["GBU_39"] = { category = Weapon.Category.BOMB, TNTe = 118 },
		["GBU_54_V_1B"] = { category = Weapon.Category.BOMB, TNTe = 0 }, -- New
		["HB-F4E_GBU15V1"] = { category = Weapon.Category.BOMB, TNTe = 340 }, -- New
		["HB-F4E_GBU_8_HOBOS"] = { category = Weapon.Category.BOMB, TNTe = 340 }, -- New
		["HEBOMB"] = { category = Weapon.Category.BOMB, TNTe = 40 },
		["HEBOMBD"] = { category = Weapon.Category.BOMB, TNTe = 40 },
		["IAB-500"] = { category = Weapon.Category.BOMB, TNTe = 524 }, -- New
		["KAB_1500Kr"] = { category = Weapon.Category.BOMB, TNTe = 675 },
		["KAB_1500LG"] = { category = Weapon.Category.BOMB, TNTe = 448 }, -- New
		["KAB_1500T"] = { category = Weapon.Category.BOMB, TNTe = 468 }, -- New
		["KAB_500"] = { category = Weapon.Category.BOMB, TNTe = 213 },
		["KAB_500Kr"] = { category = Weapon.Category.BOMB, TNTe = 213 },
		["KAB_500S"] = { category = Weapon.Category.BOMB, TNTe = 184 }, -- New
		["LS-6-100"] = { category = Weapon.Category.BOMB, TNTe = 40 }, -- New
		["LS_6_100"] = { category = Weapon.Category.BOMB, TNTe = 40 }, -- New
		["MK106"] = { category = Weapon.Category.BOMB, TNTe = 2.27 }, -- New
		["MK76"] = { category = Weapon.Category.BOMB, TNTe = 11.3 }, -- New
		["MK_82AIR"] = { category = Weapon.Category.BOMB, TNTe = 118 },
		["MK_82SNAKEYE"] = { category = Weapon.Category.BOMB, TNTe = 118 }, -- New
		["M117"] = { category = Weapon.Category.BOMB, TNTe = 140 }, -- New
		["Mk_81"] = { category = Weapon.Category.BOMB, TNTe = 60 },
		["Mk_82"] = { category = Weapon.Category.BOMB, TNTe = 118 },
		["Mk_82Y"] = { category = Weapon.Category.BOMB, TNTe = 72 }, -- New
		["Mk_83"] = { category = Weapon.Category.BOMB, TNTe = 274 },
		["Mk_83CT"] = { category = Weapon.Category.BOMB, TNTe = 160 }, -- New
		["Mk_84"] = { category = Weapon.Category.BOMB, TNTe = 582 },
		["Mk_84AIR_GP"] = { category = Weapon.Category.BOMB, TNTe = 582 }, -- New
		["Mk_84AIR_TP"] = { category = Weapon.Category.BOMB, TNTe = 582 }, -- New
		["ODAB-500PM"] = { category = Weapon.Category.BOMB, TNTe = 40000 }, -- New
		["OFAB-100 Jupiter"] = { category = Weapon.Category.BOMB, TNTe = 36 }, -- New
		["OFAB-100-120TU"] = { category = Weapon.Category.BOMB, TNTe = 88.6 }, -- New
		["P-50T"] = { category = Weapon.Category.BOMB, TNTe = 0.1 }, -- New
		["PTAB-2-5"] = { category = Weapon.Category.BOMB, TNTe = 0.65 }, -- New
		["RN-24"] = { category = Weapon.Category.BOMB, TNTe = 18000000 },
		["RN-28"] = { category = Weapon.Category.BOMB, TNTe = 1400000 },
		["SAMP125LD"] = { category = Weapon.Category.BOMB, TNTe = 64 },
		["SAMP250HD"] = { category = Weapon.Category.BOMB, TNTe = 118 },
		["SAMP250LD"] = { category = Weapon.Category.BOMB, TNTe = 118 },
		["SAMP400HD"] = { category = Weapon.Category.BOMB, TNTe = 274 },
		["SAMP400LD"] = { category = Weapon.Category.BOMB, TNTe = 274 },
		["SC_250_T1_L2"] = { category = Weapon.Category.BOMB, TNTe = 100 }, -- ("SC 250 Type 1 L2 - 250kg GP Bomb LD")
		["SC_250_T3_J"] = { category = Weapon.Category.BOMB, TNTe = 135 }, -- New
		["SC_50"] = { category = Weapon.Category.BOMB, TNTe = 25 }, -- New
		["SC_500_L2"] = { category = Weapon.Category.BOMB, TNTe = 213 },
		["SD_250_Stg"] = { category = Weapon.Category.BOMB, TNTe = 135 },
		["SD_500_A"] = { category = Weapon.Category.BOMB, TNTe = 213 },
		["Type_200A"] = { category = Weapon.Category.BOMB, TNTe = 90 }, -- New						

		-- Missiles
		["AGM_114"] = { category = Weapon.Category.MISSILE, TNTe = 5.67 }, -- New
		["AGM_114K"] = { category = Weapon.Category.MISSILE, TNTe = 10 },
		["AGM_119"] = { category = Weapon.Category.MISSILE, TNTe = 176 }, -- ???
		["AGM_122"] = { category = Weapon.Category.MISSILE, TNTe = 15 },
		["AGM_123"] = { category = Weapon.Category.MISSILE, TNTe = 274 },
		["AGM_12A"] = { category = Weapon.Category.MISSILE, TNTe = 36 }, -- New
		["AGM_12B"] = { category = Weapon.Category.MISSILE, TNTe = 40 }, -- New
		["AGM_12C"] = { category = Weapon.Category.MISSILE, TNTe = 45.2 }, -- New
		["AGM_12C_ED"] = { category = Weapon.Category.MISSILE, TNTe = 160 }, -- New
		["AGM_130"] = { category = Weapon.Category.MISSILE, TNTe = 582 },
		["AGM_154"] = { category = Weapon.Category.MISSILE, TNTe = 305 },

		["AGM_154A"] = { category = Weapon.Category.MISSILE, flare = true, clusterName = "BLU-97/B" }, -- New: cluster BLU-97/B
		["AGM_154B"] = { category = Weapon.Category.MISSILE, flare = true, clusterName = "BLU-108" }, -- New: cluster BLU-108
		["GB-6"] = { category = Weapon.Category.MISSILE },                                 -- clusterName="PTAB-2_5KO"
		["GB-6-HE"] = { category = Weapon.Category.MISSILE, flare = true, clusterName = "BLU-108" }, -- New: cluster BLU-108
		["GB-6-SFW"] = { category = Weapon.Category.MISSILE, flare = true, clusterName = "BLU-108" }, -- New: cluster BLU-108

		["AGM_45A"] = { category = Weapon.Category.MISSILE, TNTe = 26.4 },                 -- New
		["AGM_45B"] = { category = Weapon.Category.MISSILE, TNTe = 26.4 },                 -- New
		["AGM_65A"] = { category = Weapon.Category.MISSILE, TNTe = 15.6 },                 -- New
		["AGM_65B"] = { category = Weapon.Category.MISSILE, TNTe = 15.6 },                 -- New
		["AGM_65D"] = { category = Weapon.Category.MISSILE, TNTe = 130 },
		["AGM_65E"] = { category = Weapon.Category.MISSILE, TNTe = 300 },
		["AGM_65F"] = { category = Weapon.Category.MISSILE, TNTe = 300 },
		["AGM_65G"] = { category = Weapon.Category.MISSILE, TNTe = 90 }, -- New
		["AGM_65H"] = { category = Weapon.Category.MISSILE, TNTe = 130 },
		["AGM_65K"] = { category = Weapon.Category.MISSILE, TNTe = 300 },
		["AGM_65L"] = { category = Weapon.Category.MISSILE, TNTe = 300 },
		["AGM_78A"] = { category = Weapon.Category.MISSILE, TNTe = 38.8 }, -- New
		["AGM_78B"] = { category = Weapon.Category.MISSILE, TNTe = 38.8 }, -- New
		["AGM_84A"] = { category = Weapon.Category.MISSILE, TNTe = 90 }, -- New
		["AGM_84D"] = { category = Weapon.Category.MISSILE, TNTe = 88.4 }, -- New: cruise missile
		["AGM_84E"] = { category = Weapon.Category.MISSILE, TNTe = 488 }, -- New: cruise missile
		["AGM_84H"] = { category = Weapon.Category.MISSILE, TNTe = 144 }, -- New: cruise missile
		["AGM_84S"] = { category = Weapon.Category.MISSILE, TNTe = 88.4 }, -- New
		["AGM_86"] = { category = Weapon.Category.MISSILE, TNTe = 180 }, -- New
		["AGM_86C"] = { category = Weapon.Category.MISSILE, TNTe = 400 }, -- New: cruise missile
		["AGM_86D"] = { category = Weapon.Category.MISSILE, TNTe = 400 }, -- New: cruise missile
		["AGM_88"] = { category = Weapon.Category.MISSILE, TNTe = 89 },
		["AGR_20A"] = { category = Weapon.Category.MISSILE, TNTe = 8 },
		["AGR_20_M282"] = { category = Weapon.Category.MISSILE, TNTe = 8 }, -- A10C/AV8B APKWS  															
		["AKD-10"] = { category = Weapon.Category.MISSILE, TNTe = 5.67 }, -- New
		["ALARM"] = { category = Weapon.Category.MISSILE, TNTe = 26.4 }, -- New
		["AT-6"] = { category = Weapon.Category.MISSILE, TNTe = 2.4 },  -- New
		["Ataka_9M120"] = { category = Weapon.Category.MISSILE, TNTe = 7.4 }, -- New
		["Ataka_9M120F"] = { category = Weapon.Category.MISSILE, TNTe = 7.4 }, -- New
		["Ataka_9M220"] = { category = Weapon.Category.MISSILE, TNTe = 5.4 }, -- New
		["BGM_109B"] = { category = Weapon.Category.MISSILE, TNTe = 125.2 }, -- New
		["BK90_MJ1"] = { category = Weapon.Category.MISSILE, TNTe = 0 }, -- New: cluster MJ1
		["BK90_MJ1_MJ2"] = { category = Weapon.Category.MISSILE, TNTe = 0 }, -- New: cluster
		["BK90_MJ2"] = { category = Weapon.Category.MISSILE, TNTe = 0 }, -- New: cluster
		["C-701IR"] = { category = Weapon.Category.MISSILE, TNTe = 15 }, -- New
		["CM-802AKG_AI"] = { category = Weapon.Category.MISSILE, TNTe = 100 }, -- New: cruise missile
		["CM-802AKG"] = { category = Weapon.Category.MISSILE, TNTe = 76 }, -- New: cruise missile
		["C_701T"] = { category = Weapon.Category.MISSILE, TNTe = 15 }, -- New
		["C_802AK"] = { category = Weapon.Category.MISSILE, TNTe = 76 }, -- New: cruise missile
		["DWS39_MJ1"] = { category = Weapon.Category.MISSILE, TNTe = 0 }, -- New: cluster MJ1
		["DWS39_MJ1_MJ2"] = { category = Weapon.Category.MISSILE, TNTe = 0 }, -- New: cluster	MJ1-MJ2
		["DWS39_MJ2"] = { category = Weapon.Category.MISSILE, TNTe = 0 }, -- New: cluster MJ2
		["HOT2"] = { category = Weapon.Category.MISSILE, TNTe = 4 },
		["HOT3_MBDA"] = { category = Weapon.Category.MISSILE, TNTe = 5 }, -- New
		["HY-2"] = { category = Weapon.Category.MISSILE, TNTe = 196 },  -- New
		["KD_20"] = { category = Weapon.Category.MISSILE, TNTe = 200 }, -- New: cruise missile
		["KD_63"] = { category = Weapon.Category.MISSILE, TNTe = 200 }, -- New: cruise missile
		["KD_63B"] = { category = Weapon.Category.MISSILE, TNTe = 200 }, -- New: cruise missile
		["Kh25MP_PRGS1VP"] = { category = Weapon.Category.MISSILE, TNTe = 34.4 }, -- New
		["LS_6"] = { category = Weapon.Category.MISSILE, TNTe = 40 },   -- New
		["LS_6_500"] = { category = Weapon.Category.MISSILE, TNTe = 80 }, -- New
		["Mistral"] = { category = Weapon.Category.MISSILE, TNTe = 0.170 }, -- manpads missile
		["YJ_12"] = { category = Weapon.Category.MISSILE, TNTe = 400 }, -- New: cruise missile
		["YJ_83"] = { category = Weapon.Category.MISSILE, TNTe = 400 }, -- New: cruise missile

		-- rockets
		["90-1_HE_Rocket"] = { category = Weapon.Category.ROCKET, TNTe = 4.6 }, -- New
		["AGR_20_M151_unguided"] = { category = Weapon.Category.ROCKET, TNTe = 4 }, -- New
		["AGR_20_M282_unguided"] = { category = Weapon.Category.ROCKET, TNTe = 11 }, -- New	
		["BRM-1_90MM"] = { category = Weapon.Category.ROCKET, TNTe = 5 },  -- New

		-- LAU-3/61/68/131 (incl. on BRU-33/42), M260/261, XM158
		["HYDRA_70_M151"] = { category = Weapon.Category.ROCKET, TNTe = 7 },
		["HYDRA_70_M151_M433"] = { category = Weapon.Category.ROCKET, TNTe = 4 },
		["HYDRA_70_M156"] = { category = Weapon.Category.ROCKET, TNTe = 4 }, -- New
		["HYDRA_70_M229"] = { category = Weapon.Category.ROCKET, TNTe = 8 },
		["HYDRA_70_M257"] = { category = Weapon.Category.ROCKET, TNTe = 4 }, -- New
		["HYDRA_70_M259"] = { category = Weapon.Category.ROCKET, TNTe = 11 },
		["HYDRA_70_M282"] = { category = Weapon.Category.ROCKET, TNTe = 11 },
		["HYDRA_70_M274"] = { category = Weapon.Category.ROCKET, TNTe = 4 }, -- New
		["HYDRA_70_MK1"] = { category = Weapon.Category.ROCKET, TNTe = 4 }, -- New
		["HYDRA_70_MK5"] = { category = Weapon.Category.ROCKET, TNTe = 4 },
		["HYDRA_70_MK61"] = { category = Weapon.Category.ROCKET, TNTe = 4 }, -- New
		["HYDRA_70_WTU1B"] = { category = Weapon.Category.ROCKET, TNTe = 8 }, -- BDU
		["Vikhr_M"] = { category = Weapon.Category.ROCKET, TNTe = 11 },

		-- ZUNI launchers: LAU-10 (incl. on BRU-33)
		["Zuni_127"] = { category = Weapon.Category.ROCKET, TNTe = 20 }, 

		-- ZUNI launchers: LR-25
		["ARF8M3API"] = { category = Weapon.Category.ROCKET, TNTe = 11 },
		["ARF8M3HEI"] = { category = Weapon.Category.ROCKET, TNTe = 11 },
		["ARF8M3TPSM"] = { category = Weapon.Category.ROCKET, TNTe = 11 },

		-- MATRA F1/F4, Telson 8
		["SNEB_TYPE250_F1B"] = { category = Weapon.Category.ROCKET, TNTe = 8 },
		["SNEB_TYPE251_F1B"] = { category = Weapon.Category.ROCKET, TNTe = 8 },
		["SNEB_TYPE252_F1B"] = { category = Weapon.Category.ROCKET, TNTe = 8 },
		["SNEB_TYPE253_F1B"] = { category = Weapon.Category.ROCKET, TNTe = 8 },
		["SNEB_TYPE256_F1B"] = { category = Weapon.Category.ROCKET, TNTe = 8 },
		["SNEB_TYPE257_F1B"] = { category = Weapon.Category.ROCKET, TNTe = 8 },
		["SNEB_TYPE251_F4B"] = { category = Weapon.Category.ROCKET, TNTe = 4 },
		["SNEB_TYPE252_F4B"] = { category = Weapon.Category.ROCKET, TNTe = 4 },
		["SNEB_TYPE253_F4B"] = { category = Weapon.Category.ROCKET, TNTe = 5 },
		["SNEB_TYPE256_F4B"] = { category = Weapon.Category.ROCKET, TNTe = 6 },
		["SNEB_TYPE257_F4B"] = { category = Weapon.Category.ROCKET, TNTe = 8 },
		["SNEB_TYPE251_H1"] = { category = Weapon.Category.ROCKET, TNTe = 4 },
		["SNEB_TYPE252_H1"] = { category = Weapon.Category.ROCKET, TNTe = 4 },
		["SNEB_TYPE253_H1"] = { category = Weapon.Category.ROCKET, TNTe = 5 },
		["SNEB_TYPE256_H1"] = { category = Weapon.Category.ROCKET, TNTe = 6 },
		["SNEB_TYPE257_H1"] = { category = Weapon.Category.ROCKET, TNTe = 8 },
		["MATRA_F4_SNEBT251"] = { category = Weapon.Category.ROCKET, TNTe = 8 }, -- New				
		["MATRA_F4_SNEBT253"] = { category = Weapon.Category.ROCKET, TNTe = 8 }, -- New
		["MATRA_F4_SNEBT256"] = { category = Weapon.Category.ROCKET, TNTe = 8 }, -- New
		["MATRA_F1_SNEBT253"] = { category = Weapon.Category.ROCKET, TNTe = 8 }, -- New
		["MATRA_F1_SNEBT256"] = { category = Weapon.Category.ROCKET, TNTe = 8 }, -- New

		-- UB-16, UB-32A
		["C_5"] = { category = Weapon.Category.ROCKET, TNTe = 8 },
		["S_5KP"] = { category = Weapon.Category.ROCKET, TNTe = 8 },
		["S_5M"] = { category = Weapon.Category.ROCKET, TNTe = 8 },

		-- launchers: B-8V20A, B-8M1 (incl. twin-pylon versions)

		-- launchers: APU-68
		["C_13"] = { category = Weapon.Category.ROCKET, TNTe = 21 },
		["C_24"] = { category = Weapon.Category.ROCKET, TNTe = 123 },
		["C_25"] = { category = Weapon.Category.ROCKET, TNTe = 151 },
		["S-25-O"] = { category = Weapon.Category.ROCKET, TNTe = 8 }, -- new									
		["C_8"] = { category = Weapon.Category.ROCKET, TNTe = 8 },
		["C_8OM"] = { category = Weapon.Category.ROCKET, TNTe = 8 }, -- new									
		["C_8CM"] = { category = Weapon.Category.ROCKET, TNTe = 8 }, -- new									
		["C_8CM_GN"] = { category = Weapon.Category.ROCKET, TNTe = 8 }, -- new									
		["C_8CM_RD"] = { category = Weapon.Category.ROCKET, TNTe = 8 }, -- new									
		["C_8CM_WH"] = { category = Weapon.Category.ROCKET, TNTe = 8 }, -- new									
		["C_8CM_BU"] = { category = Weapon.Category.ROCKET, TNTe = 8 }, -- new									
		["C_8CM_VT"] = { category = Weapon.Category.ROCKET, TNTe = 8 }, -- new									
		["C_8CM_YE"] = { category = Weapon.Category.ROCKET, TNTe = 8 }, -- new									
		["C_8OFP2"] = { category = Weapon.Category.ROCKET, TNTe = 3 },
		["FFAR Mk1 HE"] = { category = Weapon.Category.ROCKET, TNTe = 8 },
		["FFAR Mk5 HEAT"] = { category = Weapon.Category.ROCKET, TNTe = 8 },
		["FFAR_Mk61"] = { category = Weapon.Category.ROCKET, TNTe = 8 },
		["FFAR M156 WP"] = { category = Weapon.Category.ROCKET, TNTe = 8 },


		["KH-66_Grom"] = { category = Weapon.Category.BOMB, TNTe = 108 },
		["M_117"] = { category = Weapon.Category.BOMB, TNTe = 201 },
		["X_23"] = { category = Weapon.Category.BOMB, TNTe = 111 },
		["X_23L"] = { category = Weapon.Category.BOMB, TNTe = 111 },
		["X_28"] = { category = Weapon.Category.BOMB, TNTe = 160 },
		["X_25ML"] = { category = Weapon.Category.BOMB, TNTe = 89 },
		["X_25MP"] = { category = Weapon.Category.BOMB, TNTe = 89 },
		["X_25MR"] = { category = Weapon.Category.BOMB, TNTe = 140 },
		["X_58"] = { category = Weapon.Category.BOMB, TNTe = 140 },
		["X_29L"] = { category = Weapon.Category.BOMB, TNTe = 320 },
		["X_29T"] = { category = Weapon.Category.BOMB, TNTe = 320 },
		["X_29TE"] = { category = Weapon.Category.BOMB, TNTe = 320 },
		["S-24A"] = { category = Weapon.Category.BOMB, TNTe = 24 },
		["S-24B"] = { category = Weapon.Category.BOMB, TNTe = 123 },
		["S-25OF"] = { category = Weapon.Category.BOMB, TNTe = 194 },
		["S-25OFM"] = { category = Weapon.Category.BOMB, TNTe = 150 },
		["S-25O"] = { category = Weapon.Category.BOMB, TNTe = 150 },
		["S_25L"] = { category = Weapon.Category.BOMB, TNTe = 190 },
		["S-5M"] = { category = Weapon.Category.BOMB, TNTe = 1 },
		["ARAKM70BHE"] = { category = Weapon.Category.BOMB, TNTe = 4 },
		["Rb 05A"] = { category = Weapon.Category.BOMB, TNTe = 217 }
	}

	---clusters transco
	---TODO modifier la règle de transco car 1 bomblet peut être portée par plusieurs munition
	---@class BLAST.clusters
	BLAST.clusters = {
		-- no modelization possible currently ["BLG-66"] = "", -- New BLG66_AC(GR66AC/TNTe2kg), BLG66_EG=BLG66_AC
		-- no modelization possible currently ["Mk 118"] = "", -- New
		-- no modelization possible currently ["BK90 MJ1"] = "", -- New: cluster MJ1
		-- no modelization possible currently ["BK90 MJ1_MJ2"] = "", -- New: cluster MJ1_MJ2
		-- no modelization possible currently ["BK90 MJ2"] = "", -- New: cluster MJ2
		-- no modelization possible currently ["MUS_JAS_1"] = "", -- New: cluster DWS39_MJ1
		-- no modelization possible currently ["MUS_JAS_2"] = "", -- New: cluster DWS39_MJ2
		-- no modelization possible currently ["PTAB-10-5"] = "", -- New: cluster RBK_500AO
		-- no modelization possible currently ["PTAB-1M"] = "", -- New: cluster RBK_500U
		-- no modelization possible currently ["PTAB-2-5"] = "", -- New: cluster RBK_250
		-- no modelization possible currently ["BETAB-M"] = "", -- New: cluster RBK_500U_DETAB_M
		-- no modelization possible currently ["OAB-2-5RT"] = "", -- New: cluster RBK_500U_OAB-2-5RT
		-- no modelization possible currently ["AO-1SCh"] = "", -- New: cluster RBK_250_275_AO_1SCH
		-- no modelization possible currently ["PTAB-2.5KO"] = "", -- New: cluster GB-6

		["Mk 118"] = { -- CBU-99 sub-munitions / ROCKEYE / MK-20
			count = 20, -- number of explosions
			TNTe = 0.980, -- power eq. TNT real 0.180gr
			lenght = 120, -- length of zone
			width = 85, -- width of zone
			disp = 1.2, -- dispersion (%) of the initial zone size
			physics = { -- physicals props  BLU and skeets
				m0 = 0.6, -- mass during step 1 of flight (kg)
				s0 = 0.01, -- surface (m²)
				cx0 = 1.40, -- Drag coef step 1 (no unit)
				sx0 = 0.28, -- Lift coef step 1 (no unit)

				m1 = 0.00, -- mass during step 2 of flight (kg)
				s1 = 0.00, -- surface (m²)
				cx1 = 0.0, -- Drag coef step 2 (no unit)
				sx1 = 0.0, -- Lift coef step 2 (no unit)

				sr = 1.0, -- speed rate when cluster is ejected
				mh = 50.0, -- minimal height of IP
				de = 0, -- delay between step 1 and 2 of the trajectory
				we = 1.0, -- wind effect (no unit)
				di = 0.6 -- dispersion (%) of the initial zone size
			}
		},

		["BLU-97B"] = { -- CBU-97 sub-munitions
			count = 20, -- number of explosions
			TNTe = 2.900, -- power eq. TNT
			lenght = 190, -- length of zone
			width = 85, -- width of zone
			disp = 1.2, -- dispersion (%) of the initial zone size
			physics = { -- physicals props  BLU and skeets
				m0 = 1.54, -- mass during step 1 of flight (kg)
				s0 = 0.01, -- surface (m²)
				cx0 = 0.21, -- Drag coef step 1 (no unit)
				sx0 = 0.01, -- Lift coef step 1 (no unit)

				m1 = 0.00, -- mass during step 2 of flight (kg)
				s1 = 0.00, -- surface (m²)
				cx1 = 0.0, -- Drag coef step 2 (no unit)
				sx1 = 0.0, -- Lift coef step 2 (no unit)

				sr = 1.0, -- speed rate when cluster is ejected
				mh = 120.0, -- minimal height of IP
				de = 0, -- delay between step 1 and 2 of the trajectory
				we = 1.0, -- wind effect (no unit)
				di = 0.2 -- dispersion (%) of the initial zone size
			}
		},
		["BLU-108"] = { -- CBU-97 sub-munitions
			count = 20, -- number of explosions
			TNTe = 0.900, -- power eq. TNT
			lenght = 190, -- length of zone
			width = 85, -- width of zone
			disp = 1.2, -- dispersion (%) of the initial zone size
			physics = { -- physicals props  BLU and skeets
				m0 = 29.5, -- mass during step 1 of flight (kg)
				s0 = 0.11, -- surface (m²)
				cx0 = 4.0, -- Drag coef step 1 (no unit)
				sx0 = 0.28, -- Lift coef step 1 (no unit)

				m1 = 5.00, -- mass during step 2 of flight (kg)
				s1 = 0.04, -- surface (m²)
				cx1 = 4.5, -- Drag coef step 2 (no unit)
				sx1 = 0.6, -- Lift coef step 2 (no unit)

				sr = 1.378, -- speed rate when cluster is ejected
				mh = 50.0, -- minimal height of IP
				de = 4.5, -- delay between step 1 and 2 of the trajectory
				we = 1.0, -- wind effect (no unit)
				di = 0.2 -- dispersion (%) of the initial zone size
			}
		},
		["BLU-97/B"] = { -- CBU-97 sub-munitions
			count = 20, -- number of explosions
			TNTe = 2.900, -- power eq. TNT
			lenght = 190, -- length of zone
			width = 85, -- width of zone
			disp = 1.2, -- dispersion (%) of the initial zone size
			physics = { -- physicals props  BLU and skeets
				m0 = 1.54, -- mass during step 1 of flight (kg)
				s0 = 0.01, -- surface (m²)
				cx0 = 0.41, -- Drag coef step 1 (no unit)
				sx0 = 0.01, -- Lift coef step 1 (no unit)

				m1 = 0.00, -- mass during step 2 of flight (kg)
				s1 = 0.00, -- surface (m²)
				cx1 = 0.0, -- Drag coef step 2 (no unit)
				sx1 = 0.0, -- Lift coef step 2 (no unit)

				sr = 1.0, -- speed rate when cluster is ejected
				mh = 120.0, -- minimal height of IP
				de = 0, -- delay between step 1 and 2 of the trajectory
				we = 1.0, -- wind effect (no unit)
				di = 1.8 -- dispersion (%) of the initial zone size
			}
		}
	}

	-- Naes of modes
	BLAST.ModesNames = {
		[false] = "local",
		[true] = "server"
	}

	-- Names of object categories
	BLAST.ObjectCategoryNames = {
		[0] = "NONE",
		[Object.Category.UNIT] = "UNIT",
		[Object.Category.WEAPON] = "WEAPON",
		[Object.Category.STATIC] = "STATIC",
		[Object.Category.BASE] = "BASE",
		[Object.Category.SCENERY] = "SCENERY",
		[Object.Category.CARGO] = "Cargo"
	}

	-- Names of unit catgories
	BLAST.UnitCategoryNames = {
		[Unit.Category.AIRPLANE] = "Airplane",
		[Unit.Category.HELICOPTER] = "Helicopter",
		[Unit.Category.GROUND_UNIT] = "Ground Unit",
		[Unit.Category.SHIP] = "Ship",
		[Unit.Category.STRUCTURE] = "Structure"
	}

	-- Names of static categories
	BLAST.StaticCategoryNames = {
		[StaticObject.Category.VOID] = "VOID",
		[StaticObject.Category.UNIT] = "UNIT",
		[StaticObject.Category.WEAPON] = "WEAPON",
		[StaticObject.Category.STATIC] = "STATIC",
		[StaticObject.Category.BASE] = "BASE",
		[StaticObject.Category.SCENERY] = "SCENERY",
		[StaticObject.Category.CARGO] = "CARGO"
	}

	-- Names of weapon categories
	BLAST.WeaponCategoryNames = {
		[Weapon.Category.SHELL] = "SHELL",
		[Weapon.Category.MISSILE] = "MISSILE",
		[Weapon.Category.ROCKET] = "ROCKET",
		[Weapon.Category.BOMB] = "BOMB"
	}

	-- Names of missiles categories
	BLAST.MissileCategoryNames = {
		[Weapon.MissileCategory.AAM] = "AAM",
		[Weapon.MissileCategory.SAM] = "SAM",
		[Weapon.MissileCategory.BM] = "BM",
		[Weapon.MissileCategory.ANTI_SHIP] = "ANTI SHIP",
		[Weapon.MissileCategory.CRUISE] = "CRUISE",
		[Weapon.MissileCategory.OTHER] = "OTHER"
	}

	-- list of hemispheres
	BLAST.hemisphere = {
		North = 0,
		South = 1
	}

	-- list of maps with map's name and hemisphere
	BLAST.maps = {
		["Caucasus"] = { name = "Caucasus", hemisphere = BLAST.hemisphere.North },
		["NTTR"] = { name = "Nevada", hemisphere = BLAST.hemisphere.North },
		["Normandy"] = { name = "Normandy", hemisphere = BLAST.hemisphere.North },
		["PersianGulf"] = { name = "PersianGulf", hemisphere = BLAST.hemisphere.North },
		["TheChannel"] = { name = "TheChannel", hemisphere = BLAST.hemisphere.North },
		["Syria"] = { name = "Syria", hemisphere = BLAST.hemisphere.North },
		["MarianaIslands"] = { name = "MarianaIslands", hemisphere = BLAST.hemisphere.North },
		["Falklands"] = { name = "Falklands", hemisphere = BLAST.hemisphere.South },
		["SinaiMap"] = { name = "SinaiMap", hemisphere = BLAST.hemisphere.North },
		["Kola"] = { name = "Kola", hemisphere = BLAST.hemisphere.North },
		["Afghanistan"] = { name = "Afghanistan", hemisphere = BLAST.hemisphere.North },
		["Iraq"] = { name = "Iraq", hemisphere = BLAST.hemisphere.North },
		["GermanyCW"] = { name = "GermanyCW", hemisphere = BLAST.hemisphere.North }
	}


	--**** list of static functions ****

	-- function to call subfunction with parameters with error handling exceptions
	local function blastProtectedCall(...)
		local ErrorHandler = function(errmsg)
			env.info("BLAST: Error " .. errmsg)
			env.info(debug.traceback())
			return errmsg
		end

		local status, error = xpcall(..., ErrorHandler)
		--[[		
		if error then
			env.warning( errmsg, true )
			if blast.options.msgInGame then
				trigger.action.outText( errmsg, 10 )
			end
		end
--]]
	end

	-- log and show a message depending of the options set
	BLAST.info = function(s, forceShow)
		forceShow = forceShow or false
		s = s or ""
		if BLAST.options.debugManaged or forceShow then
			env.info("BLAST: " .. s)
			if BLAST.options.msgInGame or forceShow then
				trigger.action.outText(s, 10)
			end
		end
	end

	-- format a string with diff between start and end time
	BLAST.timerStr = function(starttime, endtime)
		local difftime = endtime - starttime
		local hours = math.floor(difftime / 3600)
		local minutes = math.floor((difftime % 3600) / 60)
		local seconds = math.floor(difftime % 60)
		local millisecondes = math.floor((difftime % 1) * 1000)
		return string.format("%02d:%02d:%02d,%03d", hours, minutes, seconds, millisecondes)
	end

	---open csv file to store telemetry datas
	---@param filename string
	BLAST.openTelemetry = function(filename)
		local handle

		if io then
			handle = assert(io.open(lfs.writedir() .. "Logs\\" .. filename, "w+"))
			if handle then
				handle.write("time\torigin\tinitiator\tmunition\tname\tagl\tpos.x\tpos.y\tpos.z\r\n")
				BLAST.info(string.format("Telemetry open : %s", filename))
			end
		else
			BLAST.info("Telemetry file can't be open, io not permitted.")
		end

		return handle
	end

	-- close and flush datas in the file of telemetry
	BLAST.closeTelemetry = function(handle)
		if io and handle then
			if handle then
				handle:close()
				handle = false
				BLAST.info("Telemetry closed")
			end
		end
		return false
	end

	-- write in telemetry file one record
	BLAST.writeTelemetry = function(handle, fn, w)
		if io and handle then
			-- object agl in feet
			local agl = BLAST.getGroundHeight(w.pos) * 3.28084 -- in feet
			local abstime = timer.getTime()
			local hh = math.floor(abstime / 3600)
			local mm = math.floor((abstime - hh * 3600) / 60)
			local ss = math.floor(abstime - hh * 3600 - mm * 60)
			local v, ms = math.modf(abstime)
			ms = math.floor(ms * 1000)
			local speed = BLAST.vec3_mag(w.velocity) * 1.9438478 -- m/sec -> Kph
			-- time of record
			-- weapon id, which event or state triggers the
			handle:write(string.format("%02i:%02i:%02i.%03i\t%i\t%s\t%s\t%s\t%s\t%.3f\t%.3f\t%.3f\t%.3f\t%.3f\r\n",
				hh, mm, ss, ms, w.id, fn, w.initiatorName, w.name, w.type, agl, speed, w.position.x, w.position.y,
				w.position.z))
		end
	end

	-- check if a key exist in a table given
	---@param t table
	---@param k string
	---@return boolean result
	BLAST.tableHasKey = function(t, k)
		local result = (t ~= nil) and (t[k] ~= nil)
		return result
	end

	-- copy content of a source table to a new one
	---@param orig table
	---@return table|type copy of orig
	BLAST.deepcopy = function(orig)
		local orig_type = type(orig)
		local copy
		if orig_type == 'table' then
			copy = {}
			for orig_key, orig_value in next, orig, nil do
				copy[BLAST.deepcopy(orig_key)] = BLAST.deepcopy(orig_value)
			end
			setmetatable(copy, BLAST.deepcopy(getmetatable(orig)))
		else -- number, string, boolean, etc
			copy = orig
		end
		return copy
	end
	---Converts radian to degrees
	---@param angle number
	---@return number result
	BLAST.rad2degree = function(angle)
		local result = angle * 180 / math.pi
		return result
	end

	local vec3 = table

	---calculates heading from a vec3
	---@param v vec3
	---@return number result
	BLAST.vec3Heading = function(v)
		local result = math.deg(math.atan2(v.z, v.x))
		if result < 0 then
			result = result + 360
		end
		return result
	end

	---calculates heading from a vec2
	---@param v table vec2
	---@return number result
	BLAST.vec2Heading = function(v)
		local result = math.deg(math.atan2(v.z, v.x))
		if result < 0 then
			result = result + 360
		end
		return result
	end

	-- make a vec2 with coordinates x, y
	---@param x number
	---@param y number
	---@return table vec2
	BLAST.vec2 = function(x, y)
		local result = { x = x, y = y }
		return result
	end

	-- make a vec3 with coordinates x, y, z
	---@param x number
	---@param y number
	---@param z number
	---@return table vec3 result
	BLAST.vec3 = function(x, y, z)
		local result = { x = x, y = y, z = z }
		return result
	end

	-- get vec2 coordinates from vec3
	---@param v table vec3
	---@return table vec2 result
	BLAST.vec3tovec2 = function(v)
		local result = { x = v.x, y = v.z }
		return result
	end

	-- get vec2 coordinates from vec 3
	---@param v table vec2
	---@param h number
	---@return table vec3
	BLAST.vec2tovec3 = function(v, h)
		local result = { x = v.x, y = h, z = v.y }
		return result
	end

	-- addition of two vectors
	---@param v1 table vec3
	---@param v2 table vec3
	---@return table vec3 result
	BLAST.vec3_add = function(v1, v2)
		local result = BLAST.vec3(v1.x + v2.x, v1.y + v2.y, v1.z + v2.z)
		return result
	end

	-- substraction of two vectors
	---@param v1 table vec3
	---@param v2 table vec3
	---@return table vec3 result
	BLAST.vec3_sub = function(v1, v2)
		local result = BLAST.vec3(v1.x - v2.x, v1.y - v2.y, v1.z - v2.z)
		return result
	end

	-- multiply a vec3 with a coef
	---@param v table vec3
	---@param coef number
	---@return table vec3
	BLAST.vec3_mul = function(v, coef)
		local result = BLAST.vec3(v.x * coef, v.y * coef, v.z * coef)
		return result
	end

	-- get the norm of one vectors
	---@param v vec3
	---@return number result
	BLAST.vec3_mag = function(v)
		local result = math.sqrt(v.x ^ 2 + v.y ^ 2 + v.z ^ 2)
		return result
	end

	-- get the cross product of two vectors
	---@param a table vec3
	---@param b table vec3
	---@return table vec3 result
	BLAST.vec3_cross = function(a, b)
		local result = {
			x = a.y * b.z - a.z * b.y,
			y = a.z * b.x - a.x * b.z,
			z = a.x * b.y - a.y * b.x
		}
		return result
	end

	-- convertion feet to meters with optional rounded to the unit
	---@param feet number value to convert in meters
	---@param rouded boolean true to return a rounded value
	---@return integer|number
	BLAST.feet2meters = function(feet, rouded)
		local result = feet * 0.3048
		if rouded then
			result = math.floor(result + 0.5)
		end
		return result
	end

	-- convertion meters to feet with optional rounded to the unit
	---@param meters number value to convert in feet
	---@param rounded boolean true to return a rounded value
	---@return integer|number
	BLAST.meters2feet = function(meters, rounded)
		local result = meters * 3.28084
		if rounded then
			result = math.floor(result + 0.5)
		end
		return result
	end

	-- just a fancy function to have a "string" value for a boolean input
	---@param bool boolean
	---@return string
	BLAST.bool2string = function(bool)
		return bool and "true" or "false"
	end

	-- get the height from the ground level at p (vec2 or vec3)
	---@param p vec3 ip coordinates
	---@return integer height
	BLAST.getGroundHeight = function(p)
		local result = 0
		if p.z then
			local vec2 = BLAST.vec3tovec2(p)
			result = land.getHeight(vec2)
		else
			result = land.getHeight(p)
		end
		return result
	end

	-- get the wind vector at 1 altitude or for each step
	---@param p vec3 ip coordinates
	---@param step integer intervalle entre 2 captures de vent (m)
	---@param alt integer altitude
	---@return table of vec3 as list of winds
	BLAST.getWinds = function(p, step, alt)
		local winds = {}
		local w = {}
		local a = BLAST.vec3(p.x, math.floor(p.y / step) * step, p.z)

		while a.y >= alt do
			w = atmosphere.getWind(a)
			winds[a.y] = w
			a.y = a.y - step
		end

		return winds
	end

	-- get a rectangle oriented
	---@param p vec3 ip coordinates
	---@param L integer length of the strike zone (m)
	---@param W integer Width of the strike zone (m)
	---@param a number heading of the trajectory (degree)
	---@param d number coef of dispersion (no unit)
	---@return table of vec3 as list of zone's angles
	BLAST.rectangle3D = function(p, L, W, a, d)
		local angles = {}
		local r = math.rad(a)
		local cos_a = math.cos(r)
		local sin_a = math.sin(r)

		-- Définition des 4 coins relatifs au centre (0,0,0)
		-- Dans ton repère : x (vertical/profondeur), z (horizontal)
		local offsets = {
			{ x = -L / 2, z = -W / 2 },
			{ x = L / 2, z = -W / 2 },
			{ x = L / 2, z = W / 2 },
			{ x = -L / 2, z = W / 2 }
		}

		for i, offset in ipairs(offsets) do
			-- 1. Rotation autour de l'axe Y (altitude)
			local x_rot = (offset.x * cos_a - offset.z * sin_a) * d
			local z_rot = (offset.x * sin_a + offset.z * cos_a) * d

			-- 2. Translation vers le point p(x, y, z)
			angles[i] = {
				x = x_rot + p.x,
				y = p.y, -- L'altitude reste constante
				z = z_rot + p.z
			}
		end
		return angles
	end

	-- get point p (vec2) after rotation a (rad) relative of center c (vec2)
	-- ({x=c.x+l2, y=c.y+w2}, c, a)
	BLAST.rotate = function(p, c, a)
		local x0 = p.x - c.x;
		local y0 = p.y - c.y;
		local x = x0 * math.cos(a) + y0 * math.sin(a) + c.x;
		local y = -x0 * math.sin(a) + y0 * math.cos(a) + c.y;

		return BLAST.vec2(x, y)
	end

	-- translate point p with range d
	BLAST.translateVec3 = function(p, d)
		local result = BLAST.vec3(p.x + d.x, p.y + d.y, p.z + d.z)
		return result
	end

	-- get true if a point p is in the radius r of center c
	BLAST.inRadius = function(p, c, r)
		local result = ((p.x - c.x) ^ 2 + (p.y - c.y) ^ 2) ^ 0.5 <= r
		return result
	end

	-- get true if a point p is in the polygon define by verticies
	BLAST.inPolygon = function(v, p)
		local n = 1
		local o = #v
		local result = false

		while (n <= #v) do
			if (((v[n].y > p.y) ~= (v[o].y > p.y)) and (p.x < (v[o].x - v[n].x) * (p.x - v[n].y) / (v[o].y - v[n].y) + v[n].x)) then
				result = not result
			end
			o = n
			n = n + 1
		end
		return result
	end

	-- get horizontal distance between two points in 2D
	BLAST.distance2D = function(point1, point2)
		local result = math.sqrt(math.abs(point1.x - point2.x) ^ 2 + math.abs(point1.y - point2.y) ^ 2)
		return result
	end

	-- get distance between two points in 3D
	BLAST.distance3D = function(point1, point2)
		local result = math.sqrt(math.abs(point1.x - point2.x) ^ 2 + math.abs(point1.y - point2.y) ^ 2 +
		math.abs(point1.z - point2.z) ^ 2)
		return result
	end

	BLAST.getLifePercentage = function(o)
		local result = 0
		local life0 = 1
		local life = 0
		if o and o:isExist() then
			local c = Object.getCategory(o)
			-- ground units, statics, scenary and cargos
			if (c == Object.Category.UNIT) then
				life0 = o:getLife0()
				life = o:getLife()
			elseif (c == Object.Category.SCENERY) then
				life0 = o:getLife() or 1
				life = o:getLife()
			elseif (c == Object.Category.STATIC) then
				life = o:getLife()
				life0 = o.life or 1
			end

			result = math.floor((life / life0) * 100)
		end
		return result
	end

	-- check if an object define by his central point is in an exclusion zone
	-- TODO : ajouyer à la fonction de traitement des clusters
	BLAST.isInExclusionArea = function(location, exclusionAreas)
		local result = false
		local l = BLAST.vec3tovec2(location)
		local c = { x = 0, y = 0 }
		for k, area in pairs(exclusionAreas) do
			if (area.zoneType == 0) then
				c.x = area.x
				c.y = area.y
				result = result or BLAST.inRadius(l, area, area.radius)

				-- polygon
			elseif (area.zoneType == 2) then
				result = result or BLAST.inPolygon(area.verticies, l)
			end
			-- stop loop when a zone is found
			if (result) then
				break
			end
		end

		return result
	end

	-- Get the list of zones where blast effects must be disabled
	BLAST.getExclusionAreas = function(areasPattern)
		local name = ""
		local match = ""
		local i = 0
		local exclusionAreas = {}

		for k, z in pairs(env.mission.triggers.zones) do
			name = string.upper(z.name)
			match = string.match(name, areasPattern)

			if (match == areasPattern) then
				i = #exclusionAreas + 1
				exclusionAreas[i] = {}
				exclusionAreas[i].name = name
				exclusionAreas[i].zoneType = z.type

				-- 0 = x,y,radius,
				if (z.type == 0) then
					exclusionAreas[i].x = z.x
					exclusionAreas[i].y = z.y
					exclusionAreas[i].radius = z.radius

					-- 2 = verticies
				elseif (z.type == 2) then
					exclusionAreas[i].verticies = z.verticies --  array of 4 coordinates x&y
				end
			end
		end
		return exclusionAreas
	end

	-- get dcs map number
	BLAST.getDCSMap = function()
		return env.mission.theatre
	end

	-- get world hemisphere depending of the map
	BLAST.getHemisphere = function()
		local map = tostring(BLAST.getDCSMap())
		local h = BLAST.hemisphere.North

		if map and BLAST.maps[map] then
			h = BLAST.maps[map].hemisphere
		end
		return h
	end

	-- Get a polygon oriented sw/ne
	BLAST.getSearchBox = function(polygon)
		local sw = { x = polygon[1].x, y = polygon[1].y, z = polygon[1].z }
		local ne = { x = polygon[1].x, y = polygon[1].y, z = polygon[1].z }

		for i, p in ipairs(polygon) do
			-- sw is the southernmost, westernmost and lowest angle of the polygon
			sw.x = math.min(p.x, sw.x)
			sw.y = math.min(p.y, sw.y)
			sw.z = math.min(p.z, sw.z)

			-- ne is the northernmost, easternmost and highest angle of the polygon
			ne.x = math.max(p.x, ne.x)
			ne.y = math.max(p.y, ne.y)
			ne.z = math.max(p.z, ne.z)
		end
		return { ne = ne, sw = sw }
	end

	-- Peak of overpressure calculation based on Hopkinson-Cranz Scaling Law
	BLAST.getPso = function(range, TNTe, angle)
		-- R [m] is the distance between the center of the object and the Impact Point (ip)
		local R = range
		-- W [kg] is the equivalent TNT mass, currently only TNT is used
		local W = TNTe
		-- Angle [rad] of incidence for spherical (0°<A<180°) or hemispherical (A=0°) explosion
		local A = angle
		-- P [hPa] is the ambient pressure (without evaluation of altitude) : todo manage gap pressure std/height
		local Pa = 1013.25
		if A > 0 then
			R = math.floor(R / math.cos(math.rad(A)) + 0.5)
		end
		-- Z [m/kg] is the coefficient dependency on angle of incidence (Hopkinson-Cranz Scaling Law)
		local Z = R / W ^ (1 / 3)
		-- Pso [hPa] is Peak scaled incident positive overpressure  (Kinney and Graham)
		local Pso = Pa * (808 * (1 + (Z / 4.5) ^ 2)) /
		math.sqrt((1 + (Z / 0.048) ^ 2) * (1 + (Z / 0.32) ^ 2) * (1 + (Z / 1.35) ^ 2))

		-- return the list of values
		return { R = R, Pso = Pso }
	end

	-- Construct the table of all peaks in descending order until there is no longer a lethal effect on humans.
	BLAST.getPsoTable = function(TNTe, angle)
		-- initialise the Pso table
		local result = {}

		-- R [m] is the distance between the center of the object and the Impact Point (ip)
		local R = 1
		-- W [kg] is the equivalent TNT mass, currently only TNT is used
		local W = TNTe
		-- Angle [rad] of incidence for spherical (0°< A < 180°) or hemispherical (A=0°) explosion
		local A = angle
		-- P [hPa] is the ambient pressure (without evaluation of altitude)
		local Pa = 1013.25
		-- I Increment by 1 meter
		local Incr = 1

		-- repeat until the Pso is below the minimum human damage threshold (<50 hPa)
		local thresholdPso = 50
		local Pso = {}
		-- repeat for each meter the Pso calculation until Pso < 50hPa
		repeat
			Pso = BLAST.getPso(R, W, A)
			table.insert(result, Pso)
			-- next
			R = R + Incr
		until Pso.Pso <= thresholdPso

		local PsoMax = result[1].Pso
		return result, R - 1, math.floor((R - 1) / 2 + 0.5)
	end

	-- Get a string value of a weapon with category / subcategory names and more
	BLAST.getWeaponCategoryName = function(track)
		local result = BLAST.WeaponCategoryNames[track.category];

		if track.category == Weapon.Category.SHELL then
			if track.type and string.find(track.type, "_AP", 1, true) then
				result = result .. " AP"
			elseif track.type and string.find(track.type, "_HE", 1, true) then
				result = result .. " HE"
			end
		elseif track.category == Weapon.Category.BOMB then
			local attributes = track.desc.attributes
			if attributes then
				local attr = ""
				for k, a in pairs(attributes) do
					if a then
						attr = attr .. ":" .. k
					end
				end
				result = string.format("%s attr:%s", result, attr)
			end
		elseif track.category == Weapon.Category.MISSILE then
			if track.missileCategory then
				result = string.format("%s %s", result, BLAST.MissileCategoryNames[track.missileCategory])
			else
				result = string.format("%s %i", result, track.missileCategory)
			end
		end

		return result
	end

	-- Get value of power set for a munition given
	BLAST.getWarhead = function(weaponType, isCluster)
		local result = 0.0

		if BLAST.weapons[weaponType] and BLAST.weapons[weaponType].TNTe then
			local w = BLAST.weapons[weaponType]

			if (w.TNTe > 0) then
				result = w.TNTe
			end

			if (w.category == Weapon.Category.ROCKET) then
				result = result * BLAST.options.rocketBoost
			end
		elseif isCluster then 
			local clusterName = ""
			if BLAST.weapons[weaponType] then
				clusterName = BLAST.weapons[weaponType].clusterName
			elseif BLAST.clusters[weaponType] then
				clusterName = weaponType
			else
				-- TODO msg unknow cluster
			end
			if clusterName and BLAST.clusters[clusterName].TNTe then
				result = BLAST.clusters[clusterName].TNTe
			end
		end

		return result
	end

	BLAST.getClusterBox = function(track)
		if BLAST.clusters[track.clusterName] then
			local cluster = BLAST.clusters[track.clusterName]
			if cluster then 
			local dispersion = cluster.disp + track.cluster.elapsTime * 0.018
				if dispersion > 2 then dispersion = 2 end

					track.cluster.polygon = BLAST.rectangle3D(track.cluster.ip, cluster.lenght, cluster.width, track.heading,dispersion)

				-- define a box to detect all units into (SW min, NE max)
				track.cluster.box = BLAST.getSearchBox(track.cluster.polygon)

				-- a cloud of smoke to see where is the box BLAST.getGroundHeight( track.position.ip )
				if BLAST.options.debugManaged and BLAST.options.smoke then
					trigger.action.smoke(track.cluster.ip, trigger.smokeColor.Red)
					trigger.action.smoke(track.cluster.polygon[1], trigger.smokeColor.Green)
					trigger.action.smoke(track.cluster.polygon[2], trigger.smokeColor.Red)
					trigger.action.smoke(track.cluster.polygon[3], trigger.smokeColor.White)
					trigger.action.smoke(track.cluster.polygon[4], trigger.smokeColor.Blue)
				end
			end
		end
		return true
	end

	-- get units list in a oriented box for cluster
	BLAST.getUnitsInBox = function(sw, ne)
		local result = {}
		local u = {}
		local box = {
			id = world.VolumeType.BOX,
			params = {
				min = sw,
				max = ne
			}
		}
		world.searchObjects(Object.Category.UNIT, box, function(unit)
			if unit:isExist() then
				local u = {
					id = unit.id_,
					name = unit:getName(),
					type = unit:getTypeName(),
					category = Object.getCategory(unit),
					life = unit:getLife0(),
					health = unit:getLife(),
					object = unit,
					p = unit:getPosition().p
				}
				table.insert(result, u)
			end
			return true
		end)

		return result
	end

	-- apply an explosion and add flare if requested
	BLAST.applyExplosion = function(ip, TNTe, flare)
		trigger.action.explosion(ip, TNTe)

		if flare then
			for i = 1, BLAST.options.flareNumber do
				local az = math.random(0, 359) -- Random angle for scatter
				local oX = math.random(-5, 5) -- Position offset (meters)
				local oZ = math.random(-5, 5)
				local p = { x = ip.x + oX, y = ip.y, z = ip.z + oZ }
				trigger.action.signalFlare(p, 2, az)
			end
		end

		return nil
	end

	-- get true when the weapon is trackable
	-- TODO : the weapons trackable should be configured in the settings
	BLAST.isTrackable = function(weapon)
		local result = false
		if (type(weapon) == "table") and weapon.isExist and weapon:isExist() then
			local d = weapon:getDesc()
			-- should be a weapon except SHELL
			result = (
				(d.category == Weapon.Category.SHELL) or
				(d.category == Weapon.Category.BOMB) or
				(d.category == Weapon.Category.ROCKET) or
				(
					(d.category == Weapon.Category.MISSILE) and
					(
						(d.missileCategory == Weapon.MissileCategory.AAM) or
						(d.missileCategory == Weapon.MissileCategory.BM) or
						(d.missileCategory == Weapon.MissileCategory.ANTI_SHIP) or
						(d.missileCategory == Weapon.MissileCategory.CRUISE) or
						(d.missileCategory == Weapon.MissileCategory.OTHER)
					)
				)
			)
		end
		return result
	end


	BLAST.getClusterIP = function(
		position, -- Position (vec3)
		velocity, -- Velocity (vec3)
		physics -- Physical properties and behaviours of the cluster
	)
		-- get wind layers
		local alt = BLAST.getGroundHeight(position)
		local winds = BLAST.getWinds(position, BLAST.windStep, alt)

		-- telemetry
		local trajectory = {}

		-- Constantes physiques
		local g = 9.81         -- Gravitational acceleration (m/s^2)
		local rho0 = 1.225     -- Air density at sea level (kg/m^3)
		local rho = 0.0        -- Air density
		local H = 8500         --  Scale height for atmospheric conditions (m)
		local wind = { x = 0, y = 0, z = 0 } -- Wind vector
		local windIndex = 0    -- Wwind index
		local et = 0.0         -- Elaps Time, start time = 0
		local dt = 0.1         -- more little more precise

		-- physicals proprerties
		local mass = physics.m0
		local surface = physics.s0
		local cx = physics.cx0
		local sx = physics.sx0
		local we = physics.we
		local mh = physics.mh
		local step = 1 -- 1st step of the trajectory

		-- init locals
		local ip = { x = position.x, y = position.y, z = position.z }
		local ve = { x = velocity.x * physics.sr, y = velocity.y * physics.sr, z = velocity.z * physics.sr }
		local ve_rel = { x = 0.0, y = 0.0, z = 0.0 }
		local ve_mag = 0.0
		local ve_unit = { x = 0.0, y = 0.0, z = 0.0 }

		local drag = { x = 0.0, y = 0.0, z = 0.0 }
		local drag_mag = 0.0
		local lift_mag = 0.0
		local lift = { x = 0.0, y = 0.0, z = 0.0 }
		local fx = { x = 0.0, y = 0.0, z = 0.0 }

		if BLAST.options.debugManaged then
			BLAST.info(string.format("position = {x=%.0f,y=%.0f,z=%.0f}", position.x, position.y, position.z))
			BLAST.info(string.format("velocity = {x=%.2f,y=%.2f,z=%.2f} = %3.2fm/s", velocity.x, velocity.y, velocity.z,
				math.sqrt(velocity.x ^ 2 + velocity.y ^ 2 + velocity.z ^ 2)))
			BLAST.info(string.format("vel*sr   = {x=%.2f,y=%.2f,z=%.2f} = %3.2fm/s", ve.x, ve.y, ve.z,
				math.sqrt(ve.x ^ 2 + ve.y ^ 2 + ve.z ^ 2)))
		end

		-- while the cluster is above the minimum heigh
		while ip.y > mh + alt do
			-- 1. Calculation of air density based on altitude (simplified model)
			rho = rho0 * math.exp(-ip.y / H)

			-- 2. Relative speed relative to the wind

			windIndex = math.floor(ip.y / BLAST.windStep) * BLAST.windStep
			if winds[windIndex] then
				wind = winds[windIndex]
			end
			ve_rel = { x = ve.x - wind.x * we, y = ve.y - wind.y * we, z = ve.z - wind.z * we }
			ve_mag = math.sqrt(ve_rel.x ^ 2 + ve_rel.y ^ 2 + ve_rel.z ^ 2)

			-- optimization when the velocity vector is purely vertical
			if ve_mag > 0 then
				-- physicals props of the object can change if elapsed time is over elaps time in opening of the cluster
				if (step == 1) and (physics.de > 0) and (physics.de < et) then
					mass = physics.m1
					surface = physics.s1
					cx = physics.cx1
					sx = physics.sx1
					step = 2
				end

				-- 3. Unitary vector of relative velocity (direction)
				ve_unit = { x = ve_rel.x / ve_mag, y = ve_rel.y / ve_mag, z = ve_rel.z / ve_mag }

				-- 4. Calculation of Drag
				drag_mag = 0.5 * rho * ve_mag ^ 2 * surface * cx
				drag = { x = -ve_unit.x * drag_mag, y = -ve_unit.y * drag_mag, z = -ve_unit.z * drag_mag }

				-- 5. Calculation of Lift - Simplified, Perpendicular to the Direction of Travel
				-- Note: For lift, we assume here that it acts upward (y)
				lift_mag = 0.5 * rho * ve_mag ^ 2 * surface * sx
				lift = { x = 0, y = lift_mag, z = 0 }

				-- 6. Sum of forces and acceleration (F = m*a => a = F/m)
				fx = { x = drag.x / mass, y = (drag.y + lift.y) / mass - g, z = drag.z / mass }

				-- 7. Speed Update (v = v + a*dt)
				ve = { x = ve.x + fx.x * dt, y = ve.y + fx.y * dt, z = ve.z + fx.z * dt }
			else
				-- If there is no movement, only gravity is at work
				ve.z = ve.z - g * dt
			end

			-- 8. IP update (p = p + v*dt)
			ip = { x = ip.x + ve.x * dt, y = ip.y + ve.y * dt, z = ip.z + ve.z * dt }

			-- 9. next time step
			et = et + dt

			-- todo : save telemetry in a file
			if BLAST.options.telemetryManaged then
				table.insert(trajectory, { et = et, x = ip.x, y = ip.y, z = ip.z, v = ve_mag })
			end
		end

		if BLAST.options.debugManaged then
			BLAST.info(string.format("délai %.3fs, ip={x=%.0f,y=%.0f,z=%.0f}", et, ip.x, ip.y, ip.z))
			if BLAST.options.smoke then
				trigger.action.smoke(ip, trigger.smokeColor.Orange)
			end
		end

		return ip, et
	end

	-- create a new instance of BLAST class
	function BLAST:new()
		local instance = setmetatable({}, BLAST)
		return instance
	end

	-- get all useful details to manage a weapon track from an event
	function BLAST:getTrack(event)
		local result = {}

		if type(event.weapon) == "table" and event.weapon.isExist and event.weapon:isExist() and event.initiator then
			if event.weapon.getCategory(event.weapon) == Object.Category.WEAPON then
				local isCluster = false
				result = {
					id = event.weapon.id_,
					weapon = event.weapon,
					name = event.weapon:getDesc().displayName or "no displayname",
					category = event.weapon:getDesc().category,
					desc = event.weapon:getDesc(),
					type = event.weapon:getTypeName() or "no type",
					position = event.weapon:getPosition(),
					velocity = event.weapon:getVelocity(),
					hit = 0,
					dead = false,
					initiatorId = event.initiator and event.initiator.id_,
					initiatorName = event.initiator and event.initiator:getName() or "no initiator",
					playerName = (Object.getCategory(event.initiator) == Object.Category.UNIT) and
					event.initiator:getPlayerName() or false,
					TNTo = 0.0
				}
				result.heading = BLAST.vec3Heading(result.position.x)
				result.height = result.position.p.y - BLAST.getGroundHeight(result.position.p)
				result.ip = land.getIP(result.position.p, result.position.x, 150)

				if (result.category == Weapon.Category.MISSILE) then
					result.missileCategory = result.desc.missileCategory
				end
				result.categoryName = BLAST.getWeaponCategoryName(result)

				if BLAST.weapons[result.type] and BLAST.weapons[result.type].clusterName then
					result.clusterName = BLAST.weapons[result.type].clusterName
					isCluster = true
				end

				result.TNTe = BLAST.getWarhead(result.type, isCluster)
				if (result.desc.warhead and result.desc.warhead.mass) then
					result.TNTo = result.desc.warhead.mass
				end
				if (result.desc.warhead and result.desc.warhead.caliber) then
					result.TNTo = result.desc.warhead.caliber
				end

				result.flare = self.options.flareVisualEffect and BLAST.tableHasKey(BLAST.weapons[result.type], "flare") and
				BLAST.weapons[result.type].flare or false

				-- get default warhead to trace diff between blast damage and DCS
				if BLAST.tableHasKey(result.desc, "warhead") then
					result.warhead = result.desc.warhead.explosiveMass or result.desc.warhead.shapedExplosiveMass
				else
					result.warhead = -1
				end

				-- apply boost power if this is a hit and we know the target
				if event.target then
					local o = self:getObject(event.target)
					if o then
						result.object = o
						if (result.object.category == Object.Category.STATIC) then
							result.TNTe = result.TNTe * BLAST.options.staticBoost
						elseif (result.object.category == Object.Category.SCENERY) then
							result.TNTe = result.TNTe * BLAST.options.sceneryBoost
						end
					end
				end
			end
		end

		return result
	end

	-- get all useful details to manage a weapon track from an event
	function BLAST:getCluster(w, id)

		local cluster
		if type(w) == "table" and w.isExist and w:isExist() and (w.getCategory(w) == Object.Category.WEAPON) then
			local position = w:getPosition()
			cluster = {
				id = w.id_,
				weapon = w,
				type = w:getTypeName(),
				category = w:getDesc().category,
				position = position,
				velocity = w:getVelocity(),
				height = position.p.y - BLAST.getGroundHeight(position.p),
				heading = BLAST.vec3Heading(position.x),
				altitude = position.p.y,
				speed = 0.0,
				ip = {},
				box = {},
				TNTe = 0.0,
				hit = 0
			}
		else
			w = self.trackedWeapons[id]
			cluster = {
				id = -1,
				weapon = nil,
				type = w.clusterName,
				category = w.category,
				position = BLAST.deepcopy(w.position),
				velocity = w.velocity,
				height = w.position.p.y - BLAST.getGroundHeight(w.position.p),
				heading = BLAST.vec3Heading(w.position.x),
				altitude = w.position.p.y,
				speed = 0.0,
				ip = {},
				box = {},
				TNTe = 0.0,
				hit = 0
			}
		end
		cluster.speed = BLAST.vec3_mag(cluster.velocity)
		cluster.TNTe = BLAST.getWarhead(cluster.type, true)

		self.trackedWeapons[id].clusterDead = false

		return cluster
	end

	-- get all useful information about an object
	function BLAST:getObject(o)
		local result = {}

		if o and o:isExist() then
			local objectCategory = Object.getCategory(o)

			if (objectCategory == Object.Category.UNIT) or (objectCategory == Object.Category.STATIC) or (objectCategory == Object.Category.SCENERY) then
				result = {
					name = o:getName(),
					type = o:getTypeName(),
					category = objectCategory,
					subCategory = o:getDesc().category,
					isInfantry = o:hasAttribute("Infantry"),
					isVehicle = o:hasAttribute("Vehicles"),
					life = 0,
					health = 0,
					position = o:getPosition(),
					object = o,
					blastTNT = 0,
					range = 0
				}

				-- get the box if object have it otherwise 1 unit of surface
				result.boxLength = 1
				result.boxHeight = 1
				result.boxDepth = 1
				if BLAST.tableHasKey(o:getDesc(), "box") then
					local box        = o:getDesc().box
					result.boxLength = (box.max.x + math.abs(box.min.x))
					result.boxHeight = (box.max.y + math.abs(box.min.y))
					result.boxDepth  = (box.max.z + math.abs(box.min.z))
				end
				result.surface = result.boxLength * result.boxHeight
				result.heading = BLAST.vec3Heading(result.position.x)

				-- ground units, statics, scenary and cargos
				if (result.category == Object.Category.UNIT) then
					result.life = o:getLife0()
					result.health = o:getLife()
				elseif (result.category == Object.Category.STATIC) then
					result.life = o:getLife() or 1
					result.health = result.life
				elseif (result.category == Object.Category.SCENERY) then
					result.life = o:getLife()
					result.health = o:getLife()
				else
					result.life = o:getLife() or 1
					result.health = result.life
				end
			end
		end

		return result
	end

	-- apply damages when thresholds are reached
	function BLAST:applyDamages(track, o)
		if o.object:isExist() then
			-- eval percentage of health remaining
			local healthRemaining = (o.healthRemaining - 1) / (o.life - 1) * 100

			-- for all ground units alive
			if (o.healthRemaining > 0) then
				-- health threshold depending of the ground unit's category
				if (o.isInfantry and (healthRemaining <= self.options.infantryFireThreshold)) or (o.isVehicle and (healthRemaining <= self.options.vehicleFireThreshold)) then
					local c = o.object:getController()
					c:setOption(AI.Option.Ground.id.ROE, AI.Option.Ground.val.ROE.WEAPON_HOLD)
					self:addStatsForHoldWeapon(track.type, track.name, o.type, o.name, track.playerName)
					BLAST.info(string.format("Unit %s disable fire.", o.name))
				end

				-- for all units alive disable ability to move below threshold
				if (o.isInfantry and (healthRemaining <= self.options.infantryMovementThreshold)) or (o.isVehicle and (healthRemaining <= self.options.vehicleMovementThreshold)) then
					local c = o.object:getController()
					c:setTask({ id = 'Hold', params = {} })
					c:setOnOff(false)
					self:addStatsForHoldMovement(track.type, track.name, o.type, o.name, track.playerName)
					BLAST.info(string.format("Unit %s disable movements.", o.name))
				end
			end
		end
	end

	-- scheduled function to manage blast effect and damages
	function BLAST:applyBlastEffect(track, o)
		-- object not dead
		if o.object:isExist() and o.blastTNT then
			timer.scheduleFunction(
				function(args)
					local p = args[1]
					local TNTe = args[2]
					local flare = args[3]
					local track = args[4]
					local o = args[5]

					BLAST.applyExplosion(p, TNTe, flare)

					if o.object:isExist() then
						o.healthRemaining = o.object:getLife()
						BLAST.info(string.format('Weapon %s %s:%s (%i) BLAST %s %s:%s, TNTe %.3fkg, health %.3f/%.3f',
							track.categoryName, track.type, track.name, track.id, BLAST.ObjectCategoryNames[o.category],
							o.type, o.name,
							o.blastTNT, o.healthRemaining, o.health))

						-- apply damange model only on ground units found
						if BLAST.options.damageManaged and (o.isInfantry or o.isVehicle) and o.object:isExist() then
							self:applyDamages(track, o)
						end
						self:addStatsForWeaponBlast(track.type, track.name, o.type, o.name, track.playerName)
					else
						o.healthRemaining = 0.0
					end
				end,
				{ o.position.p, o.blastTNT, false, track, o },
				timer.getTime() + o.range / BLAST.options.blastDiffusionDelay
			)
		end

		track.objectsCount = track.objectsCount - 1
	end

	-- detect and apply effects to all units / objects identified
	function BLAST:getBlastedObjects(track)
		local objects = {}
		local added = false
		-- get the Pso table and the maxRange to apply effect
		local PsoTable, infantryRadius, vehicleRadius = BLAST.getPsoTable(track.TNTe, 0)

		if (#PsoTable > 1) or (track.weaponDead == false) then
			local PsoMax = PsoTable[1].Pso
			local searchSphere = { id = world.VolumeType.SPHERE, params = { point = track.ip, radius = infantryRadius } }

			-- will found the list of all objects in the blast wave area and out of excludes zones
			local ifSearchObjects = function(object, val)
				-- object is not dead
				if object:isExist() then
					local o = self:getObject(object)

					-- out of an exclusion area
					if o and (not BLAST.isInExclusionArea(o.position.p, self.exclusionAreas)) then
						o.range = math.floor(BLAST.distance3D(track.ip, o.position.p) + 0.5)

						-- limit the blast effect to nearby vehic	les only as the effect is far too weak
						if (o.category == Object.Category.UNIT) and (o.subCategory == Unit.Category.GROUND_UNIT) then
							-- in the effect radius depending of the unit infantry or vehicle
							if (o.isInfantry and (o.range <= infantryRadius)) or (o.isVehicle and (o.range <= vehicleRadius)) then
								-- blast power by the range and eq TNT and exposed surface
								o.blastTNT = track.TNTe * ((PsoTable[o.range].Pso / PsoMax) / 100) * o.surface
								table.insert(objects, o)
								local added = true
							end
						elseif (o.category == Object.Category.STATIC) then
							o.blastTNT = track.TNTe * self.options.staticBoost
							table.insert(objects, o)
							local added = true
						elseif (o.category == Object.Category.SCENERY) then
							o.blastTNT = track.TNTe * self.options.sceneryBoost
							table.insert(objects, o)
							local added = true
						else
							o.blastTNT = 0.01
						end

						if added then
							BLAST.info(string.format(
								'Weapon %s %s:%s (%i) %s %s:%s (%i) object added at range %ift < %ift/%ift, blastTNT %.3fkg, health %.3f',
								track.categoryName, track.type, track.name, track.id,
								BLAST.ObjectCategoryNames[o.category], o.type, o.name, o.id,
								BLAST.meters2feet(o.range, false), BLAST.meters2feet(vehicleRadius, true),
								BLAST.meters2feet(infantryRadius, true), o.blastTNT, o.health))
						end
					end -- exclusion area
				end

				return true
			end -- local function

			-- inventory of objects having to support blast wave
			-- , Object.Category.CARGO and SCENERY excluded because too many objects without interest
			world.searchObjects({ Object.Category.UNIT, Object.Category.STATIC }, searchSphere, ifSearchObjects)
		end

		if (#objects > 1) then
			-- sort from near to far objects
			table.sort(objects, function(left, right) return left.range < right.range end)
		end

		return objects
	end

	-- apply blast effect
	---@param track table of weapon params
	---@param objects table of objects detected
	---@return nil
	function BLAST:blastObjects(track, objects)
		-- for each object found, apply the right blast effect
		for k, o in pairs(objects) do
			if (o.blastTNT > 0) and (o.health > 1) then
				self:applyBlastEffect(track, o)
			end
		end
	end

	-- apply effect after that the weapon is hitting or dead.
	---@param track table weapon
	---@return nil
	function BLAST:standardWeapon(track)
		--effect must be applyed at the explosion location or the object hitted
		if not track.hit then
			-- impact point: terrain intersection point with weapon's nose.  Only search out 50 meters though.
			track.ip = land.getIP(track.position.p, track.position.x, 200)
			if not track.ip then -- use last calculated IP
				track.ip = track.position.p
			end
		else
			track.ip = track.position.p
		end

		if BLAST.options.debugManaged and BLAST.options.smoke then
			trigger.action.smoke(track.ip, BLAST.options.smokeColor)
		end

		-- proceed to the standard damages with the power of weapon set
		if (BLAST.options.explosionsManaged) then
			BLAST.applyExplosion(track.ip, track.TNTe, track.flare)

			local life = 0
			if track.object and track.object.object then
				life = BLAST.getLifePercentage(track.object.object)
			end

			if track.hit and track.object and track.object.name then
				BLAST.info(string.format(
					"Weapon %s %s:%s (%i) explosion, TNTe/warhead = %.3f, on object [%s] %s:%s, health %i%% / %.3f",
					track.categoryName, track.type, track.name, track.id, track.TNTe,
					BLAST.ObjectCategoryNames[track.object.category],
					track.object.type, track.object.name, life, track.object.life))
			else
				BLAST.info(string.format("Weapon %s %s:%s (%i) explosion, TNTe/warhead = %.3f, health %i%% ",
					track.categoryName, track.type, track.name, track.id, track.TNTe, life))
			end
		end

		-- apply a blast effect only when the munition is deleted
		if (self.options.blastwaveManaged) and (not track.cluster) then --(not track.hit) and
			-- proceed to the peripheral damages
			local objects = self:getBlastedObjects(track)
			track.objectsCount = #objects
			BLAST.info(string.format('Weapon %s %s:%s (%i) %i objects detected', track.categoryName, track.type,
				track.name, track.id, #objects))
			if (#objects > 0) then
				self:blastObjects(track, objects)
			end
		end

		track.weaponDead = true
	end

	-- apply effect of a number of bomblets defined by the cluster
	---@param args table of params
	---@return nil
	function BLAST:clusterWeapon(args)
		local track = args[1]

		BLAST.getClusterBox(track)
		local units = BLAST.getUnitsInBox(track.cluster.box.sw, track.cluster.box.ne)

		if (#units > 0) then
			for i = 1, self.clusters[track.clusterName].count do
				local u = units[math.random(1, #units)]
				if u and u.object:isExist() then
					timer.scheduleFunction(
						function(args)
							local no = args[1]
							local u = args[2]
							local p = u.p
							local TNTe = args[3]
							local flare = args[4]
							BLAST.applyExplosion(p, TNTe, flare)
							u.health = u.object:getLife()

							BLAST.info(string.format(
								"Cluster (%i) bomblet #%02d, unit %s, power=%.3f, health %i%% / %.3f",
								args[5].id, no, u.name, TNTe, BLAST.getLifePercentage(u.object), u.life))

							self:addStatsForWeaponHit(track.type, track.name, u.type, u.name, track.playerName)
						end,
						{ i, u, track.cluster.TNTe, track.flare, track },
						timer.getTime() + math.random(1, math.floor(track.cluster.elapsTime * 100)) / 100
					)
				end
			end
		end

		track.clusterDead = true
	end

	-- cluster detected only in local mode
	function BLAST:detectCluster(args)
		local id = args[1]
		local iteration = args[2] + 1

		local clusterName = self.trackedWeapons[id].clusterName
		local scanVol = {
			id = world.VolumeType.SPHERE,
			params = { point = self.trackedWeapons[id].position.p, radius = 400 * iteration }
		}

		local clusterFound = false
		world.searchObjects(Object.Category.WEAPON, scanVol, function(w)
			-- if the cluster is not currently tracked
			if not clusterFound and not self.trackedClusters[w.id_] and not self.trackedWeapons[w.id_] and w:isExist() then
				local weaponType = w:getTypeName()

				-- this is the cluster expected and this cluster is orphan of track
				if (weaponType == clusterName) then
					self.trackedWeapons[id].cluster = self:getCluster(w, id)
					self.trackedClusters[w.id_] = id

					local d = BLAST.distance3D(self.trackedWeapons[id].position.p,
						self.trackedWeapons[id].cluster.position.p)
					BLAST.info(string.format("Cluster found %i:%i:%s at %.2fm, altitude %.2fm, heading %i°",
						id, self.trackedWeapons[id].cluster.id, self.trackedWeapons[id].cluster.type, d,
						self.trackedWeapons[id].cluster.position.p.y,
						self.trackedWeapons[id].cluster.heading))
					clusterFound = true
				end
			end

			return not clusterFound
		end)

		-- track must be destroy if no cluster found
		if not clusterFound then
			if iteration <= 4 then
				timer.scheduleFunction(
					function(args)
						self:detectCluster(args)
					end,
					{ id, iteration },
					timer.getTime() + 0.2
				)
			else
				self.trackedWeapons[id].clusterDead = true
				BLAST.info(string.format("Cluster not found %i %s/%s", self.trackedWeapons[id].id,
					self.trackedWeapons[id].name, clusterName))
			end
		end
	end

	-- cluster tracked only in local mode
	function BLAST:onTrackClusters()
		local track

		for clusterId, trackId in pairs(self.trackedClusters) do

			if self.trackedWeapons[trackId] then
				track = self.trackedWeapons[trackId]

				if track.weaponDead and track.clusterDead then
					self.trackedClusters[clusterId] = nil
					self.trackedWeapons[trackId] = nil

					BLAST.info(string.format("Weapon %s %s:%s (%i/%i) track and cluster dead",
						track.categoryName, track.type, track.name, track.id, track.cluster.id))

				elseif track.cluster then
					-- if cluster continue to descent, follow it
					if track.cluster.weapon:isExist() then
						track.cluster.position = track.cluster.weapon:getPosition()
						track.cluster.velocity = track.cluster.weapon:getVelocity()
						track.cluster.altitude = track.cluster.position.p.y
						track.cluster.height = track.cluster.position.p.y - BLAST.getGroundHeight(track.cluster.position.p)
						track.cluster.speed = BLAST.vec3_mag(track.cluster.velocity)

						if self.options.telemetryManaged and self.options.hTelemetry then
							BLAST.writeTelemetry(self.options.hTelemetry, 'onTrackWeapons cluster live', track.cluster)
						end

					elseif not track.clusterDead then
						-- update ip (center of strike zone)

						BLAST.info(string.format("Cluster dead %i:%i/ %s", track.id, track.cluster.id, track.cluster.type))

						track.cluster.elapsTime = 1
						track.cluster.ip = track.cluster.position.p
						track.cluster.ip.y = BLAST.getGroundHeight(track.cluster.ip)

						if BLAST.options.debugManaged and BLAST.options.smoke then
							trigger.action.smoke(track.cluster.ip, BLAST.options.smokeColor)
						end

						timer.scheduleFunction(
							function(args)
								self:clusterWeapon(args)
							end,
							{ track },
							timer.getTime() + 0.01
						)
					end
				end
			end
		end

		return true
	end

	-- track all weapons registered with S_EVENT_SHOT and apply effect if conditions are met or prepare execution of cluster effect
	function BLAST:onTrackWeapons()
		for id, track in pairs(self.trackedWeapons) do
			-- weapon is alive, just update informations
			if track.weapon:isExist() then
				track.position = track.weapon:getPosition()
				track.velocity = track.weapon:getVelocity()
				track.heading = BLAST.vec3Heading(track.position.x)
				track.height = track.position.p.y - BLAST.getGroundHeight(track.position.p)
				track.speed = BLAST.vec3_mag(track.velocity)
				track.pitch = math.asin(track.position.x.y)
				if self.options.telemetryManaged and self.options.hTelemetry then
					BLAST.writeTelemetry(self.options.hTelemetry, 'onTrackWeapons live', track)
				end

				-- weapon is dead, apply effects or find out the cluster
			elseif not track.weaponDead then
				-- apply effects immediatly for a standard weapon
				if (track.TNTe > 0) and not track.clusterName then
					self:standardWeapon(track)

					-- weapon is dead, but find out and follow the cluster alive
				elseif self.options.clusterManaged and track.clusterName and not track.cluster then
					track.weaponDead = true

					-- local mode : cluster detection
					if not BLAST.isMultiPlayer then
						local iteration = 0
						timer.scheduleFunction(
							function(args)
								self:detectCluster(args)
							end,
							{ track.id, iteration },
							timer.getTime() + 0.2
						)

					-- server mode : trajectory simulation
					else
						if BLAST.options.debugManaged and BLAST.options.smoke then
							trigger.action.smoke(track.position.p, BLAST.options.smokeColor)
						end

						-- get cluster IP and elapsTime of the bomblet's strike zone	
						track.cluster = self:getCluster(nil, id)
						track.cluster.ip, track.cluster.elapsTime = BLAST.getClusterIP(track.position.p, track.velocity,
							BLAST.clusters[track.clusterName].physics)
						track.cluster.id = -1 -- no real cluster, only simulated
						track.cluster.ip.y = BLAST.getGroundHeight(track.cluster.ip)

						timer.scheduleFunction(
							function(args)
								self:clusterWeapon(args)
								if track.weaponDead and track.cluster and track.clusterDead then
									BLAST.info(string.format("Weapon %s %s:%s (%i/%i) track and cluster dead",
										track.categoryName, track.type, track.name, track.id, track.cluster.id))
								end
							end,
							{ track },
							timer.getTime() + track.cluster.elapsTime
						)
					end
				end
			end

			if (track.weaponDead and not track.clusterName) then
				BLAST.info(string.format("Weapon %s %s:%s (%i) track dead", track.categoryName, track.type, track.name,
					track.id))
				self.trackedWeapons[track.id] = nil
			elseif (track.weaponDead and track.clusterDead) then
				self.trackedWeapons[track.id] = nil
			end
		end
		return true
	end

	--[[
local function explorerTable(t, nomTable, resultats)
    resultats = resultats or { champs = {}, fonctions = {} }
    nomTable = nomTable or "root"
    local s = ""
    for k, v in pairs(t) do
        -- Construction du chemin (ex: parent.enfant)
        local chemin = nomTable .. "." .. tostring(k)

        if type(v) == "function" then
            table.insert(resultats.fonctions, chemin)
        elseif type(v) == "table" then
            -- Si c'est une table, on l'ajoute aux champs ET on l'explore
            table.insert(resultats.champs, chemin .. " (table)")
            explorerTable(v, chemin, resultats)
        else
            s = chemin .. " [" .. type(v) .. "]"
            if ((type(v) == 'number') or (type(v) == 'boolean')) then
              s = s .. " = " .. tostring(v)
            elseif (type(v) == 'string') then
              s = s .. " = " .. string.format('"%s"',v)
            elseif (type(v) == 'nil') then
              s = s .. " = " .. "nil"
            end

            table.insert(resultats.champs, s)
        end
    end

    return resultats
end

local extraction = explorerTable(event.weapon, "Weapon")
local s = ""
for _, c in ipairs(extraction.champs) do s = s .. c .."\r\n" end
for _, f in ipairs(extraction.fonctions) do s = s .. f .."\r\n" end	
BLAST.info( s )
--]]

	function BLAST:onEventManaged(event)
		-- occurs when a weapon is shoted
		if (event.id == world.event.S_EVENT_SHOT) then
			--BLAST.info( "Weapon SHOT")
			if BLAST.isTrackable(event.weapon) then
				local track = self:getTrack(event)
				if track then
					-- save weapon and parameters
					self.trackedWeapons[track.id] = track
					-- registers all weapons except that are not managed or catagory excluded
					self:addStatsForWeaponShot(track.type, track.name, track.playerName)
					BLAST.info(string.format("Weapon %s %s:%s %s(%i) (TNTe %.3f / TNTo%.3f) SHOT by %s (%i) ",
						track.categoryName, track.type, track.name, (track.clusterName or ""), track.id, track.TNTe,
						track.TNTo,
						track.initiatorName, track.initiatorId))
					self:addStatsForWeaponTrack(track.type, track.name)

					if self.options.telemetryManaged and self.options.hTelemetry then
						BLAST.writeTelemetry(self.options.hTelemetry, 'S_EVENT_SHOT', track)
					end
				end
			end

			-- occurs when a munition hit an object or an object hit an another object
		elseif (event.id == world.event.S_EVENT_HIT) then
			if event.weapon then
				if self.trackedWeapons[event.weapon.id_] then
					local track = self.trackedWeapons[event.weapon.id_]
					if track then
						track.object = self:getObject(event.target)
						track.hit = track.hit + 1
						-- when a weapon tracked hit something					

						if track.object and ((track.object.category == Object.Category.UNIT) or (track.object.category == Object.Category.STATIC) or (track.object.category == Object.Category.SCENERY)) then
							-- nothing else to do for a tracked weapon
							local pctlife = math.floor((track.object.health / track.object.life) * 100)
							BLAST.info(string.format("Weapon %s %s:%s (%i) HIT %s:%s, fired by %s, health %i%%",
								track.categoryName, track.type, track.name, track.id,
								track.object.type, track.object.name, track.initiatorName, pctlife))
							self:addStatsForWeaponHit(track.type, track.name, track.object.type, track.object.name,
								track.playerName)
							if self.options.telemetryManaged and self.options.hTelemetry then
								BLAST.writeTelemetry(self.options.hTelemetry, 'S_EVENT_HIT', track)
							end
						end
					end
				end
			end
			-- Occurs on the death of a unit
		elseif (event.id == world.event.S_EVENT_KILL) then
			--BLAST.info( "Weapon KILL")
			if event.target then
				--local objectCategory = Object.getCategory( event.target )
				local playerName = event.initiator and BLAST.tableHasKey(event.initiator, 'getPlayerName') and
				event.initiator:getPlayerName() or false
				if playerName then
					local targetType = event.target:getTypeName() or 'no type'
					local targetName = event.target.getName and event.target:getName() or "unknow"
					local weaponName = "no name"
					local weaponType = "no type"
					if event.weapon and type(event.weapon) == "table" and event.weapon.isExist and event.weapon:isExist() then
						weaponName = event.weapon:getDesc().displayName
						weaponType = event.weapon:getTypeName()
					end
					self:addStatsEventKill(targetType, targetName, playerName, weaponName, weaponType)
				end
			end

			-- Occurs when the game thinks an object is destroyed.
		elseif (event.id == world.event.S_EVENT_DEAD) then
			--BLAST.info( "Weapon DEAD")
			if event.initiator then
				local initiatorCategory = Object.getCategory(event.initiator)

				if (initiatorCategory == Object.Category.UNIT) or (initiatorCategory == Object.Category.STATIC) or --initiatorCategory == Object.Category.SCENERY  or
					(initiatorCategory == Object.Category.WEAPON) then
					local targetType = event.initiator:getTypeName() or "scenery"
					local targetName = event.initiator:getName()
					self:addStatsEventDead(targetType, targetName)
				end
			end


			-- Occurs at the end of the mission to close telemetry handle
		elseif (event.id == world.event.S_EVENT_MISSION_END) then
			if self.options.telemetryManaged and self.options.hTelemetry then
				self.options.hTelemetry = BLAST.closeTelemetry(self.options.hTelemetry)
			end

			if self.options.msgStatistics then
				self:saveStats()
			end
		end
	end

	-- event function filtering calls on only managed events
	function BLAST:onEvent(event)
		if (event.id == world.event.S_EVENT_SHOT) or (event.id == world.event.S_EVENT_HIT) or (event.id == world.event.S_EVENT_KILL) or (event.id == world.event.S_EVENT_DEAD) or (event.id == world.event.S_EVENT_MISSION_END) then
			blastProtectedCall(function()
				self:onEventManaged(event)
			end, {})
		end
	end

	-- init statistics
	function BLAST:initStatistics()
		self.stats.weapons = {}
		self.stats.weaponsOther = {}
		self.stats.players = {}
		self.stats.targets = {}
		self.stats.shotCount = 0
		self.stats.trackCount = 0
		self.stats.otherCount = 0
		self.stats.hitCount = 0
		self.stats.blastCount = 0
		self.stats.killCount = 0
		self.stats.deadCount = 0
		self.stats.weaponHoldCount = 0
		self.stats.movementHoldCount = 0
	end

	function BLAST:initWeaponStatistics(weaponName)
		local result = { name = weaponName, shotCount = 0, trackCount = 0, clusterCount = 0, ids = {}, otherCount = 0, hitCount = 0, blastCount = 0, killCount = 0, deadCount = 0, weaponHoldCount = 0, movementHoldCount = 0 }
		return result
	end

	function BLAST:initTargetStatistics(unitName)
		local result = { name = unitName, hitCount = 0, blastCount = 0, killCount = 0, deadCount = 0, weaponHoldCount = 0, movementHoldCount = 0 }
		return result
	end

	function BLAST:initPlayerStatistics(playerName)
		local result = { name = playerName, shotCount = 0, hitCount = 0, blastCount = 0, killCount = 0, deadCount = 0, weaponHoldCount = 0, movementHoldCount = 0, weapons = {} }
		return result
	end

	function BLAST:addStatsForWeaponShot(weaponType, weaponName, playerName)
		self.stats.shotCount = self.stats.shotCount + 1
		--if BLAST.weapons[weaponType] then
		if not self.stats.weapons[weaponType] then
			self.stats.weapons[weaponType] = self:initWeaponStatistics(weaponName)
		end
		self.stats.weapons[weaponType].shotCount = self.stats.weapons[weaponType].shotCount + 1
		--end

		if playerName then
			if not self.stats.players[playerName] then
				self.stats.players[playerName] = self:initPlayerStatistics(playerName)
			end
			self.stats.players[playerName].shotCount = self.stats.players[playerName].shotCount + 1

			if not self.stats.players[playerName].weapons[weaponType] then
				self.stats.players[playerName].weapons[weaponType] = self:initWeaponStatistics(weaponName)
			end
			self.stats.players[playerName].weapons[weaponType].shotCount = self.stats.players[playerName].weapons
			[weaponType].shotCount + 1
		end
	end

	function BLAST:addStatsForWeaponTrack(weaponType, weaponName)
		self.stats.trackCount = self.stats.trackCount + 1
		if not self.stats.weapons[weaponType] then
			self.stats.weapons[weaponType] = self:initWeaponStatistics(weaponName)
		end
		self.stats.weapons[weaponType].trackCount = self.stats.weapons[weaponType].trackCount + 1
	end

	function BLAST:addStatsForWeaponOther(weaponType, weaponName)
		self.stats.otherCount = self.stats.otherCount + 1
		if not self.stats.weaponsOther[weaponType] then
			self.stats.weaponsOther[weaponType] = self:initWeaponStatistics(weaponName)
		end
		self.stats.weaponsOther[weaponType].otherCount = self.stats.weaponsOther[weaponType].otherCount + 1
	end

	function BLAST:addStatsForWeaponHit(weaponType, weaponName, targetType, unitName, playerName)
		self.stats.hitCount = self.stats.hitCount + 1

		if BLAST.clusters[weaponType] then
			local clusterType = weaponType
			weaponType = BLAST.clusters[weaponType]
		end

		if self.stats.weapons[weaponType] then
			self.stats.weapons[weaponType].hitCount = self.stats.weapons[weaponType].hitCount + 1
		elseif self.stats.weaponsOther[weaponType] then
			self.stats.weaponsOther[weaponType].hitCount = self.stats.weaponsOther[weaponType].hitCount + 1
		end

		if not self.stats.targets[targetType] then
			self.stats.targets[targetType] = self:initTargetStatistics(unitName)
		end
		self.stats.targets[targetType].hitCount = self.stats.targets[targetType].hitCount + 1

		if playerName then
			if not self.stats.players[playerName] then
				self.stats.players[playerName] = self:initPlayerStatistics(playerName)
			end
			self.stats.players[playerName].hitCount = self.stats.players[playerName].hitCount + 1

			if not self.stats.players[playerName].weapons[weaponType] then
				self.stats.players[playerName].weapons[weaponType] = self:initWeaponStatistics(weaponName)
			end
			self.stats.players[playerName].weapons[weaponType].hitCount = self.stats.players[playerName].weapons
			[weaponType].hitCount + 1
		end
	end

	function BLAST:addStatsForWeaponBlast(weaponType, weaponName, targetType, unitName, playerName)
		self.stats.blastCount = self.stats.blastCount + 1
		if self.stats.weapons[weaponType] then
			self.stats.weapons[weaponType].blastCount = self.stats.weapons[weaponType].blastCount + 1
		end

		if not self.stats.targets[targetType] then
			self.stats.targets[targetType] = self:initTargetStatistics(unitName)
		end
		self.stats.targets[targetType].blastCount = self.stats.targets[targetType].blastCount + 1

		if playerName then
			if not self.stats.players[playerName] then
				self.stats.players[playerName] = self:initPlayerStatistics(playerName)
			end
			self.stats.players[playerName].blastCount = self.stats.players[playerName].blastCount + 1

			if not self.stats.players[playerName].weapons[weaponType] then
				self.stats.players[playerName].weapons[weaponType] = self:initWeaponStatistics(weaponName)
			end
			self.stats.players[playerName].weapons[weaponType].blastCount = self.stats.players[playerName].weapons
			[weaponType].blastCount + 1
		end
	end

	function BLAST:addStatsForHoldWeapon(weaponType, weaponName, targetType, unitName, playerName)
		self.stats.weaponHoldCount = self.stats.weaponHoldCount + 1

		if not self.stats.weapons[weaponType] then
			self.stats.weapons[weaponType] = self:initWeaponStatistics(weaponName)
		end
		self.stats.weapons[weaponType].weaponHoldCount = self.stats.weapons[weaponType].weaponHoldCount + 1

		if not self.stats.targets[targetType] then
			self.stats.targets[targetType] = self:initTargetStatistics(unitName)
		end
		self.stats.targets[targetType].weaponHoldCount = self.stats.targets[targetType].weaponHoldCount + 1

		if playerName then
			if not self.stats.players[playerName] then
				self.stats.players[playerName] = self:initPlayerStatistics(playerName)
			end
			self.stats.players[playerName].weaponHoldCount = self.stats.players[playerName].weaponHoldCount + 1

			if not self.stats.players[playerName].weapons[weaponType] then
				self.stats.players[playerName].weapons[weaponType] = self:initWeaponStatistics(weaponName)
			end
			self.stats.players[playerName].weapons[weaponType].weaponHoldCount = self.stats.players[playerName].weapons
			[weaponType].weaponHoldCount + 1
		end
	end

	function BLAST:addStatsForHoldMovement(weaponType, weaponName, targetType, unitName, playerName)
		self.stats.movementHoldCount = self.stats.movementHoldCount + 1
		if not self.stats.weapons[weaponType] then
			self.stats.weapons[weaponType] = self:initWeaponStatistics(weaponName)
		end
		self.stats.weapons[weaponType].movementHoldCount = self.stats.weapons[weaponType].movementHoldCount + 1

		if not self.stats.targets[targetType] then
			self.stats.targets[targetType] = self:initTargetStatistics(unitName)
		end
		self.stats.targets[targetType].movementHoldCount = self.stats.targets[targetType].movementHoldCount + 1

		if playerName then
			if not self.stats.players[playerName] then
				self.stats.players[playerName] = self:initPlayerStatistics(playerName)
			end
			self.stats.players[playerName].movementHoldCount = self.stats.players[playerName].movementHoldCount + 1

			if not self.stats.players[playerName].weapons[weaponType] then
				self.stats.players[playerName].weapons[weaponType] = self:initWeaponStatistics(weaponName)
			end
			self.stats.players[playerName].weapons[weaponType].movementHoldCount = self.stats.players[playerName]
			.weapons[weaponType].movementHoldCount + 1
		end
	end

	function BLAST:addStatsEventKill(targetType, targetName, playerName, weaponName, weaponType)
		self.stats.killCount = self.stats.killCount + 1

		if BLAST.clusters[weaponType] then
			local clusterType = weaponType
			weaponType = BLAST.clusters[weaponType]
		end

		if not self.stats.targets[targetType] then
			self.stats.targets[targetType] = self:initTargetStatistics(targetName)
		end
		self.stats.targets[targetType].killCount = self.stats.targets[targetType].killCount + 1

		if playerName then
			if not self.stats.players[playerName] then
				self.stats.players[playerName] = self:initPlayerStatistics(playerName)
			end
			self.stats.players[playerName].killCount = self.stats.players[playerName].killCount + 1

			if not self.stats.players[playerName].weapons[weaponType] then
				self.stats.players[playerName].weapons[weaponType] = self:initWeaponStatistics(weaponName)
			end
			self.stats.players[playerName].weapons[weaponType].killCount = self.stats.players[playerName].weapons
			[weaponType].killCount + 1
		end
	end

	function BLAST:addStatsEventDead(targetType, targetName, playerName, weaponName, weaponType)
		self.stats.deadCount = self.stats.deadCount + 1

		if weaponType and BLAST.clusters[weaponType] then
			local clusterType = weaponType
			weaponType = BLAST.clusters[weaponType]
		end


		if not self.stats.targets[targetType] then
			self.stats.targets[targetType] = self:initTargetStatistics(targetName)
		end
		self.stats.targets[targetType].deadCount = self.stats.targets[targetType].deadCount + 1

		if playerName then
			if not self.stats.players[playerName] then
				self.stats.players[playerName] = self:initPlayerStatistics(playerName)
			end
			self.stats.players[playerName].deadCount = self.stats.players[playerName].deadCount + 1

			if not self.stats.players[playerName].weapons[weaponType] then
				self.stats.players[playerName].weapons[weaponType] = self:initWeaponStatistics(weaponName)
			end
			self.stats.players[playerName].weapons[weaponType].deadCount = self.stats.players[playerName].weapons
			[weaponType].deadCount + 1
		end
	end

	-- function to save stats in dcs logs
	function BLAST:saveStats()
		BLAST.info("--- blast damage : statistics ---")
		BLAST.info(string.format("Shot %i", self.stats.shotCount))
		BLAST.info(string.format("Track %i", self.stats.trackCount))
		BLAST.info(string.format("Other %i", self.stats.otherCount))
		BLAST.info(string.format("Hits %i", self.stats.hitCount))
		BLAST.info(string.format("Blasts %i", self.stats.blastCount))
		BLAST.info(string.format("Kill %i", self.stats.killCount))
		BLAST.info(string.format("Dead %i", self.stats.deadCount))
		BLAST.info(string.format("Weapons hold %i", self.stats.weaponHoldCount))
		BLAST.info(string.format("Movements hold %i", self.stats.movementHoldCount))
		BLAST.info(" ")

		BLAST.info("Weapons")
		for id, weapon in pairs(self.stats.weapons) do
			BLAST.info(string.format("	%s : %i shots, %i hits, %i blasts, %i weapon hold, %i movements hold",
				weapon.name, weapon.shotCount, weapon.hitCount, weapon.blastCount, weapon.weaponHoldCount,
				weapon.movementHoldCount))
		end

		for id, weapon in pairs(self.stats.weaponsOther) do
			BLAST.info(string.format("	%s : %i shots, %i hits", weapon.name, weapon.shotCount, weapon.hitCount))
		end
		BLAST.info(" ")

		BLAST.info("Targets")
		for uId, target in pairs(self.stats.targets) do
			BLAST.info(string.format("	%s : %i hits, %i blasts, %i kill for %i dead, %i fire hold, %i movement hold",
				uId, target.hitCount, target.blastCount, target.killCount, target.deadCount, target.weaponHoldCount,
				target.movementHoldCount))
		end
		BLAST.info(" ")

		BLAST.info("Players")
		for pId, player in pairs(self.stats.players) do
			BLAST.info(string.format(
				"	%s : %i shots, %i hits, %i blasts, %i kill for %i dead, %i fire hold, %i movement hold",
				pId, player.shotCount, player.hitCount, player.blastCount, player.killCount, player.deadCount,
				player.weaponHoldCount, player.movementHoldCount))

			for wId, weapon in pairs(player.weapons) do
				BLAST.info(string.format(
					"	   %s : %i shots, %i hits, %i kill for %i dead, %i blasts, %i weapon hold, %i movements hold",
					weapon.name, weapon.shotCount, weapon.hitCount, weapon.killCount, weapon.deadCount, weapon
					.blastCount, weapon.weaponHoldCount, weapon.movementHoldCount))
			end
			BLAST.info(" ")
		end
	end

	-- function to switch state of blast damage ON/OFF depending of the mission flag "blastDamageState = 0 or 1"
	function BLAST.showStatus(sp, forceShow)
		forceShow = forceShow or false
		BLAST.info(
		string.format("--- blast damage %s : running in %s mode ---", BLAST.version,
			BLAST.isMultiPlayer and "Server" or "Local"), forceShow)
		BLAST.info(string.format("Script state is %s", sp.options.state and "ON" or "OFF"), forceShow)
		BLAST.info(string.format("Debug mode is %s", sp.options.debugManaged and "ON" or "OFF"), forceShow)
		BLAST.info(string.format("Messages in game is %s", sp.options.debugManaged and "ON" or "OFF"), forceShow)
		BLAST.info(string.format("Large explosion is %s", sp.options.explosionsManaged and "ON" or "OFF"), forceShow)
		BLAST.info(string.format("Cluster effects is %s", sp.options.clusterManaged and "ON" or "OFF"), forceShow)
		BLAST.info(string.format("Blast effect is %s", sp.options.blastwaveManaged and "ON" or "OFF"), forceShow)
		BLAST.info(string.format("Units damages is %s", sp.options.damageManaged and "ON" or "OFF"), forceShow)
		BLAST.info(string.format("Exclusion(s) area(s) found is %i ", #sp.exclusionAreas), forceShow)
	end

	-- function to switch state of blast damage ON/OFF depending of the mission flag "blastDamageState = 0 or 1"
	function BLAST.stateOnOff(sp, flag)
		if (sp.options.state ~= flag) then
			sp.removeMenu(sp)
			sp:switchState(flag)
			sp.setSubMenus(sp)
			BLAST.info(string.format("Blast Damage: %s", sp.options.state and "ON" or "OFF"))
		end
	end

	-- function to switch state of blast damage ON/OFF depending of the mission flag "blastDamageState = 0 or 1"
	function BLAST.debugOnOff(sp, flag)
		if (sp.options.debugManaged ~= flag) then
			sp.removeMenu(sp)
			sp.options.debugManaged = flag
			sp.setSubMenus(sp)
			BLAST.info(string.format("Debug mode: %s", sp.options.debugManaged and "ON" or "OFF"))
		end
	end

	-- function to switch state of blast damage ON/OFF depending of the mission flag "blastDamageState = 0 or 1"
	function BLAST.msgInGameOnOff(sp, flag)
		if (sp.options.msgInGame ~= flag) then
			sp.removeMenu(sp)
			sp.options.msgInGame = flag
			sp.setSubMenus(sp)
			BLAST.info(string.format("Messages in game: %s", sp.options.msgInGame and "ON" or "OFF"))
		end
	end

	-- function to switch Statistics live ON/OFF
	function BLAST.statisticsOnOff(sp, flag)
		if (sp.options.msgStatistics ~= flag) then
			sp.removeMenu(sp)
			sp.options.msgStatistics = flag
			sp.setSubMenus(sp)
			BLAST.info(string.format("Statistics live: %s", sp.options.msgStatistics and "ON" or "OFF"))
		end
	end

	-- function to switch state of blast damage ON/OFF depending of the mission flag "blastDamageState = 0 or 1"
	function BLAST.removeMenu(sp)
		if sp.options.state then
			missionCommands.removeItem(sp.mnuState.ON)
		else
			missionCommands.removeItem(sp.mnuState.OFF)
		end

		if sp.options.debugManaged then
			missionCommands.removeItem(sp.mnuDebug.ON)
		else
			missionCommands.removeItem(sp.mnuDebug.OFF)
		end

		if sp.options.msgInGame then
			missionCommands.removeItem(sp.mnuMsgInGame.ON)
		else
			missionCommands.removeItem(sp.mnuMsgInGame.OFF)
		end

		if sp.options.msgStatistics then
			missionCommands.removeItem(sp.mnuStatistics.ON)
		else
			missionCommands.removeItem(sp.mnuStatistics.OFF)
		end
	end

	-- function to switch state of blast damage ON/OFF depending of the mission flag "blastDamageState = 0 or 1"
	function BLAST.setSubMenus(sp)
		sp:menuState()
		sp:menuDebug()
		sp:menuMgsInGame()
		sp:menuStatistics()
	end

	-- function to set menus directly in the mission
	function BLAST:menuState()
		if self.options.state then
			self.mnuState.ON = missionCommands.addCommand("Blast Damage to OFF", self.mnuMain, self.stateOnOff, self,
				false)
		else
			self.mnuState.OFF = missionCommands.addCommand("Blast Damage to ON", self.mnuMain, self.stateOnOff, self,
				true)
		end
	end

	-- function to set menus directly in the mission
	function BLAST:menuDebug()
		if self.options.debugManaged then
			self.mnuDebug.ON = missionCommands.addCommand("Debug mode to OFF", self.mnuMain, self.debugOnOff, self, false)
		else
			self.mnuDebug.OFF = missionCommands.addCommand("Debug mode to ON", self.mnuMain, self.debugOnOff, self, true)
		end
	end

	-- function to set menus directly in the mission
	function BLAST:menuMgsInGame()
		if self.options.msgInGame then
			self.mnuMsgInGame.ON = missionCommands.addCommand("Messages in game to OFF", self.mnuMain,
				self.msgInGameOnOff, self, false)
		else
			self.mnuMsgInGame.OFF = missionCommands.addCommand("Messages in game to ON", self.mnuMain,
				self.msgInGameOnOff, self, true)
		end
	end

	-- function to set menus directly in the mission
	function BLAST:menuStatistics()
		if self.options.msgStatistics then
			self.mnuStatistics.ON = missionCommands.addCommand("Statistics to OFF", self.mnuMain, self.statisticsOnOff,
				self, false)
		else
			self.mnuStatistics.OFF = missionCommands.addCommand("Statistics to ON", self.mnuMain, self.statisticsOnOff,
				self, true)
		end
	end

	-- function to set menus directly in the mission
	function BLAST:initMenus()
		-- main menu
		self.mnuMain = missionCommands.addSubMenu("Blast Damage")

		-- show sp status
		self.mnuStatus = missionCommands.addCommand("Show status", self.mnuMain, self.showStatus, self)

		-- script ON/OFF
		BLAST.setSubMenus(self)
	end

	-- switch blast damage ON/OFF
	function BLAST:switchState(flag)
		-- activation
		if flag then
			if DCS then
				BLAST.isMultiPlayer = DCS.isMultiplayer() -- DCS.isServer()
			end

			self.exclusionAreas = BLAST.getExclusionAreas(self.options.areasPattern)

			-- add handle to track weapons
			self.hTrackWeapons = timer.scheduleFunction(
				function()
					blastProtectedCall(function()
						self:onTrackWeapons()
					end, {})
					return timer.getTime() + self.options.timerOnTrack
				end,
				{}, timer.getTime() + self.options.timerOnTrack -- time for the next call
			)

			-- add handle to track clusters
			self.hTrackClusters = timer.scheduleFunction(
				function()
					blastProtectedCall(function()
						self:onTrackClusters()
					end, {})
					return timer.getTime() + self.options.timerOnTrack
				end,
				{}, timer.getTime() + self.options.timerOnTrack
			)

			-- add event handler on DCS S_EVENT_????
			world.addEventHandler(self)

			if self.options.telemetryManaged then
				self.options.hTelemetry = BLAST.openTelemetry()
			end

			-- deactivation
		else
			world.removeEventHandler(self)
			if self.hTrackWeapons then
				timer.removeFunction(self.hTrackWeapons)
				self.hTrackWeapons = false
				timer.removeFunction(self.hTrackClusters)
				self.hTrackClusters = false
			end

			-- list of weapons flying deleted
			self.trackedWeapons = {}
			self.trackedClusters = {}
			self.exclusionAreas = {}

			-- init statistics
			self:initStatistics()

			if self.options.telemetryManaged and self.options.hTelemetry then
				self.options.hTelemetry = BLAST.closeTelemetry(self.options.hTelemetry)
			end

			if self.options.msgStatistics then
				self:saveStats()
			end
		end

		self.options.state = flag
		BLAST.info(string.format("BLAST version %s, %s mode", self.version, BLAST.ModesNames[BLAST.isMultiPlayer]))
	end

	function BLAST:start()
		if (self.options.startAuto == true) and (self.options.state == false) then
			self:switchState(true)
		end
		self:initMenus()
	end

	blast = BLAST:new()
	blast:start()
	
end -- do
