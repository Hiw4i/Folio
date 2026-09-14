# Bundled Office renderers

Folio serves these files only from the APK through `WebViewAssetLoader`. No CDN
or network fallback is used.

## docx-preview 0.4.0

- Source: https://github.com/VolodymyrBaydalka/docxjs
- Package: `docx-preview@0.4.0`
- License: Apache-2.0 (preserved in `vendor/docx-preview/LICENSE`)
- npm package SHA-1: `95800aafa393453e7b48dc79fbefc46af8da86e3`
- `docx-preview.min.js` SHA-256:
  `051ef503f2677d53159a388b7384e950eda41ea4e47a103e5e36f124d7faea40`

No renderer patch is applied. Folio supplies only host styling and a restricted
bridge. JSZip 3.10.1 is bundled for this renderer.

## JSZip 3.10.1

- Source: https://github.com/Stuk/jszip
- Package: `jszip@3.10.1`
- License: MIT/GPL-3.0-or-later (preserved in `vendor/jszip3/LICENSE.markdown`)
- npm package SHA-1: `34aee70eb18ea1faec2f589208a157d1feb091c2`
- `jszip.min.js` SHA-256:
  `acc7e41455a80765b5fd9c7ee1b8078a6d160bbbca455aeae854de65c947d59e`

## PPTXjs 1.21.1

- Source: https://github.com/meshesha/PPTXjs
- Tag: `v1.21.1`
- Commit: `1a9260b2062f89ba822aeb54da792236780af8e7`
- License: MIT (preserved in `vendor/pptxjs/LICENSE`)
- `pptxjs.min.js` SHA-256:
  `845555ec4179f557f0b78822baeffbaa6aa14c303eaaba1def7f608367eaca46`

The repository-bundled, compatible versions of jQuery, JSZip 2, FileReader,
D3, NVD3 and dingbat are kept unchanged. Their checksums are:

```text
20e11ce61890c08c0529911822233c9023ebc367df6c1050dec105e2b9628104  jquery-1.11.3.min.js
c5b5297e87ddd9a4ae8e3bf7cd46110f7463b27d2cd6f5366862b1e4c9368fc7  jszip.min.js
6694c65f8cfaa168c608fa7e3a39a7285bfe921e05e8799a8a8bced429d17ad7  filereader.js
b5fd3b4fd7336382f66ad19ea426df21fc8a33e1c0aed577149fa1702fcb9803  d3.min.js
6b6ba396052643ffdf70be80d353a27bf5bf879260197658561b6395502f59a5  nv.d3.min.js
2ea31e0affb509ff15b997e5a7655bdc3678421bfe7b1e2fc85deee22fd6b7ee  dingbat.js
e9c231c30fbd78ea0a5954b6dc002ad1ce095f86a19db68aad88093989b2e245  pptxjs.css
d2ba03ccfda9b6c876a7b8313e4a6268c2f98f333e57fc18863023a2a5a3df6e  nv.d3.min.css
```

No renderer patch is applied. Folio disables media processing, navigation and
all non-local requests in both JavaScript and the native WebView client.
