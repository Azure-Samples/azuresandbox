# Test Plan: extras/scripts/vm-mssql-win/NVMe against a sandbox `mssqlwin1`

> **Terminology:** throughout this plan, **"sandbox"** means **an Azure sandbox environment
> deployed from this repository** (`Azure-Samples/azuresandbox`) via `terraform apply` — i.e. the
> `vnet_shared` + `vnet_app` + `vm_mssql_win` (etc.) modules that stand up `adds1`, `mssqlwin1`,
> and friends. It does **not** refer to an Azure "sandbox" subscription/tenant offering or any
> other unrelated concept.
>
> **STATUS: REUSABLE TEST PLAN.** This plan tests the standalone NVMe ephemeral-storage extras
> against the `mssqlwin1` SQL Server VM of **any** freshly deployed sandbox (any region, any
> subscription). It is environment-agnostic: every resource identifier, region, VM size,
> domain, and secret is **discovered at run time** — there are no hardcoded dependencies on a
> particular deployment. The plan adds a **multi-size resize matrix** (1 → 2 → 4 local temp
> disks) to validate the extras striping/provisioning behavior across NVMe disk counts.
>
> **How to use:** deploy a sandbox from this repo with `vnet_app` + `vm_mssql_win` enabled and
> unit-tested, then work top-to-bottom: complete the pre-flight checklist (discovering all
> identifiers), run Pass A (1-disk install + deallocate validation), then Passes B and C (resize
> to 2- and 4-disk sizes and re-validate). The "Reference results" section near the end records
> one illustrative run for context only — your values (names, sizes, build numbers) will differ.
>
> ⚠️ **Resource identifiers are unique per deployment.** The resource group suffix, Key Vault
> name, private-endpoint IP, etc. are generated on each `terraform apply` — never assume the
> values from any prior run. Discover them all in the pre-flight / baseline phase before acting.

## Problem & approach

The standalone scripts in `./extras/scripts/vm-mssql-win/NVMe/` provide a self-contained
solution (scheduled task + startup script + tempdb-move T-SQL) to re-provision ephemeral
NVMe temp storage and start SQL Server after every stop/deallocate on an Azure SQL VM. This
functionality **duplicates** what the `vm_mssql_win` sandbox module already configures
automatically on `mssqlwin1`.

To test the extras scripts on the existing deployed sandbox we will:

1. **Disable the overlapping sandbox automation** on `mssqlwin1` so it does not race the extras
   task at boot.
2. **Reset tempdb off the ephemeral drive** (full end-to-end fidelity) back to the SQL default
   data path so the extras README flow (move tempdb → `T:\SQLTEMP`) is exercised as documented.
