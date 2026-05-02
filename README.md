# Blast Damage 

Blast Damage is a script designed for mission designers in DCS World. It instantly allocates the full power of your aircraft's ammunition and DCS capabilities. Blast Damage is written en lua which is a small and fast programming language, which is embedded in DCS World.
 
## Goal 

This mod enhances the realism of DCS missions, adding physical blast effects (blast wave), integrating a simulation of the real effects of a cluster and adding special effects during explosions. The blast wave is visible, additional effects show the propagation of successive explosions and environmental effects are more immersive, making combat more spectacular and realistic.  
In addition, it offers the possibility of recording statists for better analysis of the performance of each weapon and driver. 

### Main features

- Munition type management and behaviour according of his category and subcategory, except guns
- Blast wave smulation rewrite with Kingery-Bulmashis data algorythms.
- Optimization of the radius effect depending of the ground unit attribute (vehicle or infantry)
- Damages applies to vehicles in addition to infantry and ground units
- Cluster trajectory management and carpet of bomblets simulation with enhanced damages
- Statistics management for global shot, hit, ect... for each munition and pilot
- Telemetry feature from the shot to the hit including trajecttory datas, stored in csv file
- Exclusion areas management to define areas where no effect should be applied (circle and polygon)

## Installation

### Prerequisites

- Digital Combat Simulator World (version 2.9 ou more)

### Instructions

1. Download the latest version from [Releases](../../releases)
2. Extract archive contents
3. Copy the folder of your choice into your directory DCS  :
   ```
   C:\Users\[your name]\Saved Games\DCS\Mods\
   ```
4. Launch DCS, load your mission and add a trigger at the 1st line  
```
MISSION START named "Blast Damage script"
CONDITIONS : "should stay empty"
ACTIONS : DO SCRIPT FILE and select blast_damage.lua
```

### Know issues

- Cluster visual effects can overload a server if too many clusters explode simultaneously.
- Avoid situations such as invicible units receiving unlimited ammunition. The effects can be more or less pronounced in multiplayer, depending on latency.
- On heavily-loaded servers, it may be advisable to reduce or disable the flare effect.
- Not all weapons have been tested, so it's possible that you won't get the effect you're looking for. Please let me know if you encounter any problems with the context (local or multiplayer).

# Historique
The original script was called [Splash Damage 2.0](https://forum.dcs.world/topic/289290-splash-damage-20-script-make-explosions-better/). It was initially created by FrozenDroid in 2020, taken over by Grimm in 2021, supported by Kervinou in 2023 [here](https://github.com/Kervinou/DCS-Scripts/tree/master) and finally taken over with talent here [github](https://github.com/stephenpostlethwaite/DCSSplashDamageScript).

Initially, I chose to build a more "Blast wave" oriented script, i.e. 100% capable of simulating the real blast effects of a bomb according to the [formulas of Kingery-Bulmashis data algorythms](https://unsaferguard.org/fr/un-saferguard/kingery-bulmash).

Once this stage had been completed, it was time to build on the initial ideas by increasing the power of the explosion, as FrozenDroid had envisaged, adding and enhancing an inertia factor to the affected units or even rendering them inoperable without destroying them. 

Finally, by inserting almost all the weapons, DCS showed some limitations: it was unable to systematically produce the same weapon behavior in local vs multiplayer modes. This lead to a lengthy quest to identify the least cpu-intensive and most efficient method for handling the [trajectory and effects of a cluster's bomblets](https://en.wikipedia.org/wiki/Projectile_motion).

In addition, to better track weapon behavior, we've added ammunition telemetry functions, support for weapons and pilots performance statistics, and augmented reality including all possible DCS effects. 
In addition, telemetry functions have been added to better monitor weapon behavior. 

And last but not least, weapon and pilot performance statistics have been added too. 

## Contribution

Contributions are welcome! Don't hesitate to suggest changes or inform me of any issue.

# Manage your configuration
## How Blast Damage works
Blast Damage is a script that will run automatically when you launch your mission.

### Menu
You can verify that it is running by checking for the presence of the `F10 > Other > Blast Damage` menu.
The menus operate as a button ON/OFF. Example: if the menu offers you 

  → **Blast Damage to OFF**, to disable Blast Damage   
  → **Blast Damage to ON**, to reactivate it


## Configuration

### Options
Le mod peut être configuré en éditant le fichier `blast_damage.lua` situé dans le dossier du mod.

Options disponibles :
```lua
	BLAST.options = {
		explosionsManaged = true, -- enable enhanced explosions management
		blastwaveManaged = true, -- enable blast wave management
		clusterManaged = true, -- enable cluster management

		blastDiffusionDelay = 10, -- speed of the effect from the center of explosion to the peripheral (10 = 0.1 sec/meter)

		staticBoost = 1.0, -- apply extra damage to Unit.Category.STRUCTURE 
		sceneryBoost = 2.0, -- apply extra damage to Unit.Category.SCENERY
		rocketBoost = 2.0, -- apply a coefficient of power for rockets
		
		flareVisualEffect = true, -- activate visual effect of white flare

		areasPattern = "*BLAST*", -- tag contained in the name of zone

		damageManaged = true, -- allow blast wave to affect ground unit movement and weapons
		vehicleMovementThreshold = 70, -- below the threshold the movements are disabled to simulate severe injury
		vehicleFireThreshold = 80, -- below the threshold the ROE are set to ON HOLD to simulate severe injury
		infantryMovementThreshold = 70, -- below the threshold the movements are disabled to simulate severe injury
		infantryFireThreshold = 80, -- below the threshold the ROE are set to ON HOLD to simulate severe injury

		-- timer management, do not set value below 0.01s, change carrefuly the default values
		timerOnShot = 0.05, -- each 0.05s S_EVENT_SHOT event is checked 
		timerOnTrack = 0.05, -- delay between 2 checks of weapons tracked, do not set a too much long time 

		-- debug mode
		debugManaged = true, -- enable trace log
		msgInGame = false, -- enable messages in game for players
		msgStatistics = true,  -- log for statistics

		smoke = false, -- show a smoke for the impact point or zones  
		smokeColor = trigger.smokeColor.Green, -- available colors : Green Red White Orange Blue

		-- telemetry to trace munitions between start tracking and when DCS destroy munition
		telemetryManaged = false, -- if telemetry enabled, you have to unsanitize "lfs" in MissionScript.lua
		telemetryFilename = "bd_telemetry.csv",
		hTelemetry = false, -- file handle to store datas from telemetry

		-- state of blast damage & menus
		state = false, -- true when script is active, at the start it's false. let it to false
		startAuto = true -- start automatically with the mission
	}
```

## Changelog

### pre-version 0.9.1 (Date)
- preversion considered to be in development pending feedback

## Remerciements

- The DCS community, and in particular the [3rd Wing](https://www.3rd-wing.net/) for testing and feedback.
- Eagle Dynamics for [Digital Combat Simulator](https://www.digitalcombatsimulator.com/fr/downloads/world/)
- All historical contributors to the project

## 📧 Contact

- **Author** : [Detox]
- **Forum DCS** : [Lien vers topic]

---
## 📄 Licence

This project is licensed under [MIT](LICENSE) - See the LICENSE file for more details.


**Note** : DCS World and Digital Combat Simulator are registered trademarks of Eagle Dynamics.
