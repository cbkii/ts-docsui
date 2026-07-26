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
 * DocumentsProvider for TS18 storage that keeps picker discovery fast and delegates
 * root-only file operations to a bounded Magisk helper only after a root is opened.
 */
public final class RootDocumentsProvider extends DocumentsProvider {
    public static final String AUTHORITY = "com.cbkii.tsdocsui.root.documents";

    private static final String ROOT_DEVICE = "device";
    private static final String ROOT_INTERNAL = "internal";
    private static final String ROOT_USB0 = "usb0";
    private static final String ROOT_USB1 = "usb1";
    private static final String PREFS = "provider";
    private static final String TAG = "TS18RootProvider";
    private static final String DEFAULT_STAGE_DIR = "/storage/emulated/0/.TS18-Root-Provider";
    private static final long DEFAULT_STAGE_LIMIT_BYTES = 256L * 1024L * 1024L;

    private static final String[] DEFAULT_ROOT_PROJECTION = new String[] {
            Root.COLUMN_ROOT_ID,
            Root.COLUMN_MIME_TYPES,
            Root.COLUMN_FLAGS,
            Root.COLUMN_ICON,
            Root.COLUMN_TITLE,
            Root.COLUMN_SUMMARY,
            Root.COLUMN_DOCUMENT_ID,
            Root.COLUMN_AVAILABLE_BYTES
    };
    private static final String[] DEFAULT_DOCUMENT_PROJECTION = new String[] {
            Document.COLUMN_DOCUMENT_ID,
            Document.COLUMN_MIME_TYPE,
            Document.COLUMN_DISPLAY_NAME,
            Document.COLUMN_LAST_MODIFIED,
            Document.COLUMN_FLAGS,
            Document.COLUMN_SIZE,
            Document.COLUMN_SUMMARY
    };

    private final ExecutorService streamExecutor = Executors.newCachedThreadPool(r -> {
        Thread thread = new Thread(r, "ts18-root-provider-stream");
        thread.setDaemon(true);
        return thread;
    });

    private HandlerThread closeThread;
    private Handler closeHandler;

    @Override
    public boolean onCreate() {
        closeThread = new HandlerThread("ts18-root-provider-close");
        closeThread.start();
        closeHandler = new Handler(closeThread.getLooper());
        return true;
    }

    /**
     * Picker startup calls this for every DocumentsProvider. Never call su here: a missing
     * Magisk policy or root prompt would otherwise block the complete system picker.
     */
    @Override
    public Cursor queryRoots(String[] projection) {
        MatrixCursor cursor = new MatrixCursor(resolveRootProjection(projection));
        SharedPreferences prefs = prefs();

        if (prefs.getBoolean("showInternal", true)) {
            addFastRoot(cursor, ROOT_INTERNAL, "/storage/emulated/0", getString(R.string.root_internal), false);
        }
        if (prefs.getBoolean("showDevice", true)) {
            addFastRoot(cursor, ROOT_DEVICE, "/", getString(R.string.root_device), true);
        }
        if (prefs.getBoolean("showUsb", true)) {
            addFastRoot(cursor, ROOT_USB0, "/storage/usbdisk0", getString(R.string.root_usb0), false);
            addFastRoot(cursor, ROOT_USB1, "/storage/usbdisk1", getString(R.string.root_usb1), false);
        }
        return cursor;
    }

    @Override
    public Cursor queryDocument(String documentId, String[] projection) throws FileNotFoundException {
        MatrixCursor cursor = new MatrixCursor(resolveDocumentProjection(projection));
        ParsedId parsed = parseDocumentId(documentId);
        includeDocument(cursor, parsed.rootId, requireEntry(parsed));
        return cursor;
    }

    @Override
    public Cursor queryChildDocuments(String parentDocumentId, String[] projection, String sortOrder)
            throws FileNotFoundException {
        return queryChildDocumentsInternal(parentDocumentId, projection, null);
    }

