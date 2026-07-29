#!/system/bin/sh
# Remount, reconciliation and package-baseline analysis helpers.

analyse_remount_events() {
  raw=$WORK/logs/remount-provider-events.txt
  structured=$WORK/logs/remount-provider-events.tsv
  grouped=$WORK/logs/remount-provider-summary.txt
  uidmap=$WORK/packages/uid-packages.tsv
  : > "$structured"
  printf 'timestamp\tsecond_bucket\tevent_type\tphase\tuid\tmode\tpackages\traw\n' >> "$structured"

  if ! awk -F '\t' '$2 ~ /^[0-9]+$/ { map[$2] = (map[$2] ? map[$2] "," $1 : $1) } END { for (uid in map) print uid "\t" map[uid] }' \
    "$WORK/packages/package-stack.tsv" > "$uidmap" 2>/dev/null; then
    # Missing UID metadata reduces annotation quality but does not invalidate raw evidence.
    : > "$uidmap"
  fi

  if ! awk -v uidmap="$uidmap" '
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
      second=$2
      sub(/\..*$/, "", second)
      second_bucket=$1 " " second
      lower=tolower(raw)
      event_type="context"
      if (lower ~ /remountuidexternalstorage|remount.*external/) event_type="remount"
      else if (lower ~ /notifyopchanged|storagemanagerservice.*opchanged/) event_type="appops"
      phase="event"
      if (event_type == "remount" && lower ~ /start|begin/) phase="start"
      else if (event_type == "remount" && lower ~ /finish|complete| end/) phase="end"
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
      print timestamp "\t" second_bucket "\t" event_type "\t" phase "\t" uid "\t" mode "\t" packages "\t" raw
    }
  ' "$raw" >> "$structured" 2>/dev/null; then
    # Keep the raw log when an OEM-specific line cannot be parsed.
    warn 'structured remount parsing failed; raw remount evidence is still included'
  fi

  total=$(awk -F '\t' 'NR > 1 && $3 == "remount" {count++} END {print count+0}' "$structured" 2>/dev/null)
  starts=$(awk -F '\t' 'NR > 1 && $3 == "remount" && $4 == "start" {count++} END {print count+0}' "$structured" 2>/dev/null)
  ends=$(awk -F '\t' 'NR > 1 && $3 == "remount" && $4 == "end" {count++} END {print count+0}' "$structured" 2>/dev/null)
  appops=$(awk -F '\t' 'NR > 1 && $3 == "appops" {count++} END {print count+0}' "$structured" 2>/dev/null)
  seconds=$(awk -F '\t' 'NR > 1 && $3 == "remount" {seen[$2]=1} END {for (x in seen) count++; print count+0}' "$structured" 2>/dev/null)
  peak=$(awk -F '\t' 'NR > 1 && $3 == "remount" {count[$2]++} END {max=0; for (x in count) if (count[x] > max) max=count[x]; print max+0}' "$structured" 2>/dev/null)
  average=$(awk -v total="$total" -v seconds="$seconds" 'BEGIN {if (seconds > 0) printf "%.2f", total/seconds; else print "0.00"}')
  first=$(awk -F '\t' 'NR > 1 && $3 == "remount" {print $1; exit}' "$structured" 2>/dev/null)
  last=$(awk -F '\t' 'NR > 1 && $3 == "remount" {value=$1} END {print value}' "$structured" 2>/dev/null)
  unmatched=$(awk -v starts="$starts" -v ends="$ends" 'BEGIN {delta=starts-ends; if (delta < 0) delta=-delta; print delta}')

  {
    printf 'remount_events=%s\n' "$total"
    printf 'remount_start_events=%s\n' "$starts"
    printf 'remount_end_events=%s\n' "$ends"
    printf 'unmatched_start_or_end_events=%s\n' "$unmatched"
    printf 'appops_context_events=%s\n' "$appops"
    printf 'distinct_remount_seconds=%s\n' "$seconds"
    printf 'average_remount_events_per_second=%s\n' "$average"
    printf 'peak_events_per_second=%s\n' "$peak"
    printf 'first_remount_event=%s\n' "${first:-none}"
    printf 'last_remount_event=%s\n' "${last:-none}"
    printf '\n-- grouped by type/uid/package/mode/phase --\n'
    awk -F '\t' 'NR > 1 {key=$3 "\t" $5 "\t" $7 "\t" $6 "\t" $4; count[key]++} END {for (key in count) print count[key] "\t" key}' "$structured" | sort -nr
  } > "$grouped"

  REMOUNT_EVENT_COUNT=$total
  REMOUNT_PEAK_RATE=$peak
  REMOUNT_STORM=0
  if [ "$total" -ge "$REMOUNT_STORM_TOTAL_THRESHOLD" ] || [ "$peak" -ge "$REMOUNT_STORM_RATE_THRESHOLD" ]; then
    REMOUNT_STORM=1
    warn "possible external-storage remount storm: remounts=$total peak_per_second=$peak"
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
  service_log=$STATE_DIR/logs/service-v${VERSION_CODE}.log
  output=$WORK/module/reconcile-history.txt
  if [ ! -f "$service_log" ]; then
    printf 'service_log=missing path=%s\n' "$service_log" > "$output"
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
    if diff -u "$previous" "$current" > "$diff_file" 2>&1; then
      :
    else
      rc=$?
      if [ "$rc" -ne 1 ]; then
        warn "package-stack comparison failed rc=$rc"
      fi
    fi
  else
    printf 'No previous package snapshot exists.\n' > "$diff_file"
  fi
  temp=$STATE_DIR/.last-package-stack.$$
  if cp -f -- "$current" "$temp" 2>/dev/null && chmod 0600 -- "$temp" 2>/dev/null && mv -f -- "$temp" "$previous" 2>/dev/null; then
    :
  else
    if [ -e "$temp" ] && ! rm -f -- "$temp" 2>/dev/null; then
      warn "temporary package baseline could not be removed: $temp"
    fi
    warn 'could not update persistent package-stack baseline'
  fi
}
