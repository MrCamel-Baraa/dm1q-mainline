# Open questions and risks

Things flagged as "verify, don't assume" during planning. Move items to
00-overview.md once resolved, with the answer and how it was confirmed.

## High priority — blocks Step 1 of the workplan

1. **WCN Wi-Fi/BT chip generation mismatch risk.**
   Tab S9 Ultra (mid-2023) uses WCN7850 (Wi-Fi 7, ath12k driver, its own
   firmware blobs and PCIe device ID). The S23 (Feb 2023, earlier in the
   SM8550 product cycle) more commonly paired with WCN6855 (Wi-Fi 6E, ath11k)
   at that point. Different driver, different enumeration ID, different
   firmware. **Do not assume the PCIe/WiFi devicetree node structure
   transfers from the Tab S9 Ultra reference until this is checked against
   dm1q's actual crDroid kernel tree.**
   Status: unresolved.

2. **PMIC part number match.**
   Regulator *names* only transfer cleanly from the Tab S9 Ultra reference if
   dm1q uses the literal same PM8550 variant. Samsung SM8550 phones have used
   PM8550 / PM8550B / PM8550VE across different rails — worth confirming
   exactly which combination dm1q uses before assuming 1:1 node-name mapping.
   Status: unresolved.

3. **GPU/CPU OPP table retuning.**
   The S23 uses SM8550-AC ("for Galaxy" bin), a higher factory-tested
   clock/voltage bin than reference kalama. Copy-pasting the Tab S9 Ultra's
   OPP tables verbatim is likely wrong — they'll need to be checked/retuned
   against whatever clock speeds crDroid reports for dm1q.
   Status: unresolved.

## Medium priority — affects scope/expectations, not immediately blocking

4. **Camera: no known upstream ISP support.**
   No mainline qcom-camss or libcamera support found for the Spectra 780 ISP
   or the S23's specific sensors (S5KGN3, IMX564, S5K3K1). Waydroid can't
   route around this — it only passes through devices the host kernel
   already exposes. Treat as out of scope unless someone does dedicated
   camss bring-up (see the Fairphone 6 / milos / TFE665 effort in
   03-references.md as the template for what that work looks like).

5. **Modem: unpredictable, device-specific.**
   No basis for predicting dm1q's modem prospects from any reference device
   checked so far (Tab S9 Ultra has no modem at all). Historical pattern
   across other Samsung pmOS ports: modem success/failure doesn't correlate
   cleanly with Wi-Fi/BT/camera success — it's its own separate effort.

## Low priority / just for the record

6. **dm1q pmaports package provenance unconfirmed by me.**
   I (Claude) could not find dm1q/dm2q/dm3q via GitLab or general web search
   of postmarketOS/pmaports, but GitLab's public search indexing is weak for
   this kind of content — the user has directly observed dm1q in
   `pmbootstrap init`, which is authoritative (pmbootstrap clones pmaports.git
   directly). Confirm and record details (kernel type, maintainer, last
   commit) in 00-overview.md once checked locally.

7. **postmarketOS wiki page content unread.**
   wiki.postmarketos.org blocks automated fetches (Anubis anti-bot). The
   "Samsung Galaxy S23" wiki category entry exists but its content —
   maintainer, status table, whether it even lists dm1q's codename — hasn't
   been read by anyone on this project yet. Needs a human to open it in a
   browser.
