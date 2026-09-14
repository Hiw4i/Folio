# Office renderer compatibility matrix

This matrix records functional rendering checks. It is not a performance
report: stage 5 uses debug builds, and timing/memory claims belong to stage 6.

## 2026-09-13 — Android 13, device 2201116TG

| Sample | Size | Result | Position model | Text search | Known deviations / gate |
| --- | ---: | --- | --- | --- | --- |
| User DOCX: `ИЗО - украшения.docx` | 795 KB | Opened offline | 1 page | DOM text available | Visual comparison awaits user review. |
| User DOCX: `Герой нашего времени.docx` | 198 KB | Opened offline | 65 vertical sheets | `книг`: 11 hits; previous from the first hit wrapped and revealed the last hit | Automatic pagination is paragraph-level; an oversized table or drawing stays on one expanded sheet. Visual comparison awaits user review. |
| User PPTX: `Индийские изобретения (Владик).pptx` | 763 KB | Opened offline | 10 horizontally snapped slides | DOM text available | Animations, transitions and media are intentionally omitted. Visual comparison awaits user review. |
| User PPTX: `Реклама_робота_пылесоса_ХозРобот_i4.pptx` | 4.3 MB | Opened offline | 4 horizontally snapped slides | `пылесос`: 7 hits; wrap navigation revealed slide 4 | Animations, transitions and media are intentionally omitted. Visual comparison awaits user review. |

The WebView performance resource log contained only
`appassets.androidplatform.net`, `data:` and `blob:` resources for the checked
PPTX. The production manifest contains no `INTERNET` permission; Flutter's
debug/profile manifests add it for development tooling, while the native
WebView client still blocks every non-local request. The connected device did
not allow ADB input injection, so physical swipe, side-tap, keyboard and
liquid-glass sampling checks remain manual review items.

## Acceptance notes

- Office fidelity is best-effort because the bundled renderers are not the
  Microsoft Office layout engines.
- DOCX sheets preserve renderer-produced explicit page breaks and add
  paragraph-level pagination for long continuous sections.
- External links, remote resources, downloads, popups and embedded media are
  blocked.
- A content-URI Office launch still needs a provider-driven device check; ADB
  cannot grant an ExternalStorageProvider URI on the current Xiaomi firmware.
