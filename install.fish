#!/usr/bin/env fish

argparse -n 'install.fish' -X 0 \
    'h/help' \
    'noconfirm' \
    'spotify' \
    'vscode=?!contains -- "$_flag_value" codium code' \
    'discord' \
    'zen' \
    'aur-helper=!contains -- "$_flag_value" yay paru' \
    -- $argv
or exit

# Print help
if set -q _flag_h
    echo 'usage: ./install.fish [-h] [--noconfirm] [--spotify] [--vscode] [--discord] [--zen] [--aur-helper]'
    echo
    echo 'options:'
    echo '  -h, --help                  show this help message and exit'
    echo '  --noconfirm                 do not confirm package installation'
    echo '  --spotify                   install Spotify (Spicetify)'
    echo '  --vscode=[codium|code]      install VSCodium (or VSCode)'
    echo '  --discord                   install Discord (OpenAsar + Equicord)'
    echo '  --zen                       install Zen browser'
    echo '  --aur-helper=[yay|paru]     the AUR helper to use'

    exit
end


# Helper funcs
function _out -a colour text
    set_color $colour
    # Pass arguments other than text to echo
    echo $argv[3..] -- ":: $text"
    set_color normal
end

function log -a text
    _out cyan $text $argv[2..]
end

function input -a text
    _out blue $text $argv[2..]
end

function sh-read
    sh -c 'read a && echo -n "$a"' || exit 1
end

function confirm-overwrite -a path
    if test -e $path -o -L $path
        # No prompt if noconfirm
        if set -q noconfirm
            input "$path already exists. Overwrite? [Y/n]"
            log 'Removing...'
            rm -rf $path
        else
            # Prompt user
            input "$path already exists. Overwrite? [Y/n] " -n
            set -l confirm (sh-read)

            if test "$confirm" = 'n' -o "$confirm" = 'N'
                log 'Skipping...'
                return 1
            else
                log 'Removing...'
                rm -rf $path
            end
        end
    end

    return 0
end


# Variables
set -q _flag_noconfirm && set noconfirm '--noconfirm'
set -q _flag_aur_helper && set -l aur_helper $_flag_aur_helper || set -l aur_helper paru
set -q XDG_CONFIG_HOME && set -l config $XDG_CONFIG_HOME || set -l config $HOME/.config
set -q XDG_DATA_HOME && set -l data $XDG_DATA_HOME || set -l data $HOME/.local/share
set -q XDG_STATE_HOME && set -l state $XDG_STATE_HOME || set -l state $HOME/.local/state
set -l install_dir (path dirname (path resolve (status filename)))

# Startup prompt
set_color magenta
echo '╭─────────────────────────────────────────────────╮'
echo '│      ______           __          __  _         │'
echo '│     / ____/___ ____  / /__  _____/ /_(_)___ _   │'
echo '│    / /   / __ `/ _ \/ / _ \/ ___/ __/ / __ `/   │'
echo '│   / /___/ /_/ /  __/ /  __(__  ) /_/ / /_/ /    │'
echo '│   \____/\__,_/\___/_/\___/____/\__/_/\__,_/     │'
echo '│                                                 │'
echo '╰─────────────────────────────────────────────────╯'
set_color normal
log 'Welcome to the Caelestia dotfiles installer!'
log 'Before continuing, please ensure you have made a backup of your config directory.'

# Prompt for backup
if ! set -q _flag_noconfirm
    log '[1] Two steps ahead of you!  [2] Make one for me please!'
    input '=> ' -n
    set -l choice (sh-read)

    if contains -- "$choice" 1 2
        if test $choice = 2
            log "Backing up $config..."

            if test -e $config.bak -o -L $config.bak
                input 'Backup already exists. Overwrite? [Y/n] ' -n
                set -l overwrite (sh-read)

                if test "$overwrite" = 'n' -o "$overwrite" = 'N'
                    log 'Skipping...'
                else
                    rm -rf $config.bak
                    cp -r $config $config.bak
                end
            else
                cp -r $config $config.bak
            end
        end
    else
        log 'No choice selected. Exiting...'
        exit 1
    end
end


# Install AUR helper if not already installed
if ! pacman -Q $aur_helper &> /dev/null
    log "$aur_helper not installed. Installing..."

    # Install
    sudo pacman -S --needed git base-devel $noconfirm
    set -l build_dir (mktemp -d --tmpdir "caelestia-$aur_helper.XXXXXXXXXX")
    or exit 1

    git clone --depth=1 https://aur.archlinux.org/$aur_helper.git $build_dir
    or begin
        rm -rf -- $build_dir
        exit 1
    end

    cd $build_dir
    or begin
        rm -rf -- $build_dir
        exit 1
    end

    makepkg -si $noconfirm
    set -l makepkg_status $status
    cd $install_dir
    rm -rf -- $build_dir
    test $makepkg_status -eq 0 || exit $makepkg_status

    # Setup
    if test $aur_helper = yay
        $aur_helper -Y --gendb
        $aur_helper -Y --devel --save
    else
        $aur_helper --gendb
    end
end

# Cd into dir
cd $install_dir || exit 1
mkdir -p $config/caelestia
touch $config/caelestia/hypr-vars.conf $config/caelestia/hypr-user.conf

# Install metapackage for deps
log 'Installing metapackage...'

if test $aur_helper = yay
    $aur_helper -Bi . $noconfirm
else
    $aur_helper -Ui $noconfirm
end
fish -c 'rm -f caelestia-meta-*.pkg.tar.zst' 2> /dev/null

# Install hypr* configs
if confirm-overwrite $config/hypr
    log 'Installing hypr* configs...'
    ln -s (realpath hypr) $config/hypr
    chmod u+x $config/hypr/scripts/wsaction.fish
    hyprctl reload
