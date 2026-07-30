package com.cbkii.tsdocsui.rootprovider;

import android.content.Context;
import android.content.SharedPreferences;
import android.database.Cursor;
import android.database.MatrixCursor;
import android.net.Uri;
import android.os.CancellationSignal;
import android.os.Handler;
import android.os.HandlerThread;
import android.os.ParcelFileDescriptor;
import android.os.StatFs;
import android.provider.DocumentsContract;
import android.provider.DocumentsContract.Document;
import android.provider.DocumentsContract.Root;
import android.provider.DocumentsProvider;
import android.util.Log;
import android.webkit.MimeTypeMap;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileNotFoundException;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * TS18 DocumentsProvider that keeps picker discovery rootless and uses the bounded Magisk helper
 * only after a user opens content that the provider process cannot access directly.
 */
public final class RootDocumentsProvider extends DocumentsProvider {
    public static final String AUTHORITY = "com.cbkii.tsdocsui.root.documents";

    private static final String ROOT_DEVICE = "device";
    private static final String ROOT_INTERNAL = "internal";
    private static final String ROOT_USB0 = "usb0";
    private static final String ROOT_USB1 = "usb1";
    private static final String PREFS = "provider";
    private static final String TAG = "TS18RootProvider";
    private static final String DEFAULT_STAGE_DIR =
            "/storage/emulated/0/.ts-docsui-root-provider";
    private static final long DEFAULT_STAGE_LIMIT_BYTES = 256L * 1024L * 1024L;

    private static final String[] DEFAULT_ROOT_PROJECTION = {
            Root.COLUMN_ROOT_ID,
            Root.COLUMN_MIME_TYPES,
            Root.COLUMN_FLAGS,
            Root.COLUMN_ICON,
            Root.COLUMN_TITLE,
            Root.COLUMN_SUMMARY,
            Root.COLUMN_DOCUMENT_ID,
            Root.COLUMN_AVAILABLE_BYTES
    };

    private static final String[] DEFAULT_DOCUMENT_PROJECTION = {
            Document.COLUMN_DOCUMENT_ID,
            Document.COLUMN_MIME_TYPE,
            Document.COLUMN_DISPLAY_NAME,
            Document.COLUMN_LAST_MODIFIED,
            Document.COLUMN_FLAGS,
            Document.COLUMN_SIZE,
            Document.COLUMN_SUMMARY
    };

    private final ExecutorService streamExecutor = Executors.newCachedThreadPool(runnable -> {
        Thread thread = new Thread(runnable, "ts-docsui-root-provider-stream");
        thread.setDaemon(true);
        return thread;
    });

    private HandlerThread closeThread;
    private Handler closeHandler;

    @Override
    public boolean onCreate() {
        closeThread = new HandlerThread("ts-docsui-root-provider-close");
        closeThread.start();
        closeHandler = new Handler(closeThread.getLooper());
        return true;
    }

    /** Picker discovery must never invoke su or wait for a root policy prompt. */
    @Override
    public Cursor queryRoots(String[] projection) {
        MatrixCursor cursor = new MatrixCursor(resolveRootProjection(projection));
        SharedPreferences preferences = prefs();
        if (preferences.getBoolean("showInternal", true)) {
            addFastRoot(
                    cursor,
                    ROOT_INTERNAL,
                    "/storage/emulated/0",
                    getString(R.string.root_internal),
                    false);
        }
        if (preferences.getBoolean("showDevice", true)) {
            addFastRoot(cursor, ROOT_DEVICE, "/", getString(R.string.root_device), true);
        }
        if (preferences.getBoolean("showUsb", true)) {
            addFastRoot(cursor, ROOT_USB0, "/storage/usbdisk0", getString(R.string.root_usb0), false);
            addFastRoot(cursor, ROOT_USB1, "/storage/usbdisk1", getString(R.string.root_usb1), false);
        }
        return cursor;
    }

    @Override
    public Cursor queryDocument(String documentId, String[] projection)
            throws FileNotFoundException {
        ParsedId parsed = parseDocumentId(documentId);
        MatrixCursor cursor = new MatrixCursor(resolveDocumentProjection(projection));
        includeDocument(cursor, parsed.rootId, requireEntry(parsed));
        return cursor;
    }

