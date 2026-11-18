# Build & Play Toolbar 01 — targeted acceptance

Use a test installation built with build-play-toolbar-01.patch and two disposable .map copies in different directories. Put an adjacent .jsonc next to each map. Include JSONC comments, a trailing comma, and a string containing https:// to exercise the parser. Record the SHA-256 of both JSONC files before and after the checks.

| Check | Procedure and expected result |
|---|---|
| Appearance | Start with engine.game. The separate Build & Play toolbar contains Game Mode, Lighting Preset, Lighting Quality, Compile and Play, in order. Main Toolbar has no Play action. Lighting Quality displays disabled Engine Default. Build Validation can be shown as a dock. |
| Modes | Select Team Deathmatch, Search & Destroy, and Capture the Flag; there is no Deathmatch option. Changing mode refreshes the dock. |
| Lighting | Set map A's sky.image to skies/evening. Map Settings shows skies/evening, Midday shows skies/midday, and Evening shows skies/evening. Source JSONC hashes are identical after the test. |
| Persistence | Set A to SD/Midday and B to CTF/Evening. Alternate A and B, create a new map, then reopen A after restarting Radiant. The choices follow the map path, with TDM/Map Settings on a new map. |
| TDM | Remove all spawn markers and omit tdm in JSONC. Confirm both diagnostics. Add a top-level marker named spawn01 and declare tdm; click Validate Map and confirm they disappear. A brush or unrelated entity named spawn01 does not satisfy the check. |
| SD | Check that missing sd_a*, sd_b*, bomb_a, bomb_b, and sd are reported. Add the corresponding top-level markers and declaration one by one. bomb_a_extra must not satisfy exact bomb_a. Confirm saving remains possible with warnings. |
| CTF | Check that missing sd_a*, sd_b*, ctf_a, ctf_b, and ctf are reported. Add the corresponding top-level markers and declaration one by one. ctf_a_extra must not satisfy exact ctf_a. |
| Compile | Click Compile. The dock shows Compiler backend unavailable. No compiler, Tools or game process starts and no map export is created. |
| Play | In a test installation configured for legacy Play, select TDM/Map Settings and use Play from the new toolbar with a valid test map. Confirm the existing save and launch path. Repeat with a known invalid legacy input to confirm its existing error is surfaced. The dock and tooltip explain that legacy Play uses TDM and the map's existing lighting. |

Source validation covers workflow checksum/order, application of all 14 patches, removal of the old toolbar action, and dispatch to the existing Build_runEnginePlay handler. GUI and runtime checks require a new Windows x64 build.
