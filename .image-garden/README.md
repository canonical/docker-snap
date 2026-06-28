# Image garden cache

This directory contains Image Garden data, such as scripts, logs or the virtual machine filesystems.

Everything in this directory is automatically generated when running the tests and should not be checked in the source control system.

You can safely delete everything in this directory to free some disk space (well, except for this readme and the `.gitignore` file), or you let the tool do the work for you:

### Clean

Removes all generated images, logs, and support files from the current directory without removing downloaded base images from the cache

```bash
image-garden make clean
```

### Distclean

Like `clean`, but also removes downloaded base images from the cache directory. Only use this if you need to reclaim disk space.

```bash
image-garden make distclean
```
