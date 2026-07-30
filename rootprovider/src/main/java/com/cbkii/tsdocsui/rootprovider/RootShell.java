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
    static final String HELPER = "/data/adb/ts-docsui/rootfs-helper.sh";
    private static final String TAG = "TS18RootProvider";
    private static final long DEFAULT_TIMEOUT_SECONDS = 4L;
    private static final long LIST_TIMEOUT_SECONDS = 8L;
    private static final ExecutorService IO_EXECUTOR = Executors.newCachedThreadPool(runnable -> {
        Thread thread = new Thread(runnable, "ts-docsui-root-shell-io");
        thread.setDaemon(true);
        return thread;
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
            if (!process.waitFor(timeoutSeconds, TimeUnit.SECONDS)) {
                process.destroy();
                if (!process.waitFor(2, TimeUnit.SECONDS)) {
                    process.destroyForcibly();
                }
                return new Result(124, getFuture(stdoutFuture, 1), getFuture(stderrFuture, 1), true);
            }
            return new Result(
                    process.exitValue(),
                    getFuture(stdoutFuture, 2),
                    getFuture(stderrFuture, 2),
                    false);
        } catch (IOException failure) {
            return failureResult(failure);
        } catch (InterruptedException failure) {
            Thread.currentThread().interrupt();
            return failureResult(failure);
        } finally {
            closeProcessStreams(process);
        }
    }

    static Process start(String action, String... args) throws IOException {
        StringBuilder command = new StringBuilder();
        command.append("exec ")
                .append(shellQuote(HELPER))
                .append(' ')
                .append(shellQuote(action));
        for (String arg : args) {
            command.append(' ').append(shellQuote(encode(arg)));
        }
        return new ProcessBuilder(findSuBinary(), "-c", command.toString()).start();
    }

    static boolean ping() {
        Result result = run(4, "ping");
        if (!result.ok()) {
            Log.w(TAG, "Root helper ping failed: exit=" + result.exitCode
                    + " err=" + result.stderrText());
        }
        return result.ok() && result.stdoutText().contains("uid=0");
    }

    static RootEntry stat(String path) {
        Result result = run(4, "stat", path);
        if (!result.ok()) {
            return null;
        }
        List<RootEntry> entries = parseEntries(result.stdoutText());
        return entries.isEmpty() ? null : entries.get(0);
    }

    static List<RootEntry> list(String path) {
        Result result = run(LIST_TIMEOUT_SECONDS, "list", path);
        return result.ok() ? parseEntries(result.stdoutText()) : Collections.emptyList();
    }

    static long availableBytes(String path) {
        Result result = run(3, "df", path);
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
        return decodedResult("create", run("create", parentPath, displayName, directory ? "dir" : "file"));
    }

    static String rename(String path, String displayName) throws IOException {
        return decodedResult("rename", run("rename", path, displayName));
    }

    static void delete(String path) throws IOException {
        requireSuccess("delete", run("delete", path));
    }

    static void copyOut(String sourcePath, File destination, int ownerUid) throws IOException {
        requireSuccess(
                "copyout",
                run(60, "copyout", sourcePath, destination.getAbsolutePath(), Integer.toString(ownerUid)));
    }

    static void copyIn(File source, String destinationPath) throws IOException {
        requireSuccess("copyin", run(60, "copyin", source.getAbsolutePath(), destinationPath));
    }

    static void copy(String sourcePath, String targetParentPath) throws IOException {
        requireSuccess("copy", run(60, "copy", sourcePath, targetParentPath));
    }

    static String move(String sourcePath, String targetParentPath) throws IOException {
        return decodedResult("move", run(60, "move", sourcePath, targetParentPath));
    }

    static String encode(String value) {
        return Base64.encodeToString(value.getBytes(StandardCharsets.UTF_8), Base64.NO_WRAP);
    }

    static String decode(String value) {
        return new String(Base64.decode(value, Base64.DEFAULT), StandardCharsets.UTF_8);
    }

    private static Result failureResult(Exception failure) {
        return new Result(
                126,
                new byte[0],
                failure.toString().getBytes(StandardCharsets.UTF_8),
                false);
    }

    private static void closeProcessStreams(Process process) {
        if (process == null) {
            return;
        }
        try {
            process.getInputStream().close();
        } catch (IOException ignored) {
            // Process cleanup is best effort after its result has already been captured.
        }
        try {
            process.getErrorStream().close();
        } catch (IOException ignored) {
            // Process cleanup is best effort after its result has already been captured.
        }
        try {
            process.getOutputStream().close();
        } catch (IOException ignored) {
            // Process cleanup is best effort after its result has already been captured.
        }
    }

    private static String findSuBinary() {
        String[] candidates = {
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

    private static String decodedResult(String action, Result result) throws IOException {
        requireSuccess(action, result);
        return decode(result.stdoutText().trim());
    }

    private static void requireSuccess(String action, Result result) throws IOException {
        if (!result.ok()) {
            throw new IOException(errorMessage(action, result));
        }
    }

    private static String errorMessage(String action, Result result) {
        String error = result.stderrText().trim();
        if (error.isEmpty()) {
            error = result.stdoutText().trim();
        }
        if (error.isEmpty()) {
            error = result.timedOut ? "timed out" : "exit " + result.exitCode;
        }
        return action + " failed: " + error;
    }

    private static List<RootEntry> parseEntries(String text) {
        List<RootEntry> result = new ArrayList<>();
        for (String line : text.split("\n")) {
            if (line.isEmpty()) {
                continue;
            }
            String[] fields = line.split("\t", -1);
            if (fields.length < 6) {
                continue;
            }
            try {
                result.add(new RootEntry(
                        fields[0],
                        Long.parseLong(fields[1]),
                        Long.parseLong(fields[2]) * 1000L,
                        fields[3],
                        decode(fields[4]),
                        decode(fields[5])));
            } catch (RuntimeException ignored) {
                // Ignore one malformed helper record and continue with other entries.
            }
        }
        return result;
    }

    private static Callable<byte[]> readAll(InputStream input) {
        return () -> {
            try (InputStream source = input; ByteArrayOutputStream output = new ByteArrayOutputStream()) {
                byte[] buffer = new byte[32 * 1024];
                int read;
                while ((read = source.read(buffer)) != -1) {
                    output.write(buffer, 0, read);
                }
                return output.toByteArray();
            }
        };
    }

    private static byte[] getFuture(Future<byte[]> future, long timeoutSeconds) {
        if (future == null) {
            return new byte[0];
        }
        try {
            return future.get(timeoutSeconds, TimeUnit.SECONDS);
        } catch (InterruptedException failure) {
            Thread.currentThread().interrupt();
        } catch (ExecutionException | TimeoutException ignored) {
            // Preserve the bounded provider call even if output collection failed.
        }
        return new byte[0];
    }

    private static String shellQuote(String value) {
        return "'" + value.replace("'", "'\\''") + "'";
    }
}
