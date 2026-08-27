# Regenerate from the repo root with:  vhs docs/demos/sidebar.tape
#
# The agents on screen are fakes built by demo-setup.el, so the demo
# records identically every time and never talks to a real agent.

Require emacs

Output docs/demos/sidebar.gif

Set FontSize 14
Set Width 1000
Set Height 620
Set Padding 10
Set Framerate 12
Set TypingSpeed 40ms

Hide
Type "emacs -nw -Q -L . -l docs/demos/demo-setup.el"
Enter
Wait+Screen@60s /Agents/
Sleep 2s
Show

# The list: four agents, three projects, live status on every row.
Sleep 1800ms

# Walk down to an agent in another project and focus it.
Down
Sleep 1s
Down
Sleep 800ms
Down
Sleep 1s
Enter
Sleep 2200ms

# Back to the sidebar; TAB folds a project group away, TAB brings it back.
Ctrl+X
Type "o"
Sleep 800ms
Tab
Sleep 1800ms
Tab
Sleep 1200ms

# Mark agents with `a` to tile them side by side.
Up
Sleep 500ms
Up
Sleep 500ms
Type "a"
Sleep 1s
Down
Sleep 500ms
Type "a"
Sleep 1800ms
Down
Sleep 400ms
Down
Sleep 400ms
Type "a"
Sleep 3s

# `t` returns to single focus.
Type "t"
Sleep 2500ms
