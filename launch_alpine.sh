echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║  launch_alpine.sh is superseded by alpine-vm.sh     ║"
echo "║  Running: ./alpine-vm.sh                            ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

exec "$(dirname "$0")/alpine-vm.sh" "$@"

