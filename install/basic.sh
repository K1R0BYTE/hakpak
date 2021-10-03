#!/usr/bin/env bash

RED="\033[1;31m"
NOCOLOR="\033[0m"

colorecho() {
	echo -e "[*] ${RED}${1}${NOCOLOR}"
}

colorecho 'Starting Installing Basic Soft'

sudo apt -y install git vim wget curl peco firefox-esr torbrowser-launcher zip unzip p7zip-full guake 

colorecho 'Finished Installing Basic Soft'

colorecho 'Starting Installing ZSH'

ZSH="${HOME}/.oh-my-zsh"
ZSH_CUSTOM="$ZSH/custom"

sudo apt -y install zsh && sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM}/plugins/zsh-syntax-highlighting
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM}/plugins/zsh-autosuggestions
git clone https://github.com/jimeh/zsh-peco-history.git ${ZSH_CUSTOM}/plugins/zsh-peco-history

mv ${HOME}/.zshrc ${HOME}/.zshrc.bak
ln -sv ${HOME}/.hakpak/configs/zsh/.zshrc ${HOME}/.zshrc

mv ${HOME}/.zsh_history ${HOME}/.zsh_history.bak
ln -sv ${HOME}/.hakpak/configs/zsh/.zsh_history ${HOME}/.zsh_history

mv ${HOME}/.dircolors ${HOME}/.dircolors.bak
ln -sv ${HOME}/.hakpak/configs/.dircolors ${HOME}/.dircolors

colorecho 'Finished Installing ZSH'

colorecho 'Starting Installing Tmux Soft'

sudo apt -y install tmux xclip
rm -rf ${HOME}/.tmux*
git clone "https://github.com/tmux-plugins/tpm" ${HOME}/.tmux/plugins/tpm
ln -sv ${HOME}/.hakpak/configs/tmux/.tmux.conf ${HOME}/.tmux.conf
tmux source-file ${HOME}/.tmux.conf

colorecho 'Finished Installing Tmux Soft'