3. **Install + configure the extras scripts** per the README (`C:\Scripts\`, register task,
   move tempdb, restart SQL).
4. **Validate with a real stop/deallocate + start** cycle and confirm the extras scheduled task
   re-provisions `T:` and brings SQL online with tempdb on the ephemeral drive.
5. **Repeat across VM sizes with 1, 2, and 4 local temp disks** (via `az vm resize`, staying in
   the sandbox's deployed VM series) to validate the extras' multi-disk Storage Spaces striping
   behavior. The default sandbox size has **1** local temp disk; after the first pass we resize
   to a **2-disk** size in the same series and re-run the same validations, then to a **4-disk**
   size and re-run again. (The target sizes are **discovered** from the deployed VM's series — see
   the resize matrix below — not hardcoded.)

**No Terraform changes.** All mutations via `az` / Azure PowerShell. Sandbox drift is
acceptable (will be destroyed).

## VM resize test matrix (1 → 2 → 4 local temp disks)

**Stay within the deployed VM's own series** (discover it — do not assume a specific family). The
sandbox's `vm_mssql_win` default is a local-NVMe "d…ds_v_" size with **1** local temp disk; pick
the smallest sizes **in that same series** that have exactly **2** and **4** local temp disks.

**Discover the series and pick targets at run time** (region-independent):

```bash
# 1. Current size + its family:
az vm show -g <RG> -n mssqlwin1 --query hardwareProfile.vmSize -o tsv      # e.g. Standard_D4ds_v6
# 2. Local temp-disk count per size in that family, in the deployment region:
az vm list-skus -l <region> --resource-type virtualMachines \
  --query "[?family=='<familyName>'].{size:name, \
    nvme:to_number(capabilities[?name=='NvmeDiskSizeInMiB']|[0].value), \
    localGiB:capabilities[?name=='MaxResourceVolumeMB']|[0].value, \
    vCPU:capabilities[?name=='vCPUs']|[0].value}" -o table
```

Pick: **Pass A** = the deployed default (1 disk), **Pass B** = smallest same-series size with 2
local temp disks, **Pass C** = smallest same-series size with 4 local temp disks. (`az vm list-skus`
exposes per-size local-disk capability; cross-check with the Microsoft Learn "…ds_v_ sizes series"
local-storage table for the deployed family if the capability fields are sparse.)

**Worked example — Ddsv6 (Intel local-NVMe), the current default family.** If the sandbox deploys
this family, the targets resolve to:

| Pass | Example size | Local temp disks (NVMe Direct) | Per-disk | Aggregate `T:` stripe | vCPUs |
|---|---|---|---|---|---|
| **A** | `Standard_D4ds_v6` | **1** | 220 GiB | ~218 GiB (1-col) | 4 |
| **B** | `Standard_D16ds_v6` | **2** | 440 GiB | ~880 GiB (2-col stripe) | 16 |
| **C** | `Standard_D32ds_v6` | **4** | 440 GiB | ~1760 GiB (4-col stripe) | 32 |

(In Ddsv6, `D8ds_v6` still has only 1 disk and `D48ds_v6` has 6, hence D16/D32 are the 2-/4-disk
picks.) **If the deployed series differs, substitute the discovered sizes** — the rest of the plan
is written in terms of "N local temp disks", not specific size names.

**What the resize passes prove:** the extras `Set-MssqlStartupConfiguration.ps1` enumerates
**all** poolable `*NVMe Direct Disk*` disks and creates a Simple/RAID-0 Storage Space with
`NumberOfColumns = <disk count>`. Passes B and C confirm it correctly detects and stripes 2 and
4 local disks (not just the N=1 case), formats the larger aggregate volume, and reprovisions it
after deallocate — while the remote managed OS/data/log disks (`Virtual_Disk NVME Ultra/Premium`)
are correctly **excluded** from the pool.

**Key efficiency:** the tempdb catalog path (`T:\SQLTEMP`) is **stable across all sizes**, so
`Move-TempdbToEphemeral.sql` is run **once** (Pass A). In Passes B and C, tempdb simply comes
back online at the same `T:\SQLTEMP` path once the larger stripe is reprovisioned — no second
move needed.

## Environment characteristics & discovery (what to probe before executing)

These are the **invariant characteristics of any `vm_mssql_win` sandbox** the plan relies on,
each paired with how to discover/confirm it on the deployment under test. The right-hand column
shows **illustrative example values from one reference deployment** — treat them as the *shape* of
the answer, not literal truth for your sandbox.

| Item | How to discover / what to confirm | Example value (illustrative only) |
|---|---|---|
| Auth | `az account show`; `gh auth status` | signed-in to the sub hosting the sandbox; `gh` authed |
| Region | `az vm show -g <RG> -n mssqlwin1 --query location -o tsv` | (any region — e.g. `eastus2`) |
| Resource group | `az group list --query "[?starts_with(name,'rg-sand')].name"` (or your naming) | `rg-sand-dev-<suffix>` |
| VMs | `az vm list -g <RG> -d -o table` — `adds1` (DC), `mssqlwin1`, optionally `jumpwin1` | `adds1` running, `mssqlwin1` running |
| Image | `az vm show ... --query storageProfile.imageReference` — confirm WS2025 / SQL2025 | `MicrosoftSQLServer/sql2025-ws2025/entdev-gen2` |
| VM size / family | `az vm show ... --query hardwareProfile.vmSize` (drives the resize matrix) | local-NVMe `d…ds_v_`, **1** local temp disk |
| NVMe temp | on-VM: `Get-PhysicalDisk \| ? FriendlyName -like '*NVMe Direct Disk*'` | N local NVMe Direct Disk(s) → `T:` |
| Storage pool | on-VM: `Get-StoragePool` — module pool exists + Healthy; `T:\SQLTEMP` present | `StoragePool-Temp` (module), `T:\SQLTEMP` |
| Data/log paths | Tier-2 SQL: `SELECT physical_name FROM sys.master_files` — note tempdb **default** data path | data `M:\MSSQL\DATA`, log `L:\MSSQL\LOG` |
| Services | on-VM: `Get-Service MSSQLSERVER,SQLSERVERAGENT` | StartType Manual, Running |
| Overlap task | on-VM: `Get-ScheduledTask` — the module's **AtStartup** `Set-MssqlStartupConfiguration` is the one to disable | AtStartup, runs as domain admin, Highest |
| Other module task | identify any one-shot `Set-MssqlConfiguration-Reboot` TimeTrigger (not a boot competitor) | elapsed `Restart-Computer`, harmless |
| Domain / admin | on-VM: `(Get-WmiObject Win32_ComputerSystem).Domain`; confirm the bootstrap domain-admin account | default `mysandbox.local` / `MYSANDBOX`, admin `bootstrapadmin` (RID-500) |
| run-command identity | `az vm run-command invoke ... --scripts "whoami"` | `NT AUTHORITY\SYSTEM` |
| **SYSTEM vs sysadmin** | Tier-2 probe `IS_SRVROLEMEMBER('sysadmin')` as SYSTEM | **0** — SYSTEM is **not** a SQL sysadmin; all SQL admin work runs as the domain admin |
| Domain-admin task injection | SYSTEM holds `SeTcbPrivilege` + Schedule service running → can register one-shot tasks running as the domain admin | confirmed viable |
| **Managed identity → KV** | on-VM IMDS token → KV REST over the private endpoint to read `adminpassword`/`adminuser` | MI fetches secrets via PE (no public access needed) |
| KV name + PE IP | `az keyvault list -g <RG> --query "[].name"`; resolve its private-endpoint IP on-VM | `kv-sand-dev-<suffix>` → `10.x.x.x` |
| KV public access | expect **Disabled** (barrier) — direct `az keyvault secret show` fails; use the MI path | Disabled |

**Key invariants the plan depends on (true for every sandbox, regardless of names/region):**
SYSTEM (run-command identity) is **not** a SQL sysadmin → SQL work goes through a one-shot
domain-admin scheduled task (Tier 2); the VM's system-assigned MI can read KV secrets over the
private endpoint; KV public access is barrier-disabled; tempdb's off-ephemeral home is the SQL
**default data path** (discover it — typically `M:\MSSQL\DATA`, **not** `C:`).

## Execution model (two-tier — accounts for SYSTEM vs domain-admin privileges)

Because `az vm run-command` runs as **SYSTEM** (not a SQL sysadmin), work is split:

- **Tier 1 — OS-level, as SYSTEM (direct run-command):** manage scheduled tasks/services,
  Storage Spaces cleanup, deliver the 4 extras files to `C:\Scripts\`, read OS/disk/volume
  state, and **fetch KV secrets via the VM managed identity** (IMDS → KV REST over the private
  endpoint). SYSTEM can do all of this.
- **Tier 2 — SQL/sysadmin T-SQL, as `bootstrapadmin` (injected one-shot scheduled task):** for
  anything requiring sysadmin (read tempdb metadata, reset tempdb, run
  `Move-TempdbToEphemeral.sql`, verify tempdb). The SYSTEM run-command:
  1. retrieves the `bootstrapadmin` password from KV via MI (in memory),
  2. registers a one-shot scheduled task (`-User <DOMAIN>\bootstrapadmin -Password <pwd>`,
     RunLevel Highest) whose action runs a PowerShell/`sqlcmd -E` payload that writes results to
     a temp file on the VM,
  3. starts the task, waits for completion, reads back the result file,
  4. **unregisters the task** immediately (so the stored credential does not linger).

This mirrors exactly how the sandbox module itself runs privileged SQL work, and is the
technique noted for this test.

## Secret handling (validated, fully unattended)

- The `bootstrapadmin` password is obtained **on the VM** from Key Vault secret `adminpassword`
  using mssqlwin1's system-assigned managed identity over the private endpoint — no
  user-pasted secret, no need to re-enable KV public access.
- The secret is used only in memory on the VM for the duration of a single injected task and is
  **never written to disk by us, never echoed, never passed as a logged plain-text CLI arg**.
- Caveat (acceptable for a throwaway sandbox): `Register-ScheduledTask -Password` causes Windows
  to persist the credential in the Task Scheduler credential store while the task exists; we
  delete the task right after use to minimize the window.

## Test phases (todos)

### Pass A — 1 local temp disk (default sandbox size, e.g. `Standard_D4ds_v6`)

1. **discover-environment** — On the deployed sandbox, discover everything (names/region are
   unique per deploy): region, RG, KV name + private-endpoint IP, VM size + family, image,
   domain/NetBIOS, the bootstrap domain-admin account, tempdb default data path, disk/volume
   layout, the module's overlap task name, and confirm `az`/`gh` auth + `mssqlwin1`/`adds1`
   running. (The values in the discovery table are illustrative examples, not literal truth for
   your deployment.)
2. **capture-baseline** — Tier 1 + Tier 2: record scheduled tasks, service startup types, `T:`
   volume + module storage-pool state, and (via the domain-admin task) current `tempdb`
   `sys.master_files` paths (expected `T:\SQLTEMP`). Save as the success baseline.
3. **disable-sandbox-automation** — Tier 1: `Unregister-ScheduledTask Set-MssqlStartupConfiguration`
   (the AtStartup competitor); confirm removed. Verify the one-shot `Set-MssqlConfiguration-Reboot`
   is not pending. Leave services Manual (both solutions want Manual).
4. **reset-tempdb-off-ephemeral** — Tier 2 (domain admin): `ALTER DATABASE tempdb MODIFY FILE`
   all tempdb data+log files to the **discovered SQL default data path** (e.g. `M:\MSSQL\DATA` —
   NOT `C:`; the sandbox keeps no tempdb on C:); restart `MSSQLSERVER`; verify tempdb now on the
   default path. Then Tier 1: free `T:` cleanly — remove the module's virtual disk + storage pool
   so the extras task provisions from a clean slate (mirrors README premise: tempdb off-ephemeral,
   `T:` absent). **Watch for the active `T:\pagefile.sys` blocker** (see learnings): set
   `PagingFiles` to C:-only and reboot before the pool can be removed.
5. **install-extras-scripts** — Tier 1: base64-encode the 4 NVMe files locally, write them to
   `C:\Scripts\` in a **single** run-command invocation (atomic); verify length/hash match in a
   **separate** invocation.
6. **register-extras-task** — Tier 1: replicate `Register-MssqlStartupTask.cmd` —
   `sc config ... start= demand` (already Manual) + register `SQL Server Startup - Ephemeral
   Storage` (AtStartup, SYSTEM). Confirm registered. (Run the operative steps directly; the
   `.cmd`'s trailing `pause` hangs under run-command.)
7. **provision-T-and-move-tempdb** — Tier 1: run `C:\Scripts\Set-MssqlStartupConfiguration.ps1`
   once to create `T:`; Tier 2 (bootstrapadmin): run `Move-TempdbToEphemeral.sql` (sqlcmd needs
   `-C`); restart SQL; verify tempdb on `T:\SQLTEMP` (README Step 4). **This is the only tempdb
   move for the whole test** — the path is stable across resizes.
8. **validate-deallocate-cycle** — `az vm deallocate` then `az vm start mssqlwin1` (monitored,
   long-running, ~2-min progress reports). After boot, verify via run-command + bootstrapadmin
   task: `T:` exists + NTFS, `T:\SQLTEMP` present, `MSSQLSERVER`+`SQLSERVERAGENT` running, tempdb
   files resolve on `T:\SQLTEMP`, and `C:\Scripts\Set-MssqlStartupConfiguration.log` shows a
   clean run (README Step 5). For Pass A the log should show **1** poolable disk, 1-column stripe.
9. **smoke-test-sql** — confirm SQL healthy end-to-end (`SELECT @@VERSION`, tempdb online) via the
   domain-admin (Tier-2) context.
10. **report-and-note-drift** — summarize PASS/FAIL per README Step 5 for Pass A; document
    intentional Terraform drift. (Do NOT clean up the installed extras yet — Passes B/C reuse
    them.) Final cleanup happens after Pass C.

### Pass B — 2 local temp disks (discovered 2-disk size, e.g. `Standard_D16ds_v6`) — resize + re-validate

### Pass C — 4 local temp disks (discovered 4-disk size, e.g. `Standard_D32ds_v6`) — resize + re-validate

Passes B and C follow the identical **resize procedure** below, then run the **same Pass A
validations (phases 8–9)** at the new disk count. See "## VM resize passes (B & C)".

## VM resize passes (B & C)

After Pass A is green and the extras solution is installed + tempdb is on `T:\SQLTEMP`, resize
the VM to exercise 2- and 4-disk striping. **Per target size** (the discovered 2-disk size, then
the 4-disk size from the resize matrix):

**Reused from Pass A — do NOT repeat in B/C (already in place and persistent on `C:`/catalog):**

- Environment discovery + auth (region, RG, KV name/PE IP, MI) — discovered once in Pass A.
- Tier-2 domain-admin execution model + on-VM MI→KV secret retrieval pattern — unchanged.
- Module overlap task `Set-MssqlStartupConfiguration` already unregistered (disable-automation).
- Extras files in `C:\Scripts\` + the `SQL Server Startup - Ephemeral Storage` AtStartup task —
  both persist across deallocate/resize (`C:` is durable); **no reinstall, no re-register**.
- tempdb catalog already points at `T:\SQLTEMP` — **no `Move-TempdbToEphemeral.sql`, no
  off-ephemeral reset, no clean-slate pool teardown** (the resize wipes local disks for us).

So Pass B/C skip Pass A phases 1–7 (and 10's cleanup) entirely and run only the resize +
re-validation below.

**Resize procedure**

1. Pre-clear `C:\Scripts\Set-MssqlStartupConfiguration.log` (so the post-resize boot run is
   cleanly attributable). Confirm `adds1` is still running.
2. `az vm deallocate -g <RG> -n mssqlwin1` (async + ~2-min reports). The local NVMe disks are
   wiped — this IS the post-deallocate scenario the extras handle.
3. `az vm resize -g <RG> -n mssqlwin1 --size <target>` **while deallocated** (so Azure can place
   it on any compatible host/zone in the region, not just the current host's available set).
4. `az vm start -g <RG> -n mssqlwin1` (async + ~2-min reports). Boot fires the AtStartup extras
   task, which now finds the new disk count and stripes accordingly.

**Re-validation at the new size (same checks as Pass A phases 8–9, plus disk-count assertions)**

5. Confirm size changed: `az vm show ... --query hardwareProfile.vmSize` = target.
6. Read `C:\Scripts\Set-MssqlStartupConfiguration.log` and assert it reports the **expected disk
   count**: "Found **N** poolable NVMe Direct Disk(s)" and "Creating Virtual Disk ... (Simple/
   Stripe, **N** columns)" where N = 2 (Pass B) or 4 (Pass C).
7. Assert Storage Spaces stripe width: `(Get-VirtualDisk NVMeTempDisk).NumberOfColumns` = N, pool
   `NVMeTempPool` Healthy, and `T:` aggregate size ≈ N × (per-disk GiB for the size) (NTFS, 64 KB AU).
8. Assert only **local** disks were pooled — the remote `Virtual_Disk NVME Ultra/Premium` managed
   disks remain out of the pool (`CanPool` reflects this); only `*NVMe Direct Disk*` are consumed.
9. `T:\SQLTEMP` present; tempdb 3 files **ONLINE on `T:\SQLTEMP`** (Tier-2, no re-move needed);
   `MSSQLSERVER` + `SQLSERVERAGENT` Running; task `LastTaskResult=0`.
10. Smoke test (Tier-2): `SELECT @@VERSION`, tempdb writable (`#temp` create/insert/drop),
    `DATABASEPROPERTYEX('tempdb','Status')=ONLINE`.
11. Record PASS/FAIL for the size. On any infra/command error follow the Error-handling policy
    (STOP + file issue). A legitimate test FAIL (e.g. extras mis-stripe N disks) is a real
    finding to report, not a workflow error.

> **Note — resize already exercises a deallocate cycle.** The resize procedure itself is a
> deallocate → (resize) → start, i.e. a genuine post-deallocate reprovision at the new disk
> count, so steps 5–10 above ARE the "same validation" Pass A ran in phase 8. Optionally run one
> additional plain `deallocate`/`start` at the new size for steady-state confidence, but it is
> not required to satisfy the matrix.

**After Pass C:** resize back is unnecessary (sandbox to be destroyed). Do the final cleanup
(remove Tier-2 helper files + local `/tmp` scripts) and write the consolidated 3-pass report.

## Error handling

Per repo policy: on the **first** infrastructure/command error (az failure, run-command failure,
injected-task failure, deallocate failure, SQL error), STOP, document exact command + full output
+ phase + context, open a GitHub issue (`gh issue create`), and report back with the link. Do not
auto-retry or self-patch. A test reporting a legitimate FAIL is an expected outcome, not a
workflow error.

## Pre-flight checklist

**A. Tooling & auth**
1. `az` logged in to the subscription hosting the sandbox (`az account show`).
2. `gh` authenticated (for error filing).

**B. Environment — discover on the deployed sandbox (all identifiers are unique per deploy)**
3. Region + RG (`az group list ...`); VM `mssqlwin1` size + family (`az vm show ... hardwareProfile.vmSize`).
4. Image is WS2025 / SQL2025 (extras-compatible) — confirm via `storageProfile.imageReference`.
5. KV name + private-endpoint IP — discover (`az keyvault list -g <RG>`); reachable from VM via MI.
6. Confirm `mssqlwin1` **and** `adds1` (DC, AD/DNS dependency) are **running** just before
   execution; do not deallocate `adds1`.

**C. Secrets — no user input needed**
7. Domain-admin password retrieved on-VM via managed identity from KV secret `adminpassword`; held
   in memory only. No paste, no KV public-access change required.

**D. Behavioral confirmations to get from the user**
8. tempdb reset target = the **discovered SQL default data path** (e.g. `M:\MSSQL\DATA`, NOT C:).
   Confirm OK.
9. Deallocate cycle count per pass: single cycle (default) vs. two for extra confidence.
10. Acknowledge `mssqlwin1` will be **drifted** from Terraform (no apply afterward) and the
    sandbox will be destroyed — drift intentional/acceptable.
11. Maintenance window OK: `mssqlwin1` incurs downtime during the deallocate/start in phase 8
    **and during each of the two resize passes** (deallocate → resize → start).
12. Accept the transient credential-store caveat of `Register-ScheduledTask -Password` (task is
    deleted immediately after each use).

**E. Resize matrix pre-flight (for Passes B & C — all in the deployment region/family)**
15. **Resolve the resize targets** first (see "VM resize test matrix"): the discovered VM family's
    smallest sizes with **2** and **4** local temp disks (B and C).
16. **vCPU quota** for the VM's family in the deployment region ≥ the larger target's vCPU count.
    Check `az vm list-usage -l <region> -o table` and filter the family row. (`adds1`/`jumpwin1`
    are typically B-series and don't count against this family's quota.)
17. **Size availability / zone restrictions** for both targets in the deployment region:
    `az vm list-skus -l <region> --size <target> -o table`; confirm not
    `NotAvailableForSubscription` / zone-restricted for the VM's zone.
18. **Confirm resize order** = deallocate → `az vm resize` (while stopped) → start, and that the
    extras tempdb path stays `T:\SQLTEMP` (no second `Move-TempdbToEphemeral.sql` for B/C).
19. Confirm the test should stay in the **deployed VM's series** (1 → 2 → 4 disk sizes within it)
    rather than switching families to hit specific disk counts.

**F. Safety rails**
13. No concurrent `terraform apply` against this sandbox state during the test.
14. Do not inspect/lock Terraform state during the test (we use `az` only).

## Notes / considerations

- Pass A: a single local NVMe disk → Storage Spaces single-disk "stripe"; both module and extras
  handle N=1 uniformly. Passes B/C scale this to 2- and 4-column stripes.
- The extras `Set-MssqlStartupConfiguration.ps1` cleans only its own `NVMeTempPool` and does not
  `Reset-PhysicalDisk` stale metadata — removing the module's `StoragePool-Temp` in phase 4
  prevents first-boot interference.
- Resizing a local-NVMe size **wipes the ephemeral disks**, so each resize+start is itself a
  post-deallocate reprovision event at the new disk count (no separate cycle strictly required).
- Resize **while deallocated** so Azure isn't constrained to the current host's available size
  set.
- All long-running ops (`deallocate`/`start`/`resize`) run with bash `mode="async"` + ~2-min
  progress reports per repo conventions.

## Reference results — one illustrative 1-disk run (example only)

> ⚠️ **Illustrative example from a single past run on one deployment** — kept solely for the
> **learnings/gotchas and the expected drift inventory** below. The specific names, sizes, build
> numbers, and capacities are **not** literal truth for any other sandbox; your Pass A will
> produce its own equivalents. Passes B & C (resize to 2- and 4-disk) are validated the same way
> but were not part of this example run.

Example outcome: all Pass-A phases completed and the run was **PASS**.

- [x] **Phase 1-3** Confirmed `adds1`/`jumpwin1`/`mssqlwin1` running; baseline captured;
  `Unregister-ScheduledTask Set-MssqlStartupConfiguration` (the AtStartup overlap) — confirmed
  gone. `Set-MssqlConfiguration-Reboot` one-shot already spent (no NextRunTime). Services left
  Manual.
- [x] **Phase 4** Reset tempdb off ephemeral → `M:\MSSQL\DATA` (Tier-2 ALTER + restart, verified
  3 files on `M:`); removed module `VirtualDisk-Temp` then `StoragePool-Temp`; freed `T:`. NVMe
  Direct Disk v2 (220 GB) returned to `CanPool=True`.
- [x] **Phase 5** Delivered the 4 extras files to `C:\Scripts` (atomic single-invocation write,
  SHA256-verified, persistence re-checked in a separate invocation).
- [x] **Phase 6** `sc config MSSQLSERVER/SQLSERVERAGENT start= demand` + registered task
  `SQL Server Startup - Ephemeral Storage` (SYSTEM, AtStartup/`MSFT_TaskBootTrigger`, Highest).
- [x] **Phase 7** Manual `Set-MssqlStartupConfiguration.ps1` provisioned `T:` from RAW
  (`NVMeTempPool`/`NVMeTempDisk`, NTFS 64 KB, `T:\SQLTEMP` + `NT Service\MSSQLSERVER` ACL,
  SQL started). Tier-2 `Move-TempdbToEphemeral.sql` (as `bootstrapadmin`, `sysadmin=1`) →
  restart → tempdb 3 files **ONLINE on `T:\SQLTEMP`**, writable.
- [x] **Phase 8** `az vm deallocate` (~1 min) → `az vm start` (~2m13s). **Post-boot the extras
  task fired automatically** (`LastTaskResult=0`); log showed the full RAW→provisioned path
  (`Volume T: not found` → pool → format NTFS 64 KB → `T:` 218 GB → `T:\SQLTEMP`+ACL → start
  SQL). `T:` NTFS present, 3 tempdb files on `T:\SQLTEMP`, both services Running, `NVMeTempPool`
  Healthy.
- [x] **Phase 9** Smoke test (Tier-2): `SQL Server 2025 (RTM) 17.0.1000.7`; tempdb 3 files
  `ONLINE` on `T:\SQLTEMP`; `DATABASEPROPERTYEX('tempdb','Status')=ONLINE`; tempdb writable
  (create/insert/drop `#temp`).
- [x] **Phase 10** Removed Tier-2 helper files (`t2_payload.ps1`, `t2_result.txt`,
  `t2_whoami.txt`, `t2_role.txt`) from `C:\Scripts` and local `/tmp/*` scripts. The 4 installed
  extras files + `Set-MssqlStartupConfiguration.log` remain (the installed solution).

### README Step 5 verification result

| Check | Result |
|---|---|
| `T:` exists + NTFS | ✅ 218 GB NTFS, label "Temporary Storage" |
| `T:\SQLTEMP` exists | ✅ with `tempdb.mdf` / `tempdb_mssql_2.ndf` / `templog.ldf` |
| SQL + Agent running | ✅ both Running (StartType Manual) |
| Startup log clean | ✅ task `LastTaskResult=0`, clean provisioning run |
| tempdb on ephemeral | ✅ 3 files `ONLINE` on `T:\SQLTEMP`, writable |

### Learnings / gotchas discovered this run (carry forward)

1. **`az vm run-command invoke` has a single run-command slot per VM.** Firing rapid
   sequential `invoke` calls (e.g. a per-file delivery loop) can let them clobber each other —
   each returns its own self-consistent success message, yet not all writes survive once the
   next invocation reuses the slot. **Fix:** do multi-file writes in **one** invocation (atomic)
   and verify in a **separate, later** invocation. (The newer managed run-command,
   `az vm run-command create`, avoids this but wasn't needed.)
2. **sqlcmd uses ODBC Driver 18 (encrypt-by-default).** Must pass **`-C`** (trust server
   certificate) or every connection fails with `SSL Provider: The certificate chain was issued
   by an authority that is not trusted`. Applies to all Tier-2 `sqlcmd -E` calls.
3. **Active pagefile on `T:` blocks pool removal.** `T:` had an OS-created `T:\pagefile.sys`
   (~2944 MB active per `Win32_PageFileUsage`) even though the registry showed `T:\pagefile.sys
   0 0` and `Test-Path` returned False. **Fix:** set `PagingFiles` to `C:` only, **reboot** to
   release it, then `Remove-VirtualDisk`/`Remove-StoragePool`. (A reboot — not deallocate —
   preserves the NVMe pool, so `T:` is still removable afterward.)
4. **Startup log is UTF-16** (`Out-File` default) — appears as spaced-out characters when read
   raw; cosmetic only, content is correct.
5. **`Register-MssqlStartupTask.cmd` ends in `pause`** and didn't run cleanly under
   run-command. Replicating its operative steps directly (`sc config ...` + the inline
   `Register-ScheduledTask` from the `.ps1`) is more reliable and functionally identical.
6. **Stale abandoned tempdb copies remain on `M:\MSSQL\DATA`** after the move — SQL does not
   delete the old files when you `MODIFY FILE` the path; harmless, intentional drift.

### Resize-pass learnings / expectations (Passes B & C — NEW, to be confirmed live)

7. **Resize while deallocated.** `az vm resize` on a stopped VM lets Azure place it on any
   region/zone-compatible host; resizing a running VM is restricted to sizes the current host
   cluster offers (the local-NVMe sizes may not all be present there).
8. **Local NVMe disks are ephemeral and wiped by resize.** Each resize+start is a genuine
   post-deallocate reprovision at the new disk count — exactly the scenario the extras script
   targets — so it doubles as the validation cycle.
9. **Stripe width must scale with disk count.** Expect
   `(Get-VirtualDisk NVMeTempDisk).NumberOfColumns` = N (2 for the 2-disk size, 4 for the 4-disk
   size), with `T:` ≈ N × per-disk GiB. The startup log should print "Found N poolable NVMe
   Direct Disk(s)".
10. **Remote managed disks must stay excluded.** Only `*NVMe Direct Disk*` (local) disks are
    pooled; the OS/data/log managed disks surface as `Virtual_Disk NVME Ultra/Premium` and must
    NOT be absorbed into `NVMeTempPool` — a regression here would be a real FAIL to report.
11. **tempdb path is size-invariant.** `T:\SQLTEMP` is stable across all three sizes; run
    `Move-TempdbToEphemeral.sql` once in Pass A only — B/C just need tempdb back ONLINE at the
    same path after the larger stripe is reprovisioned.
12. **Resource identifiers are unique per deployment** — every sandbox has a different region, RG
    suffix, KV name, and PE IP; discover all of them in the Pass A discover phase, never assume
    values from any prior run.

### Intentional Terraform drift left on `mssqlwin1` (sandbox to be destroyed)

- Module startup task `Set-MssqlStartupConfiguration` unregistered.
- Module `StoragePool-Temp`/`VirtualDisk-Temp` removed; replaced by extras `NVMeTempPool`/
  `NVMeTempDisk`.
- Pagefile is now **C:-only** (T: entry removed).
- tempdb relocated to `T:\SQLTEMP` via the extras flow; abandoned copies linger in `M:\MSSQL\DATA`.
- 4 extras files + `Set-MssqlStartupConfiguration.log` in `C:\Scripts`.
- Extras scheduled task `SQL Server Startup - Ephemeral Storage` (SYSTEM, AtStartup) installed.

No Terraform was run at any point; `adds1` (DC) stayed running throughout.