    private Cursor queryChildDocumentsInternal(String parentDocumentId, String[] projection,
                                                CancellationSignal signal) throws FileNotFoundException {
        MatrixCursor cursor = new MatrixCursor(resolveDocumentProjection(projection));
        ParsedId parent = parseDocumentId(parentDocumentId);
        RootEntry parentEntry = requireEntry(parent);
        if (!parentEntry.isDirectory()) {
            throw new FileNotFoundException("Not a directory: " + parent.path);
        }

        List<RootEntry> children = listEntries(parent);
        for (RootEntry child : children) {
            if (signal != null) {
                signal.throwIfCanceled();
            }
            includeDocument(cursor, parent.rootId, child);
        }
        return cursor;
    }

    @Override
    public String createDocument(String parentDocumentId, String mimeType, String displayName)
            throws FileNotFoundException {
        ensureCreateAllowed();
        ParsedId parent = parseDocumentId(parentDocumentId);
        String safeName = validateDisplayName(displayName);
        try {
            String created = RootShell.create(parent.path, safeName, Document.MIME_TYPE_DIR.equals(mimeType));
            notifyChildren(parentDocumentId);
            return buildDocumentId(parent.rootId, created);
        } catch (IOException e) {
            throw fileNotFound("Create failed", e);
        }
    }

    @Override
    public void deleteDocument(String documentId) throws FileNotFoundException {
        ensureDeleteAllowed();
        ParsedId parsed = parseDocumentId(documentId);
        ensureNotRootDocument(parsed);
        try {
            RootShell.delete(parsed.path);
            notifyDocument(documentId);
        } catch (IOException e) {
            throw fileNotFound("Delete failed", e);
        }
    }

    @Override
    public String renameDocument(String documentId, String displayName) throws FileNotFoundException {
        ensureRenameAllowed();
        ParsedId parsed = parseDocumentId(documentId);
        ensureNotRootDocument(parsed);
        try {
            String renamed = RootShell.rename(parsed.path, validateDisplayName(displayName));
            String newId = buildDocumentId(parsed.rootId, renamed);
            notifyDocument(documentId);
            notifyDocument(newId);
            return newId;
        } catch (IOException e) {
            throw fileNotFound("Rename failed", e);
        }
    }

    @Override
    public String copyDocument(String sourceDocumentId, String targetParentDocumentId)
            throws FileNotFoundException {
        ensureCreateAllowed();
        ParsedId source = parseDocumentId(sourceDocumentId);
        ParsedId target = parseDocumentId(targetParentDocumentId);
        try {
            RootShell.copy(source.path, target.path);
            String newPath = new File(target.path, new File(source.path).getName()).getAbsolutePath();
            notifyChildren(targetParentDocumentId);
            return buildDocumentId(target.rootId, newPath);
        } catch (IOException e) {
            throw fileNotFound("Copy failed", e);
        }
    }

    @Override
    public String moveDocument(String sourceDocumentId, String sourceParentDocumentId,
                               String targetParentDocumentId) throws FileNotFoundException {
        ensureRenameAllowed();
        ParsedId source = parseDocumentId(sourceDocumentId);
        ParsedId target = parseDocumentId(targetParentDocumentId);
        try {
            String moved = RootShell.move(source.path, target.path);
            notifyChildren(sourceParentDocumentId);
            notifyChildren(targetParentDocumentId);
            return buildDocumentId(target.rootId, moved);
        } catch (IOException e) {
            throw fileNotFound("Move failed", e);
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
            if (parentPath.equals(childPath)) {
                return true;
            }
            return childPath.startsWith(parentPath.endsWith("/") ? parentPath : parentPath + "/");
        } catch (FileNotFoundException ignored) {
            return false;
        }
    }

    @Override
    public String getDocumentType(String documentId) throws FileNotFoundException {
        ParsedId parsed = parseDocumentId(documentId);
        return mimeType(requireEntry(parsed));
    }

