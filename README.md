# CarboniteQuestieBridge

Bridge between Questie-335 and Carbonite for World of Warcraft 3.3.5a.

## Current version

Version 0.5.0 renders Questie-335's filtered available quest markers through Carbonite's native icon pool.

Implemented:

- Questie-335 remains the quest authority.
- Carbonite remains the renderer.
- Questie AreaID/UiMapID values map to Carbonite map IDs.
- Marker alpha follows Carbonite's map fade.
- Normal quests use Blizzard quest-difficulty colors.
- Repeatable, group, PvP, dungeon, and raid quests receive distinct colors and sizes.
- `/cqb icons on` and `/cqb icons off` toggle bridge markers.

## Install

Install the repository folder as:

`Interface/AddOns/CarboniteQuestieBridge`

The folder must contain:

- `CarboniteQuestieBridge.toc`
- `CarboniteQuestieBridge.lua`

Required addons:

- Carbonite
- Questie-335

## Commands

- `/cqb status`
- `/cqb refresh`
- `/cqb icons on`
- `/cqb icons off`
- `/cqb unresolved`
- `/cqb debug on`
- `/cqb debug off`

## Design

Questie-335 is responsible for availability, prerequisites, completion, blacklists, and its configured level filters. Carbonite only renders the resulting markers.

## Roadmap

- Add a Carbonite map button to toggle local/current-area filtering versus all visible mapped quests.
- Refine quest-type presentation after in-game testing.
- Add configuration only where it provides clear value.
