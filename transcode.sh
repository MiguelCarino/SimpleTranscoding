#!/bin/bash

# Default settings
VIDEO_CODEC="libvpx-vp9"  # Default software codec
OUTPUT_EXTENSION="webm"   # Default extension
KEEP_AUDIO_SUBS=true
SELECTED_AUDIO_INDEX=""
SELECTED_SUBTITLE_INDEX=""
RESOLUTION="original"
QUALITY=23  # Default quality setting (CRF/CQ)
GPU_TYPE="none"
PASSES=1  # Default to one-pass encoding

# Function to check encoder availability
function encoder_exists {
    ffmpeg -encoders | grep -q "$1"
}

# Function to detect GPU
function detect_gpu {
    if lspci | grep -i "nvidia" &>/dev/null; then
        GPU_TYPE="nvidia"
    elif lspci | grep -i "intel" &>/dev/null; then
        GPU_TYPE="intel"
    elif lspci | grep -i "amd" &>/dev/null; then
        GPU_TYPE="amd"
    else
        GPU_TYPE="none"
    fi
}

detect_gpu

# Choose the best default codec based on GPU availability
case $GPU_TYPE in
    nvidia)
        VIDEO_CODEC="h264_nvenc"
        OUTPUT_EXTENSION="mp4"
        ;;
    intel)
        VIDEO_CODEC="h264_qsv"
        OUTPUT_EXTENSION="mp4"
        ;;
    amd)
        VIDEO_CODEC="h264_amf"
        OUTPUT_EXTENSION="mp4"
        ;;
    none)
        VIDEO_CODEC="libx264"
        OUTPUT_EXTENSION="mp4"
        ;;
esac

# Parse arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        vp9) 
            case $GPU_TYPE in
                nvidia) VIDEO_CODEC="vp9_vaapi" ;;
                intel) VIDEO_CODEC="vp9_qsv" ;;
                amd) VIDEO_CODEC="libvpx-vp9" ;;
                none) VIDEO_CODEC="libvpx-vp9" ;;
            esac
            OUTPUT_EXTENSION="webm"
            ;;
        av1) 
            case $GPU_TYPE in
                nvidia) VIDEO_CODEC="av1_nvenc" ;;
                intel) VIDEO_CODEC="av1_qsv" ;;
                amd) VIDEO_CODEC="av1_amf" ;;
                none) VIDEO_CODEC="libaom-av1" ;;
            esac
            OUTPUT_EXTENSION="mkv"
            ;;
        hevc) 
            case $GPU_TYPE in
                nvidia) VIDEO_CODEC="hevc_nvenc" ;;
                intel) VIDEO_CODEC="hevc_qsv" ;;
                amd) VIDEO_CODEC="hevc_amf" ;;
                none) VIDEO_CODEC="libx265" ;;
            esac
            OUTPUT_EXTENSION="mkv"
            ;;
        h264) 
            case $GPU_TYPE in
                nvidia) VIDEO_CODEC="h264_nvenc" ;;
                intel) VIDEO_CODEC="h264_qsv" ;;
                amd) VIDEO_CODEC="h264_amf" ;;
                none) VIDEO_CODEC="libx264" ;;
            esac
            OUTPUT_EXTENSION="mp4"
            ;;
        quality=*) QUALITY="${1#*=}" ;;
        1080) RESOLUTION="1080" ;;
        720) RESOLUTION="720" ;;
        no-audio-subs) KEEP_AUDIO_SUBS=false ;;
        audio=*) SELECTED_AUDIO_INDEX="${1#*=}"; KEEP_AUDIO_SUBS=false ;;
        subs=*) SELECTED_SUBTITLE_INDEX="${1#*=}" ;;
        passes=*) PASSES="${1#*=}" ;;  # Allow user to specify passes
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
    shift
done

# Inform the user about selected settings
echo "Detected GPU: $GPU_TYPE"
echo "Video codec: $VIDEO_CODEC"
echo "Output extension: .$OUTPUT_EXTENSION"
echo "Keep all audio and subs: $KEEP_AUDIO_SUBS"
echo "Quality setting: CRF/CQ $QUALITY"
echo "Encoding passes: $PASSES"
if [[ -n "$SELECTED_AUDIO_INDEX" ]]; then
    echo "Selected audio stream index: $SELECTED_AUDIO_INDEX"
fi
if [[ -n "$SELECTED_SUBTITLE_INDEX" ]]; then
    echo "Selected subtitle stream index: $SELECTED_SUBTITLE_INDEX"
fi
echo "Resolution: $RESOLUTION"

# Process files
for file in *.mkv *.mp4 *.avi; do
    if [[ -e "$file" ]]; then
        base_name="${file%.*}"
        output_file="${base_name}_${VIDEO_CODEC}.${OUTPUT_EXTENSION}"

        SCALE_FILTER=""
        if [[ "$RESOLUTION" == "1080" ]]; then
            SCALE_FILTER="-vf scale=-1:1080"
        elif [[ "$RESOLUTION" == "720" ]]; then
            SCALE_FILTER="-vf scale=-1:720"
        fi

        AUDIO_MAP="-map 0:a"
        SUBTITLE_MAP="-map 0:s?"
        if [[ "$KEEP_AUDIO_SUBS" == false ]]; then
            AUDIO_MAP=""
            SUBTITLE_MAP=""
        elif [[ -n "$SELECTED_AUDIO_INDEX" ]]; then
            AUDIO_MAP="-map 0:a:$SELECTED_AUDIO_INDEX"
            SUBTITLE_MAP=""
        fi

        AUDIO_CODEC="-c:a copy"
        SUBTITLE_CODEC="-c:s copy"
        if [[ "$OUTPUT_EXTENSION" == "webm" ]]; then
            AUDIO_CODEC="-c:a libopus"
            SUBTITLE_CODEC="-c:s webvtt"
        fi

        QUALITY_OPTIONS="-crf $QUALITY -preset slow"

        echo "Processing $file..."

        START_TIME=$(date +%s)

        if [[ "$PASSES" -eq 2 ]]; then
            # First pass (log stats, no audio, no output file)
            ffmpeg -y -i "$file" -c:v "$VIDEO_CODEC" $SCALE_FILTER \
                $QUALITY_OPTIONS -b:v 0 -pass 1 -an -f null /dev/null

            # Second pass (final output with audio)
            ffmpeg -i "$file" -c:v "$VIDEO_CODEC" $SCALE_FILTER \
                $QUALITY_OPTIONS -b:v 0 -pass 2 \
                $AUDIO_CODEC $SUBTITLE_CODEC \
                -map 0:v $AUDIO_MAP $SUBTITLE_MAP \
                "$output_file"

            # Clean up FFmpeg log files
            rm -f ffmpeg2pass-0.log ffmpeg2pass-0.log.mbtree
        else
            # Single pass encoding (default)
            ffmpeg -i "$file" -c:v "$VIDEO_CODEC" $SCALE_FILTER \
                $QUALITY_OPTIONS \
                $AUDIO_CODEC $SUBTITLE_CODEC \
                -map 0:v $AUDIO_MAP $SUBTITLE_MAP \
                "$output_file"
        fi

        END_TIME=$(date +%s)
        TIME_TAKEN=$((END_TIME - START_TIME))

        if [[ $? -eq 0 ]]; then
            echo "Converted $file to $output_file in $TIME_TAKEN seconds."
        else
            echo "Failed to convert $file. Please check the input file or parameters."
        fi
    fi
done