    @Override
    public ParcelFileDescriptor openDocument(String documentId, String mode,
                                              CancellationSignal signal) throws FileNotFoundException {
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
            throw new FileNotFoundException("This device entry cannot be edited as a regular file");
        }
        if (writable && entry.size > stageLimit && entry.size > 0) {
            throw new FileNotFoundException(
                    "File is too large for root write staging: " + entry.size + " bytes");
        }
        return openStaged(parsed.path, mode, writable, signal);
    }

    private ParcelFileDescriptor openStaged(String sourcePath, String mode, boolean writable,
                                             CancellationSignal signal) throws FileNotFoundException {
        String configuredStageDir = prefs().getString("stageDir", DEFAULT_STAGE_DIR);
        if (configuredStageDir == null
                || !normalizePath(configuredStageDir).startsWith("/storage/emulated/0/")) {
            configuredStageDir = DEFAULT_STAGE_DIR;
        }
        File stageDir = new File(configuredStageDir);
        if (!stageDir.isDirectory() && !stageDir.mkdirs()) {
            throw new FileNotFoundException("Cannot create shared provider staging directory");
        }

        final File stage;
        try {
            stage = File.createTempFile("root-", ".stage", stageDir);
        } catch (IOException e) {
            throw fileNotFound("Cannot create shared staging file", e);
        }

        try {
            if (shouldStageExistingContent(mode)
                    && !copyOutLocally(sourcePath, stage)) {
                // RootShell.copyOut throws on denial, timeout, or copy failure. Failing the open
                // prevents an empty stage from being served or copied back over existing data.
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
                    Log.e(TAG, "Failed to copy staged root write back to " + sourcePath, failure);
                } finally {
                    //noinspection ResultOfMethodCallIgnored
                    stage.delete();
                }
            });
        } catch (IOException | RuntimeException e) {
            //noinspection ResultOfMethodCallIgnored
            stage.delete();
            throw fileNotFound("Open failed", e);
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

    private ParcelFileDescriptor openReadPipe(String sourcePath, CancellationSignal signal)
            throws FileNotFoundException {
        try {
            ParcelFileDescriptor[] pipe = ParcelFileDescriptor.createReliablePipe();
            ParcelFileDescriptor readSide = pipe[0];
            ParcelFileDescriptor writeSide = pipe[1];
            streamExecutor.execute(() -> {
                Process rootProcess = null;
                OutputStream out = null;
                try {
                    out = new ParcelFileDescriptor.AutoCloseOutputStream(writeSide);
                    rootProcess = RootShell.start("stream-read", sourcePath);
                    byte[] buffer = new byte[64 * 1024];
                    int count;
                    while ((count = rootProcess.getInputStream().read(buffer)) != -1) {
                        if (signal != null) {
                            signal.throwIfCanceled();
                        }
                        out.write(buffer, 0, count);
                    }
                    out.flush();
                    int rc = rootProcess.waitFor();
                    if (rc != 0) {
                        throw new IOException("Root read failed with exit " + rc);
                    }
                } catch (Exception e) {
                    try {
                        writeSide.closeWithError(e.toString());
                    } catch (IOException ignored) {
                        // The descriptor may already be closed by the client.
                    }
                } finally {
                    if (out != null) {
                        try {
                            out.close();
                        } catch (IOException ignored) {
                            // Best-effort descriptor cleanup.
                        }
                    }
                    if (rootProcess != null) {
                        rootProcess.destroy();
                    }
                }
            });
            return readSide;
        } catch (IOException e) {
            throw fileNotFound("Pipe open failed", e);
        }
    }

    private void addFastRoot(MatrixCursor cursor, String rootId, String path, String title,
                             boolean alwaysPresent) {
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
        row.add(Root.COLUMN_FLAGS,
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
        // The device root itself is usually listable without privilege. Returning that shallow
        // level locally prevents DocumentsUI prefetch from invoking su during launch; deeper
        // root-only directories still use the bounded helper after the user opens them.
        if (!ROOT_DEVICE.equals(parent.rootId) || "/".equals(parent.path)) {
            List<RootEntry> local = localChildren(parent.path);
            if (local != null) {
                return local;
            }
        }
        return RootShell.list(parent.path);
    }

    private static RootEntry localEntry(String path) {
        File file = new File(path);
        if (!file.exists()) {
            return null;
        }
        String type;
        if (file.isDirectory()) {
            type = "d";
        } else if (file.isFile()) {
            type = "f";
        } else {
            type = "o";
        }
        String name = "/".equals(path) ? "/" : file.getName();
        return new RootEntry(type, file.isFile() ? file.length() : 0L,
                file.lastModified(), "local", name, normalizePath(file.getAbsolutePath()));
    }

    /** Returns null when direct app access cannot enumerate the directory. */
    private static List<RootEntry> localChildren(String path) {
        File directory = new File(path);
        File[] files = directory.listFiles();
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

    private void includeDocument(MatrixCursor cursor, String rootId, RootEntry entry) {
        SharedPreferences prefs = prefs();
        boolean rootDocument = isRootPath(rootId, entry.path);
        int flags = 0;
        if (entry.isDirectory()) {
            if (prefs.getBoolean("allowCreate", true)) {
                flags |= Document.FLAG_DIR_SUPPORTS_CREATE;
            }
        } else if (prefs.getBoolean("allowWrite", true)) {
            flags |= Document.FLAG_SUPPORTS_WRITE;
        }
        if (!rootDocument && prefs.getBoolean("allowDelete", true)) {
            flags |= Document.FLAG_SUPPORTS_DELETE;
        }
        if (!rootDocument && prefs.getBoolean("allowRename", true)) {
            flags |= Document.FLAG_SUPPORTS_RENAME | Document.FLAG_SUPPORTS_MOVE;
        }
        if (!rootDocument && prefs.getBoolean("allowCreate", true)) {
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

    private String mimeType(RootEntry entry) {
        if (entry.isDirectory()) {
            return Document.MIME_TYPE_DIR;
        }
        String name = entry.name == null ? "" : entry.name;
        int dot = name.lastIndexOf('.');
        if (dot > 0 && dot < name.length() - 1) {
            String ext = name.substring(dot + 1).toLowerCase(Locale.ROOT);
            String mime = MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext);
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

    private void ensureCreateAllowed() throws FileNotFoundException {
        if (!prefs().getBoolean("allowCreate", true)) {
            throw new FileNotFoundException("Create is disabled by module config");
        }
    }

    private void ensureDeleteAllowed() throws FileNotFoundException {
        if (!prefs().getBoolean("allowDelete", true)) {
            throw new FileNotFoundException("Delete is disabled by module config");
        }
    }

    private void ensureRenameAllowed() throws FileNotFoundException {
        if (!prefs().getBoolean("allowRename", true)) {
            throw new FileNotFoundException("Rename is disabled by module config");
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

    private Map<String, String> roots() {
        Map<String, String> roots = new LinkedHashMap<>();
        roots.put(ROOT_INTERNAL, "/storage/emulated/0");
        roots.put(ROOT_DEVICE, "/");
        roots.put(ROOT_USB0, "/storage/usbdisk0");
        roots.put(ROOT_USB1, "/storage/usbdisk1");
        return roots;
    }

    private String buildDocumentId(String rootId, String path) {
        return rootId + ":" + RootShell.encode(normalizePath(path));
    }

    private ParsedId parseDocumentId(String documentId) throws FileNotFoundException {
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
        } catch (RuntimeException e) {
            throw fileNotFound("Invalid document ID encoding", e);
        }
        String normalizedRoot = normalizePath(rootPath);
        if (!ROOT_DEVICE.equals(rootId)
                && !path.equals(normalizedRoot)
                && !path.startsWith(normalizedRoot.endsWith("/") ? normalizedRoot : normalizedRoot + "/")) {
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

    private static String validateDisplayName(String displayName) throws FileNotFoundException {
        if (displayName == null) {
            throw new FileNotFoundException("Name is missing");
        }
        String value = displayName.trim();
        if (value.isEmpty() || ".".equals(value) || "..".equals(value)
                || value.contains("/") || value.indexOf('\u0000') >= 0) {
            throw new FileNotFoundException("Invalid name");
        }
        return value;
    }

    private static boolean isWritableMode(String mode) {
        return mode != null && (mode.contains("w") || mode.contains("a") || mode.contains("+"));
    }

    private static boolean shouldStageExistingContent(String mode) {
        if (mode == null) {
            return true;
        }
        return !("w".equals(mode) || "wt".equals(mode) || "rwt".equals(mode));
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

    private String[] resolveRootProjection(String[] projection) {
        return projection == null ? DEFAULT_ROOT_PROJECTION : projection;
    }

    private String[] resolveDocumentProjection(String[] projection) {
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
        FileNotFoundException failure = new FileNotFoundException(message + ": " + cause.getMessage());
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
