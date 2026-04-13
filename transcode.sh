#!/bin/bash

# ==============================================================================
# Universal Transcoder Script
# Supports: NVIDIA (NVENC), Intel (QSV), AMD (AMF), and Software (x264/x265/VP9)
# ==============================================================================

# Default settings
VIDEO_CODEC="libx264"
OUTPUT_EXTENSION="mp4"
KEEP_AUDIO_SUBS=true
SELECTED_AUDIO_INDEX=""
SELECTED_SUBTITLE_INDEX=""
RESOLUTION="original"
QUALITY=23
GPU_TYPE="none"
PASSES=1

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

# Argument Parsing
FILES_TO_PROCESS=()
for arg in "$@"; do
    case $arg in
        vp9) 
            case $GPU_TYPE in
                nvidia) VIDEO_CODEC="vp9_vaapi" ;;
                intel)  VIDEO_CODEC="vp9_qsv" ;;
                *)      VIDEO_CODEC="libvpx-vp9" ;;
            esac
            OUTPUT_EXTENSION="webm"
            ;;
        av1) 
            case $GPU_TYPE in
                nvidia) VIDEO_CODEC="av1_nvenc" ;;
                intel)  VIDEO_CODEC="av1_qsv" ;;
                amd)    VIDEO_CODEC="av1_amf" ;;
                *)      VIDEO_CODEC="libaom-av1" ;;
            esac
            OUTPUT_EXTENSION="mkv"
            ;;
        hevc) 
            case $GPU_TYPE in
                nvidia) VIDEO_CODEC="hevc_nvenc" ;;
                intel)  VIDEO_CODEC="hevc_qsv" ;;
                amd)    VIDEO_CODEC="hevc_amf" ;;
                *)      VIDEO_CODEC="libx265" ;;
            esac
            OUTPUT_EXTENSION="mkv"
            ;;
        h264) 
            case $GPU_TYPE in
                nvidia) VIDEO_CODEC="h264_nvenc" ;;
                intel)  VIDEO_CODEC="h264_qsv" ;;
                amd)    VIDEO_CODEC="h264_amf" ;;
                *)      VIDEO_CODEC="libx264" ;;
            esac
            OUTPUT_EXTENSION="mp4"
            ;;
        quality=*) QUALITY="${arg#*=}" ;;
        1080) RESOLUTION="1080" ;;
        720)  RESOLUTION="720" ;;
        no-audio-subs) KEEP_AUDIO_SUBS=false ;;
        audio=*) SELECTED_AUDIO_INDEX="${arg#*=}"; KEEP_AUDIO_SUBS=false ;;
        subs=*)  SELECTED_SUBTITLE_INDEX="${arg#*=}" ;;
        passes=*) PASSES="${arg#*=}" ;;
        *)
            # If it's a file that exists, add to list
            if [[ -f "$arg" ]]; then
                FILES_TO_PROCESS+=("$arg")
            else
                echo "Skipping unknown option or missing file: $arg"
            fi
            ;;
    esac
done

# If no specific files were provided, default to the current folder
if [[ ${#FILES_TO_PROCESS[@]} -eq 0 ]]; then
    shopt -s nullglob
    FILES_TO_PROCESS=(*.mkv *.mp4 *.avi *.mov *.ts)
fi

# Define Quality/Rate Control based on the specific encoder
case $VIDEO_CODEC in
    *nvenc)      QUALITY_OPTIONS="-rc vbr -cq $QUALITY -preset p6" ;;
    *qsv)        QUALITY_OPTIONS="-global_quality $QUALITY -preset slow" ;;
    *amf)        QUALITY_OPTIONS="-rc cqp -qp_p $QUALITY -qp_i $QUALITY" ;;
    libvpx-vp9)  QUALITY_OPTIONS="-crf $QUALITY -b:v 0 -deadline good -cpu-used 2" ;;
    libx26*|libaom*) QUALITY_OPTIONS="-crf $QUALITY -preset slow" ;;
    *)           QUALITY_OPTIONS="-crf $QUALITY" ;;
esac

# Summary
echo "--- Configuration ---"
echo "Detected GPU: $GPU_TYPE"
echo "Video Codec:  $VIDEO_CODEC"
echo "Quality:      $QUALITY"
echo "Resolution:   $RESOLUTION"
echo "---------------------"

# Process files
for file in "${FILES_TO_PROCESS[@]}"; do
    if [[ -e "$file" ]]; then
        base_name="${file%.*}"
        output_file="${base_name}_${VIDEO_CODEC}.${OUTPUT_EXTENSION}"

        # Prevent overwriting original file
        if [[ "$file" == "$output_file" ]]; then
            output_file="${base_name}_encoded.${OUTPUT_EXTENSION}"
        fi

        # Resolution filter
        SCALE_FILTER=""
        [[ "$RESOLUTION" == "1080" ]] && SCALE_FILTER="-vf scale=-1:1080"
        [[ "$RESOLUTION" == "720" ]]  && SCALE_FILTER="-vf scale=-1:720"

        # Stream Mapping
        AUDIO_MAP="-map 0:a?"
        SUBTITLE_MAP="-map 0:s?"
        if [[ "$KEEP_AUDIO_SUBS" == false ]]; then
            AUDIO_MAP=""
            SUBTITLE_MAP=""
        elif [[ -n "$SELECTED_AUDIO_INDEX" ]]; then
            AUDIO_MAP="-map 0:a:$SELECTED_AUDIO_INDEX"
            SUBTITLE_MAP=""
        fi

        # Codec mapping for containers
        AUDIO_CODEC="-c:a copy"
        SUBTITLE_CODEC="-c:s copy"
        if [[ "$OUTPUT_EXTENSION" == "webm" ]]; then
            AUDIO_CODEC="-c:a libopus"
            SUBTITLE_CODEC="-c:s webvtt"
        fi

        echo "Processing: $file -> $output_file"
        START_TIME=$(date +%s)

        if [[ "$PASSES" -eq 2 && "$VIDEO_CODEC" != *"nvenc"* ]]; then
            # 2-Pass (Usually only for software codecs)
            ffmpeg -y -i "$file" -c:v "$VIDEO_CODEC" $SCALE_FILTER $QUALITY_OPTIONS -pass 1 -an -f null /dev/null && \
            ffmpeg -y -i "$file" -c:v "$VIDEO_CODEC" $SCALE_FILTER $QUALITY_OPTIONS -pass 2 $AUDIO_CODEC $SUBTITLE_CODEC -map 0:v $AUDIO_MAP $SUBTITLE_MAP "$output_file"
            rm -f ffmpeg2pass-0.log ffmpeg2pass-0.log.mbtree
        else
            # Single Pass (Standard)
            ffmpeg -y -i "$file" -c:v "$VIDEO_CODEC" $SCALE_FILTER $QUALITY_OPTIONS $AUDIO_CODEC $SUBTITLE_CODEC -map 0:v $AUDIO_MAP $SUBTITLE_MAP "$output_file"
        fi

        if [[ $? -eq 0 ]]; then
            END_TIME=$(date +%s)
            echo "Finished $file in $((END_TIME - START_TIME)) seconds."
        else
            echo "Error processing $file"
        fi
    fi
done
