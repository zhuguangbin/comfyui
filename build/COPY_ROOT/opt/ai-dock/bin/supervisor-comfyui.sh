#!/bin/bash

trap cleanup EXIT

LISTEN_PORT=18188
METRICS_PORT=28188
PROXY_SECURE=true

function cleanup() {
    kill $(jobs -p) > /dev/null 2>&1
    rm /run/http_ports/$PROXY_PORT > /dev/null 2>&1
}

function start() {
    if [[ -z $COMFYUI_PORT ]]; then
        COMFYUI_PORT=8188
    fi
    
    PROXY_PORT=$COMFYUI_PORT
    SERVICE_NAME="ComfyUI"
    
    file_content="$(
      jq --null-input \
        --arg listen_port "${LISTEN_PORT}" \
        --arg metrics_port "${METRICS_PORT}" \
        --arg proxy_port "${PROXY_PORT}" \
        --arg proxy_secure "${PROXY_SECURE,,}" \
        --arg service_name "${SERVICE_NAME}" \
        '$ARGS.named'
    )"
    
    printf "%s" "$file_content" > /run/http_ports/$PROXY_PORT
    
    PLATFORM_FLAGS=""
    if [[ $XPU_TARGET = "CPU" ]]; then
        PLATFORM_FLAGS="--cpu"
    fi
    
    BASE_FLAGS="--listen 127.0.0.1 --disable-auto-launch"
    
    # Delay launch until micromamba is ready
    if [[ -f /run/workspace_sync || -f /run/container_config ]]; then
        if [[ ${SERVERLESS,,} != "true" ]]; then
            printf "Waiting for workspace sync...\n"
            kill $(lsof -t -i:$LISTEN_PORT) > /dev/null 2>&1 &
            wait -n
            /usr/bin/python3 /opt/ai-dock/fastapi/logviewer/main.py \
                -p $LISTEN_PORT \
                -r 5 \
                -s "${SERVICE_NAME}" \
                -t "Preparing ${SERVICE_NAME}" &
            fastapi_pid=$!
            
            while [[ -f /run/workspace_sync || -f /run/container_config ]]; do
                sleep 1
            done
            
            kill $fastapi_pid &
            wait -n
        else
            printf "Waiting for workspace symlinks and pre-flight checks...\n"
            while [[ -f /run/workspace_sync || -f /run/container_config ]]; do
                sleep 1
            done
        fi
    fi
    
    printf "%s started: %s\n" "${SERVICE_NAME}" "$(date +"%x %T.%3N")" >> /var/log/timing_data
    printf "Starting %s...\n" "${SERVICE_NAME}"
    
    kill $(lsof -t -i:$LISTEN_PORT) > /dev/null 2>&1 &
    wait -n

    FLAGS_COMBINED="${PLATFORM_FLAGS} ${BASE_FLAGS} $(cat /etc/comfyui_flags.conf)"
    printf "Starting %s...\n" "${SERVICE_NAME}"

    cd /opt/ComfyUI && \
    micromamba run -n comfyui -e LD_PRELOAD=libtcmalloc.so python main.py \
        ${FLAGS_COMBINED} --port ${LISTEN_PORT}
}

start 2>&1