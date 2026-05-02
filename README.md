# GDScript Visual Layer Prototype

A prototype Godot addon exploring a dynamic, low-maintenance visual layer for editing regular GDScript.

This is not a finished visual scripting system.
It is a proof of concept to show the idea of using normal GDScript as the source of truth, while representing parts of the script as editable graph nodes.

Some parts work, some are rough but usable, and many things are still missing or broken.

## Status

Prototype / experimental.

I uploaded this mainly for discussion and feedback.
I do not plan to actively maintain this addon.

Expect bugs, missing nodes, broken edge cases and incomplete code generation.

## Main idea

The goal is not to create a separate scripting language or runtime.

Instead, the addon tries to work as a visual layer on top of regular GDScript:

- GDScript stays the source of truth
- The addon parses existing scripts
- Functions, variables, calls and statements are shown as graph nodes where possible
- Edited graph nodes can write changes back into the normal script editor
- Complex or unsupported code can stay as editable code or expression nodes

## Low-maintenance approach

A major goal of this prototype is to avoid manually maintaining a huge custom node library.

Where possible, the addon tries to pull information dynamically from Godot itself:

- Engine classes and methods are read through ClassDB
- Script functions are parsed from the current GDScript file
- Method signatures are used to create node inputs where possible
- Special language constructs like `if`, `return`, `for`, `await` and similar still need custom handling

This means the addon should not need a manually created node for every Godot method.

## Layout data

Node positions and graph layout data are stored in a sidecar file:

`script_name.gd.vsmeta`

The GDScript file itself should stay clean.
The `.vsmeta` file is only used for visual layout information such as node positions, graph connections and groups.

## Editing workflow

Changes are not written directly to disk.

When using `Write Function`, the addon updates the opened script in Godots script editor instead.
This allows the generated code to be reviewed before saving.

The intended workflow is:

1. Open a script
2. Open the function graph
3. Edit nodes
4. Click `Write Function`
5. Review the changed code in the script editor
6. Save manually if it looks correct

## Current goals

- Visual overview of GDScript functions and variables
- Function graph view for selected functions
- Editable nodes for common patterns like calls, returns, literals, expressions and code statements
- Dynamic method suggestions where possible
- Grouping nodes for better readability
- Store visual layout outside the script file
- Keep regular GDScript editable at all times

## Non-goals

This prototype is not trying to:

- Replace GDScript
- Build a full visual scripting language
- Support every possible GDScript expression
- Hide the code from the user
- Create a separate runtime system

## Notes

This addon is rough and incomplete.
It is mainly meant to demonstrate the concept and start a discussion about whether a lightweight visual layer for GDScript could be useful.
