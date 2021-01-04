#!/bin/bash

# found here - https://gist.github.com/seanbutnotheard/3692939

# I (alex) have hacked the below randomly.. best to use the above

# ffcapture, a hacky script to stream/capture your desktop or a window 
# REQUIRES ffmpeg, xwininfo and bc to be installed!
#
# Accepts a maximum of two parameters, from the following list:
# stream, window, composite, svideo.
#
# RUN THIS SCRIPT IN A CONSOLE because it uses prompts.
# I recommend invoking in a manner such as this (which I use in Openbox):
# urxvt -geometry 60x5+0+0 -e $HOME/bin/ffcapture stream window
#
# if "stream" is present, it will stream to your twitch.tv account.
# you can either replace the "$(cat ... /streamkey )" business below with your stream key, or put your key
# in a file called "streamkey" in the same directory as this script.
# if "stream" is absent, the default is to record the video to an .mkv container. You can tweak the settings below.
#
# if "window" is present, it will only stream/record the contents of a window (you'll be prompted to select the window).
# if "composite" is present, it will stream/record the v4l2 source specified by the COMPOSITE_SOURCE variable below.
# if "svideo" is present, it will stream/record the v4l2 source specified by the SVIDEO_SOURCE variable below.
#
# the default if invoked with no parameters is to record (not stream) the full desktop.
# RUN THIS SCRIPT IN A CONSOLE because it uses prompts.
# press 'q' in the console window to end capture/stream.


#--- Edit these default values.
OUTDIR=.
TTV_STREAMKEY=$(cat "$(dirname "${BASH_SOURCE[0]}")"/streamkey )
COMPOSITE_SOURCE="-channel 0 -standard NTSC -i /dev/video1"
SVIDEO_SOURCE="-channel 1 -standard NTSC -i /dev/video1"

#--- Check for necessary utils
type xwininfo &> /dev/null || { echo "xwininfo not found! please install it."; exit 1; }
type ffmpeg &> /dev/null || { echo "ffmpeg not found! please install it."; exit 1; }
type bc &> /dev/null || { echo "bc not found! please install it."; exit 1; }

#--- Ahem... "parse" command line parameters
[[ "$1" = "stream" || "$2" = "stream" ]] && STREAMING=true
[[ "$1" = "window" || "$2" = "window" ]] && WINDOWED=true
[[ "$1" = "composite" || "$2" = "composite" ]] && COMPOSITE=true
[[ "$1" = "svideo" || "$2" = "svideo" ]] && SVIDEO=true

#--- Detect fullscreen size
FULLWIDTH=$(xrandr --current | grep '*' | uniq | awk '{print $1}' |  cut -d 'x' -f1)
FULLHEIGHT=$(xrandr --current | grep '*' | uniq | awk '{print $1}' |  cut -d 'x' -f2)
FULLRES="${FULLWIDTH}x$FULLHEIGHT"



#--- Change video settings below if you like

if [ "$STREAMING" = "true" ]; then

  #--- Video settings for streaming
  OUTHEIGHT=780
  FPS=30
  VBITRATE=1500k
  ABITRATE=96k
  
  ACODEC="libmp3lame -b:a $ABITRATE -ar 44100"
  VCODEC="libx264 -preset ultrafast -tune animation -b:v $VBITRATE"
  
  #--- File output settings  
  FILEOUT="-f flv rtmp://live.justin.tv/app/$TTV_STREAMKEY"
  
else

  #--- Timestamp format
  TIMESTAMP=$(date +%F-%R)
  
  #--- Video settings for recording
  OUTHEIGHT=$FULLHEIGHT
  FPS=60
  VBITRATE=1000k
  ABITRATE=96k
  
  # ACODEC="libmp3lame -b:a $ABITRATE -ar 44100"
  ACODEC="flac -channel_layout octagonal -ar 44100"
  VCODEC="libx264 -preset ultrafast -tune animation -b:v $VBITRATE"
  

  #--- File output settings
  mkdir -p $OUTDIR
  FILEOUT="-y $OUTDIR/capture.mkv"
  
