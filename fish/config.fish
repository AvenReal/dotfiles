# Load wallpaper-coherent color palette (Nord Theme)
if test -f (status dirname)/conf.d/colors.fish
    source (status dirname)/conf.d/colors.fish
end

if status is-interactive
    # Commands to run in interactive sessions can go here
end
alias c="clear"
alias cl="clear && ls"
alias l="ls"

function ls
    if test (count $argv) -eq 1 -a -f "$argv[1]"
        command cat $argv
    else
        command ls $argv
    end
end

function cat
    if test (count $argv) -eq 1 -a -d "$argv[1]"
        command ls $argv
    else
        command cat $argv
    end
end

function cd
    builtin cd $argv; and ls
end

function fish_greeting
end
