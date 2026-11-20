# Load wallpaper-coherent color palette (Nord Theme)
if test -f (status dirname)/conf.d/colors.fish
    source (status dirname)/conf.d/colors.fish
end

if status is-interactive
    # Commands to run in interactive sessions can go here
end
alias c="clear"
alias cl="clear && ls"

function cd ()
    builtin cd "$argv" && ls;
end

function fish_greeting
end