fi



#--- Calculate in/out resolutions, grab source window size if necessary

if [ "$WINDOWED" = "true" ]; then

  echo Select the target window.
  unset x y w h
  eval $(xwininfo |
    sed -n -e "s/^ \+Absolute upper-left X: \+\([0-9]\+\).*/x=\1/p" \
        -e "s/^ \+Absolute upper-left Y: \+\([0-9]\+\).*/y=\1/p" \
        -e "s/^ \+Width: \+\([0-9]\+\).*/w=\1/p" \
        -e "s/^ \+Height: \+\([0-9]\+\).*/h=\1/p" )
    
  INRES=$(echo "-s ${w}x$h -r $FPS -i :0.0+$x,$y")
  if [ "$h" -lt "$OUTHEIGHT" ]; then 
    OUTHEIGHT=$h
  fi
  OUTHEIGHT=$(echo "scale=0;$OUTHEIGHT/2*2" | bc)
  OUTWIDTH=$(echo "scale=1;$OUTHEIGHT/$h*$w" | bc)
  OUTWIDTH=$(echo "scale=0;$OUTWIDTH/2*2" | bc)
  
  VIDEOSRC="-f x11grab"
  OUTRES="-s ${OUTWIDTH}x${OUTHEIGHT}"
  
elif [ "$COMPOSITE" = "true" ]; then

  VIDEOSRC="-f video4linux2 $COMPOSITE_SOURCE"
  OUTRES=

elif [ "$SVIDEO" = "true" ]; then

  VIDEOSRC="-f video4linux2 $SVIDEO_SOURCE"
  OUTRES=
  
else #No Parameter = fullscreen capture.

  INRES=$(echo "-s $FULLRES -r $FPS -i :0.0")
  OUTHEIGHT=$(echo "scale=0;$OUTHEIGHT/2*2" | bc)
  OUTWIDTH=$(echo "scale=1;$OUTHEIGHT/${FULLHEIGHT}*${FULLWIDTH}" | bc)
  OUTWIDTH=$(echo "scale=0;$OUTWIDTH/2*2" | bc)
  
  VIDEOSRC="-f x11grab"
  OUTRES="-s ${OUTWIDTH}x${OUTHEIGHT}"
  
fi



#--- Figure out a reasonable audio source
# IMPORTANT: I recommend running Pulse or Jack as your audio
# server. Personally I use Jack and have Qjackctl's patchbay
# set-up to automatically connect ffmpeg to ALSA-Jack plugin clients.
# If you're running Pulse (e.g. Ubuntu), you might need to play around
# with Pavucontrol to capture your outgoing audio.
# If you're only using ALSA, it will use the default capture
# interface, meaning your sound card's inputs, not the sound
# being played back by apps.

#AUDIOSRC="-f alsa -ac 2 -i default"
#ps ax | grep pulseaudio | grep -v grep > /dev/null
#if [ "$?" = "0" ]; then
#  AUDIOSRC="-f alsa -ac 2 -i pulse"
#fi

ps ax | grep jackd | grep -v grep > /dev/null
if [ "$?" = "0" ]; then
  #AUDIOSRC="-f alsa -ac 2 -i jackplug"
  AUDIOSRC="-async 1 -f jack -ac 8 -i ffmpeg"
fi





#NOW THE FUN BEGINS ==========================================================================
ffmpeg \
 $VIDEOSRC $INRES \
 $AUDIOSRC \
 -acodec $ACODEC -threads auto \
 -vcodec $VCODEC $OUTRES -threads auto \
 $FILEOUT
 
#exit 0

#--- rename the resulting capture file if applicable

if [ "$STREAMING" != "true" ]; then
  echo "Please type a name for the recording."
  read RENAMETO
  [[ "$RENAMETO" = "" ]] && RENAMETO=capture
  mv "$OUTDIR/capture.mkv" "$OUTDIR/$RENAMETO-$TIMESTAMP.mkv"
fi
