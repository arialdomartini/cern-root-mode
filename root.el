;;; root.el --- Major-mode for running C++ code with ROOT  -*- lexical-binding: t; -*-

;; Copyright (C) 2022  Jay Morgan

;; Author: Jay Morgan <jay@morganwastaken.com>
;; Keywords: languages, tools

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

;; ROOT (https://root.cern/) is a framework for performing data
;; analysis. This package means to integrate this framework within the
;; ecosystem of Emacs. More specifically, root.el provides functions
;; to run C++ code within the ROOT REPL and execute org-mode source
;; code blocks, replicating the jupyter environment in `root
;; --notebook'.

;;; Code:

(defcustom root nil
  "Major-mode for running C++ code with ROOT"
  :group 'languages)

(defcustom root-filepath "root"
  "Path to the ROOT executable"
  :type 'string
  :group 'root)

(defcustom root-command-options ""
  "Command line options for running ROOT"
  :type 'string
  :group 'root)

(defcustom root-prompt-regex "^\\(?:root \\[[0-9]+\\] \\)"
  "Regular expression to find prompt location in ROOT-repl."
  :type 'string
  :group 'root)

(defcustom root-terminal-backend 'inferior
  "Type of terminal to use when running ROOT"
  :type 'symbol
  :options '(inferior vterm)
  :group 'root)

(defcustom root-buffer-name "*ROOT*"
  "Name of the newly create buffer for ROOT"
  :type 'string
  :group 'root)

;;; end of user variables

(defmacro remembering-position (&rest body)
  `(save-window-excursion (save-excursion ,@body)))

(defun push-new (element lst)
  (if (member element lst)
      lst
    (push member lst)))

(defun pluck-item (el lst)
  (cdr (assoc el lst)))

(defun make-earmuff (name)
  "Give a string earmuffs, i.e. some-name -> *some-name*"
  (if (or (not (stringp name))  ;; only defined for strings
	  (= (length name) 0)   ;; but not empty strings
	  (and (string= "*" (substring name 0 1))
	       (string= "*" (substring name (1- (length name))))))
      name
    (format "*%s*" name)))

(defun make-no-earmuff (name)
  "Remove earmuffs from a string if it has them, *some-name* -> some-name"
  (if (and (stringp name)
	   (> (length name) 0)
	   (string= "*" (substring name 0 1))
	   (string= "*" (substring name (1- (length name)))))
      (substring name 1 (1- (length name)))
    name))

(defvar root--backend-functions
  '((vterm . ((start-terminal . root--start-vterm)
	      (send-function . root--send-vterm)
	      (previous-prompt . vterm-previous-prompt)
	      (next-prompt . vterm-next-prompt)))
    (inferior . ((start-terminal . root--start-inferior)
		 (send-function . root--send-inferior)
		 (previous-prompt . comint-previous-prompt)
		 (next-prompt . comint-next-prompt))))
  "Mapping from terminal type to various specific functions")

(defun root--get-functions-for-terminal (terminal)
  (pluck-item terminal root--backend-functions))

(defun root--get-function-for-terminal (terminal function-type)
  (pluck-item function-type (root--get-functions-for-terminal terminal)))

(defun root--get-function-for-current-terminal (function-type)
  (root--get-function-for-terminal root-terminal-backend function-type))

(defalias 'root--ctfun 'root--get-function-for-current-terminal
  "ctfun -- current terminal function")

(defun root--send-vterm (proc input)
  "Send a string to the vterm REPL."
  (remembering-position
   (root-switch-to-repl)
   (vterm-send-string input)
   (vterm-send-return)))

(defun root--send-inferior (proc input)
  "Send a string to an inferior REPL."
  (comint-send-string proc (format "%s\n" input)))

(defun root--preinput-clean (input)
  (string-replace
   "\t" ""
   (string-replace "\n" " " (format "%s" input))))

