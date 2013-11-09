;;; helm-git-grep.el --- helm for git grep

;; Copyright (C) 2013 mechairoi

;; Author: mechairoi
;; Maintainer: Yasuyuki Oka <yasuyk@gmail.com>
;; Version: 0.2
;; URL: https://github.com/yasuyk/helm-git-grep
;; Package-Requires: ((helm "1.0"))
;; Keywords: helm, git

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; Add the following to your emacs init file:
;;
;; (require 'helm-git-grep) ;; Not necessary if using ELPA package
;; (global-set-key (kbd "C-c g") 'helm-git-grep)

;; Original version is anything-git-grep, and port to helm.
;; https://github.com/mechairoi/anything-git-grep

;;; Code:

(eval-when-compile (require 'cl))
(require 'helm)
(require 'helm-elscreen) ;; helm-elscreen-find-file

(declare-function elscreen-get-conf-list "ext:elscreen.el" (type))

(defgroup helm-git-grep nil
  "Helm for git grep."
  :prefix "helm-git-grep-"
  :group 'convenience)

(defcustom helm-git-grep-candidate-number-limit 300
  "Limit candidate number `helm-git-grep'.

Set it to nil if you don't want this limit."
  :group 'helm-git-grep
  :type '(choice (const :tag "Disabled" nil) integer))

(defun helm-git-grep-git-string (&rest args)
  "Execute Git with ARGS, returning the first line of its output.
If there is no output return nil.  If the output begins with a
newline return an empty string."
  (with-temp-buffer
    (apply 'process-file "git" nil (list t nil) nil
           (append '("--no-pager") args))
    (unless (= (point-min) (point-max))
      (goto-char (point-min))
      (buffer-substring-no-properties
       (line-beginning-position)
       (line-end-position)))))

(defun helm-git-grep-get-top-dir (&optional cwd)
  (setq cwd (expand-file-name (file-truename (or cwd default-directory))))
  (when (file-directory-p cwd)
    (let* ((default-directory (file-name-as-directory cwd))
           (cdup (helm-git-grep-git-string "rev-parse" "--show-cdup")))
      (when cdup
        (file-name-as-directory (expand-file-name cdup cwd))))))

(defun helm-git-grep-process ()
  (helm-aif (helm-attr 'default-directory)
      (let ((default-directory it))
        (apply 'start-process "git-grep-process" nil
               "git" "--no-pager" "grep" "--full-name" "-n" "--no-color"
               (nbutlast
                (apply 'append
                       (mapcar
                        (lambda (x) (list "-e" x "--and"))
                        (split-string helm-pattern " +" t))))))
    '()))

(defun helm-git-submodule-grep-process ()
  (helm-aif (helm-attr 'default-directory)
      (let ((default-directory it))
        (apply 'start-process
               "git-submodule-grep-process" nil
               (list
                "git" "--no-pager" "submodule" "--quiet" "foreach"
                (format "git grep --full-name -n --no-color %s | sed s!^!$path/!"
                        (mapconcat (lambda (x)
                                     (format "-e %s " (shell-quote-argument x)))
                                   (split-string helm-pattern " +" t)
                                   "--and ")))))
    '()))

(defun helm-git-grep-save-results-1 ()
  "Save helm git grep result in a `grep-mode' buffer."
  (let ((prompt "GrepBufferName: ")
        (buf "*grep*")
        new-buf)
    (when (get-buffer buf)
      (setq new-buf (read-string prompt buf))
      (loop for b in (helm-buffer-list)
            when (and (string= new-buf b)
                      (not (y-or-n-p
                            (format "Buffer `%s' already exists overwrite? "
                                    new-buf))))
            do (setq new-buf (read-string prompt "*grep ")))
      (setq buf new-buf))
    (with-current-buffer (get-buffer-create buf)
      (setq buffer-read-only t)
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (format "-*- mode: grep; default-directory: \"%s\" -*-\n\n"
                        default-directory)
                (format "Git Grep Results for `%s':\n\n" helm-input))
        (save-excursion
          (insert (with-current-buffer helm-buffer
                    (goto-char (point-min)) (forward-line 1)
                    (buffer-substring (point) (point-max))))))
      (setq default-directory (helm-attr 'default-directory))
      (grep-mode)
      (pop-to-buffer buf))
    (message "Helm Git Grep Results saved in `%s' buffer" buf)))


(defun helm-git-grep-action (candidate &optional where mark)
  "Define a default action for `helm-git-grep' on CANDIDATE.
WHERE can be one of other-window, elscreen, other-frame."
  (let* ((lineno (nth 0 candidate))
         (fname (or (with-current-buffer helm-buffer
                      (get-text-property (point-at-bol) 'help-echo))
                    (nth 2 candidate))))
    (case where
      (other-window (find-file-other-window fname))
      (elscreen     (helm-elscreen-find-file fname))
      (other-frame  (find-file-other-frame fname))
      (grep         (helm-git-grep-save-results-1))
      (t            (find-file fname)))
    (unless (or (eq where 'grep))
      (helm-goto-line lineno))
    (when mark
      (set-marker (mark-marker) (point))
      (push-mark (point) 'nomsg))
    ;; Save history
    (unless (or helm-in-persistent-action
                (string= helm-input ""))
      (setq helm-grep-history
            (cons helm-pattern
                  (delete helm-pattern helm-grep-history)))
      (when (> (length helm-grep-history)
               helm-grep-max-length-history)
        (setq helm-grep-history
              (delete (car (last helm-grep-history))
                      helm-grep-history))))))

(defun helm-git-grep-other-window (candidate)
  "Jump to result in other window from helm git grep."
  (helm-git-grep-action candidate 'other-window))

(defun helm-git-grep-other-frame (candidate)
  "Jump to result in other frame from helm git grep."
  (helm-git-grep-action candidate 'other-frame))

(defun helm-git-grep-jump-elscreen (candidate)
  "Jump to result in elscreen from helm git grep."
  (require 'elscreen)
  (if (elscreen-get-conf-list 'screen-history)
      (helm-git-grep-action candidate 'elscreen)
    (error "elscreen is not running")))

(defun helm-git-grep-save-results (candidate)
  (helm-git-grep-action candidate 'grep))

(defvar helm-git-grep-actions
  (delq
   nil
   `(("Find File" . helm-git-grep-action)
     ("Find file other frame" . helm-git-grep-other-frame)
     ,(and (locate-library "elscreen")
           '("Find file in Elscreen"
             . helm-git-grep-jump-elscreen))
     ("Save results in grep buffer" . helm-git-grep-save-results)
     ("Find file other window" . helm-git-grep-other-window))))

(defun helm-git-filtered-candidate-transformer-file-line (candidates _source)
  (delq nil (mapcar 'helm-git-filtered-candidate-transformer-file-line-1
                    candidates)))

(defun helm-git-filtered-candidate-transformer-file-line-1 (candidate)
  (when (string-match "^\\(.+?\\):\\([0-9]+\\):\\(.*\\)$" candidate)
    (let ((filename (match-string 1 candidate))
          (lineno (match-string 2 candidate))
          (content (match-string 3 candidate)))
      (cons (format "%s:%s: %s"
                    (propertize filename 'face compilation-info-face)
                    (propertize lineno 'face compilation-line-face)
                    content)
            (list (string-to-number lineno) content
                  (expand-file-name
                   filename
                   (or (helm-interpret-value (helm-attr 'default-directory))
                       (and (helm-candidate-buffer)
                            (buffer-local-value
                             'default-directory (helm-candidate-buffer))))))))))

(defun helm-git-grep-init ()
  (helm-attrset 'default-directory (helm-git-grep-get-top-dir)))

(define-helm-type-attribute 'git-grep
  `((default-directory . nil)
    (requires-pattern . 3)
    (volatile)
    (delayed)
    (filtered-candidate-transformer helm-git-filtered-candidate-transformer-file-line)
    (action . ,helm-git-grep-actions)
    (init . helm-git-grep-init)))

(defvar helm-source-git-grep
  '((name . "Git Grep")
    (candidates-process . helm-git-grep-process)
    (type . git-grep)))

(defvar helm-source-git-submodule-grep
  '((name . "Git Submodule Grep")
    (candidates-process . helm-git-submodule-grep-process)
    (type . git-grep)))

(defun helm-git-grep-1 (&optional input)
  (helm :sources '(helm-source-git-grep
                   helm-source-git-submodule-grep)
        :buffer "*helm git grep*"
        :input input
        :candidate-number-limit helm-git-grep-candidate-number-limit))

;;;###autoload
(defun helm-git-grep ()
  "Helm git grep"
  (interactive)
  (helm-git-grep-1))

;;;###autoload
(defun helm-git-grep-from-here ()
  "Helm git grep with current symbol using `helm'."
  (interactive)
  (let* ((symbol (thing-at-point 'symbol))
         (input (if symbol (concat symbol " ") nil)))
    (helm-git-grep-1 input)))


(provide 'helm-git-grep)

;;; helm-git-grep.el ends here