    @Override
    public Cursor queryChildDocuments(
            String parentDocumentId, String[] projection, String sortOrder)
            throws FileNotFoundException {
        MatrixCursor cursor = new MatrixCursor(resolveDocumentProjection(projection));
        ParsedId parent = parseDocumentId(parentDocumentId);
        RootEntry parentEntry = requireEntry(parent);
        if (!parentEntry.isDirectory()) {
            throw new FileNotFoundException("Not a directory: " + parent.path);
        }
        for (RootEntry child : listEntries(parent)) {
            includeDocument(cursor, parent.rootId, child);
        }
        return cursor;
    }

    @Override
    public String createDocument(String parentDocumentId, String mimeType, String displayName)
            throws FileNotFoundException {
        ensureAllowed("allowCreate", "Create");
        ParsedId parent = parseDocumentId(parentDocumentId);
        try {
            String path = RootShell.create(
                    parent.path,
                    validateDisplayName(displayName),
                    Document.MIME_TYPE_DIR.equals(mimeType));
            notifyChildren(parentDocumentId);
            return buildDocumentId(parent.rootId, path);
        } catch (IOException failure) {
            throw fileNotFound("Create failed", failure);
        }
    }

    @Override
    public void deleteDocument(String documentId) throws FileNotFoundException {
        ensureAllowed("allowDelete", "Delete");
        ParsedId parsed = parseDocumentId(documentId);
        ensureNotRootDocument(parsed);
        try {
            RootShell.delete(parsed.path);
            notifyDocument(documentId);
        } catch (IOException failure) {
            throw fileNotFound("Delete failed", failure);
        }
    }

    @Override
    public String renameDocument(String documentId, String displayName)
            throws FileNotFoundException {
        ensureAllowed("allowRename", "Rename");
        ParsedId parsed = parseDocumentId(documentId);
        ensureNotRootDocument(parsed);
        try {
            String path = RootShell.rename(parsed.path, validateDisplayName(displayName));
            String renamedId = buildDocumentId(parsed.rootId, path);
            notifyDocument(documentId);
            notifyDocument(renamedId);
            return renamedId;
        } catch (IOException failure) {
            throw fileNotFound("Rename failed", failure);
        }
    }

    @Override
    public String copyDocument(String sourceDocumentId, String targetParentDocumentId)
            throws FileNotFoundException {
        ensureAllowed("allowCreate", "Copy");
        ParsedId source = parseDocumentId(sourceDocumentId);
        ParsedId target = parseDocumentId(targetParentDocumentId);
        try {
            RootShell.copy(source.path, target.path);
            String path = new File(target.path, new File(source.path).getName()).getAbsolutePath();
            notifyChildren(targetParentDocumentId);
            return buildDocumentId(target.rootId, path);
        } catch (IOException failure) {
            throw fileNotFound("Copy failed", failure);
        }
    }

    @Override
    public String moveDocument(
            String sourceDocumentId,
            String sourceParentDocumentId,
            String targetParentDocumentId)
            throws FileNotFoundException {
        ensureAllowed("allowRename", "Move");
        ParsedId source = parseDocumentId(sourceDocumentId);
        ParsedId target = parseDocumentId(targetParentDocumentId);
        try {
            String path = RootShell.move(source.path, target.path);
            notifyChildren(sourceParentDocumentId);
            notifyChildren(targetParentDocumentId);
            return buildDocumentId(target.rootId, path);
        } catch (IOException failure) {
            throw fileNotFound("Move failed", failure);
        }
    }

    @Override
    public boolean isChildDocument(String parentDocumentId, String documentId) {
        try {
            ParsedId parent = parseDocumentId(parentDocumentId);
            ParsedId child = parseDocumentId(documentId);
            if (!parent.rootId.equals(child.rootId)) {
                return false;
            }
            String parentPath = normalizePath(parent.path);
            String childPath = normalizePath(child.path);
            return parentPath.equals(childPath)
                    || childPath.startsWith(parentPath.endsWith("/") ? parentPath : parentPath + "/");
        } catch (FileNotFoundException ignored) {
            return false;
        }
    }

