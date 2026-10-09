# Terminal pane access

`TerminalView` supplies an unpainted semantic representation through the shared
public SwiftTUI accessibility API. It identifies the pane and its child title,
reports the live logical input caret, and exposes the current viewport as text.
The child emulator still owns terminal parsing, screen buffers and scrollback.
The representation does not infer buttons, menus or other widgets from pixels.

Freeze output review preserves an immutable viewport while the child continues
running. Earlier output and Later output move through retained normal-buffer
history; Follow latest output returns to the live viewport. Review identifies
its absolute rows and reports buffer changes or history eviction without silently
replacing a frozen copy. The live child caret is distinct from the review anchor.
Alternate-screen children have no normal scrollback navigation.

Copy reviewed output uses the host's clipboard action and reports acceptance or
refusal. Review/copy preserves Unicode and soft line wraps, skips wide-cell
continuations, removes control and bidi formatting characters, and limits a
review to 16384 Unicode scalars. A truncation notice is explicit. Child OSC/VT
commands are decoded by the emulator and are not replayed as review commands.
Custom sessions must supply trustworthy row/buffer metadata; the compatibility
defaults provide a live grid with no caret or history navigation.

Copy and line-submission results are also polite announcements, including a
repeated identical result. Feedback never includes the submitted input text.

Enter child line input provides a standard editable field and a separate Send
line to child action. Sending uses the session's paste path followed by Return;
it is appropriate for a child that accepts line input. Hide input uses a secure
field. Leave child input discards the draft and restores assistive focus to the
pane title; ordinary browser Tab navigation can return to surrounding app
controls. Control characters, embedded newlines and oversized input are rejected
without submission. A new session identity receives new review/input state.

The existing native pane keyboard route is unchanged: the host interceptor runs
first, selection/history commands stay local, and ordinary Escape can still
belong to the child. The semantic line editor does not implement an arbitrary
full-screen child's editing protocol or discover whether that child expects a
password. Applications embedding opaque interactive programs should provide the
program's accessible command/line mode or an authored semantic alternative, and
explain its supported input mode. Graphical child content also needs an authored
description or equivalent task path.

Automated semantic and PTY journeys establish structure, routing and state
behavior. They do not establish actual screen-reader speech, OS clipboard
permissions, or independent terminal-reader usability for an arbitrary child.
