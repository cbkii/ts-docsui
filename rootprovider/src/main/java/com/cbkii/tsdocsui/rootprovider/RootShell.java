package com.cbkii.tsdocsui.rootprovider;

import android.util.Base64;
import android.util.Log;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.concurrent.Callable;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.TimeoutException;

final class RootShell {
    static final String HELPER = "/data/adb/ts18-documentsui-saf/rootfs-helper.sh";
    private static final String TAG = "TS18RootProvider";
    private static final long DEFAULT_TIMEOUT_SECONDS = 12L;
    private static final ExecutorService IO_EXECUTOR = Executors.newCachedThreadPool(r -> {
        Thread t = new Thread(r, "ts18-root-shell-io");
        t.setDaemon(true);
        return t;
    });

    private RootShell() {}

    static final class Result {
        final int exitCode;
        final byte[] stdout;
        final byte[] stderr;
        final boolean timedOut;

        Result(int exitCode, byte[] stdout, byte[] stderr, boolean timedOut) {
            this.exitCode = exitCode;
            this.stdout = stdout;
            this.stderr = stderr;
            this.timedOut = timedOut;
        }

        boolean ok() {
            return !timedOut && exitCode == 0;
        }

        String stdoutText() {
            return new String(stdout, StandardCharsets.UTF_8);
        }

        String stderrText() {
            return new String(stderr, StandardCharsets.UTF_8);
        }
    }

    static Result run(String action, String... args) {
        return run(DEFAULT_TIMEOUT_SECONDS, action, args);
    }

    static Result run(long timeoutSeconds, String action, String... args) {
        Process process = null;
        Future<byte[]> stdoutFuture = null;
        Future<byte[]> stderrFuture = null;
        try {
            process = start(action, args);
            stdoutFuture = IO_EXECUTOR.submit(readAll(process.getInputStream()));
            stderrFuture = IO_EXECUTOR.submit(readAll(process.getErrorStream()));

            boolean finished = process.waitFor(timeoutSeconds, TimeUnit.SECONDS);
            if (!finished) {
                process.destroy();
                if (!process.waitFor(2, TimeUnit.SECONDS)) {
                    process.destroyForcibly();
                }
                return new Result(124, getFuture(stdoutFuture, 1), getFuture(stderrFuture, 1), true);
            }
            int exit = process.exitValue();
            return new Result(exit, getFuture(stdoutFuture, 2), getFuture(stderrFuture, 2), false);
        } catch (IOException | InterruptedException e) {
            if (e instanceof InterruptedException) {
                Thread.currentThread().interrupt();
            }
            return new Result(126, new byte[0], e.toString().getBytes(StandardCharsets.UTF_8), false);
        } finally {
            if (process != null) {
                try {
                    process.getInputStream().close();
                } catch (IOException ignored) {}
                try {
                    process.getErrorStream().close();
                } catch (IOException ignored) {}
                try {
                    process.getOutputStream().close();
                } catch (IOException ignored) {}
            }
        }
    }

    static Process start(String action, String... args) throws IOException {
        StringBuilder command = new StringBuilder();
        command.append("exec ").append(shellQuote(HELPER)).append(' ').append(shellQuote(action));
        for (String arg : args) {
            command.append(' ').append(shellQuote(encode(arg)));
        }
        return new ProcessBuilder(findSuBinary(), "-c", command.toString()).start();
    }

    private static String findSuBinary() {
        String[] candidates = new String[] {
                "/system/bin/su",
                "/system/xbin/su",
                "/sbin/su",
                "/debug_ramdisk/su"
        };
        for (String candidate : candidates) {
            File file = new File(candidate);
            if (file.isFile() && file.canExecute()) {
                return candidate;
            }
        }
        return "su";
    }

    static boolean ping() {
        Result result = run(5, "ping");
        if (!result.ok()) {
            Log.w(TAG, "Root helper ping failed: exit=" + result.exitCode + " err=" + result.stderrText());
        }
        return result.ok() && result.stdoutText().contains("uid=0");
    }

    static RootEntry stat(String path) {
        Result result = run("stat", path);
        if (!result.ok()) {
            return null;
        }
        List<RootEntry> entries = parseEntries(result.stdoutText());
        return entries.isEmpty() ? null : entries.get(0);
    }