    @Override
    public String getDocumentType(String documentId) throws FileNotFoundException {
        return mimeType(requireEntry(parseDocumentId(documentId)));
    }

    @Override
    public ParcelFileDescriptor openDocument(
            String documentId, String mode, CancellationSignal signal)
            throws FileNotFoundException {
        ParsedId parsed = parseDocumentId(documentId);
        RootEntry entry = requireEntry(parsed);
        if (entry.isDirectory()) {
            throw new FileNotFoundException("Cannot open a directory: " + parsed.path);
        }
        boolean writable = isWritableMode(mode);
        if (writable && !prefs().getBoolean("allowWrite", true)) {
            throw new FileNotFoundException("Writing is disabled by module config");
        }
        long stageLimit = prefs().getLong("stageLimitBytes", DEFAULT_STAGE_LIMIT_BYTES);
        if (!writable && (!entry.isRegularFile() || entry.size > stageLimit)) {
            return openReadPipe(parsed.path, signal);
        }
        if (writable && !entry.isRegularFile()) {
            throw new FileNotFoundException("This entry cannot be edited as a regular file");
        }
        if (writable && entry.size > stageLimit && entry.size > 0) {
            throw new FileNotFoundException(
                    "File is too large for root write staging: " + entry.size + " bytes");
        }
        return openStaged(parsed.path, mode, writable, signal);
    }

    private ParcelFileDescriptor openStaged(
            String sourcePath, String mode, boolean writable, CancellationSignal signal)
            throws FileNotFoundException {
        String configured = prefs().getString("stageDir", DEFAULT_STAGE_DIR);
        if (configured == null
                || !normalizePath(configured).startsWith("/storage/emulated/0/")) {
            configured = DEFAULT_STAGE_DIR;
        }
        File directory = new File(configured);
        if (!directory.isDirectory() && !directory.mkdirs()) {
            throw new FileNotFoundException("Cannot create shared provider staging directory");
        }

        final File stage;
        try {
            stage = File.createTempFile("root-", ".stage", directory);
        } catch (IOException failure) {
            throw fileNotFound("Cannot create shared staging file", failure);
        }

        try {
            if (shouldStageExistingContent(mode) && !copyOutLocally(sourcePath, stage)) {
                // A failed root copy aborts the open before an empty stage can replace source data.
                RootShell.copyOut(sourcePath, stage, android.os.Process.myUid());
            }
            if (signal != null) {
                signal.throwIfCanceled();
            }
            int parsedMode = ParcelFileDescriptor.parseMode(mode);
            return ParcelFileDescriptor.open(stage, parsedMode, closeHandler, error -> {
                try {
                    if (writable && error == null) {
                        RootShell.copyIn(stage, sourcePath);
                    } else if (writable) {
                        Log.w(TAG, "Discarding staged write after client close error for " + sourcePath, error);
                    }
                } catch (IOException failure) {
                    Log.e(TAG, "Failed to copy staged write back to " + sourcePath, failure);
                } finally {
                    //noinspection ResultOfMethodCallIgnored
                    stage.delete();
                }
            });
        } catch (IOException | RuntimeException failure) {
            //noinspection ResultOfMethodCallIgnored
            stage.delete();
            throw fileNotFound("Open failed", failure);
        }
    }

    private ParcelFileDescriptor openReadPipe(String sourcePath, CancellationSignal signal)
            throws FileNotFoundException {
        try {
            ParcelFileDescriptor[] pipe = ParcelFileDescriptor.createReliablePipe();
            ParcelFileDescriptor readSide = pipe[0];
            ParcelFileDescriptor writeSide = pipe[1];
            streamExecutor.execute(() -> streamRootFile(sourcePath, signal, writeSide));
            return readSide;
        } catch (IOException failure) {
            throw fileNotFound("Pipe open failed", failure);
        }
    }

