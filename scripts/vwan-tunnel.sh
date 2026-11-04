#!/bin/bash

# Runs the privileged OpenVPN operations for the vwan P2S VPN integration test
# (scripts/Test-Integration-VwanConnectivity.ps1). It is the only command that test runs as root.
#
# Usage: vwan-tunnel.sh <command> [options]
#   version          Prints the interface version. Doesn't require root.
#   check            Exits 0. Used to probe 'sudo -n' access to this script.
#   start            Reads an OpenVPN client config from stdin, validates it and starts openvpn.
#   status           Exits 0 if the tunnel is running, 3 if not.
#   log [--tail N]   Prints the openvpn start errors and log (or the last N log lines).
#   stop             Stops the tunnel and deletes its state, including the config and private key.
#
# Security model: install a root-owned copy with scripts/install-vwan-tunnel.sh and grant passwordless
# sudo for that copy only. Callers can't pass file paths or openvpn options: the config arrives on
# stdin, only allowlisted client directives and inline certificate blocks are accepted, external
# scripts are disabled (--script-security 1), and all state lives in a fixed root-only directory.
# One tunnel per host at a time. The config, including the private key, is deleted by 'stop'.
#
# Kept compatible with bash 3.2 and BSD userland so it can run on macOS (best effort, untested).

set -euo pipefail
umask 077
export PATH=/usr/sbin:/usr/bin:/sbin:/bin:/usr/local/sbin:/usr/local/bin:/opt/homebrew/sbin:/opt/homebrew/bin

# Increment when the commands, options or accepted config change, so callers can detect an outdated
# installed copy.
interface_version=1

max_config_bytes=262144

if [ "$(uname -s)" = Darwin ]; then
    state_dir=/var/run/azuresandbox-vwan
else
    state_dir=/run/azuresandbox-vwan
fi
config_file="$state_dir/vpn.ovpn"
log_file="$state_dir/openvpn.log"
stderr_file="$state_dir/openvpn-stderr.log"
pid_file="$state_dir/openvpn.pid"

usage() {
    echo "usage: vwan-tunnel.sh {version|check|start|status|log [--tail N]|stop}" >&2
    exit 2
}

fail() {
    echo "vwan-tunnel: $*" >&2
    exit 1
}

require_root() {
    [ "$(id -u)" -eq 0 ] || fail "must run as root (use sudo)"
}

# Prints the PID of the running tunnel, or nothing.
tunnel_pid() {
    local pid comm
    [ -f "$pid_file" ] || return 0
    pid=$(head -n 1 "$pid_file" 2> /dev/null | tr -d '[:space:]')
    case "$pid" in
        '' | *[!0-9]*) return 0 ;;
    esac
    comm=$(ps -p "$pid" -o comm= 2> /dev/null || true)
    case "$comm" in
        *openvpn) echo "$pid" ;;
    esac
}

# Rejects a symlinked or foreign-owned state directory before reading or deleting it.
check_state_dir() {
    if [ -L "$state_dir" ]; then
        fail "$state_dir is a symlink; refusing to use it"
    fi
    if [ -e "$state_dir" ] && [ -z "$(find "$state_dir" -maxdepth 0 -user 0 ! -perm -g+w ! -perm -o+w 2> /dev/null)" ]; then
        fail "$state_dir isn't owned by root or is writable by other users; refusing to use it"
    fi
}

# Validates an OpenVPN client config. Only directives a client needs to reach the Azure P2S gateway
# are allowed; anything that runs programs, loads plugins, reads or writes files, or opens a
# management interface is rejected.
validate_config() {
    local file="$1" line directive value block='' line_number=0

    while IFS= read -r line || [ -n "$line" ]; do
        line_number=$((line_number + 1))
        line="${line%$'\r'}"
        line="${line#"${line%%[![:space:]]*}"}"

        if [ -n "$block" ]; then
            if [ "$line" = "</$block>" ]; then
                block=''
            elif [ "${line#<}" != "$line" ]; then
                fail "config line $line_number: unexpected '$line' inside <$block>"
            fi
            continue
        fi

        case "$line" in
            '' | '#'* | ';'*) continue ;;
            '<ca>' | '<cert>' | '<key>' | '<tls-auth>' | '<tls-crypt>' | '<tls-crypt-v2>' | '<extra-certs>')
                block="${line#<}"
                block="${block%>}"
                continue
                ;;
            '<'*) fail "config line $line_number: inline block '$line' isn't allowed" ;;
        esac

        directive="${line%%[[:space:]]*}"
        value="${line#"$directive"}"
        value="${value#"${value%%[![:space:]]*}"}"

        case "$directive" in
            client | tls-client | pull | proto | remote | remote-random | resolv-retry | nobind | \
                persist-key | persist-tun | remote-cert-tls | verify-x509-name | auth | cipher | \
                data-ciphers | data-ciphers-fallback | ncp-ciphers | ncp-disable | tls-version-min | \
                tls-version-max | tls-cipher | tls-ciphersuites | tls-groups | tls-timeout | key-direction | \
                verb | mute | mute-replay-warnings | disable-dco | connect-retry | connect-retry-max | \
                connect-timeout | server-poll-timeout | hand-window | reneg-sec | ping | ping-restart | \
                ping-exit | inactive | float | explicit-exit-notify | auth-nocache | route-delay | \
                route-method | route-metric | redirect-gateway | pull-filter | topology | tun-mtu | mssfix | \
                sndbuf | rcvbuf | push-peer-info | comp-lzo | compress | allow-compression | ifconfig-nowarn | \
                fast-io)
                ;;
            dev)
                case "$value" in
                    tun | tun[0-9] | tun[0-9][0-9]) ;;
                    *) fail "config line $line_number: 'dev $value' isn't allowed (use 'dev tun')" ;;
                esac
                ;;
            ca)
                case "$value" in
                    /etc/ssl/certs/ca-certificates.crt | /etc/ssl/cert.pem | /etc/pki/tls/certs/ca-bundle.crt) ;;
                    *) fail "config line $line_number: 'ca' may only name the system CA bundle; use an inline <ca> block instead" ;;
                esac
                ;;
            *) fail "config line $line_number: directive '$directive' isn't allowed" ;;
        esac
    done < "$file"

    [ -z "$block" ] || fail "config: <$block> isn't closed"
}

