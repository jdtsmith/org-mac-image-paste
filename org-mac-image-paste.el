;;; omip.el --- Org Mac Image Paste  -*- lexical-binding: t; -*-

;; Copyright (C) 2022  J.D. Smith

;; Author: J.D. Smith
;; Homepage: https://github.com/jdtsmith/org-mac-image-paste
;; Package-Requires: ((emacs "27.1") (org "9.5.2"))
;; Version: 0.0.1
;; Keywords: convenience
;; Prefix: omip
;; Separator: -

;; OMIP is free software: you can redistribute it and/or
;; modify it under the terms of the GNU General Public License as
;; published by the Free Software Foundation, either version 3 of the
;; License, or (at your option) any later version.

;; OMIP is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;; General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; OMIP (Org Mac Image Paste) enables direct pasting of images and
;; PDFs as attachments into org files.

;; Requires:
;;   - The emacs-mac fork (https://bitbucket.org/mituharu/emacs-mac/).
;;   - pngpaste (brew install pngpaste).
;;   - pdfinfo (brew install poppler).

;; Usage: Simply copy an image/screenshot/PDF area/etc., then yank
;;   (paste) into an org file.

;; Details:
;;   - Inspects the clipboard for image data (or URL data, which
;;     images copied from a webpage present as).
;;   - Uses applescript to examine the clipboard, saving either PDF or
;;     (via pngpaste) PNG image files to a name like pasted_graphic...
;;     These are then automatically included as /attachements/ (see
;;     org-attach), inserted into the buffer and viewed inline.
;;   - High-DPI files (with advertised resolution above
;;     `omip-high-dpi-limit') are marked as such with @2x in their
;;     names, and org image display is patched to scale these down by
;;     50%.
;;     

;;; Code:
(eval-when-compile
  (require 'cl-lib))
(require 'org)
(require 'org-element)

(defcustom omip-high-dpi-limit 115.
  "DPI limit above which images are considered high-DPI.
For PNG images with DPI above this value, the attachment filename
will end in @2x.png, which will result in the property :scale 0.5
being applied when inlining the image."
  :group 'org
  :type 'float)

(defconst omip--save-script
  "set base to \"%s\"
if (count of (clipboard info for «class PDF »)) is not 0 then
	set theFile to base & \".pdf\"
	set fd to open for access theFile as POSIX file with write permission
	write (the clipboard as «class PDF ») to fd
	close access fd
else if (count of (clipboard info for «class PNGf»)) is not 0 then
	set theFile to base & \".png\"
	do shell script \"pngpaste \" & theFile
else
	return
end if
return theFile"
  "Applescript to examine the clipboard and write PNG or PDF to file.
Uses pngpaste for speed.")

(defconst omip--pdfinfo-box-regex
  (rx bol "CropBox:"
      (+ ?\s) (group (+ (any ?. num))) (+ ?\s) (group (+ (any ?. num)))
      (+ ?\s) (group (+ (any ?. num))) (+ ?\s) (group (+ (any ?. num)))?\n
      (* nonl) ?\n
      "TrimBox:" (+ ?\s)
      (group (+ (any ?. num))) (+ ?\s) (group (+ (any ?. num))) (+ ?\s)
      (group (+ (any ?. num))) (+ ?\s) (group (+ (any ?. num)))))

(defun omip-attach-and-display-file (file)
  "Attach file FILE, link and display image. "
  (if-let (((string-suffix-p ".png" file)) ; PNG, check for HDPI
	   (sips-str (string-trim
		      (with-output-to-string
			(call-process "sips" nil standard-output nil
				      "-g" "dpiWidth" "-g" "dpiHeight"
				      file))))
	   ((string-match
	     (rx "dpi" (or "Width" "Height") ?: (+ ?\s)
		 (group (+ (any num ?.))) (* nonl) ?\n (+ ?\s)
		 "dpi" (or "Width" "Height") ?: (+ ?\s)
		 (group (+ (any num ?.))))
	     sips-str))
	   ((> (sqrt (* (string-to-number (match-string 1 sips-str))
			(string-to-number (match-string 2 sips-str))))
	       omip-high-dpi-limit))
	   (new (concat (substring file 0 -4) "@2x.png")))
      (progn (rename-file file new t)
	     (setq file new))
    (if-let (((string-suffix-p ".pdf" file)) ; PDF, check for crop
	     (pdfinfo (with-output-to-string
			(call-process "pdfinfo" nil standard-output nil
				      "-box" file)))
	     ((string-match omip--pdfinfo-box-regex pdfinfo)))
	(pcase-let* ((`(,cx0 ,cy0 ,cx1 ,cy1 ,tx0 ,ty0 ,tx1 ,ty1 )
		      (cl-loop for i from 1 to 8
			       collect (string-to-number
					(match-string i pdfinfo)))))
	  (unless (and (= tx0 cx0) (= ty0 cy0) (= tx1 cx1) (= ty1 cy1))
	    (let* ((crop-info (format "_%0.1f_%0.1f_%0.1f_%0.1f" ; w h x y
				      (- cx1 cx0) (- cy1 cy0) cx0 (- ty1 cy1)))
		   (new (concat (substring file 0 -4)
				crop-info ".pdf")))
	      (rename-file file new t)
	      (setq file new))))))
  (let ((org-attach-store-link-p 'attached))
    (org-attach-attach file nil 'mv))
  (org-insert-link nil (caar org-stored-links) "")
  (org-display-inline-images nil t (line-beginning-position) (point)))

(defun omip-org-yank (&optional _arg)
  "Yank, creating an org attachment:link if image/pdf on the clipboard.
Requires pngpaste and pdfinfo to be installed.  Also toggles
inline image display of the attachment.  To be added as
:before-until advice to `org-yank'.  Note that images copied from
the browser are also presented as text URLs, so we also check in
this case.  Note that Emacs and image-io use the upper left as
the origin for crop, and PDF boxes use the lower left."
  (interactive "p")
  (if org-mac-image-paste-mode
      (let* ((clip (current-kill 0))
	     (disp (cdr (get-text-property 0 'display clip)))
	     attach-file base)
	(when (or (eq (plist-get disp :type) 'image-io)
		  (if-let ((url (url-generic-parse-url clip))) (url-type url)))
	  (setq base (concat (temporary-file-directory)
			     (make-temp-name "pasted_graphic_") "-"
			     (format-time-string "%s"))
		attach-file (string-trim
			     (do-applescript (format omip--save-script base))
			     "[ \"]" "[ \"\n]"))
	  (when (and (not (string-empty-p attach-file))
		     (file-exists-p attach-file))
	    (omip-attach-and-display-file attach-file)
	    t)))))

(defalias 'omip--orig-create-image (symbol-function 'create-image)
  "Saved copy of `create-image'.")

(defconst omip--crop-file-regexp
  (rx (group (+ (any ?. num))) ?_ (group (+ (any ?. num))) ?_
      (group (+ (any ?. num))) ?_ (group (+ (any ?. num))) ".pdf" eos))

(defun omip--calculate-pdf-properties (filename props)
  "Calculate a :crop property from the crop info encoded in a PDF filename (if any).
Pass a plist of image PROPS, which will be modified, e.g. by
replacing :width with an equivalent :scale.  Returns the modified
PROPS."
  (setq props (plist-put props :background "white"))
  (when-let (((string-match omip--crop-file-regexp filename))
	     (crop (cl-loop for i from 1 to 4
			    collect (string-to-number (match-string i filename)))))
    (when-let ((width (car crop)) 
	       (pwidth (plist-get props :width)))
      (plist-put props :scale (/ (float pwidth) width))
      (setq props (org-plist-delete props :width)))	; scale overrides width
    (plist-put props :crop
	       (cl-loop with scale = (or (plist-get props :scale) 1.0)
			for c in crop collect (round (* c scale)))))
  props)

(defun omip--create-image (file-or-data &optional _type data-p &rest props)
  "A `create-image' substitute which scales high-DPI files.
Also substitutes the (emacs-mac specific) 'image-io image type in
place of 'imagemagick, and sets PDF background to white.  To be
set during `org--create-inline-image'."
  (when (not data-p)				   ; a file
    (if (string-suffix-p "@2x.png" file-or-data) ; HDPI PNG
	(unless (plist-get props :width)
	  (setq props (plist-put props :scale 0.5)))
      (when (string-suffix-p ".pdf" file-or-data) ; PDF
	(setq props (omip--calculate-pdf-properties file-or-data props))))
    (if (plist-member props :width)
	(unless (plist-get props :width) ;image-io dislikes :width nil
	  (setq props (org-plist-delete props :width)))))
  (apply #'omip--orig-create-image file-or-data 'image-io data-p props))

(defun omip--create-inline-image (fun &rest r)
  "Temporarily substitute `create-image' with `omip--create-image'.
To be set as :around advice for `org--create-inline-image'."
  (cl-letf (((symbol-function #'create-image) #'omip--create-image))
    (apply fun r)))

(defun org-mac-image-paste-refresh-this-node ()
  "Convenience function to refresh all images in the node at point.
If not in a node, refresh entire file."
  (interactive)
  (save-excursion
    (org-previous-visible-heading 1)
    (let* ((elem (org-element-at-point))
	   (beg (org-element-property :contents-begin elem))
	   (end (org-element-property :contents-end elem)))
      (when (and beg end)
	(setq org-inline-image-overlays
	      (cl-loop for ov in org-inline-image-overlays
		       if (let ((ov-start (overlay-start ov))
				(ov-end (overlay-end ov)))
			    (if (and ov-start ov-end)
				(if (and (>= ov-start beg) (<= ov-end end))
				    (progn (delete-overlay ov) nil)
				  t) ; not in this node, just collect
			      nil))
		       collect ov))
	(org-display-inline-images nil t beg end)))))

(defun omip-dnd (url _action)
  "Handle file drag-and-drop."
  (if-let ((url (url-generic-parse-url url))
	   ((equal (url-type url) "file"))
	   (file (url-unhex-string (url-filename url))))
      (let* ((tmp-file (concat (temporary-file-directory)
			       (file-name-nondirectory file))))
	(copy-file file tmp-file)
	(omip-attach-and-display-file tmp-file))))

;;;###autoload
(define-minor-mode org-mac-image-paste-mode
  "Minor mode enabling direct pasting of images/pdfs in org-mode."
  :global t
  (if org-mac-image-paste-mode
      (progn
	(cl-pushnew "pdf" image-file-name-extensions)
	(advice-add #'org-yank :before-until #'omip-org-yank)
	(advice-add #'org--create-inline-image :around
		    #'omip--create-inline-image)
	(cl-pushnew (cons (rx bos "file:") #'omip-dnd) dnd-protocol-alist))
    (cl-delete "pdf" image-file-name-extensions)
    (setq dnd-protocol-alist
	  (delq (rassq 'omip-dnd dnd-protocol-alist) dnd-protocol-alist))
    (advice-remove #'org-yank #'omip-org-yank)
    (advice-remove #'org--create-inline-image #'omip--create-inline-image)))

(provide 'org-mac-image-paste)
;;; org-mac-image-paste.el ends here
