#!/bin/bash

#-connect to LinuxSampler, create a new LS channel
# -> JACK client with one MIDI input (sink) and two audio outputs (sources) (L,R)
#-load provided .gig file to this channel
#//tb/1706

#these variables can be set to match personal preferences
#(hardcoded in this script):
#default audio sinks to connect LS audio output
JACK_CONNECT_L="system:playback_1"
JACK_CONNECT_R="system:playback_2"
#default midi source to connect to LS midi input
JACK_CONNECT_MIDI="a2j:MidiSport 2x2 [20] (capture): MidiSport 2x2 MIDI 1"
#see help output (no args) for more

checkAvail()
{
	which "$1" >/dev/null 2>&1
	ret=$?
	if [ $ret -ne 0 ]
	then
		echo "/!\\ tool \"$1\" not found. please install" >&2
		exit 1
	fi
}

for tool in {gigdump,netcat,dos2unix,unix2dos,jack_lsp,jack_disconnect,xterm,linuxsampler}; \
	do checkAvail "$tool"; done

if [ $# -lt 1 ]
then
	echo "need argument(s): <.gig file> (<hostname> (<port>) (<reset LS) (<excl. MIDI>)))" >&2
	echo "hostname: localhost (default)" >&2
	echo "port: 8888 (LinuxSampler default)" >&2
	exit 1
fi

GIGFILE="$1"
JACK_CLIENT_NAME="LS $GIGFILE `date +%s`"

LS_HOST=localhost
#standard tcp port of LinuxSampler
LS_PORT=8888

if [ $# -gt 1 ]
then
	LS_HOST="$2"
fi

if [ $# -gt 2 ]
then
	LS_PORT="$3"
fi

#if set to 1: will reset LS (all channels and connections gone!)
#this is handy to start over
DO_RESET=0

if [ $# -gt 3 ]
then
	if [ x"$4" = "x1" ]
	then
		DO_RESET=1
	fi
fi

#if set to 1: will disconnect all other connections from the $JACK_CONNECT_MIDI port
#only the newly created instance will get midi (connected) from $JACK_CONNECT_MIDI
JACK_CONNECT_MIDI_EXCLUSIVE=0

if [ $# -gt 4 ]
then
	if [ x"$5" = "x1" ]
	then
		JACK_CONNECT_MIDI_EXCLUSIVE=1
	fi
fi

#default audio sinks to connect LS audio output
JACK_CONNECT_L="system:playback_1"
JACK_CONNECT_R="system:playback_2"

#default midi source to connect to LS midi input
JACK_CONNECT_MIDI="a2j:MidiSport 2x2 [20] (capture): MidiSport 2x2 MIDI 1"

#test if the TCP port can possibly be used to contact LS
netcat -z "$LS_HOST" "$LS_PORT"
ret=$?
if [ $ret -ne 0 ]
then
	echo "no LinuxSampler found on $LS_HOST:$LS_PORT" >&2
#	exit 1
#	experimental: autostarting LinuxSampler in xterm
	echo "=== AUTOSTARTING LinuxSampler ========="
	xterm -e "linuxsampler --lscp-port $LS_PORT" &
	sleep 1
fi

#regular file
if [ ! -f "$GIGFILE" ]
then
	echo "file '"$1"' not found or not a regular file" >&2
	exit 1
fi
#can read
if [ ! -r "$GIGFILE" ]
then
	echo "file '"$1"' not found or cannot read" >&2
	exit 1
fi
#gigfile ok
gigdump "$GIGFILE" >/dev/null 2>&1
ret=$?
if [ $ret -ne 0 ]
then
	echo "file '"$1"' cannot be read or is not a valid .gig file" >&2
	exit 1
fi

#query something from LS to be sure it's LS
#this also checks if LS can be used with JACK
echo "GET AUDIO_OUTPUT_DRIVER_PARAMETER INFO JACK SAMPLERATE" | netcat "$LS_HOST" "$LS_PORT" | dos2unix \
	| grep "^DEFAULT: "
ret=$?
if [ $ret -ne 0 ]
then
	echo "cannot connect to LinuxSampler or no JACK support found" >&2
	exit 1
fi

if [ $DO_RESET -eq 1 ]
then
	echo "=== RESETTING LINUX SAMPLER ==========="
	echo "RESET" | netcat "$LS_HOST" "$LS_PORT"
fi

##could break this out to jack_connect_exclusive
##jack_disconnect_all

if [ $JACK_CONNECT_MIDI_EXCLUSIVE -eq 1 ]
then
	echo "=== DISCONNECTING OTHER MIDI =========="
	#first line is requested port
	jack_lsp -c "$JACK_CONNECT_MIDI" \
		| tail -n +2 \
		| while read line;
		do
			echo disconnecting "\"$JACK_CONNECT_MIDI\" \"$line\"";
			jack_disconnect "${JACK_CONNECT_MIDI}" "${line}";
			sleep 0.05
		done
fi

echo "=== CONNECTING TO LINUX SAMPLER ======="
#answer from linuxsampler is cr lf terminated -> dos2unix
#the count can be used as index after a new item was added
MIDI_INDEX=`echo "GET MIDI_INPUT_DEVICES" | netcat "$LS_HOST" "$LS_PORT" | dos2unix`
AUDIO_INDEX=`echo "GET AUDIO_OUTPUT_DEVICES" | netcat "$LS_HOST" "$LS_PORT" | dos2unix`
CHANNEL_INDEX=`echo "GET CHANNELS" | netcat "$LS_HOST" "$LS_PORT" | dos2unix`

#echo "midi_index ${MIDI_INDEX}"
#echo "audio_index $AUDIO_INDEX"
#echo "channel_index $CHANNEL_INDEX"

echo "=== CREATING CHANNEL @INDEX [$CHANNEL_INDEX] ======="

#zero-based, i.e. first is at index 0
#LS comments can't contain -, '
#filter lines starting with # before sending to LS
#suppress return "OK* lines

#cat - | grep -v "^#" << __EOF__
(cat - | grep -v "^#" | unix2dos | (netcat "$LS_HOST" "$LS_PORT" | grep -v "^OK" | dos2unix)) << __EOF__
#RESET

# Audio JACK Device 0 (n)

CREATE AUDIO_OUTPUT_DEVICE JACK ACTIVE='true' CHANNELS='2' NAME='${JACK_CLIENT_NAME}' SAMPLERATE='44100'

# Left #INTERNAL 0 (n)
# SET AUDIO_OUTPUT_CHANNEL_PARAMETER <dev-id> <chn> <key>=<value>

SET AUDIO_OUTPUT_CHANNEL_PARAMETER ${AUDIO_INDEX} 0 NAME='audio_out_1_L'
SET AUDIO_OUTPUT_CHANNEL_PARAMETER ${AUDIO_INDEX} 0 JACK_BINDINGS='${JACK_CONNECT_L}'

# Right #INTERNAL 1
SET AUDIO_OUTPUT_CHANNEL_PARAMETER ${AUDIO_INDEX} 1 NAME='audio_out_2_R'
SET AUDIO_OUTPUT_CHANNEL_PARAMETER ${AUDIO_INDEX} 1 JACK_BINDINGS='${JACK_CONNECT_R}'

# MIDI JACK Device 0
# if same name as audio: same jack client

CREATE MIDI_INPUT_DEVICE JACK ACTIVE='true' NAME='${JACK_CLIENT_NAME}' PORTS='1'
SET MIDI_INPUT_PORT_PARAMETER ${MIDI_INDEX} 0 NAME='midi_in_0'
SET MIDI_INPUT_PORT_PARAMETER ${MIDI_INDEX} 0 JACK_BINDINGS='${JACK_CONNECT_MIDI}'

# MIDI instrument maps
ADD MIDI_INSTRUMENT_MAP 'Chromatic'
ADD MIDI_INSTRUMENT_MAP 'Drum Kits'

###############################################################################
# Channel 0 (n)
ADD CHANNEL

#SET CHANNEL AUDIO_OUTPUT_DEVICE <sampler-channel> <audio-device-id>
SET CHANNEL AUDIO_OUTPUT_DEVICE ${CHANNEL_INDEX} ${AUDIO_INDEX}

#SET CHANNEL MIDI_INPUT_DEVICE <sampler-channel> <midi-device-id>
SET CHANNEL MIDI_INPUT_DEVICE ${CHANNEL_INDEX} ${MIDI_INDEX}

#SET CHANNEL MIDI_INPUT_PORT <sampler-channel> <midi-input-port>
SET CHANNEL MIDI_INPUT_PORT ${CHANNEL_INDEX} 0

SET CHANNEL MIDI_INPUT_CHANNEL ${CHANNEL_INDEX} ALL

LOAD ENGINE GIG ${CHANNEL_INDEX}

###############################################################################
#LOAD INSTRUMENT [NON_MODAL] <filename> <instr-index> <sampler-channel>
LOAD INSTRUMENT NON_MODAL '${GIGFILE}' 0 ${CHANNEL_INDEX}

#SET CHANNEL AUDIO_OUTPUT_CHANNEL <sampler-chan> <audio-out> <audio-in>
SET CHANNEL AUDIO_OUTPUT_CHANNEL ${CHANNEL_INDEX} 0 0
SET CHANNEL AUDIO_OUTPUT_CHANNEL ${CHANNEL_INDEX} 1 1

SET CHANNEL VOLUME ${CHANNEL_INDEX} 1
SET CHANNEL MIDI_INSTRUMENT_MAP ${CHANNEL_INDEX} 0

# Global volume level
SET VOLUME 1.00
__EOF__

ret=$?
#echo "return was: $ret"
if [ $ret -ne 0 ]
then
	echo "there was an error" >&2
	exit 1
fi

echo "=== CHANNEL INFO ======================"
#list newly added channel
(cat - | grep -v "^#" | unix2dos | (netcat "$LS_HOST" "$LS_PORT" | dos2unix)) << __EOF__
GET CHANNEL INFO ${CHANNEL_INDEX}
__EOF__

ret=$?
#echo "return was: $ret"
if [ $ret -ne 0 ]
then
	echo "there was an error" >&2
	exit 1
fi

echo "=== JACK INFO ========================="
#list newly created jack client ports
jack_lsp | grep "$JACK_CLIENT_NAME"

ret=$?
#echo "return was: $ret"
if [ $ret -ne 0 ]
then
	echo "there was an error" >&2
	return 1
fi
echo "success"
echo "=== GIGLOAD DONE ======================"

exit 0

#EOF
