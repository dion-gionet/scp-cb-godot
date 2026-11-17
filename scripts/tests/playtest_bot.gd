extends "res://scripts/tests/bot_tools.gd"
# Scripted playtest of the real game, driven by input actions and physics.
#   SCP_BOT=1 [SCP_SEED=n] [SCP_BOT_ONLY=fast|full|tools|name,name] [SCP_SHOT=1] [SCP_REPORT=path]
# The class is assembled as a chain, each file adding scenarios to the previous one:
#   bot_base.gd      runner, scenario sets, world reset, helpers (check, secs, place_player...)
#   bot_world.gd     spawn, blink/stamina, doors, gaps, streaming, persistence, elevators, perf, save/load
#   bot_173.gd       SCP-173 rules, facing, doors
#   bot_items_ui.gd  items, using items, keypad, inventory and menus
#   bot_npcs.gd      SCP-049, hazmat, audio, pathfinding, 106, MTF, guards and other NPCs
#   bot_events.gd    room events, gates, the intro and 079/096/895/860 scenes
#   bot_systems.gd   ambient events, console, lighting, infection, room drawing and the save of actors
#   bot_tools.gd     screenshot and map dumpers (not part of any test set)