    private void streamRootFile(
            String sourcePath, CancellationSignal signal, ParcelFileDescriptor writeSide) {
        Process process = null;
        OutputStream output = null;
        try {
            output = new ParcelFileDescriptor.AutoCloseOutputStream(writeSide);
            process = RootShell.start("stream-read", sourcePath);
            byte[] buffer = new byte[64 * 1024];
            int count;
            while ((count = process.getInputStream().read(buffer)) != -1) {
                if (signal != null) {
                    signal.throwIfCanceled();
                }
                output.write(buffer, 0, count);
            }
            output.flush();
            int result = process.waitFor();
            if (result != 0) {
                throw new IOException("Root read failed with exit " + result);
            }
        } catch (Exception failure) {
            try {
                writeSide.closeWithError(failure.toString());
            } catch (IOException ignored) {
                // The descriptor may already be closed by the client.
            }
        } finally {
            if (output != null) {
                try {
                    output.close();
                } catch (IOException ignored) {
                    // Descriptor cleanup is best effort after stream completion.
                }
            }
            if (process != null) {
                process.destroy();
            }
        }
    }

    private static boolean copyOutLocally(String sourcePath, File destination) {
        File source = new File(sourcePath);
        if (!source.isFile() || !source.canRead()) {
            return false;
        }
        try (InputStream input = new FileInputStream(source);
             OutputStream output = new FileOutputStream(destination, false)) {
            byte[] buffer = new byte[64 * 1024];
            int count;
            while ((count = input.read(buffer)) != -1) {
                output.write(buffer, 0, count);
            }
            output.flush();
            return true;
        } catch (IOException | SecurityException failure) {
            Log.d(TAG, "Direct stage initialisation unavailable for " + sourcePath, failure);
            return false;
        }
    }

    private void addFastRoot(
            MatrixCursor cursor, String rootId, String path, String title, boolean alwaysPresent) {
        RootEntry entry = localEntry(path);
        if (!alwaysPresent && (entry == null || !entry.isDirectory())) {
            return;
        }
        if (entry == null) {
            entry = syntheticRootEntry(path);
        }
        MatrixCursor.RowBuilder row = cursor.newRow();
        row.add(Root.COLUMN_ROOT_ID, rootId);
        row.add(Root.COLUMN_MIME_TYPES, "*/*");
        row.add(
                Root.COLUMN_FLAGS,
                Root.FLAG_LOCAL_ONLY | Root.FLAG_SUPPORTS_CREATE | Root.FLAG_SUPPORTS_IS_CHILD);
        row.add(Root.COLUMN_ICON, 0);
        row.add(Root.COLUMN_TITLE, title);
        row.add(Root.COLUMN_SUMMARY, path);
        row.add(Root.COLUMN_DOCUMENT_ID, buildDocumentId(rootId, path));
        row.add(Root.COLUMN_AVAILABLE_BYTES, localAvailableBytes(path));
    }

    private RootEntry requireEntry(ParsedId parsed) throws FileNotFoundException {
        RootEntry entry = entryFor(parsed);
        if (entry == null) {
            throw new FileNotFoundException("Path is unavailable: " + parsed.path);
        }
        return entry;
    }

    private RootEntry entryFor(ParsedId parsed) {
        RootEntry local = localEntry(parsed.path);
        if (local != null) {
            return local;
        }
        if (isRootPath(parsed.rootId, parsed.path)) {
            return syntheticRootEntry(parsed.path);
        }
        return RootShell.stat(parsed.path);
    }

    private List<RootEntry> listEntries(ParsedId parent) {
        // Keep initial root discovery local. Deeper root-only directories use the helper.
        if (!ROOT_DEVICE.equals(parent.rootId) || "/".equals(parent.path)) {
            List<RootEntry> local = localChildren(parent.path);
            if (local != null) {
                return local;
            }
        }
        return RootShell.list(parent.path);
    }

