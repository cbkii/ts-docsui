#!/system/bin/sh
# Early shared-storage preparation. No diagnostic or persistent log output is written here.

[ -d /data/media ] || exit 0
mkdir -p /data/media/0 2>/dev/null || exit 0
chown 1023:1023 /data/media/0 2>/dev/null || true
chmod 0775 /data/media/0 2>/dev/null || true
for folder in Alarms Audiobooks DCIM Documents Download Movies Music Notifications Pictures Podcasts Ringtones; do
  mkdir -p "/data/media/0/$folder" 2>/dev/null || continue
  chown 1023:1023 "/data/media/0/$folder" 2>/dev/null || true
  chmod 0775 "/data/media/0/$folder" 2>/dev/null || true
done
restorecon -RF /data/media/0 >/dev/null 2>&1 || true
exit 0
