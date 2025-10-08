#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Starting all services..."
echo ""
echo "Opening 3 terminals..."
echo ""

if command -v gnome-terminal &> /dev/null; then
    gnome-terminal --tab --title="API" -- bash -c "cd '$SCRIPT_DIR' && ./start-api.sh; exec bash"
    gnome-terminal --tab --title="Worker" -- bash -c "cd '$SCRIPT_DIR' && ./start-worker.sh; exec bash"
    gnome-terminal --tab --title="Frontend" -- bash -c "cd '$SCRIPT_DIR' && ./start-frontend.sh; exec bash"
elif command -v xterm &> /dev/null; then
    xterm -hold -e "cd '$SCRIPT_DIR' && ./start-api.sh" &
    xterm -hold -e "cd '$SCRIPT_DIR' && ./start-worker.sh" &
    xterm -hold -e "cd '$SCRIPT_DIR' && ./start-frontend.sh" &
else
    echo "Please open 3 terminals manually and run:"
    echo "  Terminal 1: ./start-api.sh"
    echo "  Terminal 2: ./start-worker.sh"
    echo "  Terminal 3: ./start-frontend.sh"
fi
