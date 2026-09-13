# Open questions and risks

Things flagged as "verify, don't assume" during planning. Resolved items stay
here with their answer and source, and are also reflected in 00-overview.md.

## Resolved

1. **WCN Wi-Fi/BT chip generation mismatch — RESOLVED 2026-09-13.**
   dm1q/dm2q (S23, S23+) use Qualcomm FastConnect 6900 (WCN6855-class,
   Wi-Fi 6E, `ath11k`). dm3q (S23 Ultra) uses FastConnect 7800
   (WCN7850/WCN7851-class — same chip family as the Tab S9 Ultra reference
   device — Wi-Fi 7 silicon software-limited to 6E, `ath12k`). Confirmed via
   iFixit's S23 Ultra chip-ID teardown plus multiple Samsung Community/XDA
   threads citing Qualcomm's device finder page. **For dm1q: use ath11k/
   WCN6855 as the working assumption, not the Tab S9 Ultra's ath12k setup.**
   Still worth a final grep of the crDroid tree to be 100% sure before
   writing DT code, since this is sourced from retail teardowns/community
   reporting rather than dm1q's kernel source directly.

## High priority — blocks Step 1 of the workplan

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
