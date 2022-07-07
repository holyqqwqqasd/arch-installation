# The following lines were added by compinstall
zstyle :compinstall filename '/home/karen/.zshrc'

autoload -Uz compinit promptinit
compinit
promptinit
# End of lines added by compinstall

alias ll='ls -al --color'
alias ..='cd ..'

PROMPT='%B%F{9}%T %n %~%f%b $ '

if [ -f /usr/bin/grc ]; then
    alias ping="grc --colour=auto ping"
    alias free="grc --colour=auto free"
    alias df="grc --colour=auto df"
fi
