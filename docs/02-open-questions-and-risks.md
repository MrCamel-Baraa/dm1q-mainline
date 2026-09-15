# Open questions and risks

Things flagged as "verify, don't assume" during planning. Resolved items stay
here with their answer and source, and are also reflected in 00-overview.md.

## Resolved

1. **WCN Wi-Fi/BT chip — CORRECTED 2026-09-13 (second pass, overturns the
   teardown-based "resolved" verdict below).**
   Ground-truth check against dm1q's actual Samsung downstream devicetree
   source (`crdroidandroid/android_kernel_samsung_sm8550-devicetrees`, real
   `.dts` files, all 10 available board revisions r01–r13) shows dm1q uses
   **QCA6490** (`qcom,cnss-qca6490`, `bt_qca6490`), not WCN6855. Zero of the
   10 revisions reference WCN6855; all 10 reference QCA6490. This is
   directly from real hardware-description source, not teardown/community
   inference — treat as settled, higher confidence than the item below it.
   Good news buried in the correction: QCA6490 is still `ath11k`-family
   (same mainline driver as WCN6855) and was actually mainlined *earlier*,
   so driver maturity is likely equal or better than assumed. Practical
   effect: use QCA6490's specific compatible strings/firmware naming, not
   WCN6855's, when building the WLAN/BT devicetree nodes and picking
   firmware blobs. dm2q/dm3q not re-checked against real source — the item
   below may still hold for dm3q specifically, but shouldn't be trusted for
   dm1q anymore.
   *(Original "resolved" text, now superseded, kept for history:)*
   dm1q/dm2q (S23, S23+) use Qualcomm FastConnect 6900 (WCN6855-class,
   Wi-Fi 6E, `ath11k`). dm3q (S23 Ultra) uses FastConnect 7800
   (WCN7850/WCN7851-class — same chip family as the Tab S9 Ultra reference
   device — Wi-Fi 7 silicon software-limited to 6E, `ath12k`). This was
   sourced from iFixit teardown + community reporting, not dm1q's own
   kernel source — exactly the kind of secondary-source claim that turned
   out to need the direct check above.

## High priority — blocks Step 1 of the workplan