    private void includeDocument(MatrixCursor cursor, String rootId, RootEntry entry) {
        SharedPreferences preferences = prefs();
        boolean rootDocument = isRootPath(rootId, entry.path);
        int flags = 0;
        if (entry.isDirectory()) {
            if (preferences.getBoolean("allowCreate", true)) {
                flags |= Document.FLAG_DIR_SUPPORTS_CREATE;
            }
        } else if (preferences.getBoolean("allowWrite", true)) {
            flags |= Document.FLAG_SUPPORTS_WRITE;
        }
        if (!rootDocument && preferences.getBoolean("allowDelete", true)) {
            flags |= Document.FLAG_SUPPORTS_DELETE;
        }
        if (!rootDocument && preferences.getBoolean("allowRename", true)) {
            flags |= Document.FLAG_SUPPORTS_RENAME | Document.FLAG_SUPPORTS_MOVE;
        }
        if (!rootDocument && preferences.getBoolean("allowCreate", true)) {
            flags |= Document.FLAG_SUPPORTS_COPY;
        }

        MatrixCursor.RowBuilder row = cursor.newRow();
        row.add(Document.COLUMN_DOCUMENT_ID, buildDocumentId(rootId, entry.path));
        row.add(Document.COLUMN_MIME_TYPE, mimeType(entry));
        row.add(Document.COLUMN_DISPLAY_NAME, displayName(entry));
        row.add(Document.COLUMN_LAST_MODIFIED, entry.modifiedMillis);
        row.add(Document.COLUMN_FLAGS, flags);
        row.add(Document.COLUMN_SIZE, entry.isDirectory() ? null : entry.size);
        row.add(Document.COLUMN_SUMMARY, entry.path);
    }

    private static RootEntry localEntry(String path) {
        File file = new File(path);
        if (!file.exists()) {
            return null;
        }
        String type = file.isDirectory() ? "d" : file.isFile() ? "f" : "o";
        String name = "/".equals(path) ? "/" : file.getName();
        return new RootEntry(
                type,
                file.isFile() ? file.length() : 0L,
                file.lastModified(),
                "local",
                name,
                normalizePath(file.getAbsolutePath()));
    }

    private static List<RootEntry> localChildren(String path) {
        File[] files = new File(path).listFiles();
        if (files == null) {
            return null;
        }
        Arrays.sort(files, Comparator.comparing(File::getName, String.CASE_INSENSITIVE_ORDER));
        List<RootEntry> entries = new ArrayList<>(files.length);
        for (File file : files) {
            RootEntry entry = localEntry(file.getAbsolutePath());
            if (entry != null) {
                entries.add(entry);
            }
        }
        return entries;
    }

    private static RootEntry syntheticRootEntry(String path) {
        String normalized = normalizePath(path);
        String name = "/".equals(normalized) ? "/" : new File(normalized).getName();
        return new RootEntry("d", 0L, 0L, "root", name, normalized);
    }

    private static long localAvailableBytes(String path) {
        try {
            return new StatFs(path).getAvailableBytes();
        } catch (RuntimeException ignored) {
            return -1L;
        }
    }

