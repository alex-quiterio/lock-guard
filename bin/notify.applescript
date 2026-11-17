-- Shows a Lock Guard report as a macOS notification, with a sound.
-- Usage: osascript notify.applescript <title> <message>
on run argv
	set theTitle to item 1 of argv
	set theMessage to item 2 of argv
	display notification theMessage with title theTitle sound name "Basso"
end run