2. **PMIC part number match — RESOLVED 2026-09-13.**
   Confirmed directly from dm1q's real Samsung downstream devicetree source
   (same repo/method as the WCN correction above): dm1q uses **PM8550
   (main), PM8550B, PM8550VE, PM8550VS, PM8010, and PM8350C** — a
   multi-PMIC setup, not a single part. This is ground truth, not inferred.
   The Tab S9 Ultra reference used PM8550/PM8550VS/PMK8550 — overlapping but
   not identical (no PM8550B/PM8550VE/PM8010/PM8350C on the tablet, at least
   not visible in that board's devicetree). Regulator *names* will need
   verifying node-by-node against dm1q's real rail usage rather than assumed
   1:1 from the tablet reference. See
   `../_scratch/crdroid-dm1q-dts/samsung/dm1q_eur_openx_w00_r13.dts` for the
   real source.

3. **GPU/CPU OPP table retuning.**
   The S23 uses SM8550-AC ("for Galaxy" bin), a higher factory-tested
   clock/voltage bin than reference kalama. Copy-pasting the Tab S9 Ultra's
   OPP tables verbatim is likely wrong — they'll need to be checked/retuned
   against whatever clock speeds crDroid reports for dm1q.
   Status: unresolved.

3b. **Panel driver and touch controller — RESOLVED 2026-09-13.**
   From the same real dm1q devicetree source: dm1q is **dual-sourced** for
   the display panel — primary is Samsung's own `S6E3FAC` panel driver IC
   (cell part `AMB606AW01`), with `LX83118` (Silicon Works, cell
   `CM002`) as an alternate/second-source panel. Both will realistically
   need their own DSI panel driver work — dual-sourcing on flagship phones
   is normal but means two drivers, not one, if full hardware coverage
   matters (unclear yet whether crDroid/OneUI treat these as
   interchangeable at the DT level or select one via board-revision
   fragments — worth checking which is more common in retail units before
   prioritizing). Touch controller is **Goodix Berlin**
   (`goodix-berlin@5d`, I2C address 0x5d) — a real, known touch IC family
   with some existing mainline Linux interest elsewhere, worth checking for
   upstream driver status separately.

## Medium priority — affects scope/expectations, not immediately blocking

4. **Camera: RE-UPGRADED 2026-09-13 (second pass) — credible prior art
   confirmed real, one specific claim still worth checking.**
   Full history: this item went no-known-support → briefly "credible" →
   "discredited as likely fabricated" → **corrected back to credible**, all
   within 2026-09-13. The "discredited" verdict was itself wrong — see
   03-references.md for the full correction. Verified directly: real V4L2
   driver patch code against actual mainline `drivers/media/i2c/hi847.c`,
   real pmOS deviceinfo conventions, a real citation of an actual resolvable
   commit hash in pmaports history. This is legitimate, technically
   competent work, not fabrication.
   **Still open:** the specific claim of *full* camera support (4 cameras,
   autofocus, flash all working) is unusually strong even for legitimate
   projects — worth reading `docs/hardware-status.md` from
   `ubuntu-galaxy-tab-s9-ultra` directly for the evidence behind that claim
   before assuming it's fully solved. dm1q's own sensors (S5KGN3/IMX564/
   S5K3K1) differ from the Tab S9 Ultra's (hi847/hi1337) regardless, so even
   fully-confirmed camera work there is a methodology/pattern reference for
   dm1q, not drop-in code.

5. **Modem: unpredictable, device-specific.**
   No basis for predicting dm1q's modem prospects from any reference device
   checked so far (Tab S9 Ultra has no modem at all). Historical pattern
   across other Samsung pmOS ports: modem success/failure doesn't correlate
   cleanly with Wi-Fi/BT/camera success — it's its own separate effort.

## High priority — contradicts a prior "confirmed" claim

1b. **dm1q pmaports package: does not exist in current pmaports — CONFIRMED
   AND CLOSED 2026-09-13.**
   Directly confirmed by running `pmbootstrap init` interactively and
   selecting `samsung-dm1q`: pmbootstrap itself returned "The specified
   device ('samsung-dm1q') could not be found in existing ports" and offered
   to launch its new-device-port wizard (postmarketos.org/porting/). This
   matches the earlier `git ls-tree` search exactly — no fuzzy-match
   artifact, no branch issue (pmbootstrap's error message covers the "did
   you mean the edge branch" case explicitly and it still didn't find it).
   **Conclusion: the original "confirmed by hand" note was simply wrong** —
   likely a misremembering, or confused with a different device/session.
   Not worth further investigation. This is a ground-up port; see
   docs/01-phase1-workplan.md for the updated Step 0/1 sequencing that
   follows from this.
   (Prior text, kept for history:)
   Previously (see old item 6 below) this was treated as settled because the
   user had directly observed dm1q in `pmbootstrap init`. On 2026-09-13 a
   sparse partial clone of the live pmaports repo (main branch, HEAD
   `1c99c07`) was searched directly with `git ls-tree -r` for `dm1q`, `dm2q`,
   `dm3q`, `kalama`, and `sm8550` across every device tier
   (main/testing/community/archived/downstream) — **zero matches, all
   terms**. This is hard evidence against a real dm1q package existing right
   now. Two things can be true at once: pmaports migrated hosts in 2024 (see
   00-overview.md), AND the device may simply not be there. Needs a fresh,
   carefully-observed interactive `pmbootstrap init` session — type `dm1q`
   into the device search and record verbatim what appears (real match /
   fuzzy near-match / nothing) — to find out whether the original observation
   was a typo/fuzzy-match artifact or something else. Until resolved: treat
   Phase 1 as a from-scratch port with no existing dm1q package to reference,
   which doesn't change the plan (Tab S9 Ultra was always just an
   SM8550-family reference) but does mean don't expect to find a
   maintainer/kernel-type/last-commit-date to record, because there may be no
   package to have those.

## Low priority / just for the record

6. *(superseded 2026-09-13 by item 1b above — kept for history)*
   **dm1q pmaports package provenance unconfirmed by me.**
   Explanation upgraded 2026-09-13: postmarketOS moved `pmaports` from
   `gitlab.com` to a self-hosted `gitlab.postmarketos.org` in Oct 2024, and
   the new host isn't well-crawled by web search either, so a negative search
   result there means little. The user has directly observed dm1q in
   `pmbootstrap init`, which is authoritative (pmbootstrap clones pmaports.git
   directly). Confirm and record details (kernel type, maintainer, last
   commit) in 00-overview.md once checked locally against
   `gitlab.postmarketos.org/postmarketOS/pmaports`.

7. **postmarketOS wiki page content unread.**
   wiki.postmarketos.org blocks automated fetches (Anubis anti-bot); Wayback
   Machine and search-engine snippets also failed to surface the page content
   as of 2026-09-13. The "Samsung Galaxy S23" wiki category entry exists but
   its content — maintainer, status table, whether it even lists dm1q's
   codename — hasn't been read by anyone on this project yet. Needs a human
   to open it in a browser.

8. **Camera/Fairphone 6/camss claim and Waydroid mechanics — not re-verified
   in the 2026-09-13 pass.** These came from single sources checked when the
   project started and were not re-cross-checked during the most recent fact
   review (time/effort was spent on the WCN chip and GitLab migration findings
   instead, since those were higher-impact corrections). Treat as "probably
   still accurate" but lower-confidence than the WCN finding above until
   someone re-checks them specifically.

9. **Kupfer's exact current device count/list — not freshly re-checked.**
   Confirmed the *general pattern* holds (Kupfer's own 2022–2023 blog posts
   describe "three currently supported SDM845 devices": OnePlus 6/6T, Poco F1,
   plus SHIFT6mq mentioned elsewhere), consistent with "SDM845-and-older only."
   The exact current number/list in 00-overview.md ("~10 devices") was not
   re-verified live against `kupfer.gitlab.io/devices/` on 2026-09-13 — treat
   that specific figure as dated until checked again.
