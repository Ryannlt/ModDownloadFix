# ModDownloadFix

[![Latest release](https://img.shields.io/github/v/release/Ryannlt/ModDownloadFix?label=latest&style=flat-square)](https://github.com/Ryannlt/ModDownloadFix/releases/latest)
[![License](https://img.shields.io/badge/license-MIT-blue?style=flat-square)](https://github.com/Ryannlt/ModDownloadFix/blob/main/LICENSE)

A [BepInEx](https://github.com/BepInEx/BepInEx) client mod for **Holdfast: Nations At War** that fixes a soft crash
after downloading or updating a server's Workshop mods.

## The bug

When you join a server running a Workshop mod you don't have, or one that needs an update, the game opens a download
popup. If the download finishes while you are still connected, the popup joins the server for you after a short
countdown. The map loads, but the round never finishes setting up and the spawn menu never opens.

The game throws away the server's join details, including the map rotation, before that auto-join uses them. The
scoreboard then looks up the current map in an empty list, and setting up the round stops partway through.

ModDownloadFix keeps those details until the join has used them. It also adds bounds checks to the two map rotation
lookups, so a short list can't stop a round from loading.

## Install

Install through [r2modman](https://r2modman.com/) or Thunderstore Mod Manager. It is client side, has no settings,
and nobody else on the server needs it.

To install by hand, install
[BepInExPack](https://thunderstore.io/c/holdfast-nations-at-war/p/BepInEx/BepInExPack/) first, then put
`ModDownloadFix.dll` from the [latest release](https://github.com/Ryannlt/ModDownloadFix/releases/latest) in
`BepInEx\plugins\ModDownloadFix\`.

## Did it work?

`BepInEx\LogOutput.log` shows this on launch:

```
[Info   :ModDownloadFix] Ready.
```

When the download popup joins for you, it also shows:

```
[Info   :ModDownloadFix] Kept the handshake packet for the Workshop auto-join.
[Info   :ModDownloadFix] Released the handshake packet after loading.
```

A normal join adds nothing else. A warning from ModDownloadFix means a bounds check caught something the main fix
didn't, which is worth reporting with `BepInEx\LogOutput.log` and the game's `Player.log` attached.

## Building

Needs the game, BepInEx in an r2modman profile, and a [.NET SDK](https://dotnet.microsoft.com/download).
`build.ps1` compiles the mod and copies it into the `Dev` profile. `package.ps1` produces a Thunderstore zip in
`Package\`.

## Licence

[MIT](https://github.com/Ryannlt/ModDownloadFix/blob/main/LICENSE).
