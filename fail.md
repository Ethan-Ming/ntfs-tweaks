# NTFS Performance Tuning - Findings & Failure Analysis

This document summarizes the attempts to optimize NTFS performance on a USB 2.0 HDD and the causes of subsequent failures.

## 1. The "Golden State" (v2/v3)
*   **Version:** v2 (Balanced) / v3 (Removable/HDD Tuning)
*   **Result:** Sequential Read **~110-154 MB/s** (RAM Cache enabled).
*   **Result:** Sequential Write **~136 MB/s**.
*   **Status:** Successful sequentially, but poor random 4K performance (~0.3 MB/s).
*   **Configuration:**
    *   Driver: `ntfs3`
    *   Mounting Tool: Direct `mount` command or OS defaults (via File Manager).
    *   Key Performance Factor: **4MB Read-Ahead** (`blockdev --setra 4096`).
    *   Caching: Relied on default Linux `async` behavior.

## 2. The Performance Regression (v4/v5/v6)
*   **Observation:** Sequential performance dropped to **~32-42 MB/s** (raw hardware limit).
*   **The Cause:** Introduction of "Safety" measures:
    1.  **Aggressive Syncing:** `sysctl vm.dirty_expire_centisecs` set to low values (500) and explicit `sync` calls in scripts.
    2.  **Sync-on-Unmount:** This forced flush-to-disk behavior, bypassing the RAM cache benefit.
*   **Conclusion:** The perceived "boost" was 100% dependent on the Linux asynchronous write cache. Explicitly forcing safety removed the performance gain.

## 3. The Protocol Failure (v7/v8)
*   **The Goal:** Fix the "dirty disk" and "wrong permissions (uid=0)" issues by configuring `udisks2`.
*   **The Error:** `An invalid or malformed option has been given: Mount option 'async' [or 'prealloc' / 'windows_names'] is not allowed`.
*   **Root Cause Analysis:**
    *   **The Middleman (udisks2):** In v2, the File Manager used `udisks2` internal defaults for `ntfs3`, which are valid and naturally `async`.
    *   **The Injection Failure:** In v7/v8, we injected environment variables (`UDISKS_MOUNT_OPTIONS_DEFAULTS`) into the udev rule. 
    *   **Strict Validation:** `udisks2` has a strict internal whitelist of allowed mount options for the `ntfs3` driver profile. It considers `async`, `prealloc`, and `windows_names` to be "malformed" when passed as explicit parameters, even though the driver itself would support them.
    *   **The Result:** `udisks2` aborted the mount entirely, making the disk inaccessible until the custom rules were removed.

## 4. Key Takeaways
1.  **Read-Ahead is King:** For USB 2.0 HDDs, a large read-ahead buffer (4096KB) is the only way to significantly improve read throughput.
2.  **Safety vs. Speed:** Total "boosted" speed requires accepting asynchronous caching. If the disk is unplugged before a sync, it *will* be dirty.
3.  **Udisks2 Constraints:** OS-level auto-mounting is restricted by internal security validation. Direct `mount` commands (as in v2) bypass these restrictions but are harder for the end-user to manage.
