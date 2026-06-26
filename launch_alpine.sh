echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║  launch_alpine.sh is superseded by alpine-vm.sh     ║"
echo "║  Running: ./alpine-vm.sh                            ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

exec "$(dirname "$0")/alpine-vm.sh" "$@"
exec ssh-keygen -f "~/.ssh/known_hosts" -R "[localhost]:2222"