cmd_start() {
    local pid size
    require_root
    check_state_dir

    pid=$(tunnel_pid)
    if [ -n "$pid" ]; then
        fail "a tunnel is already running (PID $pid); run 'vwan-tunnel.sh stop' first"
    fi

    # Clears state left behind by a run that ended without stopping its tunnel.
    rm -rf "$state_dir"
    mkdir -m 0700 "$state_dir"

    head -c $((max_config_bytes + 1)) > "$config_file"
    size=$(wc -c < "$config_file" | tr -d '[:space:]')
    if [ "$size" -eq 0 ]; then
        rm -rf "$state_dir"
        fail "no config received on stdin"
    fi
    if [ "$size" -gt "$max_config_bytes" ]; then
        rm -rf "$state_dir"
        fail "config is larger than $max_config_bytes bytes"
    fi

    if ! (validate_config "$config_file"); then
        rm -rf "$state_dir"
        exit 1
    fi

    command -v openvpn > /dev/null 2>&1 || fail "openvpn not found; install OpenVPN and retry"

    # Options after --config override the config. All standard streams are redirected so the
    # daemon doesn't hold the caller's pipes open.
    if ! openvpn --config "$config_file" --script-security 1 --daemon \
        --log "$log_file" --writepid "$pid_file" \
        < /dev/null > /dev/null 2> "$stderr_file"; then
        cat "$stderr_file" >&2
        fail "openvpn failed to start"
    fi
}

cmd_status() {
    local pid
    require_root
    check_state_dir
    pid=$(tunnel_pid)
    if [ -n "$pid" ]; then
        echo "running $pid"
        exit 0
    fi
    echo "stopped"
    exit 3
}

cmd_log() {
    local tail_lines=''
    require_root
    check_state_dir

    if [ "$#" -gt 0 ]; then
        [ "$#" -eq 2 ] && [ "$1" = --tail ] || usage
        case "$2" in
            '' | *[!0-9]*) usage ;;
        esac
        [ "${#2}" -le 5 ] || usage
        tail_lines="$2"
    fi

    if [ -s "$stderr_file" ]; then
        cat "$stderr_file"
    fi
    if [ -f "$log_file" ]; then
        if [ -n "$tail_lines" ]; then
            tail -n "$tail_lines" "$log_file"
        else
            cat "$log_file"
        fi
    fi
}

cmd_stop() {
    local pid waited=0
    require_root
    check_state_dir

    pid=$(tunnel_pid)
    if [ -n "$pid" ]; then
        kill -TERM "$pid" 2> /dev/null || true
        while kill -0 "$pid" 2> /dev/null && [ "$waited" -lt 10 ]; do
            sleep 1
            waited=$((waited + 1))
        done
        if kill -0 "$pid" 2> /dev/null; then
            kill -KILL "$pid" 2> /dev/null || true
        fi
        echo "stopped tunnel (PID $pid)"
    fi
    rm -rf "$state_dir"
}

[ "$#" -ge 1 ] || usage
command_name="$1"
shift

case "$command_name" in
    version)
        [ "$#" -eq 0 ] || usage
        echo "$interface_version"
        ;;
    check)
        [ "$#" -eq 0 ] || usage
        require_root
        ;;
    start)
        [ "$#" -eq 0 ] || usage
        cmd_start
        ;;
    status)
        [ "$#" -eq 0 ] || usage
        cmd_status
        ;;
    log) cmd_log "$@" ;;
    stop)
        [ "$#" -eq 0 ] || usage
        cmd_stop
        ;;
    *) usage ;;
esac
