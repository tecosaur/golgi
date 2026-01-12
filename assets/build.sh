#!/usr/bin/env bash

set -euo pipefail

declare -A svgs_formatted=()

svgfmt () {
    local infile="$1"
    [[ -n "${svgs_formatted["$infile"]+x}" ]] && return 0
    sed -i "s/$PRIMARY_STANDIN/$PRIMARY_COLOR/g" "$infile"
    sed -i "s/$SECONDARY_STANDIN/$SECONDARY_COLOR/g" "$infile"
    svgo --input="$infile" --output="$infile" --multipass
    svgs_formatted["$infile"]=1
}

pngopt () {
    local infile="$1"
    # Use `pngquant` then `oxipng`,
    # based on <https://github.com/kornelski/pngquant/issues/386>.
    pngquant --force --ext .png --skip-if-larger --speed 1 --strip "$infile" || {
        [ "$?" -eq 98 ] || return $?
    }
    oxipng -o max --strip safe --alpha --fast --zopfli "$infile"
}

svg2png () {
    local infile="$1"
    shift || return 2
    local outfile
    if [[ $# -gt 0 && "$1" != -* ]]; then
        outfile="$1"
        shift
    else
        # default: replace .svg with .png (or just append .png)
        outfile="${infile%.svg}.png"
    fi
    svgfmt "$infile"
    rsvg-convert "$@" -f png -o "$outfile" "$infile"
    pngopt "$outfile"
}

favmake () {
    local replace=0
    local infile=""
    local outfile=""
    while (($#)); do
        case "$1" in
            --replace) replace=1; shift ;;
            --) shift ;;
            --*) 
                echo "favmake: unrecognized option '$1'" >&2
                return 2
                ;;
            *)
                if [ -z "$infile" ]; then
                    infile="$1"
                elif [ -z "$outfile" ]; then
                    outfile="$1"
                else
                    echo "favmake: too many arguments" >&2
                    return 2
                fi
                shift
                ;;
        esac
    done
    if [ -d "$infile" ]; then
        infile="$infile/favicon.svg"
    fi
    if [ -z "$outfile" ]; then
        outfile="$(dirname "$infile")/favicon.ico"
    fi
    svg2png "$infile" "$infile-f16.png" -w 16 -h 16
    svg2png "$infile" "$infile-f32.png" -w 32 -h 32
    svg2png "$infile" "$infile-f48.png" -w 48 -h 48
    echo "
from PIL import Image
images = [Image.open('$infile-f16.png'),
          Image.open('$infile-f32.png'),
          Image.open('$infile-f48.png')]
images[-1].save('$outfile', sizes=[img.size for img in images], append_images=images[:-1])
" | python3
    rm -- "$infile-f16.png" "$infile-f32.png" "$infile-f48.png"
    if (( replace )); then
        rm -- "$infile"
    fi
}

#

# Authelia
favmake authelia --replace
# Beszel
svgfmt beszel/icon.svg
# Forgejo
favmake forgejo
svg2png forgejo/favicon.svg -h 180
svg2png forgejo/avatar-default.svg -h 200
# Headscale
favmake headscale --replace
# Jellyfin
favmake jellyfin/jellyfin.svg jellyfin/jellyfin.ico
svg2png jellyfin/banner-light.svg -h 256
svg2png jellyfin/banner-dark.svg -h 256
svg2png jellyfin/jellyfin.svg jellyfin/icon-transparent.png -h 512
rm jellyfin/*.svg
# Lyrion
svg2png lyrion/icon.svg lyrion/icon-80.png -h 80
svg2png lyrion/icon.svg lyrion/icon-192.png -h 192
svg2png lyrion/icon.svg lyrion/icon.png -h 512
svg2png lyrion/icon.svg lyrion/icon-1024.png -h 1024
svg2png lyrion/icon-maskable.svg lyrion/icon-maskable-192.png -h 192
svg2png lyrion/icon-maskable.svg lyrion/icon-maskable-1024.png -h 1024
rm lyrion/icon-maskable.svg
# Mealie
favmake mealie
svg2png mealie/favicon.svg mealie/icon-x64.png -h 64
svg2png mealie/favicon.svg mealie/android-chrome-192x192.png -h 192
svg2png mealie/favicon.svg mealie/android-chrome-512x512.png -h 512
svg2png mealie/apple-touch-icon.svg -h 180
rm mealie/favicon.svg mealie/apple-touch-icon.svg
svg2png mealie/icon-maskable.svg mealie/android-chrome-maskable-192x192.png -h 192
svg2png mealie/icon-maskable.svg mealie/android-chrome-maskable-512x512.png -h 512
rm mealie/icon-maskable.svg
svg2png mealie/calendar-multiselect.svg mealie/mdiFormatListChecks-96x96.png -h 96
svg2png mealie/calendar-multiselect.svg mealie/mdiFormatListChecks-192x192.png -h 192
rm mealie/calendar-multiselect.svg
svg2png mealie/format-list-checks.svg mealie/mdiFormatListChecks-96x96-alt.png -h 96
svg2png mealie/format-list-checks.svg mealie/mdiFormatListChecks-192x192-alt.png -h 192
rm mealie/format-list-checks.svg
# Memos
svg2png memos/logo.svg -h 115
cwebp -preset icon -near_lossless 60 -m 6 -metadata none memos/logo.png -o memos/logo.webp
rm memos/logo.png
ln -sr memos/logo.webp memos/full-logo.webp
# Microbin
favmake microbin
svg2png microbin/logo.svg -h 115
# Paperless
favmake paperless --replace
# SFTPGo
svg2png sftpgo/favicon.svg -h 64
rm sftpgo/favicon.svg
svg2png sftpgo/logo.svg -h 256
rm sftpgo/logo.svg
svg2png sftpgo/openid-logo.svg -h 64
rm sftpgo/openid-logo.svg
# Site
favmake site
svg2png site/logo.svg -h 400
svg2png site/logo-bw.svg -h 400
# Storyteller
favmake storyteller
svg2png storyteller/logo.svg -h 128
rm storyteller/favicon.svg
# Vikunja
favmake vikunja/public
mkdir -p vikunja/public/images/icons
svg2png vikunja/public/icon-maskable.svg vikunja/public/images/icons/android-chrome-192x192.png -h 192
svg2png vikunja/public/icon-maskable.svg vikunja/public/images/icons/android-chrome-512x512.png -h 512
svg2png vikunja/public/icon-maskable.svg vikunja/public/images/icons/apple-touch-icon-180x180.png -h 180
ln -sr vikunja/public/images/icons/apple-touch-icon-180x180.png vikunja/public/images/icons/icon-maskable.png
svgfmt vikunja/frontend/llama.svg
svgfmt vikunja/frontend/llama-cool.svg
svgfmt vikunja/frontend/logo.svg
svgfmt vikunja/frontend/logo-full.svg
# Warracker
favmake warracker
