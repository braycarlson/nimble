# nimble

An input automation toolkit for Windows and Linux. The toolkit covers keyboard and mouse hooks, hotkeys, chords, key sequences, macros, timers, clipboard access, and input synthesis, and a middleware chain can remap, block, or log events before they reach a binding. The Linux backend works below the display server, so it behaves the same on Wayland and X11, and the `nimbled` daemon lets an application bind keys without access to the input devices. A two-second hold of both Shift keys releases a grab, so a stuck application cannot lock a person out of the machine.
