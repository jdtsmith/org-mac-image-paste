# org-mac-image-paste
Paste images and cropped PDF clips directly into org files on Mac. 

This simple package modifies org-mode so that images (including
cropped segments of PDFs) on the clipboard can be _pasted directly
into org buffers_, when using emacs-mac.

## Features and Details:

- Uses the `image-io` image type, which the emacs-mac fork provides,
  for very fast display of image/PDF chunks.
- Uses emacs-mac and applescript to examine the clipboard for image data, saving
  either a PDF or (via `pngpaste`) a PNG image file to a name like
  `pasted_graphic...`
- Uses `org-attach` to _attach_ the pasted images to the containing
  node.
- Handles images copied from webpages, which are presented as URLs.
- Automatically inserts a link at point and views pasted attachments inline.
- High-DPI files (with advertised resolution above
  `omip-high-dpi-limit`) are marked as such with `@2x` in their
  names, and automatically displayed at 50% scale to appear the correct size.
- Cropped PDF files have their cropping information saved in the
  filename, and are displayed correctly.
- Provides a convenience function to refresh all inline images in the
  current node.
- Also supports file drag-and-drop, with the same features.

## Install and Configuration

Not (yet) available on MELPA.  For now, clone the repo and, e.g.

```elisp
(use-package org-mac-image-paste
  :load-path "~/code/emacs/org-mac-image-paste" ; or wherever you cloned to
  :config (org-mac-image-paste-mode 1)
  :bind (:map org-mode-map ("<f6>" . org-mac-image-paste-refresh-this-node)))
```

## Other Requirements

The following are necessary for `org-mac-image-paste` to work:

- The excellent [emacs-mac](https://bitbucket.org/mituharu/emacs-mac/) fork of emacs.
- The in-built `sips` tool (for querying image dpi).
- `pngpaste` (`brew install pngpaste`), for (quickly) pasting PNG files from the clipboard.
- `pdfinfo` (`brew install poppler`), for reading crop info from PDF chunks.

## Tips

You may like to set to set the following org config variables:

```elisp
(org-use-property-inheritance t) ;Inherit :ID/etc. from parent nodes
(org-image-actual-width nil)  ;allow #+ATTR_ORG: :width 300 etc. 
(org-attach-id-dir ".org-attach") ; make the attachment directoy less obvious
```

The inheritance setting allows you to give a top level heading (or even the entire file) an `:ID` (`M-x org-id-get-create`).  Then attachments created at lower levels will all be grouped together under that ID's attachment directory.

If you prefer an image/PDF to display at a different size, preface it with (e.g.):

```org
#+ATTR_ORG: :width 600
```

If you bind `org-mac-image-paste-refresh-this-node` to a convenient key, you can use it to instantly refresh the inline images of just the containing node, e.g. after you have changed the `:width`.

## Other Thoughts

I wish this package didn't exist. Pasting images and PDF fragments into files is a rather basic capability which many may reasonably expect to "just work". I also wish it were fully cross-platform, and didn't rely on external tools to interact with clipboard image data, or determine image resolution and crop information.

But, AFAICT, there is no means within emacs to query the clipboard for image data.  Note that emacs-mac does present `'image-io` for (most) image data is on the clipboard.

What Emacs/Org would need to make this possible:

- Cross-platform clipboard querying of image data and metadata.
- Automatic handling of high-DPI image data (may be challenging given the different approaches across platforms).
- Native PDF display, respecting the `CropBox:` parameter.

(N.B. Imagemagick can handle displaying PDFs inline already.)