end

# Starship
if confirm-overwrite $config/starship.toml
    log 'Installing starship config...'
    ln -s (realpath starship.toml) $config/starship.toml
end

# Foot
if confirm-overwrite $config/foot
    log 'Installing foot config...'
    ln -s (realpath foot) $config/foot
end

# Fish
if confirm-overwrite $config/fish
    log 'Installing fish config...'
    ln -s (realpath fish) $config/fish
end

# Fastfetch
if confirm-overwrite $config/fastfetch
    log 'Installing fastfetch config...'
    ln -s (realpath fastfetch) $config/fastfetch
end

# Uwsm
if confirm-overwrite $config/uwsm
    log 'Installing uwsm config...'
    ln -s (realpath uwsm) $config/uwsm
end

# Btop
if confirm-overwrite $config/btop
    log 'Installing btop config...'
    ln -s (realpath btop) $config/btop
end

# Caelestia shell personal config
if confirm-overwrite $config/caelestia/shell.json
    log 'Installing Caelestia shell config...'
    ln -s (realpath caelestia/shell.json) $config/caelestia/shell.json
end

# Application launchers
mkdir -p $data/applications
for desktop in cursor.desktop steam.desktop OrcaSlicer.desktop
    if confirm-overwrite $data/applications/$desktop
        log "Installing $desktop desktop entry..."
        ln -s (realpath applications/$desktop) $data/applications/$desktop
    end
end

# Install spicetify
if set -q _flag_spotify
    log 'Installing spotify (spicetify)...'

    set -l has_spicetify (pacman -Q spicetify-cli 2> /dev/null)
    $aur_helper -S --needed spotify spicetify-cli spicetify-marketplace-bin $noconfirm

    # Set permissions and init if new install
    if test -z "$has_spicetify"
        sudo chmod a+wr /opt/spotify
        sudo chmod a+wr /opt/spotify/Apps -R
        spicetify backup apply
    end

    # Install configs
    if confirm-overwrite $config/spicetify
        log 'Installing spicetify config...'
        ln -s (realpath spicetify) $config/spicetify

        # Set spicetify configs
        spicetify config current_theme caelestia color_scheme caelestia custom_apps marketplace 2> /dev/null
        spicetify config inject_css 1 replace_colors 1 overwrite_assets 1 inject_theme_js 1
        spicetify apply
    end
end

# Discord
if set -q _flag_discord
    log 'Installing Discord (Equicord + OpenAsar)...'

    $aur_helper -S --needed vesktop-bin $noconfirm

    # Equicord Vesktop settings
    if confirm-overwrite $config/vesktop/settings
        log 'Installing Equicord Vesktop settings...'
        ln -s (realpath vesktop/settings) $config/vesktop/settings
    end

    # Discord theme
    mkdir -p $config/vesktop/themes
    if confirm-overwrite $config/vesktop/themes/caelestia.theme.css
        log 'Installing Discord theme...'
        ln -s (realpath vesktop/caelestia.theme.css) $config/vesktop/themes/caelestia.theme.css
    end
end

# VSCodium/Code
if set -q _flag_vscode
    switch $_flag_vscode
        case codium
            set -l packages vscodium-bin vscodium-marketplace
            set -l prog VSCodium
            set -l folder $config/VSCodium/User
        case code
            set -l packages visual-studio-code-bin
            set -l prog Code
            set -l folder $config/Code/User
    end

    log "Installing $prog..."

    $aur_helper -S --needed $packages $noconfirm

    # Configs
    mkdir -p $folder
    if confirm-overwrite $folder/settings.json
        log "Installing $prog settings..."
        ln -s (realpath vscode/settings.json) $folder/settings.json
        ln -s (realpath vscode/keybindings.json) $folder/keybindings.json
        ln -s (realpath vscode/flags.conf) $config/$prog-flags.conf
    end

    # Extension
    $argv = $config/$prog-flags.conf
    set -l code_cmd (string lower $prog)
    if ! $code_cmd --list-extensions | grep -q 'caelestia-vscode-integration'
        log "Installing $prog extension..."
        $code_cmd --install-extension vscode/caelestia-vscode-integration/caelestia-vscode-integration-*.vsix
    end
end

# Zen
if set -q _flag_zen
    log 'Installing Zen...'

    $aur_helper -S --needed zen-browser-bin $noconfirm

    # Native app
    set -l lib $HOME/.mozilla/native-messaging-hosts
    mkdir -p $lib
    if confirm-overwrite $lib/caelestiafox
        log 'Installing native app...'
        ln -s (realpath zen/native_app/app.fish) $lib/caelestiafox
        chmod u+x $lib/caelestiafox
    end

    # Native app manifest
    if confirm-overwrite $lib/caelestiafox.json
        log 'Installing native app manifest...'
        ln -s (realpath zen/native_app/manifest.json) $lib/caelestiafox.json
    end

    # Extension
    set -l tmp (mktemp -d)
    cp -r zen/caelestia-firefox-integration $tmp/caelestia-firefox-integration
    cd $tmp/caelestia-firefox-integration
    npm install
    npm run build
    cd $install_dir

    log 'Installing Zen extension...'
    for profile in $HOME/.zen/*
        set -l profile_name (path basename $profile)
        set -l extensions $profile/extensions
        set -l chrome $profile/chrome

        mkdir -p $extensions $chrome
        cp $tmp/caelestia-firefox-integration/caelestia-firefox-integration.xpi $extensions/caelestia-firefox-integration@caelestia.local.xpi

        # User chrome
        if confirm-overwrite $chrome/userChrome.css
            log "Installing user chrome for profile $profile_name..."
            ln -s (realpath zen/userChrome.css) $chrome/userChrome.css
        end
    end

    rm -rf $tmp
end

log 'Done!'
