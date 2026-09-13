#!/bin/bash

SESSION="AMR_FACTORY_NAVIGATOR"
WS="$HOME/ros2_ws"
ENV="$WS/scripts/amr_env.sh"

if [ ! -f "$ENV" ]; then
    echo "ERROR: $ENV not found"
    exit 1
fi

if tmux has-session -t "$SESSION" 2>/dev/null; then

    if [ -n "$TMUX" ]; then
        tmux switch-client -t "$SESSION"
    else
        tmux attach-session -t "$SESSION"
    fi

    exit 0
fi

tmux new-session -d -s "$SESSION" -n CORE

tmux new-window -t "$SESSION" -n SIMULATION
tmux new-window -t "$SESSION" -n HARDWARE
tmux new-window -t "$SESSION" -n NAVIGATION
tmux new-window -t "$SESSION" -n MONITOR
tmux new-window -t "$SESSION" -n DEVELOPMENT

for WINDOW in CORE SIMULATION HARDWARE NAVIGATION MONITOR DEVELOPMENT
do
    tmux send-keys -t "$SESSION:$WINDOW" "source $ENV" C-m
done

tmux select-window -t "$SESSION:CORE"

if [ -n "$TMUX" ]; then
    tmux switch-client -t "$SESSION"
else
    tmux attach-session -t "$SESSION"
fi
