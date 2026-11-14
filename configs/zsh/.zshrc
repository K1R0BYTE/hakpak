# If you come from bash you might have to change your $PATH.
# export PATH=$HOME/bin:/usr/local/bin:$PATH

# Path to your oh-my-zsh installation.
export ZSH="${HOME}/.oh-my-zsh"

# Set name of the theme to load --- if set to "random", it will
# load a random theme each time oh-my-zsh is loaded, in which case,
# to know which specific one was loaded, run: echo $RANDOM_THEME
# See https://github.com/ohmyzsh/ohmyzsh/wiki/Themes
ZSH_THEME="agnoster"
# With starship installed it draws the prompt instead (see the end of this
# file), in the hakpak theme picked with `hakpak-theme`.
command -v starship >/dev/null 2>&1 && ZSH_THEME=""
# -b: say which syntax to print, so dircolors doesn't need $SHELL, which a
# container or sandbox shell may not have.
[ -r ~/.dircolors ] && eval "$(dircolors -b ~/.dircolors)"

# A UTF-8 character set when the environment names none (a container or
# sandbox shell often has no locale at all). tmux reads these variables to
# decide whether your terminal speaks UTF-8, and without one it draws every
# prompt glyph as "_". An LC_ALL you set yourself is left alone.
if [[ -z "${LC_ALL:-}" && "${(L)LC_CTYPE:-${LANG:-}}" != *utf(-|)8* ]]; then
    export LC_CTYPE=C.UTF-8
fi

export CDPATH=${HOME}/pentest:/opt/

# Set list of themes to pick from when loading at random
# Setting this variable when ZSH_THEME=random will cause zsh to load
# a theme from this variable instead of looking in $ZSH/themes/
# If set to an empty array, this variable will have no effect.
# ZSH_THEME_RANDOM_CANDIDATES=( "robbyrussell" "agnoster" )

# Uncomment the following line to use case-sensitive completion.
# CASE_SENSITIVE="true"

# Uncomment the following line to use hyphen-insensitive completion.
# Case-sensitive completion must be off. _ and - will be interchangeable.
# HYPHEN_INSENSITIVE="true"

# Uncomment the following line to disable bi-weekly auto-update checks.
# DISABLE_AUTO_UPDATE="true"

# Uncomment the following line to automatically update without prompting.
# DISABLE_UPDATE_PROMPT="true"

# Uncomment the following line to change how often to auto-update (in days).
# export UPDATE_ZSH_DAYS=13

# Uncomment the following line if pasting URLs and other text is messed up.
# DISABLE_MAGIC_FUNCTIONS="true"

# Uncomment the following line to disable colors in ls.
# DISABLE_LS_COLORS="true"

# Uncomment the following line to disable auto-setting terminal title.
# DISABLE_AUTO_TITLE="true"

# Uncomment the following line to enable command auto-correction.
# ENABLE_CORRECTION="true"

# Uncomment the following line to display red dots whilst waiting for completion.
COMPLETION_WAITING_DOTS="true"

# Uncomment the following line if you want to disable marking untracked files
# under VCS as dirty. This makes repository status check for large repositories
# much, much faster.
# DISABLE_UNTRACKED_FILES_DIRTY="true"

# Uncomment the following line if you want to change the command execution time
# stamp shown in the history command output.
# You can set one of the optional three formats:
# "mm/dd/yyyy"|"dd.mm.yyyy"|"yyyy-mm-dd"
# or set a custom format using the strftime function format specifications,
# see 'man strftime' for details.
# HIST_STAMPS="mm/dd/yyyy"

# Would you like to use another custom folder than $ZSH/custom?
# ZSH_CUSTOM=/path/to/new-custom-folder

# Which plugins would you like to load?
# Standard plugins can be found in $ZSH/plugins/
# Custom plugins may be added to $ZSH_CUSTOM/plugins/
# Example format: plugins=(rails git textmate ruby lighthouse)
# Add wisely, as too many plugins slow down shell startup.
plugins=(git zsh-syntax-highlighting zsh-autosuggestions fzf)

