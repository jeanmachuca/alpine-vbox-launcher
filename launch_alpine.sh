echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║  launch_alpine.sh is superseded by alpine-vm.sh     ║"
echo "║  Running: ./alpine-vm.sh                            ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

exec "$(dirname "$0")/alpine-vm.sh" "$@"
exec ssh-keygen -f "$HOME/.ssh/known_hosts" -R "[localhost]:2222"
exec ssh -p 2222 root@localhost "cat > /tmp/bootstrap_alpine.sh && chmod +x /tmp/bootstrap_alpine.sh && /tmp/bootstrap_alpine.sh" < ./bootstrap_alpine.sh