    static List<RootEntry> list(String path) {
        Result result = run("list", path);
        if (!result.ok()) {
            return Collections.emptyList();
        }
        return parseEntries(result.stdoutText());
    }

    static long availableBytes(String path) {
        Result result = run(6, "df", path);
        if (!result.ok()) {
            return -1L;
        }
        try {
            return Long.parseLong(result.stdoutText().trim());
        } catch (NumberFormatException ignored) {
            return -1L;
        }
    }

    static String create(String parentPath, String displayName, boolean directory) throws IOException {
        Result result = run("create", parentPath, displayName, directory ? "dir" : "file");
        if (!result.ok()) {
            throw new IOException(errorMessage("create", result));
        }
        return decode(result.stdoutText().trim());
    }

    static String rename(String path, String displayName) throws IOException {
        Result result = run("rename", path, displayName);
        if (!result.ok()) {
            throw new IOException(errorMessage("rename", result));
        }
        return decode(result.stdoutText().trim());
    }

    static void delete(String path) throws IOException {
        Result result = run("delete", path);
        if (!result.ok()) {
            throw new IOException(errorMessage("delete", result));
        }
    }

    static void copyOut(String sourcePath, File destination, int ownerUid) throws IOException {
        Result result = run(60, "copyout", sourcePath, destination.getAbsolutePath(), Integer.toString(ownerUid));
        if (!result.ok()) {
            throw new IOException(errorMessage("copyout", result));
        }
    }

    static void copyIn(File source, String destinationPath) throws IOException {
        Result result = run(60, "copyin", source.getAbsolutePath(), destinationPath);
        if (!result.ok()) {
            throw new IOException(errorMessage("copyin", result));
        }
    }

    static void copy(String sourcePath, String targetParentPath) throws IOException {
        Result result = run(60, "copy", sourcePath, targetParentPath);
        if (!result.ok()) {
            throw new IOException(errorMessage("copy", result));
        }
    }

    static String move(String sourcePath, String targetParentPath) throws IOException {
        Result result = run(60, "move", sourcePath, targetParentPath);
        if (!result.ok()) {
            throw new IOException(errorMessage("move", result));
        }
        return decode(result.stdoutText().trim());
    }

    private static String errorMessage(String action, Result result) {
        String err = result.stderrText().trim();
        if (err.isEmpty()) {
            err = result.stdoutText().trim();
        }
        if (err.isEmpty()) {
            err = "exit " + result.exitCode;
        }
        return action + " failed: " + err;
    }

    private static List<RootEntry> parseEntries(String text) {
        List<RootEntry> result = new ArrayList<>();
        for (String line : text.split("\\n")) {
            if (line.isEmpty()) {
                continue;
            }
            String[] fields = line.split("\\t", -1);
            if (fields.length < 6) {
                continue;
            }
            try {
                String type = fields[0];
                long size = Long.parseLong(fields[1]);
                long mtimeSeconds = Long.parseLong(fields[2]);
                String mode = fields[3];
                String name = decode(fields[4]);
                String path = decode(fields[5]);
                result.add(new RootEntry(type, size, mtimeSeconds * 1000L, mode, name, path));
            } catch (RuntimeException ignored) {
                // Ignore one malformed record and continue with other files.
            }
        }
        return result;
    }

    private static Callable<byte[]> readAll(InputStream input) {
        return () -> {
            try (InputStream in = input; ByteArrayOutputStream out = new ByteArrayOutputStream()) {
                byte[] buffer = new byte[32 * 1024];
                int read;
                while ((read = in.read(buffer)) != -1) {
                    out.write(buffer, 0, read);
                }
                return out.toByteArray();
            }
        };
    }

    private static byte[] getFuture(Future<byte[]> future, long timeoutSeconds) {
        if (future == null) {
            return new byte[0];
        }
        try {
            return future.get(timeoutSeconds, TimeUnit.SECONDS);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        } catch (ExecutionException | TimeoutException ignored) {
        }
        return new byte[0];
    }

    static String encode(String value) {
        return Base64.encodeToString(value.getBytes(StandardCharsets.UTF_8), Base64.NO_WRAP);
    }

    static String decode(String value) {
        return new String(Base64.decode(value, Base64.DEFAULT), StandardCharsets.UTF_8);
    }

    private static String shellQuote(String value) {
        return "'" + value.replace("'", "'\\''") + "'";
    }
}
