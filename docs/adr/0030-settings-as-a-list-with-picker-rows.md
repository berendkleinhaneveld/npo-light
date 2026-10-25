# 0030. Show settings as a list, with a picker row per timing

- **Status:** Proposed
- **Date:** 2026-10-25
- **Deciders:** @berendkleinhaneveld

## Context

FR-SET-02 asks for three timings, each "a small set of sensible choices, not
free text typed with a remote". The settings screen showed every choice of a
timing as a button, side by side, in a left column whose width those buttons
decided; the account and erasing were a second column beside it, so the page
fitted without scrolling.

The still-watching question in kids mode went from four choices to six. A row
of six buttons made the left column as wide as the screen allows and pressed
the right column against the edge, and every further choice would make that
worse.

tvOS has no stepper, slider or wheel: the remote's swipes move focus, and a
control that also took them to change a value would fight the focus engine.
What the system's own Settings does for a setting like *Sleep After* is a row
that names the setting and shows its value, and opens a list of the choices
with a checkmark on the one in use.

## Decision

**Settings is a `Form`, and each timing is a `Picker` with the
`.navigationLink` style.** The row shows the setting and its value; selecting
it opens the list of choices, and choosing one goes back. Signing out and
erasing are ordinary rows in their own sections, their explanations in the
section footers. The form is no wider than 1200 points, so that a label and
its value still read as one row.

## Alternatives considered

- **Keep the buttons side by side** — it showed every choice at once and took
  one click, but it does not grow beyond five or six choices, and it is not
  what a tvOS user knows from anywhere else.
- **A menu-style picker** (`.menu`), which opens over the row — it is also a
  system control, but a long list of durations reads better as its own page,
  as the system's Settings shows it.
- **A control of our own that changes the value with left and right** — it
  would take the swipe that moves focus, and nothing else on tvOS behaves
  like it.
- **Picker rows in the left column, the two columns kept** — a `Form` is a
  scrolling list of its own and does not sit inside another scroll view;
  rows on one side and plain buttons on the other would look like two
  screens.

## Consequences

- The screen looks like the system's settings, and a timing can take as many
  choices as FR-SET-02 allows without changing the layout.
- Changing a timing takes two clicks instead of one, and only the value in use
  is visible until the row is opened.
- The page no longer fits on one screen without scrolling; focus scrolls it.
- The picker draws its own rows and list, so a choice is no longer an element
  of ours with its own accessibility identifier: a UI test finds the row by
  its identifier and a choice by its words.
- The wireframe shows the same list and the same page of choices.
