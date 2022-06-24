;;; elpaca-menu-gnu-elpa-mirror.el --- GNU ELPA menu support for elpaca  -*- lexical-binding: t; -*-

;; Copyright (C) 2022  Nicholas Vollmer

;; Author: Nicholas Vollmer
;; Keywords:

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;;  GNU ELPA support for elpaca.

;;; Code:
(require 'cl-lib)
(require 'elpaca-process)

(defcustom elpaca-menu-gnu-elpa-mirror-path
  (expand-file-name "gnu-elpa-mirror/" (temporary-file-directory))
  "Path where GNU ELPA repository is cloned."
  :type 'directory
  :group 'elpaca)

(defvar elpaca-menu-gnu-elpa-mirror--index-cache nil "Cache of index.")
(defvar elpaca-menu-gnu-elpa-mirror-address
  "https://www.github.com/emacs-straight/gnu-elpa-mirror.git"
  "Address of the menu repository.")

(defun elpaca-menu-gnu-elpa-mirror--clone ()
  "Clone GNU ELPA recipes repo to PATH."
  (message "Downloading GNU ELPA recipes...")
  (let ((default-directory user-emacs-directory))
    (elpaca-with-process
        (elpaca-process-call "git" "clone"
                             elpaca-menu-gnu-elpa-mirror-address
                             elpaca-menu-gnu-elpa-mirror-path)
      ;;@TODO: make stderr match more robust
      (if (or success (and stderr (string-match-p "already" stderr)))
          (message "GNU ELPA recipes downloaded.")
        (warn "Unable to download GNU ELPA recipes. This menu will not work!")))))

(defun elpaca-menu-gnu-elpa-mirror--update ()
  "Update recipes in GNU ELPA menu."
  (message "Checking GNU ELPA for updates...")
  (condition-case _
      (progn
        (call-process "git" nil nil nil "pull")
        (message "GNU ELPA updates downloaded"))
    ((error) (message "Unable to pull GNU ELPA recipes"))))

(declare-function dom-by-tag "dom")
(declare-function dom-texts  "dom")
(defun elpaca-menu-gnu-elpa-mirror--metadata ()
  "Return alist of package metadata."
  (when (libxml-available-p)
    (require 'url)
    (require 'dom)
    (with-current-buffer (url-retrieve-synchronously "https://elpa.gnu.org/packages/")
      (when-let ((html (libxml-parse-html-region (point-min) (point-max)))
                 (rows (dom-by-tag html 'tr)))
        (pop rows) ;discard table headers
        (mapcar (lambda (row)
                  (let* ((s (split-string (dom-texts row) " " 'omit-nulls))
                         (item (intern (pop s))))
                    (pop s) ;discard version info
                    (cons item (string-join s " "))))
                rows)))))

(defun elpaca-menu-gnu-elpa-mirror--date (file)
  "Return time of last modification for FILE."
  (elpaca-with-process
      (elpaca-process-call "git" "log" "-1" "--pretty=\"%ci\"" file)
    (when success (date-to-time stdout))))

(defun elpaca-menu-gnu-elpa-mirror--index (&optional recache)
  "Return candidate list of available GNU ELPA recipes.
If RECACHE is non-nil, recompute the cache."
  (or (and (not recache) elpaca-menu-gnu-elpa-mirror--index-cache)
      (let ((metadata (elpaca-menu-gnu-elpa-mirror--metadata))
            (files (directory-files default-directory nil "\\(?:^[^.]\\)"))) ; Only stores descriptions.
        (setq elpaca-menu-gnu-elpa-mirror--index-cache
              (cl-loop for file in files
                       when (file-exists-p (expand-file-name file))
                       for item = (intern file)
                       collect (cons item
                                     (list :source "GNU ELPA Mirror"
                                           :description (or (alist-get item metadata) "This package has not been released yet.")
                                           :date (elpaca-menu-gnu-elpa-mirror--date file)
                                           :url (format "https://elpa.gnu.org/packages/%s.html" item)
                                           :recipe (list :package file
                                                         :host 'github
                                                         :repo (concat "emacs-straight/" file)))))))))

;;;###autoload
(defun elpaca-menu-gnu-elpa-mirror (request)
  "Delegate REQUEST.
If REQUEST is `index`, return a recipe candidate alist.
If REQUEST is `update`, update the GNU ELPA recipe cache."
  (let* ((repo (file-name-as-directory elpaca-menu-gnu-elpa-mirror-path))
         (default-directory repo))
    (unless (file-exists-p repo) (elpaca-menu-gnu-elpa-mirror--clone))
    (pcase request
      ('index  (elpaca-menu-gnu-elpa-mirror--index))
      ('update (setq elpaca-menu-gnu-elpa-mirror--index-cache nil)
               (elpaca-menu-gnu-elpa-mirror--update)))))

(provide 'elpaca-menu-gnu-elpa-mirror)
;;; elpaca-menu-gnu-elpa-mirror.el ends here