(defun root--send-string (proc input)
  "Send a string to the ROOT repl."
  (funcall (root--ctfun 'send-function) proc (root--preinput-clean input)))

(defun root--start-vterm ()
  "Run an instance of ROOT in vterm"
  (let ((vterm-shell root-filepath))
    (vterm root-buffer-name)))

(defun root--start-inferior ()
  "Run an inferior instance of ROOT"
  (let ((root-exe root-filepath)
	(buffer (comint-check-proc (make-no-earmuff root-buffer-name)))
	(created-vars (root--set-env-vars)))
    (pop-to-buffer-same-window
     (if (or buffer (not (derived-mode-p 'root-mode))
	     (comint-check-proc (current-buffer)))
	 (get-buffer-create (or buffer root-buffer-name))
       (current-buffer)))
    (unless buffer
      (make-comint-in-buffer (make-no-earmuff root-buffer-name) buffer root-exe nil root-command-options)
      (root-mode))
    (when created-vars
      (sleep-for 0.1)  ;; give enough time for ROOT to start before removing vars
      (root--unset-env-vars))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Major mode & comint functions
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defvar root--rcfile "./.rootrc")

(defun root--set-env-vars ()
  "Setup the environment variables so that no colours or bold
fonts will be used in the REPL. This prevents comint from
creating duplicated input in trying to render the ascii colour
codes.

Function returns t if the variables have been set, else nil. This
return value is very useful for deciding if the variables should
be unset, as we will want not want to remove the user's existing
rcfiles."
  (if (not (file-exists-p root--rcfile))  ;; don't clobber existing rcfiles
    (let ((vars (list "PomptColor" "TypeColor" "BracketColor" "BadBracketColor" "TabComColor"))
	  (val  "default")
	  (buf  (create-file-buffer root--rcfile)))
      (with-current-buffer buf
	(insert (apply 'concat (mapcar (lambda (v) (format "Rint.%s\t\t%s\n" v val)) vars)))
	(write-file root--rcfile nil))
      (kill-buffer buf))
    nil))

(defun root--unset-env-vars ()
  (delete-file root--rcfile))

(defun root--initialise ()
  (setq comint-process-echoes t
	comint-use-prompt-regexp t))

(defvar root-mode-map
  (let ((map (nconc (make-sparse-keymap) comint-mode-map)))
    (define-key map "\t" 'completion-at-point)
    map)
  "Basic mode map for ROOT")

(define-derived-mode root-mode comint-mode
  "ROOT"
  "Major for `run-root'.

\\<root-mode-map>"
  nil "ROOT"
  (setq comint-prompt-regexp root-prompt-regex
	comint-prompt-read-only nil
	process-connection-type 'pipe)
  (set (make-local-variable 'paragraph-separate) "\\'")
  (set (make-local-variable 'paragraph-start) root-prompt-regex)
  (set (make-local-variable 'comint-input-sender) 'root--send-string)
  (add-hook 'comint-dynamic-complete-functions 'root--comint-dynamic-completion-function nil 'local)
  (set (make-local-variable 'company-backends) (push-new 'company-capf company-backends))
  (add-hook 'root-mode-hook 'root--initialise))

;; (defun org-babel-execute:root (body params)
;;   "Execute a block of C++ code with ROOT in org-mode."
;;   (message "Executing C++ source code block in ROOT"))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Completion framework
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defvar root--keywords nil)

(defvar root--completion-buffer-name "*ROOT Completions*")

(defun root--get-last-output ()
  ;; TODO: needs improvement to better capture the last output
  (remembering-position
   (root-switch-to-repl)
   (end-of-buffer)
   (let* ((regex (format "%s.*"(substring root-prompt-regex 1)))
	  (np (re-search-backward regex))
	  (pp (progn (re-search-backward regex)
		    (next-line)
		    (point))))
     (buffer-substring-no-properties pp np))))

(defun root--completion-filter-function (text)
  (setf root--keywords text))

(defun root--clear-completions ()
  (when (get-buffer root--completion-buffer-name)
    (with-current-buffer root--completion-buffer-name
      (erase-buffer))))

(defun root--get-partial-input (beg end)
  (buffer-substring-no-properties beg end))

(defun root--remove-ansi-escape-codes (string)
  (let ((regex "\\[[0-9;^kD]+m?"))
    (s-replace-regexp regex "" string)))

(defun root--get-completions-from-buffer ()
  (with-current-buffer root--completion-buffer-name
    (while (not comint-redirect-completed)
      (sleep 0.01))
    (setq root--keywords (split-string (root--remove-ansi-escape-codes (buffer-string)) "\n"))))

(defun root--comint-dynamic-completion-function ()
  (cl-return)
  (when-let* ((bound (bounds-of-thing-at-point 'symbol))
	      (beg   (car bound))
	      (end   (cdr bound)))
    (when (> end beg)
      (let ((partial-input (root--get-partial-input beg end)))
	(message partial-input)
	(root--clear-completions)
	(comint-redirect-send-command-to-process
	 (format "%s\t" partial-input) root--completion-buffer-name root-buffer-name "" nil)
	(list beg end root--keywords . nil)))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; User functions
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;;###autoload
(defun run-root ()
  "Run an inferior instance of ROOT"
  (interactive)
  (funcall (root--ctfun 'start-terminal)))

;;;###autoload
(defun run-root-other-window ()
  "Run an inferior instance of ROOT in an different window"
  (interactive)
  (split-window-sensibly)
  (other-window 1)
  (run-root))

(defun root-switch-to-repl ()
  "Switch to the ROOT REPL"
  (interactive)
  (let ((win (get-buffer-window root-buffer-name)))
    (if win
	(select-window win)
      (switch-to-buffer root-buffer-name))))

(defun root-eval-region (beg end)
  "Evaluate a region in ROOT"
  (interactive "r")
  (kill-ring-save beg end)
  (let ((string (format "%s" (buffer-substring beg end))))
    (root-switch-to-repl)
    (root--send-string root-buffer-name string)))

(defun root-eval-line ()
  "Evaluate this line in ROOT"
  (interactive)
  (remembering-position
   (let ((beg (progn (beginning-of-line) (point)))
	 (end (progn (end-of-line) (point))))
     (root-eval-region beg end))))

(defun root-eval-defun ()
  "Evaluate a function in ROOT"
  (interactive)
  (remembering-position
   (c-mark-function)
   (root-eval-region (region-beginning) (region-end))))

(defun root-eval-defun-maybe ()
  "Evaluate a defun in ROOT if in declaration else just the line"
  (interactive)
  (condition-case err
      (root-eval-defun)
    ('error (root-eval-line))))

(defun root-eval-buffer ()
  "Evaluate the buffer in ROOT"
  (interactive)
  (remembering-position
   (mark-whole-buffer)
   (root-eval-region (region-beginning) (region-end))))

(defun root-eval-file (filename)
  "Evaluate a file in ROOT"
  (interactive "fFile to load: ")
  (comint-send-string root-buffer-name (concat ".U " filename "\n"))
  (comint-send-string root-buffer-name (concat ".L " filename "\n")))

(defun root-change-working-directory (dir)
  "Change the working directory of ROOT"
  (interactive "DChange to directory: ")
  (comint-send-string root-buffer-name (concat "gSystem->cd(\"" (expand-file-name dir) "\")\n")))

(defun root-list-input-history ()
  "List the history of previously entered statements"
  (interactive)
  (comint-dynamic-list-input-ring))

(provide 'root-mode)
;;; root.el ends here
