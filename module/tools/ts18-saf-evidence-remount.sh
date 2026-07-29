#!/system/bin/sh
# Remount, reconciliation and package-baseline analysis helpers.

analyse_remount_events() {
  raw=$WORK/logs/remount-provider-events.txt
  structured=$WORK/logs/remount-provider-events.tsv
  grouped=$WORK/logs/remount-provider-summary.txt
  uidmap=$WORK/packages/uid-packages.tsv
  : > "$structured"
  printf 'timestamp\tphase\tuid\tmode\tpackages\traw\n' >> "$structured"

  awk -F '\t' 'NF >= 2 { map[$2] = (map[$2] ? map[$2] "," $1 : $1) } END { for (uid in map) print uid "\t" map[uid] }' \
    "$WORK/packages/package-stack.tsv" > "$uidmap" 2>/dev/null || true

  awk -v uidmap="$uidmap" '
    BEGIN {
      FS="\t"
      while ((getline line < uidmap) > 0) {
        split(line, parts, "\t")
        pkg[parts[1]]=parts[2]
      }
      close(uidmap)
    }
    {
      raw=$0
      timestamp=$1 " " $2
      phase="event"
      lower=tolower(raw)
      if (lower ~ /start|begin/) phase="start"
      else if (lower ~ /finish|complete| end/) phase="end"
      uid="unknown"
      mode="unknown"
      if (match(lower, /uid[=: (]+[0-9]+/)) {
        token=substr(lower, RSTART, RLENGTH)
        gsub(/[^0-9]/, "", token)
        if (token != "") uid=token
      }
      if (match(lower, /mode[=: (]+[a-z0-9_-]+/)) {
        token=substr(lower, RSTART, RLENGTH)
        sub(/^.*mode[=: (]+/, "", token)
        mode=token
      }
      packages=(uid in pkg ? pkg[uid] : "unknown")
      gsub(/\t/, " ", raw)
      print timestamp "\t" phase "\t" uid "\t" mode "\t" packages "\t" raw
    }
  ' "$raw" >> "$structured" 2>/dev/null || true

  total=$(awk 'NR > 1 {count++} END {print count+0}' "$structured" 2>/dev/null)
  starts=$(awk -F '\t' 'NR > 1 && $2 == "start" {count++} END {print count+0}' "$structured" 2>/dev/null)
  seconds=$(awk -F '\t' 'NR > 1 {seen[$1]=1} END {for (x in seen) count++; print count+0}' "$structured" 2>/dev/null)
  peak=$(awk -F '\t' 'NR > 1 {count[$1]++} END {max=0; for (x in count) if (count[x] > max) max=count[x]; print max+0}' "$structured" 2>/dev/null)
  average=$(awk -v total="$total" -v seconds="$seconds" 'BEGIN {if (seconds > 0) printf "%.2f", total/seconds; else print "0.00"}')
  first=$(awk -F '\t' 'NR == 2 {print $1; exit}' "$structured" 2>/dev/null)
  last=$(awk -F '\t' 'NR > 1 {value=$1} END {print value}' "$structured" 2>/dev/null)

  {
    printf 'total_events=%s\n' "$total"
    printf 'start_events=%s\n' "$starts"
    printf 'distinct_seconds=%s\n' "$seconds"
    printf 'average_events_per_second=%s\n' "$average"
    printf 'peak_events_per_second=%s\n' "$peak"
    printf 'first_event=%s\n' "${first:-none}"
    printf 'last_event=%s\n' "${last:-none}"
    printf '\n-- grouped by uid/package/mode/phase --\n'
    awk -F '\t' 'NR > 1 {key=$3 "\t" $5 "\t" $4 "\t" $2; count[key]++} END {for (key in count) print count[key] "\t" key}' "$structured" | sort -nr
  } > "$grouped"

  REMOUNT_EVENT_COUNT=$total
  REMOUNT_PEAK_RATE=$peak
  REMOUNT_STORM=0
  if [ "$total" -ge "$REMOUNT_STORM_TOTAL_THRESHOLD" ] || [ "$peak" -ge "$REMOUNT_STORM_RATE_THRESHOLD" ]; then
    REMOUNT_STORM=1
    warn "possible external-storage remount storm: total=$total peak_per_second=$peak"
  fi
}

capture_system_server_stack() {
  [ "$REMOUNT_STORM" = 1 ] || return 0
  [ "$DIAG_CAPTURE_SYSTEM_SERVER_STACK" = 1 ] || return 0
  pid=$(pidof system_server 2>/dev/null | awk '{print $1}')
  [ -n "$pid" ] || { warn 'system_server PID unavailable for remount-storm stack capture'; return 0; }
  before=$(date '+%m-%d %H:%M:%S' 2>/dev/null || echo unknown)
  if kill -3 "$pid" 2>/dev/null; then
    sleep 2
    file=$WORK/logs/system-server-remount-stack.txt
    {
      printf 'trigger_time=%s\n' "$before"
      printf 'system_server_pid=%s\n' "$pid"
    } > "$file"
    run_sh_to 20 "$file" "logcat -d -v threadtime -t 6000 | grep -A120 -B10 -E 'system_server|remountUidExternalStorage|StorageManagerService|AppOpsService'"
  else
    warn 'system_server stack signal failed'
  fi
}

collect_reconcile_history() {
  service_log=$STATE_DIR/logs/service-v130.log
  output=$WORK/module/reconcile-history.txt
  if [ ! -f "$service_log" ]; then
    printf 'service_log=missing\n' > "$output"
    LATEST_MUTATIONS=unknown
    return 0
  fi
  awk '/===== TS18 Full File Picker/ || /boot wait completed/ || /MUTATION:/ || /reconcile summary/ || /service complete/' "$service_log" > "$output"
  latest=$(grep 'reconcile summary' "$service_log" 2>/dev/null | tail -n 1)
  previous=$(grep 'reconcile summary' "$service_log" 2>/dev/null | tail -n 2 | head -n 1)
  LATEST_MUTATIONS=$(printf '%s\n' "$latest" | sed -n 's/.*mutations=\([0-9][0-9]*\).*/\1/p')
  LATEST_NOOPS=$(printf '%s\n' "$latest" | sed -n 's/.*noops=\([0-9][0-9]*\).*/\1/p')
  PREVIOUS_MUTATIONS=$(printf '%s\n' "$previous" | sed -n 's/.*mutations=\([0-9][0-9]*\).*/\1/p')
  [ -n "$LATEST_MUTATIONS" ] || LATEST_MUTATIONS=unknown
  [ -n "$LATEST_NOOPS" ] || LATEST_NOOPS=unknown
  [ -n "$PREVIOUS_MUTATIONS" ] || PREVIOUS_MUTATIONS=unknown

  case "$MODE" in
    boot2|settled)
      if [ "$LATEST_MUTATIONS" != 0 ]; then
        warn "settled-boot mode expected zero reconciliation mutations; observed $LATEST_MUTATIONS"
      fi
      ;;
  esac
}

update_package_baseline() {
  current=$WORK/packages/package-stack.tsv
  previous=$STATE_DIR/last-package-stack.tsv
  diff_file=$WORK/packages/package-stack-diff.txt
  if [ -f "$previous" ]; then
    copy_file_limited "$previous" "$WORK/packages/package-stack-previous.tsv"
    diff -u "$previous" "$current" > "$diff_file" 2>&1 || true
  else
    printf 'No previous successful package snapshot exists.\n' > "$diff_file"
  fi
  temp=$STATE_DIR/.last-package-stack.$$
  if cp -f "$current" "$temp" 2>/dev/null && chmod 0600 "$temp" 2>/dev/null && mv -f "$temp" "$previous" 2>/dev/null; then
    :
  else
    rm -f "$temp" 2>/dev/null || true
    warn 'could not update persistent package-stack baseline'
  fi
}
