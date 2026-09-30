# Bloxelizer-Function-Import
A small Windows utility for importing Bloxelizer Minecraft Java Edition `.mcfunction` exports into a Minecraft datapack.

It turns a Bloxelizer ZIP containing files such as:

```text
creation.mcfunction
creation_0.mcfunction
creation_1.mcfunction
```

into a named Minecraft function that can be run with:

```mcfunction
/function bloxelizer:village
```

## Features

- Simple Windows Forms GUI.
- Standard ZIP file picker.
- User-selected structure names.
- Automatic lowercase and safe-name normalization.
- Overwrite warning before replacing an existing structure.
- Renames `creation.mcfunction` and all numbered files.
- Updates exact `bloxelizer:creation_N` references.
- Converts Bloxelizer entity markers into valid `summon` commands.
- Converts the legacy Bloxelizer `chain` block alias to Java’s `iron_chain`.
- Uses a temporary extraction directory and cleans it up afterward.
- Preserves the original ZIP.
- Does not modify `pack.mcmeta` or unrelated datapack files.
- Uses a one-process PowerShell execution-policy bypass; it does not change the system-wide policy.

## Download and run

Keep these files together:

- `Bloxelizer Importer.bat`
- `Bloxelizer Importer.ps1`

Double-click **Bloxelizer Importer.bat**.

Then:

1. Click **Browse...** and select the Bloxelizer ZIP.
2. Enter the structure name, for example `village`.
3. Click **Import**.
4. Confirm any name-normalization or overwrite prompt.
5. In Minecraft, run `/reload`.
6. Run the displayed function command.

Example:

```mcfunction
/function bloxelizer:village
```

To place the structure with its origin one block below the player:

```mcfunction
/execute positioned ~ ~-1 ~ run function bloxelizer:village
```

## Destination

By default, processed functions are copied to:

```text
C:\Users\<username>\AppData\Roaming\.minecraft\saves\Dadlands\datapacks\bloxelizer\data\bloxelizer\function
```

The namespace is `bloxelizer`.

## Bloxelizer compatibility conversions

Some Bloxelizer exports encode entities as pseudo-blocks such as:

```mcfunction
setblock ~11 ~24 ~12 zombie[__entity=1,...]
```

The importer converts these to commands like:

```mcfunction
summon minecraft:zombie ~11 ~24 ~12 {Rotation:[64.38916015625f,0f]}
```

The importer preserves the relative position and rotation. It intentionally does not copy embedded Paper/Bukkit server snapshot data because that data is not reliable vanilla datapack entity NBT.

Older exports may contain:

```mcfunction
setblock ~1 ~8 ~8 chain[axis=y,waterlogged=false]
```

These are converted to `iron_chain` for Java Edition.

## Troubleshooting

### The function runs but nothing appears

Run `/reload` after importing. Minecraft keeps datapack functions in memory until the datapack is reloaded.

Then run the command again:

```mcfunction
/function bloxelizer:your_structure_name
```

### Unknown function

Use the `bloxelizer:` namespace explicitly. For example:

```mcfunction
/function bloxelizer:homestead
```

If Minecraft reports an invalid block type, run `/reload` and check the latest Minecraft log. The importer should convert Bloxelizer entity markers and legacy `chain` entries automatically.

### Existing structure warning

The importer checks for files matching the selected structure name, such as:

```text
village.mcfunction
village_0.mcfunction
village_1.mcfunction
```

It asks for confirmation before overwriting them.
