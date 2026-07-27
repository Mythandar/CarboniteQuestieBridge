# CarboniteQuestieBridge

Experimental bridge between Questie 3.3.5a and Carbonite.

## Current version

Version 0.1.0 is a diagnostic build. It does not draw Carbonite markers yet. It safely hooks Questie's `QuestieMap:DrawWorldIcon` function after Questie has filtered available quests.

## Install

Place the repository folder in the Wrath 3.3.5a `Interface/AddOns` directory as:

`Interface/AddOns/CarboniteQuestieBridge`

The folder must contain:

- `CarboniteQuestieBridge.toc`
- `CarboniteQuestieBridge.lua`

Carbonite and Questie must both be enabled.

## Test

After logging in, run:

- `/cqb status`
- `/cqb debug on`

Then reload the UI or cause Questie to refresh its available quest markers.

Expected chat output includes:

`CQB: Questie marker hook installed.`

With debug enabled, each filtered available quest marker will produce a line containing its quest ID, starter, Questie icon type, area ID, and coordinates.

Disable diagnostic spam with:

`/cqb debug off`

## Design

Questie remains responsible for quest availability, prerequisites, completion, blacklist, and low-level filtering. Carbonite will eventually act only as the renderer.