# Suggestions in dim purple, to go with the prompt themes
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=#5b4a78'

source $ZSH/oh-my-zsh.sh

# Command highlighting and the fzf history search (Ctrl+R) in the same
# purple palette as the prompt themes
typeset -A ZSH_HIGHLIGHT_STYLES
ZSH_HIGHLIGHT_STYLES[command]='fg=#2de2e6'
ZSH_HIGHLIGHT_STYLES[builtin]='fg=#2de2e6'
ZSH_HIGHLIGHT_STYLES[alias]='fg=#2de2e6'
ZSH_HIGHLIGHT_STYLES[function]='fg=#2de2e6'
ZSH_HIGHLIGHT_STYLES[precommand]='fg=#2de2e6,underline'
ZSH_HIGHLIGHT_STYLES[unknown-token]='fg=#ff3864'
ZSH_HIGHLIGHT_STYLES[single-hyphen-option]='fg=#e0aaff'
ZSH_HIGHLIGHT_STYLES[double-hyphen-option]='fg=#e0aaff'
ZSH_HIGHLIGHT_STYLES[single-quoted-argument]='fg=#c77dff'
ZSH_HIGHLIGHT_STYLES[double-quoted-argument]='fg=#c77dff'
ZSH_HIGHLIGHT_STYLES[globbing]='fg=#f9f002'
ZSH_HIGHLIGHT_STYLES[comment]='fg=#8b7aa8'
# (added once: a shell started from this one inherits it)
[[ "${FZF_DEFAULT_OPTS:-}" == *"--color=fg:#d9cdf2"* ]] ||
    export FZF_DEFAULT_OPTS="--color=fg:#d9cdf2,hl:#ff2a9d,fg+:#ffffff,bg+:#3c096c,hl+:#ff2a9d,info:#8b7aa8,prompt:#c77dff,pointer:#ff2a9d,marker:#2de2e6,spinner:#c77dff,header:#7b2cbf,border:#7b2cbf ${FZF_DEFAULT_OPTS:-}"

# User configuration

# export MANPATH="/usr/local/man:$MANPATH"

# You may need to manually set your language environment
# export LANG=en_US.UTF-8

# Preferred editor for local and remote sessions
# if [[ -n $SSH_CONNECTION ]]; then
#   export EDITOR='vim'
# else
#   export EDITOR='mvim'
# fi

# Compilation flags
# export ARCHFLAGS="-arch x86_64"

# Set personal aliases, overriding those provided by oh-my-zsh libs,
# plugins, and themes. Aliases can be placed here, though oh-my-zsh
# users are encouraged to define aliases within the ZSH_CUSTOM folder.
# For a full list of active aliases, run `alias`.
#
# Example aliases
# alias zshconfig="mate ~/.zshrc"
# alias ohmyzsh="mate ~/.oh-my-zsh"

# Resolve HAKPAK_DIR from this file's real path (~/.zshrc links here),
# so the repo can be cloned anywhere.
HAKPAK_DIR="${${(%):-%x}:A:h:h:h}"
if [ ! -d "$HAKPAK_DIR/system" ]; then
    echo "Unable to find hakpak, exiting..."
    return
fi
# Source dotfiles
for DOTFILE in "$HAKPAK_DIR"/system/.*; do
    [ -f "$DOTFILE" ] && . "$DOTFILE"
done

# Prompt theme: starship with the hakpak theme in use (neon unless you chose
# another). `hakpak-theme` lists the themes and `hakpak-theme <name>`
# switches: this shell at once, other open shells when they next start.
hakpak-theme() {
    "$HAKPAK_DIR/tools/hakpak-theme" "$@" || return
    export STARSHIP_CONFIG="$("$HAKPAK_DIR/tools/hakpak-theme" --path starship)"
}
if command -v starship >/dev/null 2>&1; then
    export STARSHIP_CONFIG="$("$HAKPAK_DIR/tools/hakpak-theme" --path starship)"
    eval "$(starship init zsh)"
fi
