if status is-interactive
    set -g fish_greeting
end

starship init fish | source
fastfetch
alias i "paru -S"
alias s "paru -Ss"
alias r "paru -R"
alias rns "paru -Rns"
alias update paru


# Added by Antigravity CLI installer
set -gx PATH "/home/lunar/.local/bin" $PATH
