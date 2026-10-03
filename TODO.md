# TODO List

## Features

### General

- [x] Rename body to group

### Coordinate Systems

- [x] When a coordinate system is selected, it should highlight (subtle color change/glow around the origin dot)
- [x] Each group in the side bar should have a coordinate system visibility toggle. (Parts had one for their override frame, removed along with overrides.)
- [x] Group coordinate systems should be visibly different than the global coordinate system - a little smaller with thinner lines.
- [x] Identify origin identity (which entity it belongs to) with tooltip on hover
- [x] Identify COM identity (which entity it belongs to) with tooltip on hover

### Parts

- [x] Right clicking a part in the side bar or the viewport should bring up a menu with "Select Others". This should replace the "Select All" button on the right sidebar.
- [x] Delete the Assembly line from the right hand side bar
- [x] Remove the mass source options (None and Override). A part just has a mass, which defaults to 0 g.
- [x] Delete the group line from the right side bar
- [x] On the right side bar, delete volume
- [x] On the right side bar, delete Mass under "Mass Properties" and move the form field there instead.
- [x] On the right side bar, render the interitas in grey text like the other non-editable values.

### Groups


- [x] Right click menus should work when clicking parts in the viewport, not just the parts/group sidebar.
- [x] When right clicking part(s), the menu should have "Add to group" along with "New Group".
- [x] Right clicking a group in the side bar should bring up a menu with "Select Parts"
- [x] Double clicking a group in the side bar should allow the name to be edited in place.


** Math

- [x] Implement a toggle to calculate interitas about COM vs global origin.