    private String mimeType(RootEntry entry) {
        if (entry.isDirectory()) {
            return Document.MIME_TYPE_DIR;
        }
        String name = entry.name == null ? "" : entry.name;
        int dot = name.lastIndexOf('.');
        if (dot > 0 && dot < name.length() - 1) {
            String extension = name.substring(dot + 1).toLowerCase(Locale.ROOT);
            String mime = MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension);
            if (mime != null) {
                return mime;
            }
        }
        return "application/octet-stream";
    }

    private String displayName(RootEntry entry) {
        if ("/".equals(entry.path)) {
            return getString(R.string.root_device);
        }
        return entry.name == null || entry.name.isEmpty() ? entry.path : entry.name;
    }

    private void ensureAllowed(String key, String operation) throws FileNotFoundException {
        if (!prefs().getBoolean(key, true)) {
            throw new FileNotFoundException(operation + " is disabled by module config");
        }
    }

    private void ensureNotRootDocument(ParsedId parsed) throws FileNotFoundException {
        if (isRootPath(parsed.rootId, parsed.path)) {
            throw new FileNotFoundException("The provider root cannot be changed");
        }
    }

    private boolean isRootPath(String rootId, String path) {
        String rootPath = roots().get(rootId);
        return rootPath != null && normalizePath(rootPath).equals(normalizePath(path));
    }

    private static Map<String, String> roots() {
        Map<String, String> roots = new LinkedHashMap<>();
        roots.put(ROOT_INTERNAL, "/storage/emulated/0");
        roots.put(ROOT_DEVICE, "/");
        roots.put(ROOT_USB0, "/storage/usbdisk0");
        roots.put(ROOT_USB1, "/storage/usbdisk1");
        return roots;
    }

    private static String buildDocumentId(String rootId, String path) {
        return rootId + ":" + RootShell.encode(normalizePath(path));
    }

    private static ParsedId parseDocumentId(String documentId) throws FileNotFoundException {
        int separator = documentId.indexOf(':');
        if (separator <= 0 || separator == documentId.length() - 1) {
            throw new FileNotFoundException("Invalid document ID");
        }
        String rootId = documentId.substring(0, separator);
        String rootPath = roots().get(rootId);
        if (rootPath == null) {
            throw new FileNotFoundException("Unknown root: " + rootId);
        }
        final String path;
        try {
            path = normalizePath(RootShell.decode(documentId.substring(separator + 1)));
        } catch (RuntimeException failure) {
            throw fileNotFound("Invalid document ID encoding", failure);
        }
        String normalizedRoot = normalizePath(rootPath);
        if (!ROOT_DEVICE.equals(rootId)
                && !path.equals(normalizedRoot)
                && !path.startsWith(
                        normalizedRoot.endsWith("/") ? normalizedRoot : normalizedRoot + "/")) {
            throw new FileNotFoundException("Document is outside its root");
        }
        return new ParsedId(rootId, path);
    }

    private static String normalizePath(String path) {
        if (path == null || path.isEmpty()) {
            return "/";
        }
        String value = path.replaceAll("/+", "/");
        if (!value.startsWith("/")) {
            value = "/" + value;
        }
        while (value.length() > 1 && value.endsWith("/")) {
            value = value.substring(0, value.length() - 1);
        }
        List<String> parts = new ArrayList<>();
        for (String part : value.split("/")) {
            if (part.isEmpty() || ".".equals(part)) {
                continue;
            }
            if ("..".equals(part)) {
                if (!parts.isEmpty()) {
                    parts.remove(parts.size() - 1);
                }
            } else {
                parts.add(part);
            }
        }
        return "/" + String.join("/", parts);
    }

    private static String validateDisplayName(String displayName)
            throws FileNotFoundException {
        if (displayName == null) {
            throw new FileNotFoundException("Name is missing");
        }
        String value = displayName.trim();
        if (value.isEmpty()
                || ".".equals(value)
                || "..".equals(value)
                || value.contains("/")
                || value.indexOf('\u0000') >= 0) {
            throw new FileNotFoundException("Invalid name");
        }
        return value;
    }

    private static boolean isWritableMode(String mode) {
        return mode != null && (mode.contains("w") || mode.contains("a") || mode.contains("+"));
    }

    private static boolean shouldStageExistingContent(String mode) {
        return mode == null || !("w".equals(mode) || "wt".equals(mode) || "rwt".equals(mode));
    }

    private SharedPreferences prefs() {
        Context context = getContext();
        if (context == null) {
            throw new IllegalStateException("Provider context unavailable");
        }
        return context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }

    private String getString(int id) {
        Context context = getContext();
        return context == null ? "TS18 storage" : context.getString(id);
    }

    private static String[] resolveRootProjection(String[] projection) {
        return projection == null ? DEFAULT_ROOT_PROJECTION : projection;
    }

    private static String[] resolveDocumentProjection(String[] projection) {
        return projection == null ? DEFAULT_DOCUMENT_PROJECTION : projection;
    }

    private void notifyDocument(String documentId) {
        Context context = getContext();
        if (context != null) {
            Uri uri = DocumentsContract.buildDocumentUri(AUTHORITY, documentId);
            context.getContentResolver().notifyChange(uri, null);
        }
    }

    private void notifyChildren(String parentDocumentId) {
        Context context = getContext();
        if (context != null) {
            Uri uri = DocumentsContract.buildChildDocumentsUri(AUTHORITY, parentDocumentId);
            context.getContentResolver().notifyChange(uri, null);
        }
    }

    private static FileNotFoundException fileNotFound(String message, Exception cause) {
        FileNotFoundException failure =
                new FileNotFoundException(message + ": " + cause.getMessage());
        failure.initCause(cause);
        return failure;
    }

    private static final class ParsedId {
        final String rootId;
        final String path;

        ParsedId(String rootId, String path) {
            this.rootId = rootId;
            this.path = path;
        }
    }
}
