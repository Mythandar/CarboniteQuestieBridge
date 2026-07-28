# CarboniteQuestieBridge architecture

The bridge is a thin adapter between two supported APIs.

```text
QuestieMapAPI
    normalized available-quest markers and RESET events
        ↓
CarboniteQuestieBridge
    map-ID translation, tooltip/style policy, action translation
        ↓
CarboniteExternalMarkerAPI
    frame lifecycle, map projection, tooltip display, navigation
```

## Ownership

### Questie

- Determines quest availability.
- Publishes normalized marker records.
- Announces marker snapshot changes.
- Owns quest metadata.

### Carbonite

- Allocates and recycles map frames.
- Projects zone coordinates to world coordinates.
- Draws marker textures and tooltips.
- Owns Goto, HUD, route and waypoint behaviour.
- Owns native available-quest visibility.

### Bridge

- Maps Questie UI map IDs to Carbonite map IDs.
- Registers the Questie provider.
- Supplies marker styles and tooltips.
- Translates Track into a Carbonite external navigation target.
- Contains no quest filtering and no map frame allocation.

## Runtime files

Only these files are loaded:

```text
CarboniteQuestieBridge.toc
FormalIntegration.lua
```

The package version comes only from the TOC through `GetAddOnMetadata()`.

## Commands

```text
/cqb status
/cqb refresh
/cqb icons on
/cqb icons off
/cqb native on
/cqb native off
```

Settings are stored in `CarboniteQuestieBridgeDB`.

## Current compatibility boundary

The explicit map table covers verified maps first. Name matching remains a fallback until the complete deterministic map table is generated and tested.
