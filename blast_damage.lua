--[[
0.9.1
	- new: Cluster's trajectory management with wind corretions, munitions tested BLU-108 only

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

	-- class definition
	BLAST = {
		className_ = "BLAST", -- class name
		exclusionAreas = {}, -- list of zone where effects are excluded
		trackedWeapons = {}, -- list of tracked weapons (mainly bombs)
		hTrackWeapons = false, -- store handle of the scheduled function trackWeapons 
		multiPlayer = false, -- true when mission exec in multiplayer mode

		-- menus
		mnuMain = nil, -- add the main menu 
		mnuState = { ON = nil, OFF = nil }, -- add a menu enable/disable 
		mnuDebug = { ON = nil, OFF = nil }, -- add a menu enable/disable debug mode
		mnuMsgInGame = { ON = nil, OFF = nil }, -- add a menu to enable/disable messages in game 
		mnuStatistics = { ON = nil, OFF = nil }, -- add a menu to enable/disable messages in game 

		version = "0.9.1", -- current version
	}
	BLAST.__index = BLAST

----[[ ##### SCRIPT CONFIGURATION ##### ]]----
	BLAST.options = {
		explosionsManaged = true, -- enable enhanced explosions management
		blastwaveManaged = true, -- enable blast wave management
		clusterManaged = true,	 -- enable cluster management

		blastDiffusionDelay = 10, -- speed of the effect from the center of explosion to the peripheral (10 = 0.1 sec/meter)

		staticBoost = 1.0, -- apply extra damage to Unit.Category.STRUCTURE 
		sceneryBoost = 2.0, -- apply extra damage to Unit.Category.SCENERY
		rocketBoost = 2.0, -- apply a coefficient of power for rockets
		
		flareVisualEffect = true, -- activate visual effect of white flare, consumes a lot of resources
		
		areasPattern = "#BLAST#", -- tag contained in the name of an exclusion aera

		damageManaged = true, -- allow blast wave to affect ground unit movement and fire
		vehicleMovementThreshold = 70, -- below the threshold the movements are disabled to simulate severe injury
		vehicleFireThreshold = 80, -- below the threshold the ROE are set to ON HOLD to simulate severe injury
		infantryMovementThreshold = 70, -- below the threshold the movements are disabled to simulate severe injury
		infantryFireThreshold = 80, -- below the threshold the ROE are set to ON HOLD to simulate severe injury

		-- timer management, do not set value below 0.01s, change carrefuly the default values
		timerOnShot = 0.05, -- each 0.05s S_EVENT_SHOT event is checked 
		timerOnTrack = 0.05, -- delay between 2 checks of weapons tracked, do not set a too much long time 

		-- debug mode
		debugManaged = false, -- enable trace log
		msgInGame = false, -- enable messages in game for players
		msgStatistics = true,  -- log for statistics

		smoke = false, -- show a smoke for the impact point or zones  
		smokeColor = trigger.smokeColor.Green, -- available colors : Green Red White Orange Blue


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
		shotCount = 0, -- number of shots for existing weapons
		trackCount = 0, -- number of tracked weapons
		otherCount = 0, -- number of weapons excluded of the tracking
		hitCount = 0, -- number of direct hits for existing weapons
		blastCount = 0, -- number of objects hits by the blast effect
		killCount = 0, -- number of objects kill (for DCS bda)
		deadCount = 0, -- number of objects dead (for DCS and blast)
		weaponHoldCount = 0, -- number of objects having damages with ROE = Weapon hold 
		movementHoldCount = 0, -- number of objects having damages with movements hold
	}

	-- munitions: bombs, missiles and rockets, for each munition type the value of equivalent TNT
	-- new means that this munitions was not present at the origin (splash)  
	-- 0 means that there is no explosive charge, AGM-154A for example
	BLAST.weapons = {
		-- bombs
		["250-2"] = {category=Weapon.Category.BOMB, TNTe=80}, -- New, China Asset Pack by Deka Ironwork Simulations and Eagle Dynamics
		["250-3"] = {category=Weapon.Category.BOMB, TNTe=80}, -- New, China Asset Pack by Deka Ironwork Simulations and Eagle Dynamics
		["AB_250_2_SD_10A"] = {category=Weapon.Category.BOMB, TNTe=0.12}, -- New, World War II AI Units by Eagle Dynamics
		["AB_250_2_SD_2"] = {category=Weapon.Category.BOMB, TNTe=0.12}, -- New, World War II AI Units by Eagle Dynamics
		["AB_500_1_SD_10A"] = {category=Weapon.Category.BOMB, TNTe=0.9}, -- New, World War II AI Units by Eagle Dynamics
		["AGM_62"] = {category=Weapon.Category.BOMB, TNTe=400},
		["AGM_62_I"] = {category=Weapon.Category.BOMB, TNTe=149.6}, -- New
		["AN_M30A1"] = {category=Weapon.Category.BOMB, TNTe=45}, -- ("AN-M30A1 - 100lb GP Bomb LD")
		["AN_M57"] = {category=Weapon.Category.BOMB, TNTe=100}, -- ("AN-M57 - 250lb GP Bomb LD")
		["AN_M64"] = {category=Weapon.Category.BOMB, TNTe=121}, -- New
		["AN_M65"] = {category=Weapon.Category.BOMB, TNTe=400}, -- ("AN-M65 - 1000lb GP Bomb LD")
		["AN_M66"] = {category=Weapon.Category.BOMB, TNTe=800}, -- ("AN-M66 - 2000lb GP Bomb LD")
		["KMGU_2_AO_2_5RT"] = {category=Weapon.Category.BOMB, TNTe=1.2}, -- New
		["BAP_100"] = {category=Weapon.Category.BOMB, TNTe=3.5}, -- New
		["BAP-100"] = {category=Weapon.Category.BOMB, TNTe=3.5}, -- New
		["BAP-120"] = {category=Weapon.Category.BOMB, TNTe=10.8}, -- New
		["BDU_33"] = {category=Weapon.Category.BOMB, TNTe=0}, -- New
		["BDU_45"] = {category=Weapon.Category.BOMB, TNTe=0}, -- New
		["BDU_45B"] = {category=Weapon.Category.BOMB, TNTe=0}, -- New
		["BDU_45LGB"] = {category=Weapon.Category.BOMB, TNTe=0}, -- New
		["BDU_50HD"] = {category=Weapon.Category.BOMB, TNTe=0}, -- New
		["BDU_50LD"] = {category=Weapon.Category.BOMB, TNTe=0}, -- New
		["BDU_50LGB"] = {category=Weapon.Category.BOMB, TNTe=0}, -- New
		["BEER_BOMB"] = {category=Weapon.Category.BOMB, TNTe=1}, -- New 
		["BELOUGA"] = {category=Weapon.Category.BOMB, TNTe=94}, -- New
		["BETAB-500M"] = {category=Weapon.Category.BOMB, TNTe=551.6}, -- New
		["BETAB-500S"] = {category=Weapon.Category.BOMB, TNTe=280}, -- New
		["BIN_200"] = {category=Weapon.Category.BOMB, TNTe=20}, -- New
		["BKF_AO2_5RT"] = {category=Weapon.Category.BOMB, TNTe=1.2}, -- New
		["BKF_PTAB2_5KO"] = {category=Weapon.Category.BOMB, TNTe=0.65}, -- New
		["BLG66"] = {category=Weapon.Category.BOMB, TNTe=94}, -- New
		["BLG66_BELOUGA"] = {category=Weapon.Category.BOMB, TNTe=32},
		["BLU-3B_GROUP"] = {category=Weapon.Category.BOMB, TNTe=0.17}, -- New
		["BLU-3_GROUP"] = {category=Weapon.Category.BOMB, TNTe=0.17}, -- New
		["BL_755"] = {category=Weapon.Category.BOMB, TNTe=0.5}, -- New
		["BR_250"] = {category=Weapon.Category.BOMB, TNTe=118},
		["BR_500"] = {category=Weapon.Category.BOMB, TNTe=118},
		["BetAB_500"] = {category=Weapon.Category.BOMB, TNTe=98},
		["BetAB_500ShP"] = {category=Weapon.Category.BOMB, TNTe=107},
		["British_AP_25LBNo1_3INCHNo1"] = {category=Weapon.Category.BOMB, TNTe=4}, -- ("RP-3 25lb AP Mk.I")
		["British_GP_250LB_Bomb_Mk1"] = {category=Weapon.Category.BOMB, TNTe=100}, -- ("250 lb GP Mk.I")
		["British_GP_250LB_Bomb_Mk4"] = {category=Weapon.Category.BOMB, TNTe=100}, -- ("250 lb GP Mk.IV")
		["British_GP_250LB_Bomb_Mk5"] = {category=Weapon.Category.BOMB, TNTe=100}, -- ("250 lb GP Mk.V")
		["British_GP_500LB_Bomb_Mk1"] = {category=Weapon.Category.BOMB, TNTe=213}, -- ("500 lb GP Mk.I")
		["British_GP_500LB_Bomb_Mk4"] = {category=Weapon.Category.BOMB, TNTe=213}, -- ("500 lb GP Mk.IV")
		["British_GP_500LB_Bomb_Mk4_Short"] = {category=Weapon.Category.BOMB, TNTe=213}, -- ("500 lb GP Short tail")
		["British_GP_500LB_Bomb_Mk5"] = {category=Weapon.Category.BOMB, TNTe=213}, -- ("500 lb GP Mk.V")
		["British_HE_60LBSAPNo2_3INCHNo1"] = {category=Weapon.Category.BOMB, TNTe=4}, -- ("RP-3 60lb SAP No2 Mk.I")
		["British_HE_60LBFNo1_3INCHNo1"] = {category=Weapon.Category.BOMB, TNTe=4}, -- ("RP-3 60lb F No1 Mk.I")
		["British_MC_250LB_Bomb_Mk1"] = {category=Weapon.Category.BOMB, TNTe=100}, -- ("250 lb MC Mk.I")
		["British_MC_250LB_Bomb_Mk2"] = {category=Weapon.Category.BOMB, TNTe=100}, -- ("250 lb MC Mk.II")
		["British_MC_500LB_Bomb_Mk1_Short"] = {category=Weapon.Category.BOMB, TNTe=213}, -- ("500 lb MC Short tail")
		["British_MC_500LB_Bomb_Mk2"] = {category=Weapon.Category.BOMB, TNTe=213}, -- ("500 lb MC Mk.II")
		["British_SAP_250LB_Bomb_Mk5"] = {category=Weapon.Category.BOMB, TNTe=100}, -- ("250 lb S.A.P.")
		["British_SAP_500LB_Bomb_Mk5"] = {category=Weapon.Category.BOMB, TNTe=213}, -- ("500 lb S.A.P.")
		["CBU_103"] = {category=Weapon.Category.BOMB, TNTe=0}, -- New
		["CBU_105"] = {category=Weapon.Category.BOMB, TNTe=0}, -- New
		["CBU_52B"] = {category=Weapon.Category.BOMB, TNTe=0},
		["CBU_87"] = {
			category=Weapon.Category.BOMB,  
			cluster = {
				type="BLU-97B", count=202/10, TNTe=0.287, lenght=50, width=45, flare=true,
				phy = {
					m0	= 29.5,		-- mass during step 1 of flight (kg)
					Cx0	= 0.55, 	-- Drag coef (no unit)
					S0	= 0.2, 		-- Surface (m2)
					m1	= 1.5,		-- mass during step 2 of flight (kg) 
					Cx1	= 1.0, 	 	-- Drag coef (no unit)
					S1	= 0.11, 	-- Surface (m2)
					we	= 0.4,		-- wind effect (no unit)
					tc	= 1.0, 		-- delay of step 1 of flight
					hm	= 50		-- minimal height to calculate
				}
			} 
		},
		["CBU_97"] = {
			category=Weapon.Category.BOMB, 
			cluster = {
				type="BLU-108", count=20, TNTe=0.900, lenght=190, width=85, flare=true, 
				phy = {
					m0	= 29.5,		-- mass during step 1 of flight (kg)
					Cx0	= 0.55, 	-- Drag coef (no unit)
					S0	= 0.2, 		-- Surface (m2)
					m1	= 1.5,		-- mass during step 2 of flight (kg) 
					Cx1	= 1.0, 	 	-- Drag coef (no unit)
					S1	= 0.11, 	-- Surface (m2)
					we	= 0.4,		-- wind effect (no unit)
					tc	= 1.0, 		-- delay of step 1 of flight
					hm	= 50		-- minimal height to calculate
				}
			} 
		}, 
		["ROCKEYE"] = { -- CBU-99
			category=Weapon.Category.BOMB, 
			cluster = {
				type="Mk118", count=247/10, TNTe=0.600*2, lenght=80, width=200, flare=true, 
				phy = {
					m0	= 0.60,		-- mass during step 1 of flight (kg)
					Cx0	= 0.55, 	-- Drag coef (no unit)
					S0	= 0.2, 		-- Surface (m2)
					m1	= 0,		-- mass during step 2 of flight (kg) 
					Cx1	= 0, 	 	-- Drag coef (no unit)
					S1	= 0, 		-- Surface (m2)
					we	= 0.4,		-- wind effect (no unit)
					tc	= 0.0, 		-- delay of step 1 of flight
					hm	= 50		-- minimal height to calculate
				}
			}
		},
		["Durandal"] = {category=Weapon.Category.BOMB, TNTe=320}, -- New
		["FAB-250-M62"] = {category=Weapon.Category.BOMB, TNTe=80}, -- New
		["FAB-250M54"] = {category=Weapon.Category.BOMB, TNTe=226}, -- New
		["FAB_250M54TU"] = {category=Weapon.Category.BOMB, TNTe=100},
		["FAB_500M54"] = {category=Weapon.Category.BOMB, TNTe=428}, -- New
		["FAB_500M54TU"] = {category=Weapon.Category.BOMB, TNTe=428}, -- New
		["FAB_500SL"] = {category=Weapon.Category.BOMB, TNTe=440}, -- New
		["FAB_500TA"] = {category=Weapon.Category.BOMB, TNTe=382}, -- New
		["FAB_100"] = {category=Weapon.Category.BOMB, TNTe=45},
		["FAB_100M"] = {category=Weapon.Category.BOMB, TNTe=45}, -- New
		["FAB_100SV"] = {category=Weapon.Category.BOMB, TNTe=40}, -- New
		["FAB_1500"] = {category=Weapon.Category.BOMB, TNTe=675},
		["FAB_250"] = {category=Weapon.Category.BOMB, TNTe=100},
		["FAB_50"] = {category=Weapon.Category.BOMB, TNTe=25}, -- New
		["FAB_500"] = {category=Weapon.Category.BOMB, TNTe=213},
		["GBU_10"] = {category=Weapon.Category.BOMB, TNTe=582},
		["GBU_12"] = {category=Weapon.Category.BOMB, TNTe=118},
		["GBU_15_V_31_B"] = {category=Weapon.Category.BOMB, TNTe=349.6}, -- New
		["GBU_16"] = {category=Weapon.Category.BOMB, TNTe=274},
		["GBU_24"] = {category=Weapon.Category.BOMB, TNTe=582},
		["GBU_31"] = {category=Weapon.Category.BOMB, TNTe=582},
		["GBU_31_V_2B"] = {category=Weapon.Category.BOMB, TNTe=582},
		["GBU_31_V_3B"] = {category=Weapon.Category.BOMB, TNTe=582},
		["GBU_31_V_4B"] = {category=Weapon.Category.BOMB, TNTe=582},
		["GBU_32_V_2B"] = {category=Weapon.Category.BOMB, TNTe=202},
		["GBU_38"] = {category=Weapon.Category.BOMB, TNTe=118, flare=true},
		["GBU_39"] = {category=Weapon.Category.BOMB, TNTe=118},
		["GBU_54_V_1B"] = {category=Weapon.Category.BOMB, TNTe=0}, -- New
		["HB-F4E_GBU15V1"] = {category=Weapon.Category.BOMB, TNTe=340}, -- New
		["HB-F4E_GBU_8_HOBOS"] = {category=Weapon.Category.BOMB, TNTe=340}, -- New
		["HEBOMB"] = {category=Weapon.Category.BOMB, TNTe=40},
		["HEBOMBD"] = {category=Weapon.Category.BOMB, TNTe=40},
		["IAB-500"] = {category=Weapon.Category.BOMB, TNTe=524}, -- New
		["KAB_1500Kr"] = {category=Weapon.Category.BOMB, TNTe=675},
		["KAB_1500LG"] = {category=Weapon.Category.BOMB, TNTe=448}, -- New
		["KAB_1500T"] = {category=Weapon.Category.BOMB, TNTe=468}, -- New
		["KAB_500"] = {category=Weapon.Category.BOMB, TNTe=213},
		["KAB_500Kr"] = {category=Weapon.Category.BOMB, TNTe=213},
		["KAB_500S"] = {category=Weapon.Category.BOMB, TNTe=184}, -- New
		["LS-6-100"] = {category=Weapon.Category.BOMB, TNTe=40}, -- New
		["LS_6_100"] = {category=Weapon.Category.BOMB, TNTe=40}, -- New
		["MK106"] = {category=Weapon.Category.BOMB, TNTe=2.27}, -- New
		["MK76"] = {category=Weapon.Category.BOMB, TNTe=11.3}, -- New
		["MK_82AIR"] = {category=Weapon.Category.BOMB, TNTe=118},
		["MK_82SNAKEYE"] = {category=Weapon.Category.BOMB, TNTe=118}, -- New
		["M117"] = {category=Weapon.Category.BOMB, TNTe=140}, -- New
		["Mk_81"] = {category=Weapon.Category.BOMB, TNTe=60},
		["Mk_82"] = {category=Weapon.Category.BOMB, TNTe=118},
		["Mk_82Y"] = {category=Weapon.Category.BOMB, TNTe=72}, -- New
		["Mk_83"] = {category=Weapon.Category.BOMB, TNTe=274},
		["Mk_83CT"] = {category=Weapon.Category.BOMB, TNTe=160}, -- New
		["Mk_84"] = {category=Weapon.Category.BOMB, TNTe=582},
		["Mk_84AIR_GP"] = {category=Weapon.Category.BOMB, TNTe=582}, -- New
		["Mk_84AIR_TP"] = {category=Weapon.Category.BOMB, TNTe=582}, -- New
		["ODAB-500PM"] = {category=Weapon.Category.BOMB, TNTe=40000}, -- New
		["OFAB-100 Jupiter"] = {category=Weapon.Category.BOMB, TNTe=36}, -- New
		["OFAB-100-120TU"] = {category=Weapon.Category.BOMB, TNTe=88.6}, -- New
		["P-50T"] = {category=Weapon.Category.BOMB, TNTe=0.1}, -- New
		["PTAB-2-5"] = {category=Weapon.Category.BOMB, TNTe=0.65}, -- New
		["RN-24"] = {category=Weapon.Category.BOMB, TNTe=18000000},
		["RN-28"] = {category=Weapon.Category.BOMB, TNTe=1400000},
		["SAMP125LD"] = {category=Weapon.Category.BOMB, TNTe=64},
		["SAMP250HD"] = {category=Weapon.Category.BOMB, TNTe=118},
		["SAMP250LD"] = {category=Weapon.Category.BOMB, TNTe=118},
		["SAMP400HD"] = {category=Weapon.Category.BOMB, TNTe=274},
		["SAMP400LD"] = {category=Weapon.Category.BOMB, TNTe=274},
		["SC_250_T1_L2"] = {category=Weapon.Category.BOMB, TNTe=100}, -- ("SC 250 Type 1 L2 - 250kg GP Bomb LD")
		["SC_250_T3_J"] = {category=Weapon.Category.BOMB, TNTe=135}, -- New
		["SC_50"] = {category=Weapon.Category.BOMB, TNTe=25}, -- New
		["SC_500_L2"] = {category=Weapon.Category.BOMB, TNTe=213},
		["SD_250_Stg"] = {category=Weapon.Category.BOMB, TNTe=135},
		["SD_500_A"] = {category=Weapon.Category.BOMB, TNTe=213},
		["Type_200A"] = {category=Weapon.Category.BOMB, TNTe=90}, -- New						   

		-- Missiles
		["AGM_114"] = {category=Weapon.Category.MISSILE, TNTe=5.67}, -- New
		["AGM_114K"] = {category=Weapon.Category.MISSILE, TNTe=10},
		["AGM_119"] = {category=Weapon.Category.MISSILE, TNTe=176}, -- ???
		["AGM_122"] = {category=Weapon.Category.MISSILE, TNTe=15},
		["AGM_123"] = {category=Weapon.Category.MISSILE, TNTe=274},
		["AGM_122"] = {category=Weapon.Category.MISSILE, TNTe=4.08}, -- New
		["AGM_12A"] = {category=Weapon.Category.MISSILE, TNTe=36}, -- New
		["AGM_12B"] = {category=Weapon.Category.MISSILE, TNTe=40}, -- New
		["AGM_12C"] = {category=Weapon.Category.MISSILE, TNTe=45.2}, -- New
		["AGM_12C_ED"] = {category=Weapon.Category.MISSILE, TNTe=160}, -- New
		["AGM_130"] = {category=Weapon.Category.MISSILE, TNTe=582},
		["AGM_154"] = {category=Weapon.Category.MISSILE, TNTe=305},
		["AGM_154A"] = {
			category=Weapon.Category.MISSILE, 
			cluster = {
				type="BLU-97/B", count=25, TNTe=0.287, lenght=120, width=45, flare=true, 
				phy = {
					m0	= 29.5,		-- mass during step 1 of flight (kg)
					Cx0	= 0.55, 	-- Drag coef (no unit)
					S0	= 0.2, 		-- Surface (m2)
					m1	= 1.5,		-- mass during step 2 of flight (kg) 
					Cx1	= 1.0, 	 	-- Drag coef (no unit)
					S1	= 0.11, 	-- Surface (m2)
					we	= 0.4,		-- wind effect (no unit)
					tc	= 1.0, 		-- delay of step 1 of flight
					hm	= 50		-- minimal height to calculate
				}
			} 
		}, 
		["AGM_154B"] = {
			category=Weapon.Category.MISSILE,
			cluster = {
				type="BLU-108", count=25, TNTe=0.9, lenght=120, width=45, flare=true, 
				phy = {
					m0	= 29.5,		-- mass during step 1 of flight (kg)
					Cx0	= 0.55, 	-- Drag coef (no unit)
					S0	= 0.2, 		-- Surface (m2)
					m1	= 1.5,		-- mass during step 2 of flight (kg) 
					Cx1	= 1.0, 	 	-- Drag coef (no unit)
					S1	= 0.11, 	-- Surface (m2)
					we	= 0.4,		-- wind effect (no unit)
					tc	= 1.0, 		-- delay of step 1 of flight
					hm	= 50		-- minimal height to calculate
				}
			} 
		}, -- New: cluster BLU-108
		["GB-6"] = {
			category=Weapon.Category.MISSILE,
			cluster = {
				type="PTAB-2_5KO", count=150, TNTe=0.287*2, lenght=120, width=45, flare=true, 
				phy = {
					m0	= 4,	-- mass during step 1 of flight (kg)
					Cx0	= 0.55, 	-- Drag coef (no unit)
					S0	= 0.2, 	-- Surface (m2)
					m1	= 1.5,		-- mass during step 2 of flight (kg) 
					Cx1	= 0.4, 	-- Drag coef (no unit)
					S1	= 0.27, 	-- Surface (m2)
					tc	= 1.0, 	-- delay of step 1 of flight
					hm	= 50		-- minimal height to calculate
				}
			}
 
		}, --	BKF_PTAB2_5KO-- New: cluster
		["GB-6-HE"] = {
			category=Weapon.Category.MISSILE, TNTe=120,
			cluster = {type="BLU-108", count=25, TNTe=0.287*2, lenght=120, width=45, flare=true, 
				phy = {
					m0	= 29.5,		-- mass during step 1 of flight (kg)
					Cx0	= 0.55, 	-- Drag coef (no unit)
					S0	= 0.2, 		-- Surface (m2)
					m1	= 1.5,		-- mass during step 2 of flight (kg) 
					Cx1	= 1.0, 	 	-- Drag coef (no unit)
					S1	= 0.11, 	-- Surface (m2)
					we	= 0.4,		-- wind effect (no unit)
					tc	= 1.0, 		-- delay of step 1 of flight
					hm	= 50		-- minimal height to calculate
				}
			} 
		}, -- New
		["GB-6-SFW"] = {
			category=Weapon.Category.MISSILE, TNTe=0,
			cluster = {type="BLU-108", count=25, TNTe=0.287*2, lenght=120, width=45, flare=true, 
				phy = {
					m0	= 29.5,		-- mass during step 1 of flight (kg)
					Cx0	= 0.55, 	-- Drag coef (no unit)
					S0	= 0.2, 		-- Surface (m2)
					m1	= 1.5,		-- mass during step 2 of flight (kg) 
					Cx1	= 1.0, 	 	-- Drag coef (no unit)
					S1	= 0.11, 	-- Surface (m2)
					we	= 0.4,		-- wind effect (no unit)
					tc	= 1.0, 		-- delay of step 1 of flight
					hm	= 50		-- minimal height to calculate
				}
			} 
		}, -- New: cluster
		["AGM_45A"] = {category=Weapon.Category.MISSILE, TNTe=26.4}, -- New
		["AGM_45B"] = {category=Weapon.Category.MISSILE, TNTe=26.4}, -- New
		["AGM_65A"] = {category=Weapon.Category.MISSILE, TNTe=15.6}, -- New
		["AGM_65B"] = {category=Weapon.Category.MISSILE, TNTe=15.6}, -- New
		["AGM_65D"] = {category=Weapon.Category.MISSILE, TNTe=130},
		["AGM_65E"] = {category=Weapon.Category.MISSILE, TNTe=300},
		["AGM_65F"] = {category=Weapon.Category.MISSILE, TNTe=300},
		["AGM_65G"] = {category=Weapon.Category.MISSILE, TNTe=90}, -- New
		["AGM_65H"] = {category=Weapon.Category.MISSILE, TNTe=130},
		["AGM_65K"] = {category=Weapon.Category.MISSILE, TNTe=300},
		["AGM_65L"] = {category=Weapon.Category.MISSILE, TNTe=300},
		["AGM_78A"] = {category=Weapon.Category.MISSILE, TNTe=38.8}, -- New
		["AGM_78B"] = {category=Weapon.Category.MISSILE, TNTe=38.8}, -- New
		["AGM_84A"] = {category=Weapon.Category.MISSILE, TNTe=90}, -- New
		["AGM_84D"] = {category=Weapon.Category.MISSILE, TNTe=88.4}, -- New: cruise missile
		["AGM_84E"] = {category=Weapon.Category.MISSILE, TNTe=488}, -- New: cruise missile
		["AGM_84H"] = {category=Weapon.Category.MISSILE, TNTe=144}, -- New: cruise missile
		["AGM_84S"] = {category=Weapon.Category.MISSILE, TNTe=88.4}, -- New
		["AGM_86"] = {category=Weapon.Category.MISSILE, TNTe=180}, -- New
		["AGM_86C"] = {category=Weapon.Category.MISSILE, TNTe=400}, -- New: cruise missile
		["AGM_86D"] = {category=Weapon.Category.MISSILE, TNTe=400}, -- New: cruise missile
		["AGM_88"] = {category=Weapon.Category.MISSILE, TNTe=89},
		["AGR_20A"] = {category=Weapon.Category.MISSILE, TNTe=8},
		["AGR_20_M282"] = {category=Weapon.Category.MISSILE, TNTe=8}, -- A10C/AV8B APKWS  															 
		["AKD-10"] = {category=Weapon.Category.MISSILE, TNTe=5.67}, -- New
		["ALARM"] = {category=Weapon.Category.MISSILE, TNTe=26.4}, -- New
		["AT-6"] = {category=Weapon.Category.MISSILE, TNTe=2.4}, -- New
		["Ataka_9M120"] = {category=Weapon.Category.MISSILE, TNTe=7.4}, -- New
		["Ataka_9M120F"] = {category=Weapon.Category.MISSILE, TNTe=7.4}, -- New
		["Ataka_9M220"] = {category=Weapon.Category.MISSILE, TNTe=5.4}, -- New
		["BGM_109B"] = {category=Weapon.Category.MISSILE, TNTe=125.2}, -- New
		["BK90_MJ1"] = {category=Weapon.Category.MISSILE, TNTe=0}, -- New: cluster MJ1
		["BK90_MJ1_MJ2"] = {category=Weapon.Category.MISSILE, TNTe=0}, -- New: cluster
		["BK90_MJ2"] = {category=Weapon.Category.MISSILE, TNTe=0}, -- New: cluster
		["C-701IR"] = {category=Weapon.Category.MISSILE, TNTe=15}, -- New
		["CM-802AKG_AI"] = {category=Weapon.Category.MISSILE, TNTe=100}, -- New: cruise missile
		["CM-802AKG"] = {category=Weapon.Category.MISSILE, TNTe=76}, -- New: cruise missile
		["C_701T"] = {category=Weapon.Category.MISSILE, TNTe=15}, -- New
		["C_802AK"] = {category=Weapon.Category.MISSILE, TNTe=76}, -- New: cruise missile
		["DWS39_MJ1"] = {category=Weapon.Category.MISSILE, TNTe=0}, -- New: cluster MJ1
		["DWS39_MJ1_MJ2"] = {category=Weapon.Category.MISSILE, TNTe=0}, -- New: cluster	MJ1-MJ2
		["DWS39_MJ2"] = {category=Weapon.Category.MISSILE, TNTe=0}, -- New: cluster MJ2
		["HOT2"] = {category=Weapon.Category.MISSILE, TNTe=4},
		["HOT3_MBDA"] = {category=Weapon.Category.MISSILE, TNTe=5}, -- New
		["HY-2"] = {category=Weapon.Category.MISSILE, TNTe=196}, -- New
		["KD_20"] = {category=Weapon.Category.MISSILE, TNTe=200}, -- New: cruise missile
		["KD_63"] = {category=Weapon.Category.MISSILE, TNTe=200}, -- New: cruise missile
		["KD_63B"] = {category=Weapon.Category.MISSILE, TNTe=200}, -- New: cruise missile
		["Kh25MP_PRGS1VP"] = {category=Weapon.Category.MISSILE, TNTe=34.4}, -- New
		["LS_6"] = {category=Weapon.Category.MISSILE, TNTe=40}, -- New
		["LS_6_500"] = {category=Weapon.Category.MISSILE, TNTe=80}, -- New
		["Mistral"] = {category=Weapon.Category.MISSILE, TNTe=0.170}, -- manpads missile
		["YJ_12"] = {category=Weapon.Category.MISSILE, TNTe=400}, -- New: cruise missile
		["YJ_83"] = {category=Weapon.Category.MISSILE, TNTe=400}, -- New: cruise missile

		-- rockets
		["90-1_HE_Rocket"] = {category=Weapon.Category.ROCKET, TNTe=4.6}, -- New
		["AGR_20_M151_unguided"] = {category=Weapon.Category.ROCKET, TNTe=4}, -- New
		["AGR_20_M282_unguided"] = {category=Weapon.Category.ROCKET, TNTe=11}, -- New	
		["BRM-1_90MM"] = {category=Weapon.Category.ROCKET, TNTe=5}, -- New

			-- LAU-3/61/68/131 (incl. on BRU-33/42), M260/261, XM158
		["HYDRA_70_M151"] = {category=Weapon.Category.ROCKET, TNTe=4},
		["HYDRA_70_M151_M433"] = {category=Weapon.Category.ROCKET, TNTe=4},
		["HYDRA_70_M156"] = {category=Weapon.Category.ROCKET, TNTe=4}, -- New
		["HYDRA_70_M229"] = {category=Weapon.Category.ROCKET, TNTe=8},
		["HYDRA_70_M257"] = {category=Weapon.Category.ROCKET, TNTe=4}, -- New
		["HYDRA_70_M259"] = {category=Weapon.Category.ROCKET, TNTe=11},
		["HYDRA_70_M282"] = {category=Weapon.Category.ROCKET, TNTe=11},
		["HYDRA_70_M274"] = {category=Weapon.Category.ROCKET, TNTe=4}, -- New
		["HYDRA_70_MK1"] = {category=Weapon.Category.ROCKET, TNTe=4}, -- New
		["HYDRA_70_MK5"] = {category=Weapon.Category.ROCKET, TNTe=4},
		["HYDRA_70_MK61"] = {category=Weapon.Category.ROCKET, TNTe=4}, -- New
		["HYDRA_70_WTU1B"] = {category=Weapon.Category.ROCKET, TNTe=8}, -- BDU
		["Vikhr_M"] = {category=Weapon.Category.ROCKET, TNTe=11},

		-- ZUNI launchers: LAU-10 (incl. on BRU-33) 
		["Zuni_127"] = {category=Weapon.Category.ROCKET, TNTe=5},

		-- ZUNI launchers: LR-25
		["ARF8M3API"] = {category=Weapon.Category.ROCKET, TNTe=11},
		["ARF8M3HEI"] = {category=Weapon.Category.ROCKET, TNTe=11},
		["ARF8M3TPSM"] = {category=Weapon.Category.ROCKET, TNTe=11},

		-- MATRA F1/F4, Telson 8
		["SNEB_TYPE250_F1B"] = {category=Weapon.Category.ROCKET, TNTe=8},
		["SNEB_TYPE251_F1B"] = {category=Weapon.Category.ROCKET, TNTe=8},
		["SNEB_TYPE252_F1B"] = {category=Weapon.Category.ROCKET, TNTe=8},
		["SNEB_TYPE253_F1B"] = {category=Weapon.Category.ROCKET, TNTe=8},
		["SNEB_TYPE256_F1B"] = {category=Weapon.Category.ROCKET, TNTe=8},
		["SNEB_TYPE257_F1B"] = {category=Weapon.Category.ROCKET, TNTe=8},
		["SNEB_TYPE251_F4B"] = {category=Weapon.Category.ROCKET, TNTe=4},
		["SNEB_TYPE252_F4B"] = {category=Weapon.Category.ROCKET, TNTe=4},
		["SNEB_TYPE253_F4B"] = {category=Weapon.Category.ROCKET, TNTe=5},
		["SNEB_TYPE256_F4B"] = {category=Weapon.Category.ROCKET, TNTe=6},
		["SNEB_TYPE257_F4B"] = {category=Weapon.Category.ROCKET, TNTe=8},
		["SNEB_TYPE251_H1"] = {category=Weapon.Category.ROCKET, TNTe=4},
		["SNEB_TYPE252_H1"] = {category=Weapon.Category.ROCKET, TNTe=4},
		["SNEB_TYPE253_H1"] = {category=Weapon.Category.ROCKET, TNTe=5},
		["SNEB_TYPE256_H1"] = {category=Weapon.Category.ROCKET, TNTe=6},
		["SNEB_TYPE257_H1"] = {category=Weapon.Category.ROCKET, TNTe=8},
		["MATRA_F4_SNEBT251"] = {category=Weapon.Category.ROCKET, TNTe=8}, -- New				 
		["MATRA_F4_SNEBT253"] = {category=Weapon.Category.ROCKET, TNTe=8}, -- New
		["MATRA_F4_SNEBT256"] = {category=Weapon.Category.ROCKET, TNTe=8}, -- New
		["MATRA_F1_SNEBT253"] = {category=Weapon.Category.ROCKET, TNTe=8}, -- New
		["MATRA_F1_SNEBT256"] = {category=Weapon.Category.ROCKET, TNTe=8}, -- New

		-- UB-16, UB-32A
		["C_5"] = {category=Weapon.Category.ROCKET, TNTe=8},
		["S_5KP"] = {category=Weapon.Category.ROCKET, TNTe=8},
		["S_5M"] = {category=Weapon.Category.ROCKET, TNTe=8},

		-- launchers: B-8V20A, B-8M1 (incl. twin-pylon versions)

		-- launchers: APU-68
		["C_13"] = {category=Weapon.Category.ROCKET, TNTe=21},
		["C_24"] = {category=Weapon.Category.ROCKET, TNTe=123},
		["C_25"] = {category=Weapon.Category.ROCKET, TNTe=151},
		["S-25-O"] = {category=Weapon.Category.ROCKET, TNTe=8}, -- new									
		["C_8"] = {category=Weapon.Category.ROCKET, TNTe=8},
		["C_8OM"] = {category=Weapon.Category.ROCKET, TNTe=8}, -- new									
		["C_8CM"] = {category=Weapon.Category.ROCKET, TNTe=8}, -- new									
		["C_8CM_GN"] = {category=Weapon.Category.ROCKET, TNTe=8}, -- new									
		["C_8CM_RD"] = {category=Weapon.Category.ROCKET, TNTe=8}, -- new									
		["C_8CM_WH"] = {category=Weapon.Category.ROCKET, TNTe=8}, -- new									
		["C_8CM_BU"] = {category=Weapon.Category.ROCKET, TNTe=8}, -- new									
		["C_8CM_VT"] = {category=Weapon.Category.ROCKET, TNTe=8}, -- new									
		["C_8CM_YE"] = {category=Weapon.Category.ROCKET, TNTe=8}, -- new									
		["C_8OFP2"] = {category=Weapon.Category.ROCKET, TNTe=3},
		["FFAR Mk1 HE"] = {category=Weapon.Category.ROCKET, TNTe=8},
		["FFAR Mk5 HEAT"] = {category=Weapon.Category.ROCKET, TNTe=8},
		["FFAR_Mk61"] = {category=Weapon.Category.ROCKET, TNTe=8},
		["FFAR M156 WP"] = {category=Weapon.Category.ROCKET, TNTe=8},


		["KH-66_Grom"] = {category=Weapon.Category.BOMB, TNTe=108},
		["M_117"] = {category=Weapon.Category.BOMB, TNTe=201},
		["AN_M64"] = {category=Weapon.Category.BOMB, TNTe=121},
		["X_23"] = {category=Weapon.Category.BOMB, TNTe=111},
		["X_23L"] = {category=Weapon.Category.BOMB, TNTe=111},
		["X_28"] = {category=Weapon.Category.BOMB, TNTe=160},
		["X_25ML"] = {category=Weapon.Category.BOMB, TNTe=89},
		["X_25MP"] = {category=Weapon.Category.BOMB, TNTe=89},
		["X_25MR"] = {category=Weapon.Category.BOMB, TNTe=140},
		["X_58"] = {category=Weapon.Category.BOMB, TNTe=140},
		["X_29L"] = {category=Weapon.Category.BOMB, TNTe=320},
		["X_29T"] = {category=Weapon.Category.BOMB, TNTe=320},
		["X_29TE"] = {category=Weapon.Category.BOMB, TNTe=320},
		["S-24A"] = {category=Weapon.Category.BOMB, TNTe=24},
		["S-24B"] = {category=Weapon.Category.BOMB, TNTe=123},
		["S-25OF"] = {category=Weapon.Category.BOMB, TNTe=194},
		["S-25OFM"] = {category=Weapon.Category.BOMB, TNTe=150},
		["S-25O"] = {category=Weapon.Category.BOMB, TNTe=150},
		["S_25L"] = {category=Weapon.Category.BOMB, TNTe=190},
		["S-5M"] = {category=Weapon.Category.BOMB, TNTe=1},
		["ARAKM70BHE"] = {category=Weapon.Category.BOMB, TNTe=4},
		["Rb 05A"] = {category=Weapon.Category.BOMB, TNTe=217},
	}

	-- clusters transco
	-- TODO modifier la règle de transco car 1 bomblet peut être portée par plusieurs munition
	BLAST.clusters = {
		["BLG-66"] = "", -- New
		["Mk 118"] = "", -- New
		["BK90 MJ1"] = "", -- New: cluster MJ1
		["BK90 MJ1_MJ2"] = "", -- New: cluster MJ1_MJ2
		["BK90 MJ2"] = "", -- New: cluster MJ2
		["MUS_JAS_1"] = "", -- New: cluster DWS39_MJ1
		["MUS_JAS_2"] = "", -- New: cluster DWS39_MJ2
		["PTAB-10-5"] = "", -- New: cluster RBK_500AO
		["PTAB-1M"] = "", -- New: cluster RBK_500U 
		["PTAB-2-5"] = "", -- New: cluster RBK_250 
		["BETAB-M"] = "", -- New: cluster RBK_500U_DETAB_M
		["OAB-2-5RT"] = "", -- New: cluster RBK_500U_OAB-2-5RT
		["AO-1SCh"] = "", -- New: cluster RBK_250_275_AO_1SCH
		["PTAB-2.5KO"] = "", -- New: cluster GB-6
		["BLU107B_DURANDAL"] = "", -- ??? sub-munitions 
		["BLU-97B"] = "CBU_87", -- CBU-87 sub-munitions 
		["BLU-108"] = "CBU_97", -- CBU-97 sub-munitions 
		["BLU-97/B"] = "AGM_154A", -- AGM-154A sub-munitions 
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
		["Caucasus"]={name="Caucasus",hemisphere=BLAST.hemisphere.North},
		["NTTR"]={name="Nevada",hemisphere=BLAST.hemisphere.North},
		["Normandy"]={name="Normandy",hemisphere=BLAST.hemisphere.North},
		["PersianGulf"]={name="PersianGulf",hemisphere=BLAST.hemisphere.North},
		["TheChannel"]={name="TheChannel",hemisphere=BLAST.hemisphere.North},
		["Syria"]={name="Syria",hemisphere=BLAST.hemisphere.North},
		["MarianaIslands"]={name="MarianaIslands",hemisphere=BLAST.hemisphere.North},
		["Falklands"]={name="Falklands",hemisphere=BLAST.hemisphere.South},
		["SinaiMap"]={name="SinaiMap",hemisphere=BLAST.hemisphere.North},
		["Kola"]={name="Kola",hemisphere=BLAST.hemisphere.North},
		["Afghanistan"]={name="Afghanistan",hemisphere=BLAST.hemisphere.North},
		["Iraq"]={name="Iraq",hemisphere=BLAST.hemisphere.North},
		["GermanyCW"]={name="GermanyCW",hemisphere=BLAST.hemisphere.North}
	}
 

	--**** list of static functions ****

	-- function to call subfunction with parameters with error handling exceptions
	function blastProtectedCall( ... )
		local ErrorHandler = function( errmsg )
			env.info( "BLAST: Error " .. errmsg )
			env.info( debug.traceback() )
			return errmsg
		end

		local status, error = xpcall( ..., ErrorHandler )
		if error then
			env.warning( s, true )
			if blast.options.msgInGame then
				trigger.action.outText( s, 10 )
			end
		end
	end


	-- log and show a message depending of the options set  
	BLAST.info = function( s, forceShow)
		forceShow = forceShow or false
		if BLAST.options.debugManaged or forceShow then
			env.info( "BLAST: " .. s )
			if BLAST.options.msgInGame or forceShow then
				trigger.action.outText( s, 10 )
			end
		end
	end

	-- open csv file to store telemetry datas
	BLAST.openTelemetry = function(filename)
		local result = false

		if io then
			result = io.open( lfs.writedir() .. "Logs\\" .. filename, "w+" )
			io.write( result, "time\torigin\tinitiator\tmunition\tname\tagl\tpos.x\tpos.y\tpos.z\r\n" )
			BLAST.info( string.format("Telemetry open : %s", filename) )
		else
			BLAST.info( "Telemetry file can't be open, io not permitted." )
		end

		return result
	end

	-- close and flush datas in the file of telemetry
	BLAST.closeTelemetry = function(handle)
		if io and handle then
			if handle then
				handle:close()
				handle = false
				BLAST.info( "Telemetry closed" )
			end
		end
		return false
	end

	-- write in telemetry file one record 
	BLAST.writeTelemetry = function( handle, fn, w )
		if io and handle then
			-- object agl in feet
			local agl = BLAST.getHeight( w.pos ) * 3.28084 -- in feet
			local abstime = timer.getTime()
			local hh = math.floor( abstime / 3600 )
			local mm = math.floor( (abstime - hh * 3600) / 60 )
			local ss = math.floor( abstime - hh * 3600 - mm * 60 )
			local v, ms = math.modf( abstime )
			ms = math.floor( ms * 1000 )
			local speed = BLAST.vec3_mag( w.velocity ) * 1.9438478 -- m/sec -> Kph
			-- time of record
			-- weapon id, which event or state triggers the 
			handle:write( string.format( "%02i:%02i:%02i.%03i\t%i\t%s\t%s\t%s\t%s\t%.3f\t%.3f\t%.3f\t%.3f\t%.3f\r\n", 
				hh, mm, ss, ms, w.id, fn, w.initiatorName, w.name, w.type, agl, speed, w.position.x, w.position.y, w.position.z ) )
		end
	end

	-- check if a key exist in a table given
	BLAST.tableHasKey = function( table, k )
		local result = (table ~= nil) and (table[k] ~= nil)
		return result
	end

	BLAST.rad2degree = function(angle)
		return angle*180/math.pi
	end

	BLAST.vec3Heading = function(v)
		local h = math.atan2(v.z, v.x)
		if h < 0 then
			h = h + math.pi*2
		end
		return h
	end

	BLAST.vec2Heading = function(v)
		local h = math.atan2(v.y, v.x)
		if h < 0 then
			h = h + math.pi*2
		end
		return h
	end

	-- make a vec2 with x, y
	BLAST.vec2 = function(x, y) 
		local result = {x=x, y=y} 
		return result
	end

	-- translate point p (vec2) with range d (vec2)
	BLAST.translateVec2 = function( v, d)
	    local result = {x=v.x+d.x, y=v.y+d.y} 
 	    return result
    end
	
	-- make a vec3 with x, y, z
	BLAST.vec3 = function(x, y, z) 
		local result = {x=x, y=y, z=z} 
		return result
	end

	-- get vec2 coordinates from vec 3
	BLAST.vec3tovec2 = function (vec3)
		local vec2 = {x=vec3.x, y=vec3.z}
		return vec2, vec3.y
	end

	-- get vec2 coordinates from vec 3
	BLAST.vec2tovec3 = function (vec2, h)
		local vec2 = {x=vec2.x, y=h, z=vec2.y}
		return vec2
	end

	-- add two vec3
	BLAST.vec3_add = function(v1, v2) 
		local result = BLAST.vec3(v1.x + v2.x, v1.y + v2.y, v1.z + v2.z)
		return result
	end

	-- sub two vec3
	BLAST.vec3_sub = function(v1, v2) 
		local result = BLAST.vec3(v1.x - v2.x, v1.y - v2.y, v1.z - v2.z)
		return result
	end

	-- multiply a vec3 with a coef
	BLAST.vec3_mul = function(v, s)   
		local result = BLAST.vec3(v.x * s, v.y * s, v.z * s) 
		return result
	end

	-- get the norm of a vec3
	BLAST.vec3_mag = function(v)
		local result = math.sqrt(v.x^2 + v.y^2 + v.z^2) 
		return result
	end

	-- get the distance 
	BLAST.vec3_dist = function(v, a, p)
		local u = BLAST.vec3(math.sin(a), math.sin(p), math.cos(a))
		local result = v.x*u.x + v.y*u.y + v.z*u.z 
		return result
	end

	-- get the cross between two vec3
	BLAST.vec3_cross = function(a, b)
		local result = {
			x = a.y * b.z - a.z * b.y,
			y = a.z * b.x - a.x * b.z,
			z = a.x * b.y - a.y * b.x
		}
		return result
	end
	
	-- convertion feet to meters with optional rounded to the unit
	BLAST.feet2meters = function( feet, rouded )
		local result = feet * 0.3048
		if rouded then result = math.floor( result + 0.5) end
		return result
	end

	-- convertion meters to feet with optional rounded to the unit
	BLAST.meters2feet = function( meters, rounded )
		local result = meters * 3,28084
		if rouded then result = math.floor( result + 0.5) end
		return result
	end

	-- just a fancy function to have a "string" value for a boolean input
	BLAST.bool2string = function( bool )
		return bool and "true" or "false"
	end

	-- get the height from the ground level at p (vec2 or vec3) 
	BLAST.getHeight = function( p )
		local result = 0
		if p.z then
			local vec2 = BLAST.vec3tovec2(p)
			result = land.getHeight( vec2 )
		else
			result = land.getHeight( p )
		end
		return result
	end

	-- get the wind vector at 1 altitude or for each step
	BLAST.getWind = function( p, step )
		local result = {}
		if not step then
			result = atmosphere.getWind( p )
		else
			local w = {}
			local a = BLAST.vec3(p.x, math.floor(p.y / step ) * step, p.z)
			while a.y >= 0 do
				w = atmosphere.getWind( a )
				result[a.y] = w
				a.y = a.y - step
			end
			--table.sort( result, function( left, right ) return left.altitude > right.altitude end )
		end
		return result
	end

	-- get point p (vec2) after rotation a (rad) relative of center c (vec2) 
	BLAST.rotate = function(p, c, a) 
		local x0 = p.x - c.x;
		local y0 = p.y - c.y;
		x = x0 * math.cos (a) + y0 * math.sin (a) + c.x;
		y = - x0 * math.sin (a) + y0 * math.cos (a) + c.y;
		return BLAST.vec2(x, y)
	end

	-- translate point p to range r with an angle a
	BLAST.translateWithRange = function( p, r, a)
		local x = p.x + r * math.cos(a)   
		local y = p.y + r * math.sin(a)  
 		return BLAST.vec2(x, y)
	end

	-- translate point p with range d 
	BLAST.translateVec3 = function( p, d)
		local result = BLAST.vec3(p.x+d.x, p.y+d.y, p.z+d.z) 
 		return result
	end

	-- get true if a point p is in the radius r of center c 
	BLAST.inRadius = function( p, c, r )
		local result = ((p.x - c.x) ^ 2 + (p.y - c.y) ^ 2) ^ 0.5 <= r
		return result
	end

	-- get true if a point p is in the polygon define by verticies
	BLAST.inPolygon = function( v, p )
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
	BLAST.distance2D = function( point1, point2 )
		local result = math.sqrt( math.abs( point1.x - point2.x ) ^ 2 + math.abs( point1.y - point2.y ) ^ 2 )
		return result
	end

	-- get distance between two points in 3D
	BLAST.distance3D = function( point1, point2 )
		local result = math.sqrt( math.abs( point1.x - point2.x ) ^ 2 + math.abs( point1.y - point2.y ) ^ 2 + math.abs( point1.z - point2.z ) ^ 2 )
		return result
	end
	
	BLAST.getLifePercentage = function( o )
		local result = 0
		local life0 = 1
		local life = 0
		if o and o:isExist() then 
			local c = Object.getCategory(o)
			-- ground units, statics, scenary and cargos
			if (c == Object.Category.UNIT) or (c == Object.Category.SCENERY) then 
				life0 = o:getLife0()
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
	-- TODO : vérifier si la fonction est utilisée dans le traitement des clusters
	BLAST.isInExclusionArea = function( location, exclusionAreas )
		local result = false
		local l = BLAST.vec3tovec2(location)
		local c = {x=0, y=0}
		for k, area in pairs( exclusionAreas ) do
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

		for k, z in pairs( env.mission.triggers.zones ) do
			name = string.upper( z.name )
			match = string.match( name, areasPattern ) 
			
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
		local sw = {x=polygon[0].v3.x, y=polygon[0].v3.y, z=polygon[0].v3.z}
		local ne = {x=polygon[0].v3.x, y=polygon[0].v3.y, z=polygon[0].v3.z}

		for i=0,#polygon-1 do	
			-- sw is the southernmost, westernmost and lowest angle of the polygon
			sw.x = math.min(polygon[i].v3.x, sw.x) 
			sw.y = math.min(polygon[i].v3.y, sw.y) 
			sw.z = math.min(polygon[i].v3.z, sw.z) 

			-- ne is the northernmost, easternmost and highest angle of the polygon
			ne.x = math.max(polygon[i].v3.x, ne.x) 
			ne.y = math.max(polygon[i].v3.y, ne.y) 
			ne.z = math.max(polygon[i].v3.z, ne.z) 
		end
		return {NE=ne, SW=sw}
	end

	-- Peak of overpressure calculation based on Hopkinson-Cranz Scaling Law
	BLAST.getPso = function( range, TNTe, angle )
		-- R [m] is the distance between the center of the object and the Impact Point (ip)
		local R = range
		-- W [kg] is the equivalent TNT mass, currently only TNT is used
		local W = TNTe
		-- Angle [rad] of incidence for spherical (0°<A<180°) or hemispherical (A=0°) explosion 
		local A = angle
		-- P [hPa] is the ambient pressure (without evaluation of altitude) : todo manage gap pressure std/height
		local Pa = 1013.25
		if A > 0 then
			R = math.floor( R / math.cos( math.rad( A ) ) + 0.5 )
		end
		-- Z [m/kg] is the coefficient dependency on angle of incidence (Hopkinson-Cranz Scaling Law)
		local Z = R / W ^ (1 / 3)
		-- Pso [hPa] is Peak scaled incident positive overpressure  (Kinney and Graham)
		local Pso = Pa * (808 * (1 + (Z / 4.5) ^ 2)) / math.sqrt( (1 + (Z / 0.048) ^ 2) * (1 + (Z / 0.32) ^ 2) * (1 + (Z / 1.35) ^ 2) )

		-- return the list of values
		return { R = R, Pso = Pso }
	end
	
	-- Construct the table of all peaks in descending order until there is no longer a lethal effect on humans.
	BLAST.getPsoTable = function( TNTe, angle )
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
			Pso = BLAST.getPso( R, W, A )
			table.insert( result, Pso )
			-- next
			R = R + Incr
		until Pso.Pso <= thresholdPso

		PsoMax = result[1].Pso
		return result, R - 1, math.floor( (R-1) / 2 + 0.5 )
	end

	-- Get a string value of a weapon with category / subcategory names and more
	BLAST.getWeaponCategoryName = function( track )
		local result = BLAST.WeaponCategoryNames[track.category];

		if track.category == Weapon.Category.SHELL then
			if track.type and string.find( track.type, "_AP", 1, true ) then
				result = result .. " AP"
			elseif track.type and string.find( track.type, "_HE", 1, true ) then
				result = result .. " HE"
			end

		elseif track.category == Weapon.Category.BOMB then
			local attributes = track.desc.attributes
			if attributes then 
				local attr = ""
				for k,a in pairs(attributes) do
					if a then
						attr = attr..":"..k
					end
				end
				result = string.format( "%s attr:%s", result, attr )
			end
		elseif track.category == Weapon.Category.MISSILE then
			if track.missileCategory then
				result = string.format( "%s %s", result, BLAST.MissileCategoryNames[track.missileCategory] )
			else
				result = string.format( "%s %i", result, track.missileCategory )
			end
		end

		return result
	end

	-- Get value of power set for a munition given
	BLAST.getWarhead = function( weaponType )
		local result = 0

		if BLAST.weapons[weaponType] and not BLAST.weapons[weaponType] then
			local w = BLAST.weapons[weaponType]
			
			if (w.TNTe > 0) then 
				result = w.TNTe
			end
			
			if (w.category == Weapon.Category.ROCKET) then
				result = result * BLAST.options.rocketBoost
			end
		end

		return result
	end

	-- get the polygon oriented depending of a cluster 
	BLAST.getClusterPolygon = function (track) 
		local cluster = track.cluster

		local c = BLAST.vec3tovec2(track.cluster.ip)
		local w2 = cluster.width/2  -- meters
		local l2 = cluster.lenght/2 -- meters

		cluster.polygon = {[0]={}, [1]={v2={}, v3={}}, [2]={v2={}, v3={}}, [3]={v2={}, v3={}}} 

		cluster.polygon[0].v2 = BLAST.rotate({x=c.x+l2, y=c.y+w2}, c, -track.heading)
		cluster.polygon[0].v3 = BLAST.vec2tovec3(cluster.polygon[0].v2, land.getHeight(cluster.polygon[0].v2))
		
		cluster.polygon[1].v2 = BLAST.rotate({x=c.x+l2, y=c.y-w2}, c, -track.heading) 
		cluster.polygon[1].v3 = BLAST.vec2tovec3(cluster.polygon[1].v2, land.getHeight(cluster.polygon[1].v2))
	
		cluster.polygon[2].v2 = BLAST.rotate({x=c.x-l2, y=c.y-w2}, c, -track.heading)
		cluster.polygon[2].v3 = BLAST.vec2tovec3(cluster.polygon[2].v2, land.getHeight(cluster.polygon[2].v2))
		
		cluster.polygon[3].v2 = BLAST.rotate({x=c.x-l2, y=c.y+w2}, c, -track.heading)
		cluster.polygon[3].v3 = BLAST.vec2tovec3(cluster.polygon[3].v2, land.getHeight(cluster.polygon[3].v2))

		-- define a box to detect all units into (SW min, NE max)
		cluster.box = BLAST.getSearchBox(cluster.polygon)

		-- a cloud of smoke to see where is the box BLAST.getHeight( track.position.ip )
		if BLAST.options.smoke then 			
			trigger.action.smoke( track.cluster.ip, trigger.smokeColor.Red )
			trigger.action.smoke( cluster.polygon[0].v3, trigger.smokeColor.Green )
			trigger.action.smoke( cluster.polygon[1].v3, trigger.smokeColor.Red )
			trigger.action.smoke( cluster.polygon[2].v3, trigger.smokeColor.White )
			trigger.action.smoke( cluster.polygon[3].v3, trigger.smokeColor.Blue )
		end
		
		return cluster
	end

	-- get units list in a oriented box for cluster
	BLAST.getUnitsInBox = function(SW, NE) 
		local result = {}
		local u = {}
		local box = {
			id = world.VolumeType.BOX,
			params = {
				min = SW,
				max = NE
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
	BLAST.applyExplosion = function( ip, TNTe, flare )
		trigger.action.explosion( ip, TNTe )
		
		if flare then
			for i = 1, 5 do
				local az = math.random(0, 359) 	-- Random angle for scatter
				local oX = math.random(-5, 5) 	-- Position offset (meters)
				local oZ = math.random(-5, 5)
				local p = { x =  ip.x + oX, y =  ip.y, z =  ip.z + oZ }
				trigger.action.signalFlare(p, 2, az)
			end
		end

		return nil
	end

	-- get true when the weapon is trackable
	-- TODO : the weapons trackable should be configured in the settings
	BLAST.isTrackable = function( weapon )
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

	-- get cluster IP and delay of the bomblet's strike zone	
	BLAST.getClusterIP = function(
			v0,		-- Speed (m/s)
			h0,	 	-- Heading (rad)
			a0,		-- Pitch (rad)
			y0,		-- Altitude (m)
			yh,		-- Height (m)
			w,		-- Winds array of vec3 (m/s) >0 = pousse, <0 = freine
			ws,		-- Wind force by altitude step 
			phy	 	-- Physical characteristics and behaviours of the object
		)

		-- Constants
		local g = 9.81        	-- Acceleration due to gravity (m/s^2)
		local rho = 1.225 		-- Air density (kg/m^3)
		
		local t = 0.0
		local dt = 0.01
		local update = false
		
		-- Calculation of the overall friction coefficient 'k'
		local m = phy.m0
		local S = phy.S0
		local Cx = phy.Cx0
		local k = 0.5 * rho * Cx * S

		-- Initial conditions
		local dp = BLAST.vec3(0.0, y0, 0.0)	-- ip vector
		local vv = BLAST.vec3_mul(BLAST.vec3(math.cos(h0)*math.cos(a0), math.sin(a0), math.sin(h0)*math.cos(a0)), v0)
		local vn = 0.0 						-- speed
		local ac = BLAST.vec3(0, 0, 0)		-- acceleration vector
		local wa = math.floor(y0 / ws) * ws	-- wind altitude
		local wv = BLAST.vec3_mul(w[wa], dt*phy.we)-- wind vector
		local ma = y0 - yh + phy.hm			-- minimum altitude

		-- Simulation loop (iteration using Euler's method)
		while dp.y > ma do

			if not update and (t > phy.tc) then
				m = phy.m1
				Cx = phy.Cx1
				S = phy.S1
				k = 0.5 * rho * Cx * S
				update = true
			end

			-- current wind factor at this altitude 
			if (wa > dp.y) then
				wa = math.floor(dp.y / ws) * ws
				wv = BLAST.vec3_mul(w[wa], dt*phy.we)
			end

			-- 1. cCalculation of current speed (object + wind) vx = vx + w.x * dt
			vv = BLAST.vec3_add(vv, wv)
			vn = BLAST.vec3_mag(vv)

			-- 2. Calculation of accelerations (a = F/m)
			ac = BLAST.vec3(-(k * vv.x * vn / m), -g -( k * vv.y  * vn / m), - (k * vv.z * vn / m))
			
			-- 3. Speed update
			vv = BLAST.vec3_add(vv, BLAST.vec3_mul(ac, dt))
			
			-- 4. Position update
			dp = BLAST.vec3_add(dp, BLAST.vec3_mul(vv, dt))
			
			-- 5. next time step
			t = t + dt
			
		end
		-- set ground level at the IP
		dp.y = BLAST.getHeight(dp)

		-- Returns the last position if the loop ends without impact (theoretical case)
		return dp, t
	end

	--**** End of statics functions

	-- create a new instance of BLAST class
	function BLAST:new()
		local instance = setmetatable( {}, BLAST )
		return instance
	end

	-- get all useful details to manage a weapon track from an event
	function BLAST:getTrack( event )
		local result = false

		if type(event.weapon) == "table" and event.weapon.isExist and event.weapon:isExist() and event.initiator then

			if event.weapon.getCategory( event.weapon ) == Object.Category.WEAPON then

				result = { 
					id = event.weapon.id_, 
					weapon = event.weapon, 
					name = event.weapon:getDesc().displayName or "no displayname",
					category = event.weapon:getDesc().category,
					desc = event.weapon:getDesc(), 
					type = event.weapon:getTypeName() or "no type", 
					position = event.weapon:getPosition(), 
					velocity = event.weapon:getVelocity(), 
					hit = false,
					deleted = false,
					initiatorId = event.initiator and event.initiator.id_,
					initiatorName = event.initiator and event.initiator:getName() or "no initiator",
					playerName = (Object.getCategory(event.initiator) == Object.Category.UNIT) and event.initiator:getPlayerName() or false
				}
				result.heading = BLAST.vec3Heading(result.position.x)
				result.height = BLAST.getHeight( result.position.p )
				result.ip = land.getIP( result.position.p, result.position.x, 150 )
				
				if (result.category == Weapon.Category.MISSILE) then
					result.missileCategory = result.desc.missileCategory
				end
				result.categoryName = BLAST.getWeaponCategoryName( result )

				if BLAST.weapons[result.type] and BLAST.weapons[result.type].cluster then
					result.cluster = BLAST.weapons[result.type].cluster 
				end
				
				result.TNTe = BLAST.getWarhead( result.type )
				result.flare = self.options.flareVisualEffect and BLAST.tableHasKey(BLAST.weapons[result.type], "flare") and BLAST.weapons[result.type].flare or false 

				-- get default warhead to trace diff between blast damage and DCS
				if BLAST.tableHasKey(result.desc, "warhead") then 
					result.warhead = result.desc.warhead.explosiveMass or result.desc.warhead.shapedExplosiveMass
				else
					result.warhead = -1
				end

				-- apply boost power if this is a hit and we know the target
				if event.target then
					local o = self:getObject( event.target )
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

	-- get all useful information about an object
	function BLAST:getObject( o )
		local result = false

		if o and o:isExist() then
			local objectCategory = Object.getCategory(o)
			
			if (objectCategory == Object.Category.UNIT) or (objectCategory == Object.Category.STATIC) or (objectCategory == Object.Category.SCENERY) then

				result = { 
					name = o:getName(), 
					type = o:getTypeName(), 
					category = objectCategory, 
					subCategory = o:getDesc().category, 
					isInfantry = o:hasAttribute( "Infantry" ), 
					isVehicle = o:hasAttribute( "Vehicles" ),
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
				if BLAST.tableHasKey( o:getDesc(), "box" ) then
					local box = o:getDesc().box
					result.boxLength = (box.max.x + math.abs( box.min.x ))
					result.boxHeight = (box.max.y + math.abs( box.min.y ))
					result.boxDepth  = (box.max.z + math.abs( box.min.z ))
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
	function BLAST:applyDamages( track, o )

		if o.object:isExist() then
			-- eval percentage of health remaining
			local healthRemaining = (o.healthRemaining - 1) / (o.life - 1) * 100

			-- for all ground units alive
			if (o.healthRemaining > 0) then
				-- health threshold depending of the ground unit's category
				if (o.isInfantry and (healthRemaining <= self.options.infantryFireThreshold)) or (o.isVehicle and (healthRemaining <= self.options.vehicleFireThreshold)) then
					local c = o.object:getController()
					c:setOption( AI.Option.Ground.id.ROE, AI.Option.Ground.val.ROE.WEAPON_HOLD )
					self:addStatsForHoldWeapon( track.type, track.name, o.type, o.name, track.playerName )
					BLAST.info( string.format( "Unit %s disable fire.", o.name ) )
				end

				-- for all units alive disable ability to move below threshold
				if (o.isInfantry and (healthRemaining <= self.options.infantryMovementThreshold)) or (o.isVehicle and (healthRemaining <= self.options.vehicleMovementThreshold)) then
					local c = o.object:getController()
					c:setTask( { id = 'Hold', params = {} } )
					c:setOnOff( false )
					self:addStatsForHoldMovement( track.type, track.name, o.type, o.name, track.playerName )
					BLAST.info( string.format( "Unit %s disable movements.", o.name ) )
				end
			end
		end
	end

	-- scheduled function to manage blast effect and damages
	function BLAST:applyBlastEffect( track, o )
		-- object not dead 
		if o.object:isExist() and o.blastTNT then
			timer.scheduleFunction(
				function (args)
					local p = args[1]
					local TNTe = args[2]
					local flare = args[3]
					local track = args[4]
					local o = args[5]

					BLAST.applyExplosion(p, TNTe, flare)

					o.healthRemaining = o.object:getLife()
					BLAST.info( string.format( 'Weapon %s %s:%s (%i) BLAST %s %s:%s, TNTe %.3fkg, health %.3f/%.3f', 
						track.categoryName, track.type, track.name, track.id, BLAST.ObjectCategoryNames[o.category], o.type, o.name, 
						o.blastTNT, o.healthRemaining, o.health ) )
					
						-- apply damange model only on ground units found 
					if BLAST.options.damageManaged and (o.isInfantry or o.isVehicle) and o.object:isExist() then
						self:applyDamages( track, o )
					end
					self:addStatsForWeaponBlast( track.type, track.name, o.type, o.name, track.playerName )
				end,
				{o.position.p, o.blastTNT, false, track, o}, 
				timer.getTime() + o.range / BLAST.options.blastDiffusionDelay
			)

		end

		track.objectsCount = track.objectsCount - 1
	end

	-- detect and apply effects to all units / objects identified
	function BLAST:getBlastedObjects (track)
		local objects = {}
		local added = false
		-- get the Pso table and the maxRange to apply effect
		local PsoTable, infantryRadius, vehicleRadius = BLAST.getPsoTable( track.TNTe, 0 )

		if (#PsoTable > 1) or (track.deleted == false) then
			local PsoMax = PsoTable[1].Pso
			local searchSphere = { id = world.VolumeType.SPHERE, params = { point = track.ip, radius = infantryRadius } }

			-- will found the list of all objects in the blast wave area and out of excludes zones 
			local ifSearchObjects = function( object, val )
				-- object is not dead
				if object:isExist() then
					local o = self:getObject( object )

					-- out of an exclusion area
					if (not BLAST.isInExclusionArea(o.position.p, self.exclusionAreas)) then
						o.range = math.floor( BLAST.distance3D( track.ip, o.position.p ) + 0.5 )

						-- limit the blast effect to nearby vehic	les only as the effect is far too weak
						if (o.category == Object.Category.UNIT) and (o.subCategory == Unit.Category.GROUND_UNIT) then	
							-- in the effect radius depending of the unit infantry or vehicle
							if (o.isInfantry and (o.range <= infantryRadius)) or (o.isVehicle and (o.range <= vehicleRadius)) then
								-- blast power by the range and eq TNT and exposed surface
								o.blastTNT = track.TNTe * ((PsoTable[o.range].Pso / PsoMax) / 100) * o.surface
								table.insert( objects, o )
								local added = true
							end

						elseif (o.category == Object.Category.STATIC) then
							o.blastTNT = track.TNTe * self.options.staticBoost
							table.insert( objects, o )
							local added = true			

						elseif (o.category == Object.Category.SCENERY) then
							o.blastTNT = track.TNTe * self.options.sceneryBoost
							table.insert( objects, o )
							local added = true
						else
							o.blastTNT = 0.01
						end

						if added then
							BLAST.info( string.format( 'Weapon %s %s:%s (%i) %s %s:%s (%i) object added at range %ift < %ift/%ift, blastTNT %.3fkg, health %.3f', 
								track.categoryName, track.type, track.name, track.id, 
								BLAST.ObjectCategoryNames[o.category], o.type, o.name, o.id,
								BLAST.meters2feet(o.range), BLAST.meters2feet(vehicleRadius, true), BLAST.meters2feet(infantryRadius, true), o.blastTNT, o.health ) )
						end
					end -- exclusion area
				end

				return true
			end -- local function

			-- inventory of objects having to support blast wave
			-- , Object.Category.CARGO and SCENERY excluded because too many objects without interest 
			world.searchObjects( { Object.Category.UNIT, Object.Category.STATIC }, searchSphere, ifSearchObjects )
		end

		if (#objects > 1) then
			-- sort from near to far objects 
			table.sort( objects, function( left, right ) return left.range < right.range end )
		end

		return objects 
	end

	function BLAST:blastObjects(track, objects)		
		-- for each object found, apply the right blast effect 
		for k, o in pairs( objects ) do
			if (o.blastTNT > 0) and (o.health > 1) then
				self:applyBlastEffect(track, o)
			end
		end
	end

	-- apply effect after that the weapon is hitting or dead.
	function BLAST:standardWeapon( track )
		--effect must be applyed at the explosion location or the object hitted
		if not track.hit then
			-- impact point: terrain intersection point with weapon's nose.  Only search out 50 meters though.
			track.ip = land.getIP( track.position.p, track.position.x, 200 )
			if not track.ip then -- use last calculated IP
				track.ip = track.position.p
			end
		else
			track.ip = track.position.p
		end

		if BLAST.options.smoke then  
			trigger.action.smoke( track.ip, BLAST.options.smokeColor )
		end

		-- proceed to the standard damages with the power of weapon set
		if (BLAST.options.explosionsManaged) then
			BLAST.applyExplosion( track.ip, track.TNTe, track.flare )

			local life = BLAST.getLifePercentage(track.object.object)

			if track.hit and track.object and track.object.name then
				BLAST.info( string.format( "Weapon %s %s:%s (%i) explosion, TNTe/warhead = %.3f, on object [%s] %s:%s, health %i%% / %.3f", 
					track.categoryName, track.type, track.name, track.id, track.TNTe, BLAST.ObjectCategoryNames[track.object.category], 
					track.object.type, track.object.name, life, track.object.life ) )
			else
				BLAST.info( string.format( "Weapon %s %s:%s (%i) explosion, TNTe/warhead = %.3f, health %i%% ", 
					track.categoryName, track.type, track.name, track.id, track.TNTe, life ) )
			end
		end

		-- apply a blast effect only when the munition is deleted
		if (self.options.blastwaveManaged) and (not track.hit) and (not track.cluster) then
			-- proceed to the peripheral damages
			local objects = self:getBlastedObjects( track )
			track.objectsCount = #objects
			if (track.objectsCount > 0) then
				BLAST.info( string.format( 'Weapon %s %s:%s (%i) %i objects detected', track.categoryName, track.type, track.name, track.id, #objects) )
				self:blastObjects(track, objects)
			end
		end
	end

	-- apply effect of a number of bomblets defined by the cluster
	function BLAST:clusterWeapon(args)  
		local track = args[1]
		local cluster = BLAST.getClusterPolygon(track)
		local units = BLAST.getUnitsInBox(cluster.box.SW, cluster.box.NE)

		BLAST.info( string.format( "(%i) detection bomlets %s", track.id, track.cluster.type ) )   
		BLAST.info( string.format( "(%i) number of units found : %i", track.id, #units) )
		
		if (#units > 0) then
			for i = 1, cluster.count do
				if i <= cluster.count then
					u = units[math.random(1, #units)]
					if u.object:isExist() then
						timer.scheduleFunction(
							function(args)
								local u = args[2]
								local p = u.p
								local TNTe = args[3]
								local flare = args[4]
								BLAST.applyExplosion(p, TNTe, self.options.flareVisualEffect and flare)
								u.health = u.object:getLife()
								
								BLAST.info( string.format( "bomblet (%i) explosion #%i, unit %s, power=%.3f, health %i%% / %.3f", 
									args[5].id, track.id, u.name, TNTe, BLAST.getLifePercentage(u.object), u.life) )	

								self:addStatsForWeaponHit( track.type, track.name, u.type, u.name , track.playerName )
							end, 
							{i, u, cluster.TNTe, cluster.flare, track}, 
							timer.getTime() + math.random(1, cluster.delayBeforeClusterEffect*100) / 100
						)
					end
				end
			end	
		end
		track.delete = true
		track.cluster.delete = true				
	end

	-- track all weapons registered with S_EVENT_SHOT and apply effect if conditions are met or prepare execution of cluster effect
	function BLAST:onTrackWeapons()

		for id, track in pairs( self.trackedWeapons ) do
			-- weapon is alive, just update informations
			if track.weapon:isExist() then
				track.position = track.weapon:getPosition()
				track.velocity = track.weapon:getVelocity()
				track.heading = BLAST.vec3Heading(track.position.x)
				track.height = track.position.p.y - BLAST.getHeight( track.position.p )
				track.speed = BLAST.vec3_mag(track.velocity)
				track.pitch = math.asin( track.position.x.y )
				if self.options.telemetryManaged and self.options.hTelemetry then
					BLAST.writeTelemetry( self.options.hTelemetry, 'onTrackWeapons live', track )
				end

			-- weapon no longer exists, do something	
			else
				-- to avoid to reapply an effect then this track is already treated but not yet deleted
				if (not track.delete) then
					-- apply effects immediatly for a standard weapon
					if (track.TNTe > 0) then
						self:standardWeapon( track )
						track.delete = true

					-- apply effects after a delay for a cluster
					elseif (track.cluster and not track.start) then
						if self.options.clusterManaged then
							track.start = true
							local windStep = 100
							track.winds = BLAST.getWind(track.position.p, windStep)
							local w = track.winds[math.floor(track.position.p.y / windStep) * windStep]	
							
							if BLAST.options.smoke then
								trigger.action.smoke( track.position.p, BLAST.options.smokeColor )
							end

							-- get IP at the center of the strike zone and delay of the bomblet's strike zone  
							track.cluster.dp, track.cluster.delayBeforeClusterEffect = BLAST.getClusterIP(
								track.speed,			-- Speed (m/s)
								track.heading,	 		-- Heading
								track.pitch,			-- Pitch (degrees)
								track.position.p.y,		-- Altitude (m)
								track.height,			-- Height (m)
								track.winds,			-- Wind vec3 (m/s) >0 = pousse, <0 = freine
								windStep,				-- Wind step 
								track.cluster.phy		-- Physical characteristics & behaviours
							)
							track.cluster.ip = {}
							track.cluster.ip.x = track.position.p.x + track.cluster.dp.x
							track.cluster.ip.z = track.position.p.z + track.cluster.dp.z
							track.cluster.ip.y = BLAST.getHeight(track.cluster.ip) or 0

							timer.scheduleFunction(
								function(args)
									self:clusterWeapon(args)
								end, 
								{track}, 
								timer.getTime() + track.cluster.delayBeforeClusterEffect
							)
							BLAST.info( string.format( "Weapon %s %s:%s cluster (%i) DEAD at %.3fm, %.3fm/s, %.1f°, countdown %.2fs, ip x:%.2f y:%.2f z:%.2f ", 
								track.categoryName, track.type, track.name, track.id, track.height, track.speed, BLAST.rad2degree(track.pitch), track.cluster.delayBeforeClusterEffect, track.cluster.ip.x, track.cluster.ip.y, track.cluster.ip.z ) )
						else
							track.delete = true
							track.cluster.delete = true
							BLAST.info( string.format( "Weapon %s %s:%s (%i) cluster ignored", track.categoryName, track.type, track.name, track.id ) )
						end
					end
					
				-- delete all tracks treated and ready to be deleted	
				else
					if (track.delete and not track.cluster) or (track.delete and track.cluster and track.cluster.delete) then
						BLAST.info( string.format( "Weapon %s %s:%s (%i) track deleted", track.categoryName, track.type, track.name, track.id ) )
						self.trackedWeapons[track.id] = nil
					
						if self.options.telemetryManaged and self.options.hTelemetry then
							BLAST.writeTelemetry( self.options.hTelemetry, 'onTrackWeapons deleted', track )
						end
					end
				end

			end
		end

		return true
	end

	-- handler for new weapons, sub/munitions hit, close mission
	function BLAST:onEventManaged( event )

		-- occurs when a weapon is shoted
		if (event.id == world.event.S_EVENT_SHOT) then
			--BLAST.info( "Weapon SHOT")
			if BLAST.isTrackable(event.weapon) then
				local track = self:getTrack( event )
				-- save weapon and parameters
				self.trackedWeapons[track.id] = track
				-- registers all weapons except that are not managed or catagory excluded 
				self:addStatsForWeaponShot( track.type, track.name, track.playerName )
				BLAST.info( string.format( "Weapon %s %s:%s %s(%i) SHOT by %s (%i) ", track.categoryName, track.type, track.name, (track.cluster and "cluster " or ""), track.id, track.initiatorName, track.initiatorId ) )
				self:addStatsForWeaponTrack( track.type, track.name )

				if self.options.telemetryManaged and self.options.hTelemetry then
					BLAST.writeTelemetry( self.options.hTelemetry, 'S_EVENT_SHOT', track )
				end
			else
				BLAST.info( string.format( "Weapon %s %s:%s (%i) SHOT, not tracked", track.categoryName, track.type, track.name, track.id ) )
				self:addStatsForWeaponOther( track.type, track.name )

			end

			-- occurs when a munition hit an object, 
		elseif (event.id == world.event.S_EVENT_HIT) then
			--BLAST.info( "Weapon HIT")
			-- a weapon hit something 
			if BLAST.isTrackable(event.weapon) then
				local track = self.trackedWeapons[event.weapon.id_] or self:getTrack( event )
				
				if track then
					track.hit = 1
					track.object = self:getObject(event.target)  

					-- when a weapon tracked hit something					
					if track.object and ((track.object.category == Object.Category.UNIT) or (track.object.category == Object.Category.STATIC) or (track.object.category == Object.Category.SCENERY)) then
						-- nothing else to do for a tracked weapon 
						local pctlife= math.floor((track.object.health / track.object.life) * 100)
						BLAST.info( string.format( "Weapon %s %s:%s (%i) HIT %s:%s, fired by %s, health %i%%", track.categoryName, track.type, track.name, track.id, 
							track.object.type, track.object.name, track.initiatorName, pctlife ) )
						self:addStatsForWeaponHit( track.type, track.name, track.object.type, track.object.name, track.playerName )
						if self.options.telemetryManaged and self.options.hTelemetry then
							BLAST.writeTelemetry( self.options.hTelemetry, 'S_EVENT_HIT', track )
						end
					end
				end
			end

		-- Occurs on the death of a unit
		elseif (event.id == world.event.S_EVENT_KILL) then
			--BLAST.info( "Weapon KILL")
			if event.target then
				--local objectCategory = Object.getCategory( event.target )
				local playerName = event.initiator and BLAST.tableHasKey(event.initiator, 'getPlayerName') and event.initiator:getPlayerName() or "no player"
				local targetType = event.target:getTypeName() or 'no type'
				local targetName = event.target.getName and event.target:getName() or "unknow"
				local weaponName = "no name"
				local weaponType = "no type"
				if event.weapon and type(event.weapon) == "table" and event.weapon.isExist and event.weapon:isExist() then
					weaponName = event.weapon:getDesc().displayName
					weaponType = event.weapon:getTypeName()
				end
				self:addStatsEventKill( targetType, targetName, playerName, weaponName, weaponType )
			end

		-- Occurs when the game thinks an object is destroyed.
		elseif (event.id == world.event.S_EVENT_DEAD) then
			--BLAST.info( "Weapon DEAD")
			if event.initiator then
				local initiatorCategory = Object.getCategory( event.initiator )

				if (initiatorCategory == Object.Category.UNIT) or (initiatorCategory == Object.Category.STATIC) or --initiatorCategory == Object.Category.SCENERY  or 
				   (initiatorCategory == Object.Category.WEAPON) then
					local targetType = event.initiator:getTypeName() or "scenery"
					local targetName = event.initiator:getName()
					self:addStatsEventDead( targetType, targetName )
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
	function BLAST:onEvent( event )
		if (event.id == world.event.S_EVENT_SHOT) or (event.id == world.event.S_EVENT_HIT) or (event.id == world.event.S_EVENT_KILL) or (event.id == world.event.S_EVENT_DEAD) or (event.id == world.event.S_EVENT_MISSION_END) then
			blastProtectedCall( function()
				self:onEventManaged( event )
			end, {} )
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

	function BLAST:initWeaponStatistics( weaponName )
		local result = { name = weaponName, shotCount = 0, trackCount = 0, clusterCount = 0, ids = {}, otherCount = 0, hitCount = 0, blastCount = 0, killCount = 0, deadCount = 0, weaponHoldCount = 0, movementHoldCount = 0 }
		return result
	end

	function BLAST:initTargetStatistics( unitName )
		local result = { name = unitName, hitCount = 0, blastCount = 0, killCount = 0, deadCount = 0, weaponHoldCount = 0, movementHoldCount = 0 }
		return result
	end
	
	function BLAST:initPlayerStatistics( playerName )
		local result = { name = playerName, shotCount = 0, hitCount = 0, blastCount = 0, killCount = 0, deadCount = 0, weaponHoldCount = 0, movementHoldCount = 0, weapons = {} }
		return result
	end

	function BLAST:addStatsForWeaponShot( weaponType, weaponName, playerName )
		self.stats.shotCount = self.stats.shotCount + 1
		--if BLAST.weapons[weaponType] then 
			if not self.stats.weapons[weaponType] then
				self.stats.weapons[weaponType] = self:initWeaponStatistics( weaponName )
			end
			self.stats.weapons[weaponType].shotCount = self.stats.weapons[weaponType].shotCount + 1
		--end

		if playerName then
			if not self.stats.players[playerName] then
				self.stats.players[playerName] = self:initPlayerStatistics( playerName )
			end
			self.stats.players[playerName].shotCount = self.stats.players[playerName].shotCount + 1

			if not self.stats.players[playerName].weapons[weaponType] then
				self.stats.players[playerName].weapons[weaponType] = self:initWeaponStatistics( weaponName )
			end
			self.stats.players[playerName].weapons[weaponType].shotCount = self.stats.players[playerName].weapons[weaponType].shotCount + 1
		end
	end

	function BLAST:addStatsForWeaponTrack( weaponType, weaponName )
		self.stats.trackCount = self.stats.trackCount + 1
		if not self.stats.weapons[weaponType] then
			self.stats.weapons[weaponType] = self:initWeaponStatistics( weaponName )
		end
		self.stats.weapons[weaponType].trackCount = self.stats.weapons[weaponType].trackCount + 1
	end

	function BLAST:addStatsForWeaponOther( weaponType, weaponName )
		self.stats.otherCount = self.stats.otherCount + 1
		if not self.stats.weaponsOther[weaponType] then
			self.stats.weaponsOther[weaponType] = self:initWeaponStatistics( weaponName )
		end
		self.stats.weaponsOther[weaponType].otherCount = self.stats.weaponsOther[weaponType].otherCount + 1
	end

	function BLAST:addStatsForWeaponHit( weaponType, weaponName, targetType, unitName, playerName )
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
			self.stats.targets[targetType] = self:initTargetStatistics( unitName )
		end
		self.stats.targets[targetType].hitCount = self.stats.targets[targetType].hitCount + 1

		if playerName then
			if not self.stats.players[playerName] then
				self.stats.players[playerName] = self:initPlayerStatistics( playerName )
			end
			self.stats.players[playerName].hitCount = self.stats.players[playerName].hitCount + 1

			if not self.stats.players[playerName].weapons[weaponType] then
				self.stats.players[playerName].weapons[weaponType] = self:initWeaponStatistics( weaponName )
			end
			self.stats.players[playerName].weapons[weaponType].hitCount = self.stats.players[playerName].weapons[weaponType].hitCount + 1
		end
	end

	function BLAST:addStatsForWeaponBlast( weaponType, weaponName, targetType, unitName, playerName )
		self.stats.blastCount = self.stats.blastCount + 1
		if self.stats.weapons[weaponType] then
			self.stats.weapons[weaponType].blastCount = self.stats.weapons[weaponType].blastCount + 1
		end

		if not self.stats.targets[targetType] then
			self.stats.targets[targetType] = self:initTargetStatistics( unitName )
		end
		self.stats.targets[targetType].blastCount = self.stats.targets[targetType].blastCount + 1

		if playerName then
			if not self.stats.players[playerName] then
				self.stats.players[playerName] = self:initPlayerStatistics( playerName )
			end
			self.stats.players[playerName].blastCount = self.stats.players[playerName].blastCount + 1
			
			if not self.stats.players[playerName].weapons[weaponType] then
				self.stats.players[playerName].weapons[weaponType] = self:initWeaponStatistics( weaponName )
			end
			self.stats.players[playerName].weapons[weaponType].blastCount = self.stats.players[playerName].weapons[weaponType].blastCount + 1
		end
	end

	function BLAST:addStatsForHoldWeapon( weaponType, weaponName, targetType, unitName, playerName )
		self.stats.weaponHoldCount = self.stats.weaponHoldCount + 1

		if not self.stats.weapons[weaponType] then
			self.stats.weapons[weaponType] = self:initWeaponStatistics( weaponName )
		end
		self.stats.weapons[weaponType].weaponHoldCount = self.stats.weapons[weaponType].weaponHoldCount + 1

		if not self.stats.targets[targetType] then
			self.stats.targets[targetType] = self:initTargetStatistics( unitName )
		end
		self.stats.targets[targetType].weaponHoldCount = self.stats.targets[targetType].weaponHoldCount + 1

		if playerName then
			if not self.stats.players[playerName] then
				self.stats.players[playerName] = self:initPlayerStatistics( playerName )
			end
			self.stats.players[playerName].weaponHoldCount = self.stats.players[playerName].weaponHoldCount + 1

			if not self.stats.players[playerName].weapons[weaponType] then
				self.stats.players[playerName].weapons[weaponType] = self:initWeaponStatistics( weaponName )
			end
			self.stats.players[playerName].weapons[weaponType].weaponHoldCount = self.stats.players[playerName].weapons[weaponType].weaponHoldCount + 1
		end
	end

	function BLAST:addStatsForHoldMovement( weaponType, weaponName, targetType, unitName, playerName )
		self.stats.movementHoldCount = self.stats.movementHoldCount + 1
		if not self.stats.weapons[weaponType] then
			self.stats.weapons[weaponType] = self:initWeaponStatistics( weaponName )
		end
		self.stats.weapons[weaponType].movementHoldCount = self.stats.weapons[weaponType].movementHoldCount + 1

		if not self.stats.targets[targetType] then
			self.stats.targets[targetType] = self:initTargetStatistics( unitName )
		end
		self.stats.targets[targetType].movementHoldCount = self.stats.targets[targetType].movementHoldCount + 1

		if playerName then
			if not self.stats.players[playerName] then
				self.stats.players[playerName] = self:initPlayerStatistics( playerName )
			end
			self.stats.players[playerName].movementHoldCount = self.stats.players[playerName].movementHoldCount + 1

			if not self.stats.players[playerName].weapons[weaponType] then
				self.stats.players[playerName].weapons[weaponType] = self:initWeaponStatistics( weaponName )
			end
			self.stats.players[playerName].weapons[weaponType].movementHoldCount = self.stats.players[playerName].weapons[weaponType].movementHoldCount + 1
		end
	end

	function BLAST:addStatsEventKill( targetType, targetName, playerName, weaponName, weaponType )
		self.stats.killCount = self.stats.killCount + 1

		if BLAST.clusters[weaponType] then
			local clusterType = weaponType
			weaponType = BLAST.clusters[weaponType] 
		end

		if not self.stats.targets[targetType] then
			self.stats.targets[targetType] = self:initTargetStatistics( targetName )
		end
		self.stats.targets[targetType].killCount = self.stats.targets[targetType].killCount + 1

		if playerName then
			if not self.stats.players[playerName] then
				self.stats.players[playerName] = self:initPlayerStatistics( playerName )
			end
			self.stats.players[playerName].killCount = self.stats.players[playerName].killCount + 1

			if not self.stats.players[playerName].weapons[weaponType] then
				self.stats.players[playerName].weapons[weaponType] = self:initWeaponStatistics( weaponName )
			end
			self.stats.players[playerName].weapons[weaponType].killCount = self.stats.players[playerName].weapons[weaponType].killCount + 1
		end
	end

	function BLAST:addStatsEventDead( targetType, targetName )
		self.stats.deadCount = self.stats.deadCount + 1

		if BLAST.clusters[weaponType] then
			local clusterType = weaponType
			weaponType = BLAST.clusters[weaponType] 
		end


		if not self.stats.targets[targetType] then
			self.stats.targets[targetType] = self:initTargetStatistics( targetName )
		end
		self.stats.targets[targetType].deadCount = self.stats.targets[targetType].deadCount + 1

		if playerName then
			if not self.stats.players[playerName] then
				self.stats.players[playerName] = self:initPlayerStatistics( playerName )
			end
			self.stats.players[playerName].deadCount = self.stats.players[playerName].deadCount + 1

			if not self.stats.players[playerName].weapons[weaponType] then
				self.stats.players[playerName].weapons[weaponType] = self:initWeaponStatistics( weaponName )
			end
			self.stats.players[playerName].weapons[weaponType].deadCount = self.stats.players[playerName].weapons[weaponType].deadCount + 1
		end
	end

	-- function to save stats in dcs logs
	function BLAST:saveStats()
		BLAST.info( "--- blast damage : statistics ---" )
		BLAST.info( string.format( "Shot %i", self.stats.shotCount ) )
		BLAST.info( string.format( "Track %i", self.stats.trackCount ) )
		BLAST.info( string.format( "Other %i", self.stats.otherCount ) )
		BLAST.info( string.format( "Hits %i", self.stats.hitCount ) )
		BLAST.info( string.format( "Blasts %i", self.stats.blastCount ) )
		BLAST.info( string.format( "Kill %i", self.stats.killCount ) )
		BLAST.info( string.format( "Dead %i", self.stats.deadCount ) )
		BLAST.info( string.format( "Weapons hold %i", self.stats.weaponHoldCount ) )
		BLAST.info( string.format( "Movements hold %i", self.stats.movementHoldCount ) )
		BLAST.info( " " )

		BLAST.info( "Weapons" )
		for id, weapon in pairs( self.stats.weapons ) do
			BLAST.info( string.format( "	%s : %i shots, %i hits, %i blasts, %i weapon hold, %i movements hold", 
				weapon.name, weapon.shotCount, weapon.hitCount, weapon.blastCount, weapon.weaponHoldCount, weapon.movementHoldCount ) )
		end

		for id, weapon in pairs( self.stats.weaponsOther ) do
			BLAST.info( string.format( "	%s : %i shots, %i hits", weapon.name, weapon.shotCount, weapon.hitCount ) )
		end
		BLAST.info( " " )

		BLAST.info( "Targets" )
		for uId, target in pairs( self.stats.targets ) do
			BLAST.info( string.format( "	%s : %i hits, %i blasts, %i kill for %i dead, %i fire hold, %i movement hold", 
				uId, target.hitCount, target.blastCount, target.killCount, target.deadCount, target.weaponHoldCount, target.movementHoldCount ) )
		end
		BLAST.info( " " )

		BLAST.info( "Players" )
		for pId, player in pairs( self.stats.players ) do
			BLAST.info( string.format( "	%s : %i shots, %i hits, %i blasts, %i kill for %i dead, %i fire hold, %i movement hold",
				pId, player.shotCount, player.hitCount, player.blastCount, player.killCount, player.deadCount, player.weaponHoldCount, player.movementHoldCount ) )
			
			for wId, weapon in pairs( player.weapons ) do
				BLAST.info( string.format( "	   %s : %i shots, %i hits, %i kill for %i dead, %i blasts, %i weapon hold, %i movements hold", 
					weapon.name, weapon.shotCount, weapon.hitCount, weapon.killCount, weapon.deadCount, weapon.blastCount, weapon.weaponHoldCount, weapon.movementHoldCount ) )
			end
			BLAST.info( " " )
		end
	end

	-- function to switch state of blast damage ON/OFF depending of the mission flag "blastDamageState = 0 or 1"
	function BLAST.showStatus( sp, forceShow )
		forceShow = forceShow or false
		BLAST.info( string.format("--- status blast damage : running in %s mode ---", BLAST.multiPlayer and "Multiplayer" or "Local"),forceShow )
		BLAST.info( string.format( "Script state is %s", sp.options.state and "ON" or "OFF" ), forceShow )
		BLAST.info( string.format( "Debug mode is %s", sp.options.debugManaged and "ON" or "OFF" ), forceShow )
		BLAST.info( string.format( "Messages in game is %s", sp.options.debugManaged and "ON" or "OFF" ), forceShow )
		BLAST.info( string.format( "Large explosion is %s", sp.options.explosionsManaged and "ON" or "OFF" ), forceShow )
		BLAST.info( string.format( "Cluster effects is %s", sp.options.clusterManaged and "ON" or "OFF" ), forceShow )
		BLAST.info( string.format( "Blast effect is %s", sp.options.blastwaveManaged and "ON" or "OFF" ), forceShow )
		BLAST.info( string.format( "Units damages is %s", sp.options.damageManaged and "ON" or "OFF" ), forceShow )
		BLAST.info( string.format( "Exclusion(s) area(s) found is %i ", #blast.exclusionAreas), forceShow )			
	end

	-- function to switch state of blast damage ON/OFF depending of the mission flag "blastDamageState = 0 or 1"
	function BLAST.stateOnOff( sp, flag )
		if (sp.options.state ~= flag) then
			sp.removeMenu( sp )
			sp:switchState( flag )
			sp.setSubMenus( sp )
			BLAST.info( string.format( "Blast Damage: %s", sp.options.state and "ON" or "OFF" ) )
		end
	end

	-- function to switch state of blast damage ON/OFF depending of the mission flag "blastDamageState = 0 or 1"
	function BLAST.debugOnOff( sp, flag )
		if (sp.options.debugManaged ~= flag) then
			sp.removeMenu( sp )
			sp.options.debugManaged = flag
			sp.setSubMenus( sp )
			BLAST.info( string.format( "Debug mode: %s", sp.options.debugManaged and "ON" or "OFF" ) )
		end
	end

	-- function to switch state of blast damage ON/OFF depending of the mission flag "blastDamageState = 0 or 1"
	function BLAST.msgInGameOnOff( sp, flag )
		if (sp.options.msgInGame ~= flag) then
			sp.removeMenu( sp )
			sp.options.msgInGame = flag
			sp.setSubMenus( sp )
			BLAST.info( string.format( "Messages in game: %s", sp.options.msgInGame and "ON" or "OFF" ) )
		end
	end

	-- function to switch Statistics live ON/OFF 
	function BLAST.statisticsOnOff( sp, flag )
		if (sp.options.msgStatistics ~= flag) then
			sp.removeMenu( sp )
			sp.options.msgStatistics = flag
			sp.setSubMenus( sp )
			BLAST.info( string.format( "Statistics live: %s", sp.options.msgStatistics and "ON" or "OFF" ) )
		end
	end

	-- function to switch state of blast damage ON/OFF depending of the mission flag "blastDamageState = 0 or 1"
	function BLAST.removeMenu( sp )
		if sp.options.state then
			missionCommands.removeItem( sp.mnuState.ON )
		else
			missionCommands.removeItem( sp.mnuState.OFF )
		end

		if sp.options.debugManaged then
			missionCommands.removeItem( sp.mnuDebug.ON )
		else
			missionCommands.removeItem( sp.mnuDebug.OFF )
		end

		if sp.options.msgInGame then
			missionCommands.removeItem( sp.mnuMsgInGame.ON )
		else
			missionCommands.removeItem( sp.mnuMsgInGame.OFF )
		end

		if sp.options.msgStatistics then
			missionCommands.removeItem( sp.mnuStatistics.ON )
		else
			missionCommands.removeItem( sp.mnuStatistics.OFF )
		end
	end

	-- function to switch state of blast damage ON/OFF depending of the mission flag "blastDamageState = 0 or 1"
	function BLAST.setSubMenus( sp )
		sp:menuState()
		sp:menuDebug()
		sp:menuMgsInGame()
		sp:menuStatistics()
	end

	-- function to set menus directly in the mission
	function BLAST:menuState()
		if self.options.state then
			self.mnuState.ON = missionCommands.addCommand( "Blast Damage to OFF", blast.mnuMain, self.stateOnOff, self, false )
		else
			self.mnuState.OFF = missionCommands.addCommand( "Blast Damage to ON", blast.mnuMain, self.stateOnOff, self, true )
		end
	end

	-- function to set menus directly in the mission
	function BLAST:menuDebug()
		if self.options.debugManaged then
			self.mnuDebug.ON = missionCommands.addCommand( "Debug mode to OFF", blast.mnuMain, self.debugOnOff, self, false )
		else
			self.mnuDebug.OFF = missionCommands.addCommand( "Debug mode to ON", blast.mnuMain, self.debugOnOff, self, true )
		end
	end

	-- function to set menus directly in the mission
	function BLAST:menuMgsInGame()
		if self.options.msgInGame then
			self.mnuMsgInGame.ON = missionCommands.addCommand( "Messages in game to OFF", blast.mnuMain, self.msgInGameOnOff, self, false )
		else
			self.mnuMsgInGame.OFF = missionCommands.addCommand( "Messages in game to ON", blast.mnuMain, self.msgInGameOnOff, self, true )
		end
	end

	-- function to set menus directly in the mission
	function BLAST:menuStatistics()
		if self.options.msgStatistics then
			self.mnuStatistics.ON = missionCommands.addCommand( "Statistics to OFF", blast.mnuMain, self.statisticsOnOff, self, false )
		else
			self.mnuStatistics.OFF = missionCommands.addCommand( "Statistics to ON", blast.mnuMain, self.statisticsOnOff, self, true )
		end
	end

	-- function to set menus directly in the mission
	function BLAST:initMenus()
		-- main menu
		self.mnuMain = missionCommands.addSubMenu( "Blast Damage" )

		-- show sp status
		self.mnuStatus = missionCommands.addCommand( "Show status", self.mnuMain, self.showStatus, self )

		-- script ON/OFF
		BLAST.setSubMenus( self )

	end

	-- switch blast damage ON/OFF 
	function BLAST:switchState( flag )
		BLAST.info( "BLAST version " .. blast.version )

		-- activation
		if (flag) then
			self.exclusionAreas = BLAST.getExclusionAreas(self.options.areasPattern)

			-- add handle to track weapons
			self.hTrackWeapons = timer.scheduleFunction( 
				function()
					blastProtectedCall( function()
						self:onTrackWeapons()
					end, {} )
					return timer.getTime() + self.options.timerOnTrack
				end, 
				{}, timer.getTime() + self.options.timerOnTrack -- time for the next call
			 )

			-- add event handler on DCS S_EVENT_????
			world.addEventHandler( self )

			if self.options.telemetryManaged then
				self.options.hTelemetry = BLAST.openTelemetry()
			end

		-- deactivation
		else
			world.removeEventHandler( self )
			if self.hTrackWeapons then				
				timer.removeFunction( self.hTrackWeapons )
				self.hTrackWeapons = false
			end

			-- list of weapons flying deleted
			self.trackedWeapons = {}
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
	end

	function BLAST:start()
		if ((self.options.startAuto == true) and (self.options.state == false)) then
			self:switchState( true )
		end
		self:initMenus()
	end

	blast = BLAST:new()
	blast:start()
	-- show state
	BLAST.showStatus( blast, true )	

end -- do
