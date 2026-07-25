package com.cbkii.tsdocsui.rootprovider;

final class RootEntry {
    final String type;
    final long size;
    final long modifiedMillis;
    final String mode;
    final String name;
    final String path;

    RootEntry(String type, long size, long modifiedMillis, String mode, String name, String path) {
        this.type = type;
        this.size = size;
        this.modifiedMillis = modifiedMillis;
        this.mode = mode;
        this.name = name;
        this.path = path;
    }

    boolean isDirectory() {
        return "d".equals(type);
    }

    boolean isRegularFile() {
        return "f".equals(type);
    }
}
