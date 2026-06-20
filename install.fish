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

function add-gtk-bookmark -a bookmarks_file folder name
    set -l resolved (path resolve $folder 2> /dev/null)
    test -n "$resolved" || set resolved $folder

    set -l bookmark "file://"(string escape --style=url $resolved)" $name"
    if ! contains -- $bookmark (cat $bookmarks_file 2> /dev/null)
        echo $bookmark >> "$bookmarks_file"
    end
end

function set-xfconf -a channel property type value
    if command -q xfconf-query
        xfconf-query -c $channel -p $property -n -t $type -s $value > /dev/null 2>&1
    end
end

function install-forked-shell -a data noconfirm
    set -l shell_repo https://github.com/ChrisBlackoutDev/shell-fork.git
    set -l shell_dir $data/caelestia-shell-fork

    log 'Installing Caelestia Shell from ChrisBlackoutDev/shell-fork...'
    sudo pacman -S --needed git base-devel cmake ninja $noconfirm

    if test -d $shell_dir/.git
        git -C $shell_dir pull --ff-only
    else
        rm -rf $shell_dir
        git clone $shell_repo $shell_dir
    end
    or exit 1

    cmake -S $shell_dir -B $shell_dir/build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/ -DDISTRIBUTOR='ChrisBlackoutDev/shell-fork'
    or exit 1
    cmake --build $shell_dir/build
    or exit 1
    sudo cmake --install $shell_dir/build
    or exit 1
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
echo '╭───────────────────────────────────────────────╮'
echo '│      ______           __          __  _         │'
echo '│     / ____/___ ____  / /__  _____/ /_(_)___ _   │'
echo '│    / /   / __ `/ _ \/ / _ \/ ___/ __/ / __ `/   │'
echo '│   / /___/ /_/ /  __/ /  __(__  ) /_/ / /_/ /    │'
echo '│   \____/\__,_/\___/_/\___/____/\__/_/\__,_/     │'
echo '│                                                 │'
echo '╰────────────────────────────────────────────╯'
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

install-forked-shell $data $noconfirm

# File explorer defaults
if command -q xdg-user-dirs-update
    xdg-user-dirs-update
end

set -l downloads_dir (xdg-user-dir DOWNLOAD 2> /dev/null)
test -n "$downloads_dir" || set downloads_dir $HOME/Downloads

set -l documents_dir (xdg-user-dir DOCUMENTS 2> /dev/null)
test -n "$documents_dir" || set documents_dir $HOME/Documents

mkdir -p $downloads_dir $documents_dir $config/gtk-3.0
set -l gtk_bookmarks "$config/gtk-3.0/bookmarks"
touch $gtk_bookmarks
add-gtk-bookmark $gtk_bookmarks $downloads_dir Downloads
add-gtk-bookmark $gtk_bookmarks $documents_dir Documents

mkdir -p $config/Thunar $config/xfce4/xfconf/xfce-perchannel-xml
if confirm-overwrite $config/Thunar/uca.xml
    log 'Installing Thunar custom actions...'
    cp thunar/uca.xml $config/Thunar/uca.xml
end

if confirm-overwrite $config/xfce4/xfconf/xfce-perchannel-xml/thunar.xml
    log 'Installing Thunar defaults...'
    cp thunar/thunar.xml $config/xfce4/xfconf/xfce-perchannel-xml/thunar.xml
end

if confirm-overwrite $config/xfce4/xfconf/xfce-perchannel-xml/thunar-volman.xml
    log 'Installing Thunar volume defaults...'
    cp thunar/thunar-volman.xml $config/xfce4/xfconf/xfce-perchannel-xml/thunar-volman.xml
end

set-xfconf thunar /last-side-pane string ThunarShortcutsPane
set-xfconf thunar /misc-volume-management bool true
set-xfconf thunar-volman /automount-drives/enabled bool false
set-xfconf thunar-volman /automount-media/enabled bool false

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
        spicetify apply
    end
end

# Install vscode
if set -q _flag_vscode
    test "$_flag_vscode" = 'code' && set -l prog 'code' || set -l prog 'codium'
    test "$_flag_vscode" = 'code' && set -l packages 'code' || set -l packages 'vscodium-bin' 'vscodium-bin-marketplace'
    test "$_flag_vscode" = 'code' && set -l folder 'Code' || set -l folder 'VSCodium'
    set -l folder $config/$folder/User
    mkdir -p $folder

    log "Installing vs$prog..."
    $aur_helper -S --needed $packages $noconfirm

    # Install configs
    if confirm-overwrite $folder/settings.json && confirm-overwrite $folder/keybindings.json && confirm-overwrite $config/$prog-flags.conf
        log "Installing vs$prog config..."
        ln -s (realpath vscode/settings.json) $folder/settings.json
        ln -s (realpath vscode/keybindings.json) $folder/keybindings.json
        ln -s (realpath vscode/flags.conf) $config/$prog-flags.conf

        # Install extension
        $prog --install-extension vscode/caelestia-vscode-integration/caelestia-vscode-integration-*.vsix
    end
end

# Install discord
if set -q _flag_discord
    log 'Installing discord...'
    $aur_helper -S --needed discord equicord-installer-bin $noconfirm

    # Install OpenAsar and Equicord
    sudo Equilotl -install -location /opt/discord
    sudo Equilotl -install-openasar -location /opt/discord

    # Remove installer
    $aur_helper -Rns equicord-installer-bin $noconfirm
end

# Install zen
if set -q _flag_zen
    log 'Installing zen...'
    $aur_helper -S --needed zen-browser-bin $noconfirm

    # Install userChrome css
    set -l zen_profiles
    if test -d $HOME/.zen
        set zen_profiles (find $HOME/.zen -mindepth 1 -maxdepth 1 -type d 2> /dev/null)
    end

    if test (count $zen_profiles) -eq 0
        log 'No Zen profiles found; skipping zen userChrome.'
    else
        for profile in $zen_profiles
            set -l chrome $profile/chrome
            mkdir -p $chrome
            if confirm-overwrite $chrome/userChrome.css
                log "Installing zen userChrome to $chrome..."
                ln -s (realpath zen/userChrome.css) $chrome/userChrome.css
            end
        end
    end

    # Install native app
    set -l hosts $HOME/.mozilla/native-messaging-hosts
    set -l lib $HOME/.local/lib/caelestia

    if confirm-overwrite $hosts/caelestiafox.json
        log 'Installing zen native app manifest...'
        mkdir -p $hosts
        cp zen/native_app/manifest.json $hosts/caelestiafox.json
        sed -i "s|{{ \$lib }}|$lib|g" $hosts/caelestiafox.json
    end

    if confirm-overwrite $lib/caelestiafox
        log 'Installing zen native app...'
        mkdir -p $lib
        ln -s (realpath zen/native_app/app.fish) $lib/caelestiafox
    end

    # Prompt user to install extension
    log 'Please install the CaelestiaFox extension from https://addons.mozilla.org/en-US/firefox/addon/caelestiafox if you have not already done so.'
end

# Generate scheme stuff if needed
if ! test -f $state/caelestia/scheme.json
    caelestia scheme set -n shadotheme
    sleep .5
    hyprctl reload
end

# Start the shell
caelestia shell -d > /dev/null

log 'Done!'
