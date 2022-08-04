# The following lines were added by compinstall
zstyle :compinstall filename '/home/karen/.zshrc'

autoload -Uz compinit promptinit
compinit
promptinit
# End of lines added by compinstall

alias ll='ls -al --color'
alias ..='cd ..'

PROMPT='%B%F{9}%T %n %~%f%b $ '
